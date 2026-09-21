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

/// Data for a rebalancing suggestion row (categories with target allocations).
struct RebalancingRowData: Identifiable {
  var id: String { categoryName }
  let categoryName: String
  let currentValue: Decimal
  let currentPercentage: Decimal
  let targetPercentage: Decimal
  let difference: Decimal
  let actionText: String
  let actionType: RebalancingActionType
}

/// Data for a category row without a target allocation.
struct NoTargetRowData: Identifiable {
  var id: String { categoryName }
  let categoryName: String
  let currentValue: Decimal
  let currentPercentage: Decimal
}

/// Data for the uncategorized assets row.
struct UncategorizedRowData {
  let currentValue: Decimal
  let currentPercentage: Decimal
}

/// ViewModel for the Rebalancing screen.
///
/// Loads current and target allocations, computes rebalancing suggestions
/// using `RebalancingCalculator`, and presents results for display.
/// This is a read-only view — no data modification.
@Observable
@MainActor
final class RebalancingViewModel {
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching

  var suggestions: [RebalancingRowData] = []
  var noTargetRows: [NoTargetRowData] = []
  var uncategorizedRow: UncategorizedRowData?
  var summaryTexts: [String] = []
  var totalPortfolioValue: Decimal = 0
  var conversionStatus: CurrencyConversionStatus = .notNeeded
  var loadState: DataLoadState = .idle

  var isEmpty: Bool {
    if case .failed = loadState { return false }
    return suggestions.isEmpty && noTargetRows.isEmpty && uncategorizedRow == nil
      && conversionStatus.isComplete
  }

  init(modelContext: ModelContext, fetcher: (any ModelFetching)? = nil) {
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
  }

  // MARK: - Loading

  /// Loads all rebalancing data from the latest snapshot.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadRebalancing() {
    loadState = .loading
    withObservationTracking {
      performLoadRebalancing()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadRebalancing()
      }
    }
  }

  private func performLoadRebalancing() {
    defer {
      if case .loading = loadState { loadState = .loaded }
    }

    do {
      let allCategories = try fetchAllCategories()

      // Clear state
      suggestions = []
      noTargetRows = []
      uncategorizedRow = nil
      summaryTexts = []
      totalPortfolioValue = 0
      conversionStatus = .notNeeded

      guard
        let latestSnapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      else { return }

      conversionStatus =
        CurrencyConversionService.totalValueReport(
          for: latestSnapshot,
          displayCurrency: SettingsService.shared.mainCurrency,
          exchangeRate: latestSnapshot.exchangeRate
        ).status

      let displayCurrency = SettingsService.shared.mainCurrency
      guard
        let totalPortfolioValue = CurrencyConversionService.totalValue(
          for: latestSnapshot, displayCurrency: displayCurrency,
          exchangeRate: latestSnapshot.exchangeRate)
      else { return }
      self.totalPortfolioValue = totalPortfolioValue

      guard totalPortfolioValue > 0 else { return }

      // Group values by category with currency conversion
      guard
        let catValues = CurrencyConversionService.categoryValues(
          for: latestSnapshot, displayCurrency: displayCurrency,
          exchangeRate: latestSnapshot.exchangeRate)
      else { return }

      var categoryValueLookup: [String: Decimal] = [:]
      var uncategorizedValue: Decimal = 0

      for (name, value) in catValues {
        if name.isEmpty {
          uncategorizedValue += value
        } else {
          categoryValueLookup[name, default: 0] += value
        }
      }

      // Build CategoryAllocation array for the calculator
      let categoryAllocations: [CategoryAllocation] = allCategories.map { category in
        CategoryAllocation(
          name: category.name,
          currentValue: categoryValueLookup[category.name] ?? 0,
          targetPercentage: category.targetAllocationPercentage
        )
      }

      // Calculate rebalancing actions (only categories with targets)
      let actions = RebalancingCalculator.calculateAdjustments(
        categories: categoryAllocations, totalValue: totalPortfolioValue)

      let currency = SettingsService.shared.mainCurrency

      suggestions = buildSuggestionRows(actions: actions, currency: currency)

      noTargetRows = buildNoTargetRows(
        categories: allCategories,
        categoryValues: categoryValueLookup)

      if uncategorizedValue > 0 {
        let percentage = CalculationService.categoryAllocation(
          categoryValue: uncategorizedValue, totalValue: totalPortfolioValue)
        uncategorizedRow = UncategorizedRowData(
          currentValue: uncategorizedValue,
          currentPercentage: percentage
        )
      }

      summaryTexts = buildSummaryTexts(actions: actions, currency: currency)
    } catch {
      loadState = .failed(error.localizedDescription)
    }
  }

  // MARK: - Private Helpers

  /// Maps calculator actions to display row data with localized action text.
  private func buildSuggestionRows(
    actions: [RebalancingAction], currency: String
  ) -> [RebalancingRowData] {
    actions.map { action in
      let actionText: String
      switch action.action {
      case .buy:
        actionText = String(
          localized: "Buy \(abs(action.adjustmentAmount).formatted(currency: currency))",
          table: "Rebalancing")

      case .sell:
        actionText = String(
          localized: "Sell \(abs(action.adjustmentAmount).formatted(currency: currency))",
          table: "Rebalancing")

      case .noAction:
        actionText = String(localized: "No action needed", table: "Rebalancing")
      }

      return RebalancingRowData(
        categoryName: action.categoryName,
        currentValue: action.currentValue,
        currentPercentage: action.currentPercentage,
        targetPercentage: action.targetPercentage,
        difference: action.adjustmentAmount,
        actionText: actionText,
        actionType: action.action
      )
    }
  }

  /// Builds rows for categories without target allocations.
  private func buildNoTargetRows(
    categories: [Category],
    categoryValues: [String: Decimal]
  ) -> [NoTargetRowData] {
    categories
      .filter { $0.targetAllocationPercentage == nil }
      .map { category in
        let value = categoryValues[category.name] ?? 0
        let percentage = CalculationService.categoryAllocation(
          categoryValue: value, totalValue: totalPortfolioValue)
        return NoTargetRowData(
          categoryName: category.name,
          currentValue: value,
          currentPercentage: percentage
        )
      }
      .sorted {
        $0.categoryName.localizedCaseInsensitiveCompare($1.categoryName) == .orderedAscending
      }
  }

  private func fetchAllCategories() throws -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return try fetchModels(descriptor, from: fetcher, operation: "fetch categories")
  }

  /// Builds human-readable summary texts pairing sell and buy categories
  /// using greedy matching to avoid overcounting.
  private func buildSummaryTexts(
    actions: [RebalancingAction], currency: String
  ) -> [String] {
    let sellActions = actions.filter { $0.action == .sell }
      .sorted { abs($0.adjustmentAmount) > abs($1.adjustmentAmount) }
    let buyActions = actions.filter { $0.action == .buy }
      .sorted { $0.adjustmentAmount > $1.adjustmentAmount }

    guard !sellActions.isEmpty && !buyActions.isEmpty else { return [] }

    // Track remaining capacity for each sell/buy
    var sellRemaining = sellActions.map { abs($0.adjustmentAmount) }
    var buyRemaining = buyActions.map { $0.adjustmentAmount }

    var texts: [String] = []
    for (sellIndex, sellAction) in sellActions.enumerated() {
      for (buyIndex, buyAction) in buyActions.enumerated() {
        let amount = min(sellRemaining[sellIndex], buyRemaining[buyIndex])
        if amount >= 1 {
          sellRemaining[sellIndex] -= amount
          buyRemaining[buyIndex] -= amount
          texts.append(
            String(
              localized:
                "Move \(amount.formatted(currency: currency)) from \(sellAction.categoryName) to \(buyAction.categoryName)",
              table: "Rebalancing"))
        }
      }
    }

    return texts
  }
}
