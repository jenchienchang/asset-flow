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

@Suite("AssetListViewModel Tests")
@MainActor
struct AssetListViewModelTests {

  // MARK: - Test Helpers

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
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: TestDataManager.platform(named: platform, in: context))
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  private func allAssets(in groups: [AssetGroup]) -> [AssetRowData] {
    groups.flatMap { $0.assets }
  }

  /// Builds a view model with an isolated `SettingsService`. Defaults to
  /// `hideStaleAssets = false` so legacy tests focused on grouping/listing
  /// see every asset regardless of snapshot membership.
  private func makeViewModel(
    context: ModelContext,
    hideStaleAssets: Bool = false
  ) -> AssetListViewModel {
    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = hideStaleAssets
    return AssetListViewModel(modelContext: context, settingsService: settings)
  }

  // MARK: - Listing

  @Test("Lists all assets across groups")
  func listsAllAssets() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let assetA = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    let assetB = Asset(
      name: "BTC", platform: TestDataManager.platform(named: "Binance", in: context))
    let assetC = Asset(
      name: "ETH", platform: TestDataManager.platform(named: "Binance", in: context))
    context.insert(assetA)
    context.insert(assetB)
    context.insert(assetC)

    let viewModel = makeViewModel(context: context)
    viewModel.loadAssets()

    let totalAssets = allAssets(in: viewModel.groups)
    #expect(totalAssets.count == 3)
  }

  // MARK: - Platform Grouping

  @Test("Groups assets by platform with alphabetical sort")
  func groupsByPlatformWithAlphabeticalSort() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let assetA = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    let assetB = Asset(
      name: "BTC", platform: TestDataManager.platform(named: "Binance", in: context))
    let assetC = Asset(
      name: "ETH", platform: TestDataManager.platform(named: "Binance", in: context))
    context.insert(assetA)
    context.insert(assetB)
    context.insert(assetC)

    let viewModel = makeViewModel(context: context)
    viewModel.groupingMode = .byPlatform
    viewModel.loadAssets()

    #expect(viewModel.groups.count == 2)
    #expect(viewModel.groups[0].name == "Binance")
    #expect(viewModel.groups[1].name == "Firstrade")

    // Assets within Binance group sorted alphabetically
    let binanceAssets = viewModel.groups[0].assets
    #expect(binanceAssets.count == 2)
    #expect(binanceAssets[0].asset.name == "BTC")
    #expect(binanceAssets[1].asset.name == "ETH")
  }

  // MARK: - Category Grouping

  @Test("Groups assets by category with alphabetical sort")
  func groupsByCategoryWithAlphabeticalSort() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let bonds = Category(name: "Bonds")
    let equities = Category(name: "Equities")
    context.insert(bonds)
    context.insert(equities)

    let assetA = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    assetA.category = equities
    let assetB = Asset(
      name: "Treasury", platform: TestDataManager.platform(named: "Vanguard", in: context))
    assetB.category = bonds
    context.insert(assetA)
    context.insert(assetB)

    let viewModel = makeViewModel(context: context)
    viewModel.groupingMode = .byCategory
    viewModel.loadAssets()

    #expect(viewModel.groups.count == 2)
    #expect(viewModel.groups[0].name == "Bonds")
    #expect(viewModel.groups[1].name == "Equities")
  }

  // MARK: - No Platform Group

  @Test("Assets without platform appear in (No Platform) group positioned last")
  func assetsWithoutPlatformInNoPlatformGroup() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let assetA = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    let assetB = Asset(name: "Gold", platform: TestDataManager.platform(named: "", in: context))
    context.insert(assetA)
    context.insert(assetB)

    let viewModel = makeViewModel(context: context)
    viewModel.groupingMode = .byPlatform
    viewModel.loadAssets()

    #expect(viewModel.groups.count == 2)
    // "(No Platform)" should be last
    #expect(viewModel.groups[0].name == "Firstrade")
    #expect(viewModel.groups[1].name == String(localized: "(No Platform)", table: "Asset"))
    #expect(viewModel.groups[1].assets.count == 1)
    #expect(viewModel.groups[1].assets[0].asset.name == "Gold")
  }

  // MARK: - Uncategorized Group

  @Test("Assets without category appear in (Uncategorized) group positioned last")
  func assetsWithoutCategoryInUncategorizedGroup() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let assetA = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    assetA.category = equities
    let assetB = Asset(name: "Gold", platform: TestDataManager.platform(named: "", in: context))
    // assetB has no category
    context.insert(assetA)
    context.insert(assetB)

    let viewModel = makeViewModel(context: context)
    viewModel.groupingMode = .byCategory
    viewModel.loadAssets()

    #expect(viewModel.groups.count == 2)
    #expect(viewModel.groups[0].name == "Equities")
    #expect(viewModel.groups[1].name == String(localized: "(Uncategorized)", table: "Asset"))
    #expect(viewModel.groups[1].assets.count == 1)
    #expect(viewModel.groups[1].assets[0].asset.name == "Gold")
  }

  // MARK: - Latest Value

  @Test("Latest value computed from stored values in latest snapshot")
  func latestValueComputedFromStoredValuesInLatestSnapshot() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    let asset = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    context.insert(asset)
    let sav1 = SnapshotAssetValue(marketValue: 10000)
    sav1.snapshot = snap1
    sav1.asset = asset
    context.insert(sav1)

    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    let sav2 = SnapshotAssetValue(marketValue: 15000)
    sav2.snapshot = snap2
    sav2.asset = asset
    context.insert(sav2)

    let viewModel = makeViewModel(context: context)
    viewModel.loadAssets()

    let rows = allAssets(in: viewModel.groups)
    #expect(rows.count == 1)
    #expect(rows[0].latestValue == Decimal(15000))
  }

  @Test("Latest value is nil when asset has no snapshot values")
  func latestValueNilWhenAssetHasNoSnapshotValues() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(name: "NewAsset", platform: TestDataManager.platform(named: "", in: context))
    context.insert(asset)

    let viewModel = makeViewModel(context: context)
    viewModel.loadAssets()

    let rows = allAssets(in: viewModel.groups)
    #expect(rows.count == 1)
    #expect(rows[0].latestValue == nil)
  }

  // MARK: - Deletion

  @Test("Delete succeeds when asset has no snapshot values")
  func deleteSucceedsWhenNoSnapshotValues() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(name: "Deletable", platform: TestDataManager.platform(named: "", in: context))
    context.insert(asset)

    let viewModel = makeViewModel(context: context)
    try viewModel.deleteAsset(asset)

    let descriptor = FetchDescriptor<Asset>()
    let remaining = try context.fetch(descriptor)
    #expect(remaining.isEmpty)
  }

  @Test("Delete blocked when snapshot values exist")
  func deleteBlockedWhenSnapshotValuesExist() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (asset, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)

    let viewModel = makeViewModel(context: context)

    #expect(throws: AssetError.self) {
      try viewModel.deleteAsset(asset)
    }
  }

  @Test("Delete blocked message includes snapshot count")
  func deleteBlockedMessageIncludesSnapshotCount() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(
      name: "Multi", platform: TestDataManager.platform(named: "Firstrade", in: context))
    context.insert(asset)

    // Create 3 snapshots with values for this asset
    for month in 1...3 {
      let snap = Snapshot(date: makeDate(year: 2025, month: month, day: 1))
      context.insert(snap)
      let sav = SnapshotAssetValue(marketValue: Decimal(month * 1000))
      sav.snapshot = snap
      sav.asset = asset
      context.insert(sav)
    }

    let viewModel = makeViewModel(context: context)

    do {
      try viewModel.deleteAsset(asset)
      Issue.record("Expected AssetError.cannotDelete to be thrown")
    } catch let error as AssetError {
      #expect(error == .cannotDelete(snapshotCount: 3))
    }
  }

  @Test("Delete counts distinct snapshots, not SAV records")
  func deleteCountsDistinctSnapshotsNotSAVRecords() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(
      name: "Multi", platform: TestDataManager.platform(named: "Firstrade", in: context))
    context.insert(asset)

    // Create 1 snapshot with 2 SAVs for the same asset
    // (simulating e.g. two value entries in the same snapshot)
    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)

    let sav1 = SnapshotAssetValue(marketValue: 1000)
    sav1.snapshot = snap
    sav1.asset = asset
    context.insert(sav1)

    let sav2 = SnapshotAssetValue(marketValue: 2000)
    sav2.snapshot = snap
    sav2.asset = asset
    context.insert(sav2)

    let viewModel = makeViewModel(context: context)

    do {
      try viewModel.deleteAsset(asset)
      Issue.record("Expected AssetError.cannotDelete to be thrown")
    } catch let error as AssetError {
      // Should count 1 distinct snapshot, not 2 SAV records
      #expect(error == .cannotDelete(snapshotCount: 1))
    }
  }

  // MARK: - Empty State

  @Test("Empty state when no assets exist")
  func emptyStateWhenNoAssets() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = makeViewModel(context: context)
    viewModel.loadAssets()

    #expect(viewModel.groups.isEmpty)
  }

  // MARK: - Hide Stale Assets Filter

  @Test("Filter hides assets missing from the latest snapshot when enabled")
  func loadAssets_filtersStaleAssets_whenHideEnabled() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (active, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 1000,
      snapshot: snap, context: context)
    let stale = Asset(
      name: "OLD", platform: TestDataManager.platform(named: "Firstrade", in: context))
    context.insert(stale)

    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = true
    let viewModel = AssetListViewModel(modelContext: context, settingsService: settings)
    viewModel.loadAssets()

    let visible = allAssets(in: viewModel.groups)
    #expect(visible.count == 1)
    #expect(visible.first?.asset.id == active.id)
    #expect(viewModel.hasHiddenStaleAssets == true)
  }

  @Test("Filter shows all assets when disabled")
  func loadAssets_includesStaleAssets_whenHideDisabled() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 1000,
      snapshot: snap, context: context)
    let stale = Asset(
      name: "OLD", platform: TestDataManager.platform(named: "Firstrade", in: context))
    context.insert(stale)

    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = false
    let viewModel = AssetListViewModel(modelContext: context, settingsService: settings)
    viewModel.loadAssets()

    let visible = allAssets(in: viewModel.groups)
    #expect(visible.count == 2)
    #expect(viewModel.hasHiddenStaleAssets == false)
  }

  @Test("hasHiddenStaleAssets stays false when no asset is stale even with filter on")
  func loadAssets_hasHiddenStaleAssetsFalseWhenNoStale() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 1000,
      snapshot: snap, context: context)
    createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 2000,
      snapshot: snap, context: context)

    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = true
    let viewModel = AssetListViewModel(modelContext: context, settingsService: settings)
    viewModel.loadAssets()

    #expect(allAssets(in: viewModel.groups).count == 2)
    #expect(viewModel.hasHiddenStaleAssets == false)
  }

  @Test("Groups empty and hasHiddenStaleAssets true when every asset is stale and filter on")
  func loadAssets_emptyVisibleGroupsWhenAllStaleAndHidden() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let staleA = Asset(
      name: "OLD-A", platform: TestDataManager.platform(named: "Firstrade", in: context))
    let staleB = Asset(
      name: "OLD-B", platform: TestDataManager.platform(named: "Binance", in: context))
    context.insert(staleA)
    context.insert(staleB)

    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = true
    let viewModel = AssetListViewModel(modelContext: context, settingsService: settings)
    viewModel.loadAssets()

    #expect(viewModel.groups.isEmpty)
    #expect(viewModel.hasHiddenStaleAssets == true)
  }
}
