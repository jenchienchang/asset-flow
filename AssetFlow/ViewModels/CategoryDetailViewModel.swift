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

/// Value history entry for a category's total value at a snapshot date.
struct CategoryValueHistoryEntry: Identifiable {
  var id: String { "\(date.timeIntervalSince1970)-\(totalValue)" }
  let date: Date
  let totalValue: Decimal
}

/// Allocation history entry for a category's allocation percentage at a snapshot date.
struct CategoryAllocationHistoryEntry: Identifiable {
  var id: String { "\(date.timeIntervalSince1970)-\(allocationPercentage)" }
  let date: Date
  let allocationPercentage: Decimal
}

/// ViewModel for the Category detail/edit screen.
///
/// Manages editing category properties (name, target allocation),
/// loading assets in the category with latest values,
/// computing value and allocation history across snapshots,
/// and deletion with validation.
@Observable
@MainActor
final class CategoryDetailViewModel {
  let category: Category
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  var editedName: String
  var editedTargetAllocation: Decimal?

  /// Text binding for the target allocation text field.
  /// Parses the text into `editedTargetAllocation` on change.
  var targetAllocationText: String {
    didSet {
      guard targetAllocationText != oldValue else { return }
      let trimmed = targetAllocationText.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        editedTargetAllocation = nil
      } else if let value = Decimal.parse(trimmed) {
        editedTargetAllocation = value
      }
    }
  }

  var assets: [DetailAssetRowData] = []
  var valueHistory: [CategoryValueHistoryEntry] = []
  var allocationHistory: [CategoryAllocationHistoryEntry] = []
  var conversionStatus: CurrencyConversionStatus = .notNeeded
  var loadState: DataLoadState = .idle
  private var summaries: [SnapshotSummary] = []

  init(
    category: Category,
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.category = category
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.settingsService = settingsService ?? .shared
    self.editedName = category.name
    self.editedTargetAllocation = category.targetAllocationPercentage
    if let target = category.targetAllocationPercentage {
      self.targetAllocationText = NSDecimalNumber(decimal: target).stringValue
    } else {
      self.targetAllocationText = ""
    }
  }

  // MARK: - Computed Properties

  /// Whether the category can be deleted (has no assigned assets).
  var canDelete: Bool {
    (category.assets ?? []).isEmpty
  }

  /// Explanatory text for why the category cannot be deleted, or nil if deletion is allowed.
  var deleteExplanation: String? {
    guard !canDelete else { return nil }
    let assetCount = (category.assets ?? []).count
    return CategoryError.cannotDelete(assetCount: assetCount).errorDescription
  }

  // MARK: - Load Data

  /// Loads assets, value history, and allocation history for this category.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadData() {
    withObservationTracking {
      performLoadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadData()
      }
    }
  }

  private func performLoadData() {
    do {
      let allSnapshots = try SnapshotSummaryService.fetchSnapshots(using: fetcher)
      summaries = SnapshotSummaryService.makeSummaries(
        for: allSnapshots,
        displayCurrency: settingsService.mainCurrency)
      conversionStatus = CurrencyConversionStatus.merged(
        summaries.map(\.conversionStatus))

      loadAssets(allSnapshots: allSnapshots)
      loadHistory()
      loadState = .loaded
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  // MARK: - Save

  /// Validates and saves edited properties to the category model.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with another category.
  func save() throws {
    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    if let target = editedTargetAllocation {
      guard target >= 0 && target <= 100 else { throw CategoryError.invalidTargetAllocation }
    }

    // Check for conflicts with other categories (exclude self)
    let descriptor = FetchDescriptor<Category>()
    let allCategories = try fetchModels(
      descriptor,
      from: fetcher,
      operation: "validate category")

    let hasConflict = allCategories.contains { other in
      other.id != category.id
        && other.name.lowercased() == trimmed.lowercased()
    }

    if hasConflict {
      throw CategoryError.duplicateName(trimmed)
    }

    category.name = trimmed
    category.targetAllocationPercentage = editedTargetAllocation
  }

  // MARK: - Delete

  /// Deletes the category from the model context.
  /// Only call when `canDelete` is true.
  func deleteCategory() {
    modelContext.delete(category)
  }

  // MARK: - Private Helpers

  /// Loads assets in this category with their latest values.
  private func loadAssets(allSnapshots: [Snapshot]) {
    let categoryAssets = category.assets ?? []
    let displayCurrency = settingsService.mainCurrency
    let latestExchangeRate = allSnapshots.last?.exchangeRate
    let latestSnapshotDate = allSnapshots.last?.date

    // Build latest value lookup from most recent snapshot
    var latestValueLookup: [UUID: Decimal] = [:]
    if let latestSnapshot = allSnapshots.last {
      for sav in latestSnapshot.assetValues ?? [] {
        guard let asset = sav.asset else { continue }
        latestValueLookup[asset.id] = sav.marketValue
      }
    }

    assets =
      categoryAssets.map { asset in
        let value = latestValueLookup[asset.id]
        let assetCurrency = asset.currency
        let effectiveCurrency = assetCurrency.isEmpty ? displayCurrency : assetCurrency
        let converted: Decimal? =
          if let value, let snapshotDate = latestSnapshotDate,
            effectiveCurrency != displayCurrency
          {
            CurrencyConversionService.convert(
              value: value,
              from: effectiveCurrency,
              to: displayCurrency,
              using: latestExchangeRate,
              forSnapshotDate: snapshotDate)
          } else {
            nil
          }
        return DetailAssetRowData(
          asset: asset,
          latestValue: value,
          convertedValue: converted
        )
      }
      .sorted {
        $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
      }
  }

  /// Computes value and allocation history across all snapshots.
  ///
  /// **Note:** Values reflect **current** category membership applied retroactively.
  /// The data model does not track historical category assignments, so an asset
  /// moved between categories will appear in its current category for all past snapshots.
  private func loadHistory() {
    var valueEntries: [CategoryValueHistoryEntry] = []
    var allocationEntries: [CategoryAllocationHistoryEntry] = []

    for summary in summaries {
      let categoryValue = summary.categoryValues[category.name] ?? 0
      valueEntries.append(
        CategoryValueHistoryEntry(date: summary.date, totalValue: categoryValue))

      let allocation = CalculationService.categoryAllocation(
        categoryValue: categoryValue, totalValue: summary.totalValue)
      allocationEntries.append(
        CategoryAllocationHistoryEntry(date: summary.date, allocationPercentage: allocation))
    }

    valueHistory = valueEntries
    allocationHistory = allocationEntries
  }
}
