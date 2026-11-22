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

@Suite("PlatformIdentityGrouping Tests")
@MainActor
struct PlatformIdentityGroupingTests {
  @Test("A named platform cannot collide with the localized missing-platform group")
  func missingGroupHasItsOwnIdentity() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let label = String(localized: "(No Platform)", table: "Asset")
    let platform = try PlatformService.resolve(name: label, in: context)
    context.insert(Asset(name: "Named", platform: platform))
    context.insert(Asset(name: "Unassigned"))
    let settings = SettingsService.createForTesting()
    settings.hideStaleAssets = false
    let list = AssetListViewModel(modelContext: context, settingsService: settings)
    list.loadAssets()
    #expect(list.groups.count == 2)
    #expect(list.groups.first?.id == .platform(platform?.id))
    #expect(list.groups.last?.id == .platform(nil))
    #expect(list.groups.first?.assets.map { $0.asset.name } == ["Named"])
    #expect(list.groups.last?.assets.map { $0.asset.name } == ["Unassigned"])
  }

  @Test("A snapshot's platform totals retain their UUID keys after a rename")
  func summaryRetainsPlatformIdentity() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let asset = try context.findOrCreateAsset(name: "Fund", platform: "Broker")
    asset.currency = "USD"
    let platform = try #require(asset.platformRecord)
    let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    context.insert(snapshot)
    addValue(asset: asset, value: 42, snapshot: snapshot, context: context)
    let summary = SnapshotSummaryService.makeSummary(for: snapshot, displayCurrency: "USD")
    #expect(summary.platformValuesByID[platform.id] == 42)
    try PlatformService.rename(platform, to: "Renamed", in: context, settings: .createForTesting())
    #expect(summary.platformValuesByID[platform.id] == 42)
    #expect(
      SnapshotSummaryService.makeSummary(for: snapshot, displayCurrency: "USD")
        .platformValuesByID == summary.platformValuesByID)
  }

  @Test("Platform aggregates distinguish record IDs even while labels overlap in memory")
  func aggregatesUseRecordIdentity() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    // Intentionally unsaved: label uniqueness is separate from aggregation identity.
    let first = Platform(name: "Shared Label")
    let second = Platform(name: "Shared Label")
    let firstAsset = Asset(name: "First", platform: first)
    let secondAsset = Asset(name: "Second", platform: second)
    firstAsset.currency = "USD"
    secondAsset.currency = "USD"
    context.insert(firstAsset)
    context.insert(secondAsset)
    let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    context.insert(snapshot)
    addValue(asset: firstAsset, value: 40, snapshot: snapshot, context: context)
    addValue(asset: secondAsset, value: 60, snapshot: snapshot, context: context)
    let settings = SettingsService.createForTesting()
    let list = PlatformListViewModel(modelContext: context, settingsService: settings)
    list.loadPlatforms()
    #expect(list.platformRows.first { $0.id == first.id }?.totalValue == 40)
    #expect(list.platformRows.first { $0.id == second.id }?.totalValue == 60)
    let detail = PlatformDetailViewModel(
      platform: first, modelContext: context, settingsService: settings)
    detail.loadData()
    #expect(detail.valueHistory.first?.totalValue == 40)
  }

  @Test("An asset edit checks the selected platform ID rather than an overlapping label")
  func duplicateCheckUsesSelectedIdentity() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let first = Asset(name: "Fund", platform: Platform(name: "Broker"))
    let edited = Asset(name: "Cash", platform: Platform(name: "Broker"))
    context.insert(first)
    context.insert(edited)
    let originalPlatformID = edited.platformRecord?.id
    let editor = AssetDetailViewModel(asset: edited, modelContext: context)
    editor.editedName = "Fund"
    #expect(throws: Never.self) { try editor.save() }
    #expect(edited.name == "Fund")
    #expect(edited.platformRecord?.id == originalPlatformID)
  }

  @Test("Manual Bulk Entry rows join a saved platform by identity after its rename")
  func manualBulkRowsUseIdentity() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let asset = try context.findOrCreateAsset(name: "Fund", platform: "Broker")
    asset.currency = "USD"
    let platform = try #require(asset.platformRecord)
    let source = Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    context.insert(source)
    addValue(asset: asset, value: 50, snapshot: source, context: context)
    let draft = BulkEntryViewModel(
      modelContext: context, date: source.date.addingTimeInterval(86400))
    try PlatformService.rename(platform, to: "Renamed", in: context, settings: .createForTesting())
    let newID = draft.addManualRow(forPlatform: "Renamed")
    #expect(draft.platformGroups.count == 1)
    #expect(draft.platformGroups.first?.rows.count == 2)
    #expect(draft.rows.first { $0.id == newID }?.platform == "Renamed")
    #expect(draft.rows.first { $0.asset != nil }?.platform == "Renamed")
  }

  @Test("New draft groups have stable IDs and do not insert platform models")
  func draftGroupIdentities() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let existing = try #require(try PlatformService.resolve(name: "Existing", in: context))
    let draft = BulkEntryViewModel(modelContext: context, date: Date())
    _ = draft.addManualRow(forPlatform: " existing ")
    _ = draft.addManualRow(forPlatform: "New Place")
    let newID = try #require(draft.platformGroups.first { $0.platform == "New Place" }?.id)
    _ = draft.addManualRow(forPlatform: " new   PLACE ")
    _ = draft.addManualRow(forPlatform: "")
    #expect(draft.platformGroups.count == 3)
    #expect(draft.platformGroups.first { $0.id == newID }?.rows.count == 2)
    #expect(draft.platformGroups.contains { $0.id == .persisted(existing.id) })
    #expect(draft.platformGroups.contains { $0.id == .unassigned })
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
  }

  @Test("Unassigned and newly named platform scopes remain distinct when saving")
  func saveDistinctScopes() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let draft = BulkEntryViewModel(modelContext: context, date: Date())
    for name in ["", "New Place"] {
      let rowID = draft.addManualRow(forPlatform: name)
      draft.updateRowAssetName(rowID, to: "Fund")
      draft.updateRowCurrency(rowID, to: "USD")
      draft.updateRowValue(rowID, to: "50")
    }
    let snapshot = try draft.saveSnapshot()
    #expect(snapshot.assetValues?.count == 2)
    let assets = try context.fetch(FetchDescriptor<Asset>())
    #expect(assets.count == 2)
    #expect(assets.filter { $0.platformRecord == nil }.count == 1)
    #expect(assets.filter { $0.platformRecord != nil }.count == 1)
  }

  @Test("A newly named group resolves before duplicate validation without partial writes")
  func saveResolvesDraftBeforeCheckingDuplicates() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let draft = BulkEntryViewModel(modelContext: context, date: Date())
    let first = draft.addManualRow(forPlatform: "Later")
    let platform = try #require(try PlatformService.resolve(name: "Later", in: context))
    let second = draft.addManualRow(forPlatform: .persisted(platform))
    for id in [first, second] {
      draft.updateRowAssetName(id, to: "Fund")
      draft.updateRowCurrency(id, to: "USD")
      draft.updateRowValue(id, to: "50")
    }
    #expect(throws: SnapshotError.duplicateAssetName("Fund", "Later")) {
      try draft.saveSnapshot()
    }
    #expect(try context.fetchCount(FetchDescriptor<Snapshot>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 1)
  }

  @Test("A failed platform read cannot partially change an edited asset")
  func failedInputResolutionDoesNotMutate() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let asset = Asset(name: "Original")
    context.insert(asset)
    let editor = AssetDetailViewModel(
      asset: asset, modelContext: context,
      fetcher: FailingPlatformFetcher(context: context))
    editor.editedName = "Changed"
    editor.editedPlatform = "New Place"
    #expect(throws: PersistenceError.self) { try editor.save() }
    #expect(asset.name == "Original")
    #expect(asset.platformRecord == nil)
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 0)
  }

  private struct FailingPlatformFetcher: ModelFetching {
    let context: ModelContext
    private struct ReadFailure: Error {}
    func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] where T: PersistentModel {
      if T.self == Platform.self { throw ReadFailure() }
      return try context.fetch(descriptor)
    }
  }

  private func addValue(asset: Asset, value: Decimal, snapshot: Snapshot, context: ModelContext) {
    let recorded = SnapshotAssetValue(marketValue: value)
    recorded.asset = asset
    recorded.snapshot = snapshot
    context.insert(recorded)
  }
}
