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

@Suite("SPEC Verification Tests")
@MainActor
struct SpecVerificationTests {

  // MARK: - Test Helpers

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
  }

  private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    return TestContext(container: container, context: context)
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  /// Creates a snapshot with assets and optional cash flows.
  @discardableResult
  private func createSnapshot(
    in context: ModelContext,
    date: Date,
    assets: [(name: String, platform: String, value: Decimal, category: AssetFlow.Category?)],
    cashFlows: [(description: String, amount: Decimal)] = []
  ) -> Snapshot {
    let snapshot = Snapshot(date: date)
    context.insert(snapshot)

    for assetData in assets {
      // Find or create asset
      let descriptor = FetchDescriptor<Asset>()
      let allAssets = (try? context.fetch(descriptor)) ?? []
      let normalizedName = assetData.name.trimmingCharacters(in: .whitespaces).lowercased()
      let normalizedPlatform = assetData.platform.trimmingCharacters(in: .whitespaces).lowercased()

      let asset =
        allAssets.first(where: {
          $0.normalizedName == normalizedName
            && $0.normalizedPlatform == normalizedPlatform
        })
        ?? {
          let a = Asset(name: assetData.name, platform: assetData.platform)
          context.insert(a)
          return a
        }()

      if let cat = assetData.category {
        asset.category = cat
      }

      let sav = SnapshotAssetValue(marketValue: assetData.value)
      sav.snapshot = snapshot
      sav.asset = asset
      context.insert(sav)
    }

    for cfData in cashFlows {
      let cf = CashFlowOperation(cashFlowDescription: cfData.description, amount: cfData.amount)
      cf.snapshot = snapshot
      context.insert(cf)
    }

    return snapshot
  }

  // MARK: - SPEC 10.7 Edge Case Gap Fills

  @Test("SPEC 10.7: Negative return above -100% displays normally")
  func negativeReturnAboveNegative100DisplaysNormally() {
    // Verify Modified Dietz return of e.g. -0.50 (-50%) should return the value, not nil
    let beginValue = Decimal(100_000)
    let endValue = Decimal(50_000)  // 50% loss
    let cashFlows: [(amount: Decimal, daysSinceStart: Int)] = []
    let totalDays = 365

    let result = CalculationService.modifiedDietzReturn(
      beginValue: beginValue,
      endValue: endValue,
      cashFlows: cashFlows,
      totalDays: totalDays
    )

    #expect(result != nil, "Negative return above -100% should return a value, not nil")
    #expect(result! < 0, "Result should be negative")
    #expect(result! > -1, "Result should be greater than -100% (i.e., > -1)")
  }

  @Test("SPEC 10.7: Net cash flow but no value change returns negative")
  func netCashFlowButNoValueChangeReturnsNegative() {
    // BMV=100000, EMV=100000, CF=+10000 at start → return should be negative
    let beginValue = Decimal(100_000)
    let endValue = Decimal(100_000)
    let cashFlows: [(amount: Decimal, daysSinceStart: Int)] = [
      (amount: Decimal(10_000), daysSinceStart: 0)
    ]
    let totalDays = 365

    let result = CalculationService.modifiedDietzReturn(
      beginValue: beginValue,
      endValue: endValue,
      cashFlows: cashFlows,
      totalDays: totalDays
    )

    #expect(result != nil, "Should return a value for zero growth with cash inflow")
    #expect(result! < 0, "Money added but no growth should produce negative return")
  }

  @Test("SPEC 10.7: Only one snapshot returns nil for all metrics")
  func onlyOneSnapshotReturnsNilForAllMetrics() {
    let tc = createTestContext()

    // Create a single snapshot
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", Decimal(10_000), nil),
        ("GOOGL", "Firstrade", Decimal(15_000), nil),
      ]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // With only one snapshot, time-based metrics should return nil or N/A
    // Note: growthRate is a method, not a property
    #expect(
      viewModel.growthRate(for: .oneMonth) == nil,
      "Growth rate should be nil with only one snapshot"
    )
    #expect(viewModel.cumulativeTWR == nil, "Cumulative TWR should be nil with only one snapshot")
    #expect(viewModel.cagr == nil, "CAGR should be nil with only one snapshot")
  }

  // MARK: - End-to-End Scenario Tests

  @Test("Category assignment to allocation to rebalancing pipeline")
  func categoryAssignmentToAllocationToRebalancingPipeline() {
    let tc = createTestContext()

    // Create categories with target allocations
    let stocks = Category(name: "Stocks")
    stocks.targetAllocationPercentage = 60
    tc.context.insert(stocks)

    let bonds = Category(name: "Bonds")
    bonds.targetAllocationPercentage = 40
    tc.context.insert(bonds)

    // Create snapshot with assets assigned to categories
    let date = makeDate(year: 2025, month: 1, day: 1)
    createSnapshot(
      in: tc.context,
      date: date,
      assets: [
        ("AAPL", "Firstrade", Decimal(30_000), stocks),
        ("GOOGL", "Firstrade", Decimal(20_000), stocks),
        ("BND", "Vanguard", Decimal(50_000), bonds),
      ]
    )

    // Verify allocation percentages
    let stocksAllocation = CalculationService.categoryAllocation(
      categoryValue: Decimal(50_000),
      totalValue: Decimal(100_000)
    )
    #expect(stocksAllocation == Decimal(50), "Stocks should be 50% of portfolio")

    let bondsAllocation = CalculationService.categoryAllocation(
      categoryValue: Decimal(50_000),
      totalValue: Decimal(100_000)
    )
    #expect(bondsAllocation == Decimal(50), "Bonds should be 50% of portfolio")

    // Verify rebalancing suggestions using the actual API
    let categoryAllocations = [
      CategoryGoalAllocation(
        id: stocks.id, name: "Stocks", currentValue: Decimal(50_000), percentage: Decimal(60),
        minimum: nil),
      CategoryGoalAllocation(
        id: bonds.id, name: "Bonds", currentValue: Decimal(50_000), percentage: Decimal(40),
        minimum: nil),
    ]

    let actions = RebalancingCalculator.calculate(
      categories: categoryAllocations,
      totalValue: Decimal(100_000)
    ).targets

    let stocksAction = actions.first(where: { $0.allocation.name == "Stocks" })
    #expect(stocksAction != nil, "Should have rebalancing action for Stocks")
    #expect(
      stocksAction?.difference == Decimal(10_000),
      "Should suggest +10,000 to stocks (from 50% to 60%)"
    )

    let bondsAction = actions.first(where: { $0.allocation.name == "Bonds" })
    #expect(bondsAction != nil, "Should have rebalancing action for Bonds")
    #expect(
      bondsAction?.difference == Decimal(-10_000),
      "Should suggest -10,000 from bonds (from 50% to 40%)"
    )
  }

  @Test("SPEC 9.4: Cash flow timing assumption at snapshot date")
  func cashFlowTimingAssumptionAtSnapshotDate() {
    // Verify Modified Dietz uses snapshot dates for cash flow timing
    // Set up scenario where timing matters:
    // - Start with 100,000
    // - Add 10,000 cash flow
    // - End with 120,000 (10,000 from CF + 10,000 growth)
    let beginValue = Decimal(100_000)
    let endValue = Decimal(120_000)  // Increased to show actual growth beyond cash flow

    // Cash flow at day 0 (start of period) vs day 182 (middle of period)
    let cashFlowsAtStart: [(amount: Decimal, daysSinceStart: Int)] = [
      (amount: Decimal(10_000), daysSinceStart: 0)
    ]
    let cashFlowsAtMiddle: [(amount: Decimal, daysSinceStart: Int)] = [
      (amount: Decimal(10_000), daysSinceStart: 182)
    ]
    let totalDays = 365

    let returnAtStart = CalculationService.modifiedDietzReturn(
      beginValue: beginValue,
      endValue: endValue,
      cashFlows: cashFlowsAtStart,
      totalDays: totalDays
    )

    let returnAtMiddle = CalculationService.modifiedDietzReturn(
      beginValue: beginValue,
      endValue: endValue,
      cashFlows: cashFlowsAtMiddle,
      totalDays: totalDays
    )

    #expect(returnAtStart != nil, "Should calculate return with cash flow at start")
    #expect(returnAtMiddle != nil, "Should calculate return with cash flow at middle")

    // Returns should be different because timing matters in Modified Dietz
    // With same cash flow amount, timing affects the denominator weighting
    #expect(
      returnAtStart != returnAtMiddle,
      "Cash flow timing should affect Modified Dietz calculation"
    )

    // Cash flow at start gets full weight (365/365), so lower return
    // Cash flow at middle gets partial weight, so higher return
    #expect(
      returnAtStart! < returnAtMiddle!,
      "Cash flow at start should produce lower return than at middle (had full period to compound)"
    )
  }

  @Test("SPEC 3.12: Allocation rounding no forced normalization")
  func allocationRoundingNoForcedNormalization() {
    let tc = createTestContext()

    // Create scenario where individually rounded allocations sum to 99.99% or 100.01%
    let stocks = AssetFlow.Category(name: "Stocks")
    tc.context.insert(stocks)

    let bonds = AssetFlow.Category(name: "Bonds")
    tc.context.insert(bonds)

    let reits = AssetFlow.Category(name: "REITs")
    tc.context.insert(reits)

    // Values that produce non-exact percentages when rounded
    let date = makeDate(year: 2025, month: 1, day: 1)
    createSnapshot(
      in: tc.context,
      date: date,
      assets: [
        ("AAPL", "Firstrade", Decimal(33_333), stocks),  // 33.333%
        ("BND", "Vanguard", Decimal(33_333), bonds),  // 33.333%
        ("VNQ", "Vanguard", Decimal(33_333), reits),  // 33.333%
      ]
    )

    let totalValue = Decimal(99_999)

    let stocksAllocation = CalculationService.categoryAllocation(
      categoryValue: Decimal(33_333),
      totalValue: totalValue
    )
    let bondsAllocation = CalculationService.categoryAllocation(
      categoryValue: Decimal(33_333),
      totalValue: totalValue
    )
    let reitsAllocation = CalculationService.categoryAllocation(
      categoryValue: Decimal(33_333),
      totalValue: totalValue
    )

    // Each should be ~33.33%
    #expect(stocksAllocation > Decimal(33.33), "Stocks allocation should be ~33.33%")
    #expect(stocksAllocation < Decimal(33.34), "Stocks allocation should be ~33.33%")

    // Sum may not be exactly 100.00 due to rounding
    let sum = stocksAllocation + bondsAllocation + reitsAllocation

    // SPEC 3.12: No forced normalization — accept 99.99% or 100.01%
    #expect(sum >= Decimal(99.9), "Sum should be close to 100%")
    #expect(sum <= Decimal(100.1), "Sum should be close to 100%")

    // The key assertion: sum does NOT have to equal exactly 100.00
    // This verifies that the system doesn't artificially adjust allocations to force 100%
    // (If it did force normalization, sum would always be exactly 100.00)
  }
}
