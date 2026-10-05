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
import Testing

@testable import AssetFlow

@Suite("RebalancingViewModel Tests")
@MainActor
struct RebalancingViewModelTests {

  // MARK: - Test Helpers

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
  }

  private func makeTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    return TestContext(container: container, context: container.mainContext)
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  @discardableResult
  private func createAssetWithValue(
    name: String,
    platform: String,
    category: AssetFlow.Category?,
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: platform)
    asset.category = category
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  /// Creates a standard test scenario with two categories (Equities 60%, Bonds 40%)
  /// and a snapshot with assets totaling $10,000.
  private func createStandardScenario(context: ModelContext) -> (
    equities: AssetFlow.Category, bonds: AssetFlow.Category, snapshot: Snapshot
  ) {
    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    let bonds = AssetFlow.Category(
      name: "Bonds", targetAllocationPercentage: 40)
    context.insert(equities)
    context.insert(bonds)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    // Equities: $7,000 (70% of $10,000) — target 60%, should sell $1,000
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 5000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "MSFT", platform: "Firstrade", category: equities,
      marketValue: 2000, snapshot: snapshot, context: context)

    // Bonds: $3,000 (30% of $10,000) — target 40%, should buy $1,000
    createAssetWithValue(
      name: "BND", platform: "Vanguard", category: bonds,
      marketValue: 3000, snapshot: snapshot, context: context)

    return (equities, bonds, snapshot)
  }

  // MARK: - Loading

  @Test("Loads current allocation from latest snapshot direct values")
  func loadsCurrentAllocationFromLatestSnapshotDirectValues() {
    let tc = makeTestContext()
    let context = tc.context
    _ = createStandardScenario(context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.totalPortfolioValue == 10000)
    #expect(viewModel.suggestions.count == 2)
  }

  @Test("Uses target allocations from categories")
  func usesTargetAllocationsFromCategories() {
    let tc = makeTestContext()
    let context = tc.context
    _ = createStandardScenario(context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    let bondsSuggestion = viewModel.suggestions.first { $0.categoryName == "Bonds" }
    let equitiesSuggestion = viewModel.suggestions.first { $0.categoryName == "Equities" }

    #expect(bondsSuggestion?.targetPercentage == 40)
    #expect(equitiesSuggestion?.targetPercentage == 60)
  }

  @Test("Suggestions sorted by absolute magnitude")
  func suggestionsSortedByAbsoluteMagnitude() {
    let tc = makeTestContext()
    let context = tc.context
    _ = createStandardScenario(context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    // Both adjustments are $1,000 in absolute value, so order is stable from calculator
    #expect(viewModel.suggestions.count == 2)
    let firstAbs = abs(viewModel.suggestions[0].difference)
    let secondAbs = abs(viewModel.suggestions[1].difference)
    #expect(firstAbs >= secondAbs)
  }

  @Test("Summary text generated for buy/sell")
  func summaryTextGeneratedForBuySell() {
    let tc = makeTestContext()
    let context = tc.context
    _ = createStandardScenario(context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    // Should have at least one summary text
    #expect(!viewModel.summaryTexts.isEmpty)
  }

  // MARK: - Categories Without Target

  @Test("Categories without target shown separately")
  func categoriesWithoutTargetShownSeparately() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    let crypto = AssetFlow.Category(name: "Crypto")  // no target
    context.insert(equities)
    context.insert(crypto)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 7000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BTC", platform: "Coinbase", category: crypto,
      marketValue: 3000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.noTargetRows.count == 1)
    #expect(viewModel.noTargetRows[0].categoryName == "Crypto")
    #expect(viewModel.noTargetRows[0].currentValue == 3000)
  }

  // MARK: - Uncategorized Assets

  @Test("Uncategorized assets shown with current value and percentage")
  func uncategorizedAssetsShownWithCurrentValueAndPercentage() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    context.insert(equities)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 7000, snapshot: snapshot, context: context)
    // Uncategorized asset
    createAssetWithValue(
      name: "GOLD", platform: "Other", category: nil,
      marketValue: 3000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.uncategorizedRow != nil)
    #expect(viewModel.uncategorizedRow?.currentValue == 3000)
    #expect(viewModel.uncategorizedRow?.currentPercentage == 30)  // 3000/10000 * 100
  }

  // MARK: - $1 Threshold

  @Test("Adjustments under $1 display No action needed")
  func adjustmentsUnderDollarOneDisplayNoActionNeeded() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 70)
    let bonds = AssetFlow.Category(
      name: "Bonds", targetAllocationPercentage: 30)
    context.insert(equities)
    context.insert(bonds)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    // Nearly perfect allocation: 70.005% vs 29.995%
    // Equities: 7000.50 out of 10001 = ~70.00% — adjustment < $1
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 7000.50, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard", category: bonds,
      marketValue: 3000.50, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    // All suggestions with < $1 adjustment should show "No action needed"
    for suggestion in viewModel.suggestions {
      if abs(suggestion.difference) < 1 {
        #expect(
          suggestion.actionText
            == String(
              localized:
                "Small adjustment: \(CategoryGoalPresentation.amount(suggestion.difference, currency: SettingsService.shared.mainCurrency))",
              table: "Rebalancing"))
      }
    }
  }

  // MARK: - Empty States

  @Test("Empty state when no categories have targets")
  func emptyStateWhenNoCategoriesHaveTargets() {
    let tc = makeTestContext()
    let context = tc.context

    let crypto = AssetFlow.Category(name: "Crypto")  // no target
    context.insert(crypto)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "BTC", platform: "Coinbase", category: crypto,
      marketValue: 5000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.suggestions.isEmpty)
    #expect(viewModel.noTargetRows.count == 1)
  }

  @Test("Empty state when no snapshots")
  func emptyStateWhenNoSnapshots() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    context.insert(equities)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.isEmpty)
    #expect(viewModel.suggestions.isEmpty)
  }

  @Test("Handles zero portfolio value")
  func handlesZeroPortfolioValue() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    context.insert(equities)

    // Snapshot exists but with no asset values
    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(viewModel.totalPortfolioValue == 0)
    #expect(viewModel.suggestions.isEmpty)
  }

  // MARK: - Filtering

  @Test("Only categories with targets in main suggestions table")
  func onlyCategoriesWithTargetsInMainSuggestionsTable() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 60)
    let bonds = AssetFlow.Category(
      name: "Bonds", targetAllocationPercentage: 40)
    let crypto = AssetFlow.Category(name: "Crypto")  // no target
    context.insert(equities)
    context.insert(bonds)
    context.insert(crypto)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 5000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard", category: bonds,
      marketValue: 3000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BTC", platform: "Coinbase", category: crypto,
      marketValue: 2000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    // Only Equities and Bonds (with targets) in suggestions
    #expect(viewModel.suggestions.count == 2)
    #expect(
      viewModel.suggestions.allSatisfy { s in
        s.categoryName == "Equities" || s.categoryName == "Bonds"
      })
    // Crypto in noTargetRows
    #expect(viewModel.noTargetRows.count == 1)
    #expect(viewModel.noTargetRows[0].categoryName == "Crypto")
  }

  // MARK: - Percentage Computation

  @Test("Current percentage computed correctly")
  func currentPercentageComputedCorrectly() {
    let tc = makeTestContext()
    let context = tc.context
    _ = createStandardScenario(context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    let equitiesSuggestion = viewModel.suggestions.first { $0.categoryName == "Equities" }
    let bondsSuggestion = viewModel.suggestions.first { $0.categoryName == "Bonds" }

    // Equities: 7000 / 10000 * 100 = 70
    #expect(equitiesSuggestion?.currentPercentage == 70)
    // Bonds: 3000 / 10000 * 100 = 30
    #expect(bondsSuggestion?.currentPercentage == 30)
  }

  @Test("Multiple buy/sell summary texts")
  func multipleBuySellSummaryTexts() {
    let tc = makeTestContext()
    let context = tc.context

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 40)
    let bonds = AssetFlow.Category(
      name: "Bonds", targetAllocationPercentage: 30)
    let crypto = AssetFlow.Category(
      name: "Crypto", targetAllocationPercentage: 30)
    context.insert(equities)
    context.insert(bonds)
    context.insert(crypto)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    // Equities: $6000 (60% of $10000) — target 40%, oversized
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 6000, snapshot: snapshot, context: context)
    // Bonds: $2000 (20%) — target 30%, undersized
    createAssetWithValue(
      name: "BND", platform: "Vanguard", category: bonds,
      marketValue: 2000, snapshot: snapshot, context: context)
    // Crypto: $2000 (20%) — target 30%, undersized
    createAssetWithValue(
      name: "BTC", platform: "Coinbase", category: crypto,
      marketValue: 2000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    // Should have summary texts for the suggested moves
    #expect(!viewModel.summaryTexts.isEmpty)
    // Equities should be "Sell", Bonds and Crypto should be "Buy"
    let sellSuggestion = viewModel.suggestions.first { $0.categoryName == "Equities" }
    let buyBonds = viewModel.suggestions.first { $0.categoryName == "Bonds" }
    let buyCrypto = viewModel.suggestions.first { $0.categoryName == "Crypto" }

    #expect(sellSuggestion?.actionType == .sell)
    #expect(buyBonds?.actionType == .buy)
    #expect(buyCrypto?.actionType == .buy)
  }

  @Test("Summary texts do not overcount with multiple sells and buys")
  func summaryTextsDoNotOvercountWithMultipleSellsAndBuys() {
    let tc = makeTestContext()
    let context = tc.context

    // 2 sell + 2 buy categories to trigger Cartesian overcounting bug.
    // Total = $10,000
    //
    // Equities: target 10%, actual 40% ($4,000) → sell $3,000
    // RealEstate: target 10%, actual 20% ($2,000) → sell $1,000
    // Bonds: target 40%, actual 20% ($2,000) → buy $2,000
    // Crypto: target 40%, actual 20% ($2,000) → buy $2,000
    //
    // Total sell = $4,000, Total buy = $4,000
    //
    // Cartesian (WRONG): 4 pairs × min amounts = $3k + $3k + $1k + $1k = $8,000
    // Greedy (CORRECT): 3 texts totaling $4,000

    let equities = AssetFlow.Category(
      name: "Equities", targetAllocationPercentage: 10)
    let realEstate = AssetFlow.Category(
      name: "RealEstate", targetAllocationPercentage: 10)
    let bonds = AssetFlow.Category(
      name: "Bonds", targetAllocationPercentage: 40)
    let crypto = AssetFlow.Category(
      name: "Crypto", targetAllocationPercentage: 40)
    context.insert(equities)
    context.insert(realEstate)
    context.insert(bonds)
    context.insert(crypto)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "SPY", platform: "Firstrade", category: equities,
      marketValue: 4000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "REIT", platform: "Firstrade", category: realEstate,
      marketValue: 2000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard", category: bonds,
      marketValue: 2000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BTC", platform: "Coinbase", category: crypto,
      marketValue: 2000, snapshot: snapshot, context: context)

    let viewModel = RebalancingViewModel(modelContext: context)
    viewModel.loadRebalancing()

    #expect(!viewModel.summaryTexts.isEmpty)

    // With Cartesian product: 4 summary texts (2 sells × 2 buys), total $8,000
    // With greedy matching: 3 summary texts, total $4,000
    // Greedy: Equities→Bonds $2k, Equities→Crypto $1k, RealEstate→Crypto $1k
    #expect(
      viewModel.summaryTexts.count <= 3,
      "Cartesian product produces 4 texts; greedy should produce at most 3")
  }
}
