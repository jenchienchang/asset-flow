//  AssetFlow — snapshot-based portfolio management for macOS.
//  Copyright (C) 2026 Jen-Chien Chang
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import SwiftData

/// Data for a single category row in the list.
struct CategoryRowData: Identifiable {
  var id: UUID { category.id }
  let category: Category
  let targetAllocation: Decimal?
  let currentAllocation: Decimal?
  let currentValue: Decimal
  let assetCount: Int
}

/// Deviation threshold (in percentage points) for showing the warning indicator.
let significantDeviationThreshold: Decimal = 5

/// ViewModel for the Categories list screen.
///
/// Manages category listing with allocation computation,
/// and category creation, editing, and deletion with validation.
@Observable
@MainActor
final class CategoryListViewModel {
  private let modelContext: ModelContext
  private let settingsService: SettingsService

  var categoryRows: [CategoryRowData] = []
  var targetAllocationSumWarning: String?
  var hasSignificantDeviation = false
  var conversionStatus: CurrencyConversionStatus = .notNeeded

  init(modelContext: ModelContext, settingsService: SettingsService? = nil) {
    self.modelContext = modelContext
    self.settingsService = settingsService ?? .shared
  }

  // MARK: - Loading

  /// Fetches all categories, computes current values and allocations from the
  /// most recent snapshot, and builds sorted row data.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadCategories() {
    withObservationTracking {
      performLoadCategories()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadCategories()
      }
    }
  }

  private func performLoadCategories() {
    let allCategories = fetchAllCategories()
    let latestSnapshot = SnapshotSummaryService.fetchLatestSnapshot(modelContext: modelContext)
    conversionStatus =
      latestSnapshot.map {
        CurrencyConversionService.totalValueReport(
          for: $0,
          displayCurrency: settingsService.mainCurrency,
          exchangeRate: $0.exchangeRate
        ).status
      } ?? .notNeeded

    // Build latest value lookup grouped by category
    let categoryValues = buildCategoryValueLookup(
      latestSnapshot: latestSnapshot)

    let totalValue = categoryValues.values.reduce(Decimal(0), +)
    let hasSnapshots = latestSnapshot != nil

    normalizeDisplayOrderIfNeeded(allCategories)

    categoryRows =
      allCategories.map { category in
        let value = categoryValues[category.id] ?? 0
        let allocation: Decimal? =
          hasSnapshots
          ? conversionStatus.isComplete
            ? CalculationService.categoryAllocation(
              categoryValue: value, totalValue: totalValue)
            : nil
          : nil
        return CategoryRowData(
          category: category,
          targetAllocation: category.targetAllocationPercentage,
          currentAllocation: allocation,
          currentValue: value,
          assetCount: (category.assets ?? []).count
        )
      }
      .sorted {
        if $0.category.displayOrder != $1.category.displayOrder {
          return $0.category.displayOrder < $1.category.displayOrder
        }
        return $0.category.name.localizedCaseInsensitiveCompare($1.category.name)
          == .orderedAscending
      }

    targetAllocationSumWarning = computeTargetAllocationWarning(categories: allCategories)

    hasSignificantDeviation = categoryRows.contains { row in
      guard let target = row.targetAllocation, let current = row.currentAllocation else {
        return false
      }
      return abs(current - target) > significantDeviationThreshold
    }
  }

  // MARK: - Create

  /// Creates a new category with the given name and optional target allocation.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with existing category.
  @discardableResult
  func createCategory(name: String, targetAllocation: Decimal?) throws -> Category {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    if let target = targetAllocation {
      guard target >= 0 && target <= 100 else { throw CategoryError.invalidTargetAllocation }
    }

    guard !isDuplicateName(trimmed, excludingID: nil) else {
      throw CategoryError.duplicateName(trimmed)
    }

    let category = Category(name: trimmed, targetAllocationPercentage: targetAllocation)
    category.displayOrder = nextDisplayOrder()
    modelContext.insert(category)
    return category
  }

  // MARK: - Edit

  /// Updates category name and target allocation with validation.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with another category.
  func editCategory(
    _ category: Category, newName: String, newTargetAllocation: Decimal?
  ) throws {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    if let target = newTargetAllocation {
      guard target >= 0 && target <= 100 else { throw CategoryError.invalidTargetAllocation }
    }

    guard !isDuplicateName(trimmed, excludingID: category.id) else {
      throw CategoryError.duplicateName(trimmed)
    }

    category.name = trimmed
    category.targetAllocationPercentage = newTargetAllocation
  }

  // MARK: - Delete

  /// Deletes a category if it has no assigned assets.
  ///
  /// - Throws: `CategoryError.cannotDelete` if assets are assigned.
  func deleteCategory(_ category: Category) throws {
    let assets = category.assets ?? []
    guard assets.isEmpty else {
      throw CategoryError.cannotDelete(assetCount: assets.count)
    }
    modelContext.delete(category)
    compactDisplayOrder()
  }

  // MARK: - Move

  /// Reorders categories by moving items at the given offsets to the target position.
  ///
  /// Implements the same semantics as `Array.move(fromOffsets:toOffset:)` from SwiftUI
  /// without requiring a SwiftUI import in the ViewModel layer.
  func moveCategories(from source: IndexSet, to destination: Int) {
    var categories = categoryRows.map(\.category)
    // Adjust destination for removals before the insertion point
    let adjustedDestination = destination - source.filter { $0 < destination }.count
    let moved = source.sorted().map { categories[$0] }
    // Remove from highest index first to preserve indices
    for index in source.sorted().reversed() {
      categories.remove(at: index)
    }
    let insertAt = min(adjustedDestination, categories.count)
    categories.insert(contentsOf: moved, at: insertAt)
    for (index, category) in categories.enumerated() {
      category.displayOrder = index
    }
    loadCategories()
  }

  // MARK: - Private Helpers

  private func fetchAllCategories() -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  /// Returns the next available displayOrder value.
  private func nextDisplayOrder() -> Int {
    let allCategories = fetchAllCategories()
    return (allCategories.map(\.displayOrder).max() ?? -1) + 1
  }

  /// Compacts displayOrder values after a deletion to remove gaps.
  private func compactDisplayOrder() {
    let allCategories = fetchAllCategories()
    for (index, category) in allCategories.enumerated() {
      category.displayOrder = index
    }
  }

  /// Normalizes displayOrder when all categories have the same value (migration scenario).
  private func normalizeDisplayOrderIfNeeded(_ categories: [Category]) {
    guard categories.count > 1 else { return }
    let allSame = categories.allSatisfy { $0.displayOrder == categories[0].displayOrder }
    guard allSame else { return }
    let sorted = categories.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    for (index, category) in sorted.enumerated() {
      category.displayOrder = index
    }
  }

  /// Builds a lookup of category ID → total market value from the latest snapshot,
  /// converting each asset's value to the display currency.
  private func buildCategoryValueLookup(
    latestSnapshot: Snapshot?
  ) -> [UUID: Decimal] {
    guard let latestSnapshot else { return [:] }

    let assetValues = latestSnapshot.assetValues ?? []
    let displayCurrency = settingsService.mainCurrency
    let exchangeRate = latestSnapshot.exchangeRate

    let report = CurrencyConversionService.totalValueReport(
      for: latestSnapshot,
      displayCurrency: displayCurrency,
      exchangeRate: exchangeRate
    )
    guard report.status.isComplete else { return [:] }

    var lookup: [UUID: Decimal] = [:]
    for sav in assetValues {
      guard let asset = sav.asset, let categoryID = asset.category?.id else { continue }
      let assetCurrency = asset.currency
      let effectiveCurrency = assetCurrency.isEmpty ? displayCurrency : assetCurrency
      let converted = CurrencyConversionService.convert(
        value: sav.marketValue,
        from: effectiveCurrency,
        to: displayCurrency,
        using: exchangeRate,
        forSnapshotDate: latestSnapshot.date)
      lookup[categoryID, default: 0] += converted ?? 0
    }
    return lookup
  }

  /// Checks if a category name already exists (case-insensitive), optionally excluding one ID.
  private func isDuplicateName(_ name: String, excludingID: UUID?) -> Bool {
    let normalized = name.lowercased()
    let descriptor = FetchDescriptor<Category>()
    let allCategories = (try? modelContext.fetch(descriptor)) ?? []

    return allCategories.contains { category in
      category.name.lowercased() == normalized
        && category.id != excludingID
    }
  }

  /// Computes the target allocation sum warning message, or nil if sum is 100%.
  private func computeTargetAllocationWarning(categories: [Category]) -> String? {
    let categoriesWithTargets = categories.filter {
      $0.targetAllocationPercentage != nil
    }

    guard !categoriesWithTargets.isEmpty else { return nil }

    let sum = categoriesWithTargets.reduce(Decimal(0)) {
      $0 + ($1.targetAllocationPercentage ?? 0)
    }

    guard sum != 100 else { return nil }

    return String(
      localized:
        "Target allocations sum to \(sum.formattedPercentage()) instead of 100%.",
      table: "Category")
  }
}
