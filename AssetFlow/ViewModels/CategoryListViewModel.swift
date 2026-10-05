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
  var effectiveTargetAllocation: Decimal?
  var minimumStatus: MinimumBalanceStatus = .notSet
  var displayCurrency: String = ""

  var hasAllocationDeviation: Bool {
    guard let currentAllocation, let effectiveTargetAllocation,
      targetAllocation != nil
    else { return false }
    return abs(currentAllocation - effectiveTargetAllocation) > significantDeviationThreshold
  }
  var hasMinimumShortfall: Bool {
    if case .shortfall(let amount) = minimumStatus { return amount > 0 }
    return false
  }
  var hasWarning: Bool { hasAllocationDeviation || hasMinimumShortfall }
  var warningMessage: String {
    var reasons: [String] = []
    if hasAllocationDeviation {
      reasons.append(
        String(
          localized:
            "Current allocation differs from the effective target by more than 5 percentage points.",
          table: "Category"))
    }
    if case .shortfall(let amount) = minimumStatus, amount > 0 {
      reasons.append(
        String(
          localized:
            "Minimum balance shortfall: \(RebalancingHelpPresentation.monetaryValue(amount, currency: displayCurrency))",
          table: "Category"))
    }
    return reasons.map { "• " + $0 }.joined(separator: "\n")
  }
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
  @ObservationIgnored private let refresh = ObservedRefresh()

  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  var goalAssessment = CategoryGoalAssessment()

  var categoryRows: [CategoryRowData] = []
  var loadState: DataLoadState = .idle
  var targetAllocationSumWarning: String?
  var hasSignificantDeviation = false
  var conversionStatus: CurrencyConversionStatus = .notNeeded

  init(
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.settingsService = settingsService ?? .shared
  }

  /// Coalesces source-observation and query notifications before refreshing.
  func requestRefresh() {
    refresh.request { [weak self] in self?.loadCategories() }
  }

  // MARK: - Loading

  /// Fetches all categories, computes current values and allocations from the
  /// most recent snapshot, and builds sorted row data.
  ///
  /// Uses `ObservedRefresh` to track source reads and publish derived results. Any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadCategories() {
    refresh.perform {
      performLoadCategories()
    } reload: { [weak self] in
      self?.loadCategories()
    }
  }

  private func performLoadCategories() {
    do {
      let allCategories = try fetchAllCategories()
      let latestSnapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      // Ordering normalization is a source mutation; perform it before reading row order.
      normalizeDisplayOrderIfNeeded(allCategories)
      let assessment = CategoryGoalAssessmentService.assess(
        snapshot: latestSnapshot, categories: allCategories,
        displayCurrency: settingsService.mainCurrency)
      let total = assessment.totalValue ?? 0
      let targets = Dictionary(
        uniqueKeysWithValues: (assessment.plan?.targets ?? []).map { ($0.id, $0) })
      let rows = allCategories.map { category in
        let value = assessment.values[category.id] ?? 0
        let allocation: Decimal? =
          latestSnapshot != nil && total > 0 && assessment.assetConversion.isComplete
          ? CalculationService.categoryAllocation(categoryValue: value, totalValue: total) : nil
        var row = CategoryRowData(
          category: category, targetAllocation: category.targetAllocationPercentage,
          currentAllocation: allocation, currentValue: value,
          assetCount: (category.assets ?? []).count)
        row.displayCurrency = settingsService.mainCurrency
        row.minimumStatus = assessment.statuses[category.id] ?? .notSet
        if assessment.plan?.status == .feasible, total > 0,
          category.targetAllocationPercentage != nil || category.minimumBalanceAmount != nil,
          let target = targets[category.id]
        {
          row.effectiveTargetAllocation = target.targetValue / total * 100
        }
        return row
      }.sorted {
        if $0.category.displayOrder != $1.category.displayOrder {
          return $0.category.displayOrder < $1.category.displayOrder
        }
        return $0.category.name.localizedCaseInsensitiveCompare($1.category.name)
          == .orderedAscending
      }
      let sumWarning = computeTargetAllocationWarning(categories: allCategories)
      let deviation = rows.contains { $0.hasAllocationDeviation }
      refresh.publish {
        self.goalAssessment = assessment
        self.conversionStatus = assessment.assetConversion
        self.categoryRows = rows
        self.targetAllocationSumWarning = sumWarning
        self.hasSignificantDeviation = deviation
        self.loadState = .loaded
      }
    } catch {
      let message = error.localizedDescription
      refresh.publish { self.loadState = .failed(message) }
    }
  }

  // MARK: - Create

  /// Creates a new category with the given name and optional target allocation.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with existing category.
  @discardableResult
  func createCategory(
    name: String, targetAllocation: Decimal?, minimumBalance: Decimal? = nil,
    minimumCurrency: String? = nil
  ) throws -> Category {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    if let target = targetAllocation {
      guard target >= 0 && target <= 100 else { throw CategoryError.invalidTargetAllocation }
    }

    guard try !isDuplicateName(trimmed, excludingID: nil) else {
      throw CategoryError.duplicateName(trimmed)
    }

    do {
      try CategoryGoalValidator.validate(
        percentage: targetAllocation, minimum: minimumBalance, currency: minimumCurrency,
        supportedCurrencies: Set(CurrencyService.shared.currencies.map { $0.code.uppercased() }))
    } catch CategoryGoalValidationError.percentage { throw CategoryError.invalidTargetAllocation }
    let category = Category(name: trimmed, targetAllocationPercentage: targetAllocation)
    category.minimumBalanceAmount = minimumBalance
    category.minimumBalanceCurrency = minimumCurrency?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).uppercased()
    category.displayOrder = try nextDisplayOrder()
    modelContext.insert(category)
    return category
  }

  // MARK: - Edit

  /// Updates category name and target allocation with validation.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with another category.
  func editCategory(_ category: Category, newName: String, newTargetAllocation: Decimal?) throws {
    try editCategory(
      category, newName: newName, newTargetAllocation: newTargetAllocation,
      minimumBalance: category.minimumBalanceAmount,
      minimumCurrency: category.minimumBalanceCurrency)
  }

  func editCategory(
    _ category: Category, newName: String, newTargetAllocation: Decimal?, minimumBalance: Decimal?,
    minimumCurrency: String?
  ) throws {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    if let target = newTargetAllocation {
      guard target >= 0 && target <= 100 else { throw CategoryError.invalidTargetAllocation }
    }

    guard try !isDuplicateName(trimmed, excludingID: category.id) else {
      throw CategoryError.duplicateName(trimmed)
    }

    var supported = Set(CurrencyService.shared.currencies.map { $0.code.uppercased() })
    if let previous = category.minimumBalanceCurrency { supported.insert(previous) }
    do {
      try CategoryGoalValidator.validate(
        percentage: newTargetAllocation, minimum: minimumBalance, currency: minimumCurrency,
        supportedCurrencies: supported)
    } catch CategoryGoalValidationError.percentage { throw CategoryError.invalidTargetAllocation }
    category.name = trimmed
    category.targetAllocationPercentage = newTargetAllocation
    category.minimumBalanceAmount = minimumBalance
    category.minimumBalanceCurrency = minimumCurrency?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).uppercased()
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
    try compactDisplayOrder()
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

  private func fetchAllCategories() throws -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return try fetchModels(descriptor, from: fetcher, operation: "fetch categories")
  }

  /// Returns the next available displayOrder value.
  private func nextDisplayOrder() throws -> Int {
    let allCategories = try fetchAllCategories()
    return (allCategories.map(\.displayOrder).max() ?? -1) + 1
  }

  /// Compacts displayOrder values after a deletion to remove gaps.
  private func compactDisplayOrder() throws {
    let allCategories = try fetchAllCategories()
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

  /// Checks if a category name already exists (case-insensitive), optionally excluding one ID.
  private func isDuplicateName(_ name: String, excludingID: UUID?) throws -> Bool {
    let normalized = name.lowercased()
    let descriptor = FetchDescriptor<Category>()
    let allCategories = try fetchModels(
      descriptor, from: fetcher, operation: "check category uniqueness")

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
