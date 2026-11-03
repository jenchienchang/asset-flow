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

@Suite("PlatformListViewModel Tests")
@MainActor
struct PlatformListViewModelTests {

  // MARK: - Test Helpers

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let settingsService: SettingsService
  }

  private func makeTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let settingsService = SettingsService.createForTesting()
    return TestContext(
      container: container, context: container.mainContext,
      settingsService: settingsService)
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  @discardableResult
  private func createAsset(
    name: String, platform: String, in context: ModelContext
  ) -> Asset {
    let asset = Asset(name: name, platform: TestDataManager.platform(named: platform, in: context))
    context.insert(asset)
    return asset
  }

  @discardableResult
  private func createAssetWithValue(
    name: String,
    platform: String,
    category: AssetFlow.Category? = nil,
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: TestDataManager.platform(named: platform, in: context))
    asset.category = category
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  @Test("Equivalent platform spellings form one platform")
  func normalizedPlatformIdentity() {
    let tc = makeTestContext()
    createAsset(name: "Stock", platform: "Broker One", in: tc.context)
    createAsset(name: "Bond", platform: " broker   ONE ", in: tc.context)
    let viewModel = PlatformListViewModel(
      modelContext: tc.context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()
    #expect(viewModel.platformRows.count == 1)
    #expect(viewModel.platformRows.first?.assetCount == 2)
  }

  @Test("Rename preserves platform order and default import selection")
  func renamePreservesPreferences() throws {
    let tc = makeTestContext()
    createAsset(name: "Stock", platform: "Alpha", in: tc.context)
    createAsset(name: "Bond", platform: "Beta", in: tc.context)
    let platforms = try tc.context.fetch(FetchDescriptor<Platform>())
    platforms.first { $0.name == "Beta" }?.displayOrder = 0
    platforms.first { $0.name == "Alpha" }?.displayOrder = 1
    tc.settingsService.defaultPlatform = " beta "
    let viewModel = PlatformListViewModel(
      modelContext: tc.context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()
    let originalID = try #require(viewModel.platformRows.first).id
    try viewModel.renamePlatform(id: originalID, to: "Gamma")
    viewModel.loadPlatforms()
    #expect(viewModel.platformRows.first?.name == "Gamma")
    #expect(viewModel.platformRows.first?.id == originalID)
    #expect(tc.settingsService.defaultPlatform == "Gamma")
  }

  // MARK: - Listing

  @Test("Lists platforms alphabetically")
  func listsPlatformsAlphabetically() {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)
    createAsset(name: "BND", platform: "Vanguard", in: context)
    createAsset(name: "BTC", platform: "Coinbase", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    #expect(viewModel.platformRows.count == 3)
    #expect(viewModel.platformRows[0].name == "Coinbase")
    #expect(viewModel.platformRows[1].name == "Firstrade")
    #expect(viewModel.platformRows[2].name == "Vanguard")
  }

  @Test("Computes asset count per platform")
  func computesAssetCountPerPlatform() {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)
    createAsset(name: "MSFT", platform: "Firstrade", in: context)
    createAsset(name: "BND", platform: "Vanguard", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    let firstrade = viewModel.platformRows.first { $0.name == "Firstrade" }
    let vanguard = viewModel.platformRows.first { $0.name == "Vanguard" }
    #expect(firstrade?.assetCount == 2)
    #expect(vanguard?.assetCount == 1)
  }

  @Test("Computes total value from latest snapshot direct values")
  func computesTotalValueFromLatestSnapshotDirectValues() {
    let tc = makeTestContext()
    let context = tc.context

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade",
      marketValue: 5000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "MSFT", platform: "Firstrade",
      marketValue: 3000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard",
      marketValue: 2000, snapshot: snapshot, context: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    let firstrade = viewModel.platformRows.first { $0.name == "Firstrade" }
    let vanguard = viewModel.platformRows.first { $0.name == "Vanguard" }
    #expect(firstrade?.totalValue == 8000)
    #expect(vanguard?.totalValue == 2000)
  }

  // MARK: - Rename

  @Test("Rename updates all assets with old platform name")
  func renameUpdatesAllAssetsWithOldPlatformName() throws {
    let tc = makeTestContext()
    let context = tc.context

    let asset1 = createAsset(name: "AAPL", platform: "Firstrade", in: context)
    let asset2 = createAsset(name: "MSFT", platform: "Firstrade", in: context)
    createAsset(name: "BND", platform: "Vanguard", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    try viewModel.renamePlatform(
      id: TestDataManager.platform(named: "Firstrade", in: context)!.id, to: "Interactive Brokers")

    #expect(asset1.platform == "Interactive Brokers")
    #expect(asset2.platform == "Interactive Brokers")
  }

  @Test("Rename rejects existing name (case-insensitive)")
  func renameRejectsExistingNameCaseInsensitive() throws {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)
    createAsset(name: "BND", platform: "Vanguard", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)

    #expect(throws: PlatformError.duplicateName("vanguard")) {
      try viewModel.renamePlatform(
        id: TestDataManager.platform(named: "Firstrade", in: context)!.id, to: "vanguard")
    }
  }

  @Test("Rename trims and normalizes whitespace")
  func renameTrimsAndNormalizesWhitespace() throws {
    let tc = makeTestContext()
    let context = tc.context

    let asset = createAsset(name: "AAPL", platform: "Firstrade", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    try viewModel.renamePlatform(
      id: TestDataManager.platform(named: "Firstrade", in: context)!.id,
      to: "  Interactive  Brokers  ")

    #expect(asset.platform == "Interactive Brokers")
  }

  @Test("Platform disappears when all assets renamed away")
  func platformDisappearsWhenAllAssetsRenamedAway() throws {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)
    createAsset(name: "BND", platform: "Vanguard", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    try viewModel.renamePlatform(
      id: TestDataManager.platform(named: "Firstrade", in: context)!.id, to: "Interactive Brokers")

    viewModel.loadPlatforms()

    #expect(viewModel.platformRows.count == 2)
    #expect(viewModel.platformRows.contains { $0.name == "Interactive Brokers" })
    #expect(viewModel.platformRows.contains { $0.name == "Vanguard" })
    #expect(!viewModel.platformRows.contains { $0.name == "Firstrade" })
  }

  @Test("Empty platform excluded from list")
  func emptyPlatformExcludedFromList() {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)
    createAsset(name: "Unknown", platform: "", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    #expect(viewModel.platformRows.count == 1)
    #expect(viewModel.platformRows[0].name == "Firstrade")
  }

  @Test("Empty state when no platforms")
  func emptyStateWhenNoPlatforms() {
    let tc = makeTestContext()
    let context = tc.context

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    #expect(viewModel.platformRows.isEmpty)
  }

  @Test("Handles assets across multiple platforms")
  func handlesAssetsAcrossMultiplePlatforms() {
    let tc = makeTestContext()
    let context = tc.context

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade",
      marketValue: 5000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "MSFT", platform: "Firstrade",
      marketValue: 3000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard",
      marketValue: 2000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "BTC", platform: "Coinbase",
      marketValue: 10000, snapshot: snapshot, context: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    #expect(viewModel.platformRows.count == 3)

    let coinbase = viewModel.platformRows.first { $0.name == "Coinbase" }
    let firstrade = viewModel.platformRows.first { $0.name == "Firstrade" }
    let vanguard = viewModel.platformRows.first { $0.name == "Vanguard" }

    #expect(coinbase?.assetCount == 1)
    #expect(coinbase?.totalValue == 10000)
    #expect(firstrade?.assetCount == 2)
    #expect(firstrade?.totalValue == 8000)
    #expect(vanguard?.assetCount == 1)
    #expect(vanguard?.totalValue == 2000)
  }

  @Test("Self-rename with different casing succeeds")
  func selfRenameWithDifferentCasingSucceeds() throws {
    let tc = makeTestContext()
    let context = tc.context

    let asset = createAsset(name: "AAPL", platform: "Firstrade", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    try viewModel.renamePlatform(
      id: TestDataManager.platform(named: "Firstrade", in: context)!.id, to: "FIRSTRADE")

    #expect(asset.platform == "FIRSTRADE")
  }

  @Test("Total value uses only stored values from latest snapshot")
  func totalValueUsesOnlyStoredValuesFromLatestSnapshot() {
    let tc = makeTestContext()
    let context = tc.context

    // Snapshot 1: Firstrade and Vanguard both have values
    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade",
      marketValue: 5000, snapshot: snap1, context: context)
    createAssetWithValue(
      name: "BND", platform: "Vanguard",
      marketValue: 3000, snapshot: snap1, context: context)

    // Snapshot 2: Only Firstrade updated — Vanguard NOT carried forward
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade",
      marketValue: 7000, snapshot: snap2, context: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)
    viewModel.loadPlatforms()

    let firstrade = viewModel.platformRows.first { $0.name == "Firstrade" }

    #expect(firstrade?.totalValue == 7000)
    // Vanguard has no values in the latest snapshot, so it should not appear
    // with a value from carry-forward. It may still appear in the platform list
    // (since the asset exists) but its totalValue should be nil or 0.
    let vanguard = viewModel.platformRows.first { $0.name == "Vanguard" }
    #expect(vanguard == nil || vanguard?.totalValue == 0)
  }

  // MARK: - Rename Validation

  @Test("Rename rejects empty name")
  func renameRejectsEmptyName() {
    let tc = makeTestContext()
    let context = tc.context

    createAsset(name: "AAPL", platform: "Firstrade", in: context)

    let viewModel = PlatformListViewModel(
      modelContext: context, settingsService: tc.settingsService)

    #expect(throws: PlatformError.emptyName) {
      try viewModel.renamePlatform(
        id: TestDataManager.platform(named: "Firstrade", in: context)!.id, to: "   ")
    }
  }
}
