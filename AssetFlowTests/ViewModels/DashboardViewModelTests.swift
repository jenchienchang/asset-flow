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

@Suite("DashboardViewModel Tests")
@MainActor
struct DashboardViewModelTests {

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

  // MARK: - Empty State

  @Test("Empty state when no snapshots exist")
  func emptyState() {
    let tc = createTestContext()
    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.isEmpty)
    #expect(viewModel.totalPortfolioValue == 0)
    #expect(viewModel.latestSnapshotDate == nil)
    #expect(viewModel.assetCount == 0)
    #expect(viewModel.cumulativeTWR == nil)
    #expect(viewModel.cagr == nil)
    #expect(viewModel.recentSnapshots.isEmpty)
  }

  // MARK: - Summary Cards

  @Test("Total portfolio value from stored values in latest snapshot")
  func totalPortfolioValueFromDirectValues() {
    let tc = createTestContext()

    // Snapshot 1: Platform A has asset worth 100,000
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    // Snapshot 2: Only BTC on Coinbase — AAPL is NOT included (no carry-forward)
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("BTC", "Coinbase", 50_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Total = only direct values in latest snapshot = 50,000
    #expect(viewModel.totalPortfolioValue == 50_000)
  }

  @Test("Latest snapshot date is correct")
  func latestSnapshotDate() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 10_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 6, day: 15),
      assets: [("AAPL", "Firstrade", 12_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.latestSnapshotDate == makeDate(year: 2025, month: 6, day: 15))
  }

  @Test("Asset count from latest snapshot direct values only")
  func assetCount() {
    let tc = createTestContext()

    // Two assets on different platforms
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", 10_000, nil),
        ("BTC", "Coinbase", 5_000, nil),
      ]
    )

    // Only update Firstrade — BTC is NOT carried forward
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 12_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Only AAPL (direct) in latest snapshot = 1
    #expect(viewModel.assetCount == 1)
  }

  // MARK: - Cumulative TWR and CAGR

  @Test("Cumulative TWR with multiple snapshots and no cash flows")
  func cumulativeTWRNoCashFlows() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 3, day: 1),
      assets: [("AAPL", "Firstrade", 121_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let twr = try! #require(viewModel.cumulativeTWR)
    // Period 1: (110,000 - 100,000) / 100,000 = 0.10
    // Period 2: (121,000 - 110,000) / 110,000 = 0.10
    // TWR = (1.10) * (1.10) - 1 = 0.21
    #expect(abs(twr - Decimal(string: "0.21")!) < Decimal(string: "0.01")!)
  }

  @Test("TWR is nil with only one snapshot")
  func twrNilWithOneSnapshot() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.cumulativeTWR == nil)
    #expect(viewModel.cagr == nil)
  }

  @Test("CAGR calculation with two snapshots")
  func cagrWithTwoSnapshots() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2024, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let cagr = try! #require(viewModel.cagr)
    // CAGR = (110,000 / 100,000) ^ (1/1) - 1 = 0.10
    #expect(abs(cagr - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
  }

  @Test("Cumulative TWR is unavailable when a period lacks a return")
  func cumulativeTWRUnavailableWhenPeriodReturnIsNil() {
    let tc = createTestContext()

    // Snapshot 1: zero value — Modified Dietz will return nil for this → next period
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 0, nil)]
    )

    // Snapshot 2: now has value
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    // Snapshot 3: grew to 110,000
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 3, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // A missing period return must not be silently treated as 0%; the complete
    // time-weighted return history is unavailable until every period converts.
    #expect(viewModel.twrHistory.isEmpty)
    #expect(viewModel.cumulativeTWR == nil)
  }

  // MARK: - Period Performance: Growth Rate

  @Test("Growth rate for a given period")
  func growthRateForPeriod() {
    let tc = createTestContext()

    // Create a snapshot 3 months ago (on or before the 3M lookback target)
    let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    let startOf3MonthsAgo = Calendar.current.startOfDay(for: threeMonthsAgo)
    createSnapshot(
      in: tc.context,
      date: startOf3MonthsAgo,
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    // Create latest snapshot today
    let today = Calendar.current.startOfDay(for: Date())
    createSnapshot(
      in: tc.context,
      date: today,
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // 3M growth uses the 3-month-ago snapshot as beginning
    let growth3M = viewModel.growthRate(for: .threeMonths)
    #expect(growth3M != nil)
    // growth = (110,000 - 100,000) / 100,000 = 0.10
    if let g = growth3M {
      #expect(abs(g - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    }
  }

  @Test("Growth rate uses distant snapshot when no closer one exists (no distance limit)")
  func growthRateUsesDistantSnapshot() {
    let tc = createTestContext()

    // Snapshot very old - more than 14 days before 1M lookback target
    // With bidirectional lookback and no distance limit, this should still be found
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2020, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let today = Calendar.current.startOfDay(for: Date())
    createSnapshot(
      in: tc.context,
      date: today,
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // 1M growth: lookback target is ~30 days ago, closest is 5+ years ago
    // With no distance limit, the distant snapshot IS used
    let growth = viewModel.growthRate(for: .oneMonth)
    #expect(growth != nil)
    // growth = (110,000 - 100,000) / 100,000 = 0.10
    if let g = growth {
      #expect(abs(g - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    }
  }

  // MARK: - Period Performance: Return Rate (Modified Dietz)

  @Test("Return rate for a period with cash flows")
  func returnRateWithCashFlows() {
    let tc = createTestContext()

    let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    let startOf3MonthsAgo = Calendar.current.startOfDay(for: threeMonthsAgo)
    createSnapshot(
      in: tc.context,
      date: startOf3MonthsAgo,
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    // Intermediate snapshot with cash flow
    let sixWeeksAgo = Calendar.current.date(byAdding: .day, value: -42, to: Date())!
    let startOf6WeeksAgo = Calendar.current.startOfDay(for: sixWeeksAgo)
    createSnapshot(
      in: tc.context,
      date: startOf6WeeksAgo,
      assets: [("AAPL", "Firstrade", 130_000, nil)],
      cashFlows: [("Deposit", 20_000)]
    )

    let today = Calendar.current.startOfDay(for: Date())
    createSnapshot(
      in: tc.context,
      date: today,
      assets: [("AAPL", "Firstrade", 140_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Return rate should be non-nil for 3M period
    let returnRate = viewModel.returnRate(for: .threeMonths)
    #expect(returnRate != nil)
  }

  @Test("Return rate returns nil when only one snapshot")
  func returnRateNilWithOneSnapshot() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.returnRate(for: .oneMonth) == nil)
    #expect(viewModel.returnRate(for: .threeMonths) == nil)
    #expect(viewModel.returnRate(for: .oneYear) == nil)
  }

  // MARK: - Category Allocation

  @Test("Category allocation for latest snapshot")
  func categoryAllocation() {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    tc.context.insert(equities)
    tc.context.insert(bonds)

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", 75_000, equities),
        ("AGG", "Firstrade", 25_000, bonds),
      ]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let allocations = viewModel.categoryAllocations
    #expect(allocations.count == 2)

    let equityAlloc = allocations.first { $0.categoryName == "Equities" }
    #expect(equityAlloc != nil)
    #expect(equityAlloc?.value == 75_000)
    // 75,000 / 100,000 * 100 = 75
    #expect(equityAlloc?.percentage == 75)
  }

  @Test("Uncategorized assets shown in allocation")
  func uncategorizedInAllocation() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let allocations = viewModel.categoryAllocations
    #expect(allocations.count == 1)
    #expect(allocations.first?.categoryName == "Uncategorized")
    #expect(allocations.first?.percentage == 100)
  }

  // MARK: - Portfolio Value History

  @Test("Portfolio value history includes all snapshots")
  func portfolioValueHistory() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 3, day: 1),
      assets: [("AAPL", "Firstrade", 120_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let history = viewModel.portfolioValueHistory
    #expect(history.count == 3)
    // Should be sorted by date ascending
    #expect(history[0].date == makeDate(year: 2025, month: 1, day: 1))
    #expect(history[0].value == 100_000)
    #expect(history[2].value == 120_000)
  }

  // MARK: - TWR History

  @Test("TWR history shows cumulative return at each snapshot")
  func twrHistory() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 3, day: 1),
      assets: [("AAPL", "Firstrade", 121_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let history = viewModel.twrHistory
    // TWR history includes 0% origin at first snapshot + subsequent points
    #expect(history.count == 3)
    // Origin point: 0% at first snapshot date
    #expect(history[0].value == 0)
    #expect(history[0].date == makeDate(year: 2025, month: 1, day: 1))
    // First TWR point: 10% cumulative
    #expect(abs(history[1].value - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    // Second TWR point: 21% cumulative
    #expect(abs(history[2].value - Decimal(string: "0.21")!) < Decimal(string: "0.01")!)
  }

  @Test("TWR history is empty with fewer than 2 snapshots")
  func twrHistoryEmptyWithOneSnapshot() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.twrHistory.isEmpty)
  }

  // MARK: - Recent Snapshots

  @Test("Recent snapshots returns last 5 newest first")
  func recentSnapshots() {
    let tc = createTestContext()

    for month in 1...7 {
      createSnapshot(
        in: tc.context,
        date: makeDate(year: 2025, month: month, day: 1),
        assets: [("AAPL", "Firstrade", Decimal(month) * 10_000, nil)]
      )
    }

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let recent = viewModel.recentSnapshots
    #expect(recent.count == 5)
    // Newest first
    #expect(recent[0].date == makeDate(year: 2025, month: 7, day: 1))
    #expect(recent[4].date == makeDate(year: 2025, month: 3, day: 1))
  }

  @Test("Recent snapshots includes total value from direct SAVs only")
  func recentSnapshotsIncludeTotal() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", 100_000, nil),
        ("BTC", "Coinbase", 50_000, nil),
      ]
    )

    // Snapshot 2 only updates Firstrade — BTC not included (no carry-forward)
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let recent = viewModel.recentSnapshots
    #expect(recent.count == 2)
    // Latest: only direct SAVs = 110,000
    #expect(recent[0].totalValue == 110_000)
  }

  // MARK: - Period Enum

  @Test("Period enum provides correct lookback months")
  func periodLookbackMonths() {
    #expect(DashboardPeriod.oneMonth.months == 1)
    #expect(DashboardPeriod.threeMonths.months == 3)
    #expect(DashboardPeriod.oneYear.months == 12)
  }

  // MARK: - Snapshot Dates

  @Test("snapshotDates returns all dates sorted ascending")
  func snapshotDatesSortedAscending() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 3, day: 1),
      assets: [("AAPL", "Firstrade", 120_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.snapshotDates.count == 3)
    #expect(viewModel.snapshotDates[0] == makeDate(year: 2025, month: 1, day: 1))
    #expect(viewModel.snapshotDates[1] == makeDate(year: 2025, month: 2, day: 1))
    #expect(viewModel.snapshotDates[2] == makeDate(year: 2025, month: 3, day: 1))
  }

  @Test("snapshotDates is empty when no snapshots")
  func snapshotDatesEmptyWhenNoSnapshots() {
    let tc = createTestContext()
    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()
    #expect(viewModel.snapshotDates.isEmpty)
  }

  // MARK: - Category Allocations for Specific Snapshot Date

  @Test(
    "categoryAllocations(forSnapshotDate:) returns correct allocations for a historical snapshot")
  func categoryAllocationsForHistoricalSnapshot() {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    tc.context.insert(equities)
    tc.context.insert(bonds)

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", 60_000, equities),
        ("AGG", "Firstrade", 40_000, bonds),
      ]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [
        ("AAPL", "Firstrade", 80_000, equities),
        ("AGG", "Firstrade", 20_000, bonds),
      ]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Check allocations for the first snapshot (60/40 split)
    let allocations = viewModel.categoryAllocations(
      forSnapshotDate: makeDate(year: 2025, month: 1, day: 1))
    #expect(allocations.count == 2)

    let equityAlloc = allocations.first { $0.categoryName == "Equities" }
    #expect(equityAlloc?.percentage == 60)

    let bondAlloc = allocations.first { $0.categoryName == "Bonds" }
    #expect(bondAlloc?.percentage == 40)
  }

  @Test("historical pie allocation uses the selected snapshot conversion status")
  func categoryAllocationConversionStatusForHistoricalSnapshot() {
    let tc = createTestContext()

    let historicalSnapshot = createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("EU Stock", "Broker", 100_000, nil)]
    )
    historicalSnapshot.assetValues?.first?.asset?.currency = "eur"

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("US Stock", "Broker", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.latestConversionStatus.isComplete)
    #expect(
      viewModel.categoryAllocationConversionStatus(
        forSnapshotDate: historicalSnapshot.date
      ) == .missingRates(["eur"])
    )
    #expect(
      viewModel.categoryAllocations(forSnapshotDate: historicalSnapshot.date).isEmpty
    )
  }

  @Test("categoryAllocations(forSnapshotDate:) returns empty for non-existent date")
  func categoryAllocationsForNonExistentDate() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let allocations = viewModel.categoryAllocations(
      forSnapshotDate: makeDate(year: 2099, month: 1, day: 1))
    #expect(allocations.isEmpty)
  }

  // MARK: - Category Value History

  @Test("categoryValueHistory contains one series per category plus Uncategorized")
  func categoryValueHistoryPerCategory() {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [
        ("AAPL", "Firstrade", 75_000, equities),
        ("BTC", "Coinbase", 25_000, nil),
      ]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let history = viewModel.categoryValueHistory
    #expect(history.count == 2)
    #expect(history["Equities"] != nil)
    #expect(history["Uncategorized"] != nil)
    #expect(history["Equities"]?.first?.value == 75_000)
    #expect(history["Uncategorized"]?.first?.value == 25_000)
  }

  @Test("categoryValueHistory tracks values across multiple snapshots")
  func categoryValueHistoryMultipleSnapshots() {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, equities)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 1),
      assets: [("AAPL", "Firstrade", 120_000, equities)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let equitySeries = viewModel.categoryValueHistory["Equities"]
    #expect(equitySeries?.count == 2)
    #expect(equitySeries?[0].value == 100_000)
    #expect(equitySeries?[1].value == 120_000)
  }

  // MARK: - Bidirectional Lookback

  @Test("Bidirectional lookback finds snapshot after target date")
  func bidirectionalLookbackFindsAfterTarget() {
    let tc = createTestContext()

    // Latest snapshot: Feb 14
    // 1M lookback target: Jan 14
    // Only other snapshot: Jan 24 (AFTER target)
    // Old behavior: N/A (only searched on-or-before). New: finds Jan 24.
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 24),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 14),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // 1M lookback from Feb 14 → target Jan 14. Closest is Jan 24 (10 days after).
    let growth = viewModel.growthRate(for: .oneMonth)
    #expect(growth != nil)
    // growth = (110,000 - 100,000) / 100,000 = 0.10
    if let g = growth {
      #expect(abs(g - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    }
  }

  @Test("Closest snapshot wins regardless of direction")
  func closestSnapshotWinsRegardlessOfDirection() {
    let tc = createTestContext()

    // Latest: Feb 14. 1M target: Jan 14.
    // Candidate A: Jan 10 (4 days before target)
    // Candidate B: Jan 20 (6 days after target)
    // Closest to target is Jan 10.
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 10),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 20),
      assets: [("AAPL", "Firstrade", 105_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 14),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Growth from Jan 10 → Feb 14: (110,000 - 100,000) / 100,000 = 0.10
    let growth = viewModel.growthRate(for: .oneMonth)
    #expect(growth != nil)
    if let g = growth {
      #expect(abs(g - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    }
  }

  @Test("Equidistant snapshots: prefer earlier one")
  func equidistantPreferEarlier() {
    let tc = createTestContext()

    // Latest: Feb 14. 1M target: Jan 14.
    // Candidate A: Jan 12 (2 days before target)
    // Candidate B: Jan 16 (2 days after target)
    // Equidistant → prefer earlier (Jan 12).
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 12),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 16),
      assets: [("AAPL", "Firstrade", 105_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 14),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    // Growth from Jan 12 → Feb 14: (110,000 - 100,000) / 100,000 = 0.10
    let growth = viewModel.growthRate(for: .oneMonth)
    #expect(growth != nil)
    if let g = growth {
      #expect(abs(g - Decimal(string: "0.1")!) < Decimal(string: "0.01")!)
    }

    // Explicitly verify the begin date is Jan 12 (not Jan 16)
    let range = viewModel.periodDateRange(for: .oneMonth)
    #expect(range?.begin == makeDate(year: 2025, month: 1, day: 12))
  }

  @Test("Return rate works when begin snapshot is after target date")
  func returnRateWithAfterTargetBegin() {
    let tc = createTestContext()

    // Latest: Feb 14. 1M target: Jan 14.
    // Begin: Jan 24 (after target). Should still compute Modified Dietz.
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 24),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    // Intermediate snapshot with cash flow
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 4),
      assets: [("AAPL", "Firstrade", 115_000, nil)],
      cashFlows: [("Deposit", 10_000)]
    )

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 14),
      assets: [("AAPL", "Firstrade", 120_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let returnRate = viewModel.returnRate(for: .oneMonth)
    #expect(returnRate != nil)
  }

  @Test("periodDateRange returns correct begin and end dates")
  func periodDateRangeReturnsCorrectDates() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 24),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )
    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 2, day: 14),
      assets: [("AAPL", "Firstrade", 110_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    let range = viewModel.periodDateRange(for: .oneMonth)
    #expect(range != nil)
    #expect(range?.begin == makeDate(year: 2025, month: 1, day: 24))
    #expect(range?.end == makeDate(year: 2025, month: 2, day: 14))
  }

  @Test("periodDateRange returns nil with only one snapshot")
  func periodDateRangeNilWithOneSnapshot() {
    let tc = createTestContext()

    createSnapshot(
      in: tc.context,
      date: makeDate(year: 2025, month: 1, day: 1),
      assets: [("AAPL", "Firstrade", 100_000, nil)]
    )

    let viewModel = DashboardViewModel(modelContext: tc.context)
    viewModel.loadData()

    #expect(viewModel.periodDateRange(for: .oneMonth) == nil)
    #expect(viewModel.periodDateRange(for: .threeMonths) == nil)
    #expect(viewModel.periodDateRange(for: .oneYear) == nil)
  }

}
