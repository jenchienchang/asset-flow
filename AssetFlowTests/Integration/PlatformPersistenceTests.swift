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

@Suite("PlatformPersistence Tests")
@MainActor
struct PlatformPersistenceTests {
  @Test("Displayed order and relationships survive closing and reopening a disk store")
  func displayedOrderSurvivesReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "ordering.store")
    let ids = try seedDisplayedOrder(at: url)
    try checkDisplayedOrder(at: url, ids: ids)
    try checkDisplayedOrder(at: url, ids: ids)
  }

  private func seedDisplayedOrder(at url: URL) throws -> [UUID] {
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    context.autosaveEnabled = false
    let beta = try context.findOrCreateAsset(name: "B", platform: "Beta")
    let list = PlatformListViewModel(modelContext: context, settingsService: .createForTesting())
    list.loadPlatforms()
    let alpha = try context.findOrCreateAsset(name: "A", platform: "Alpha")
    list.loadPlatforms()
    #expect(list.platformRows.map(\.name) == ["Beta", "Alpha"])
    let ids = try [#require(beta.platformRecord).id, #require(alpha.platformRecord).id]
    try context.save()
    return ids
  }

  private func checkDisplayedOrder(at url: URL, ids: [UUID]) throws {
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    context.autosaveEnabled = false
    let platforms = PlatformService.orderedForDisplay(
      try context.fetch(FetchDescriptor<Platform>()))
    #expect(platforms.map(\.id) == ids)
    #expect(platforms.map(\.displayOrder) == [0, 1])
    #expect(platforms.map { $0.assets?.count } == [1, 1])
    let list = PlatformListViewModel(modelContext: context, settingsService: .createForTesting())
    list.loadPlatforms()
    #expect(list.platformRows.map(\.id) == ids)
    #expect(!context.hasChanges)
  }

  @Test("Backup round trip preserves platform IDs, ordering, empty records and assignments")
  func backupRoundTrip() async throws {
    let source = TestDataManager.createInMemoryContainer()
    let settings = SettingsService.createForTesting()
    let broker = try #require(try PlatformService.resolve(name: "Broker", in: source.mainContext))
    broker.displayOrder = 7
    let empty = try #require(try PlatformService.resolve(name: "Empty", in: source.mainContext))
    empty.displayOrder = 2
    let asset = Asset(name: "Fund", platform: broker)
    source.mainContext.insert(asset)
    let originalID = broker.id
    let emptyID = empty.id
    let assetID = asset.id
    let zip = FileManager.default.temporaryDirectory.appending(path: "platform-\(UUID()).zip")
    defer { try? FileManager.default.removeItem(at: zip) }
    try await BackupService.exportBackup(
      to: zip, modelContext: source.mainContext, settingsService: settings)
    let target = TestDataManager.createInMemoryContainer()
    try await BackupService.restoreFromBackup(
      at: zip, modelContext: target.mainContext, settingsService: settings)
    let platforms = try target.mainContext.fetch(FetchDescriptor<Platform>())
    let assets = try target.mainContext.fetch(FetchDescriptor<Asset>())
    #expect(platforms.count == 2)
    #expect(platforms.first { $0.id == originalID }?.displayOrder == 7)
    #expect(platforms.first { $0.id == emptyID }?.displayOrder == 2)
    #expect(assets.first { $0.id == assetID }?.platformRecord?.id == originalID)
  }

  @Test("V2 disk migration canonicalizes platforms and preserves the financial graph on reopen")
  func migrateV2() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "legacy.store")
    let assetID = UUID()
    try seedV2(at: url, assetID: assetID)
    let id = try checkMigrated(at: url, assetID: assetID)
    #expect(try checkMigrated(at: url, assetID: assetID) == id)
  }

  @Test("Migrated platforms without a saved order use normalized name order")
  func migrationDefaultOrder() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "order.store")
    try seedV2(at: url, assetID: UUID(), additionalPlatform: true)
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, migrationPlan: AssetFlowMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url)])
    let list = PlatformListViewModel(
      modelContext: container.mainContext,
      settingsService: .createForTesting())
    list.loadPlatforms()
    #expect(list.platformRows.map(\.name) == ["alpha", "Broker One"])
  }

  @Test("Migration rejects conflicting assets and leaves the V2 source readable")
  func collisionPreservesSource() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "collision.store")
    try seedV2(at: url, assetID: UUID(), collision: true)
    let schema = CurrentSchema.schema
    #expect(throws: (any Error).self) {
      _ = try ModelContainer(
        for: schema, migrationPlan: AssetFlowMigrationPlan.self,
        configurations: [ModelConfiguration(schema: schema, url: url)])
    }
    let old = Schema(versionedSchema: SchemaV2.self)
    let container = try ModelContainer(
      for: old, configurations: [ModelConfiguration(schema: old, url: url)])
    #expect(try container.mainContext.fetchCount(FetchDescriptor<SchemaV2.Asset>()) == 3)
    #expect(
      try container.mainContext.fetch(FetchDescriptor<SchemaV2.SnapshotAssetValue>()).first?
        .marketValue == Decimal(string: "123.456789"))
  }

  @Test("Legacy backup versions restore shared platform relationships", arguments: [1, 2, 3, 4])
  func legacyBackup(version: Int) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = BackupManifest(
      formatVersion: version,
      exportTimestamp: "2026-01-01T00:00:00Z", appVersion: "0.7.1")
    try JSONEncoder().encode(manifest).write(to: directory.appending(path: "manifest.json"))
    let categoryHeader =
      version == 1
      ? BackupCSV.Categories.v1Headers
      : (version < 4 ? BackupCSV.Categories.v3Headers : BackupCSV.Categories.headers)
    let assetHeader = version < 3 ? BackupCSV.Assets.v2Headers : BackupCSV.Assets.v4Headers
    let cashFlowHeader =
      version < 3 ? BackupCSV.CashFlowOperations.v2Headers : BackupCSV.CashFlowOperations.headers
    let currency = version < 3 ? "" : ",USD"
    let files = [
      "categories.csv": categoryHeader.joined(separator: ","),
      "assets.csv": assetHeader.joined(separator: ",")
        + "\n\(UUID()),Stock,Broker One,\(currency)"
        + "\n\(UUID()),Bond, broker   ONE ,\(currency)"
        + "\n\(UUID()),Cash,,\(currency)",
      "snapshots.csv": BackupCSV.Snapshots.headers.joined(separator: ","),
      "snapshot_asset_values.csv": BackupCSV.SnapshotAssetValues.headers.joined(separator: ","),
      "cash_flow_operations.csv": cashFlowHeader.joined(separator: ","),
      "settings.csv":
        "key,value\ndisplayCurrency,USD\ndateFormat,numeric\ndefaultPlatform,Broker One",
    ]
    for (name, text) in files {
      try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }
    let zip = FileManager.default.temporaryDirectory.appending(
      path: "legacy-platform-\(UUID()).zip")
    defer { try? FileManager.default.removeItem(at: zip) }
    try await BackupService.createZip(from: directory, to: zip)
    let container = TestDataManager.createInMemoryContainer()
    try await BackupService.restoreFromBackup(
      at: zip, modelContext: container.mainContext,
      settingsService: .createForTesting())
    let assets = try container.mainContext.fetch(FetchDescriptor<Asset>())
    let platforms = try container.mainContext.fetch(FetchDescriptor<Platform>())
    #expect(platforms.count == 1)
    #expect(assets.count == 3)
    #expect(assets.first { $0.name == "Stock" }?.platformRecord?.id == platforms.first?.id)
    #expect(assets.first { $0.name == "Bond" }?.platformRecord?.id == platforms.first?.id)
    #expect(assets.first { $0.name == "Cash" }?.platformRecord == nil)
    #expect(assets.allSatisfy { $0.currency == (version < 3 ? "" : "USD") })
  }

  @Test("Malformed platform data and dangling references reject backup validation")
  func invalidBackupPlatforms() throws {
    let id = UUID()
    for text in [
      "\(id),Broker,-1", "\(id),Broker,invalid", "\(id), ,0",
      "\(id),Broker,0\n\(UUID()), broker ,1", "\(id),Broker,0\n\(id),Other,1",
    ] {
      var issues: [BackupValidationIssue] = []
      let csv = "id,name,displayOrder\n" + text
      let records = try BackupService.parseCSVRecords(Data(csv.utf8), fileName: "platforms.csv")
      _ = BackupService.parsePlatforms(
        BackupCSVDocument(records: Array(records.dropFirst())), issues: &issues)
      #expect(!issues.isEmpty)
    }
    var issues: [BackupValidationIssue] = []
    BackupService.validateRelationships(
      platforms: [], categories: [],
      assets: [
        BackupAssetRecord(
          id: UUID(), name: "Fund", legacyPlatformName: "", platformID: id,
          categoryID: nil, currency: "USD")
      ], snapshots: [], snapshotAssetValues: [], cashFlowOperations: [], exchangeRates: [],
      issues: &issues)
    #expect(issues.contains { $0.file == "assets.csv" && $0.column == "platformID" })
  }

  private func seedV2(
    at url: URL, assetID: UUID, collision: Bool = false, additionalPlatform: Bool = false
  ) throws {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let stock = SchemaV2.Asset(name: "Fund", platform: "Broker One")
    stock.id = assetID
    stock.currency = "TWD"
    let bond = SchemaV2.Asset(name: collision ? " fund " : "Bond", platform: " broker   ONE ")
    let cash = SchemaV2.Asset(name: "Cash")
    context.insert(stock)
    context.insert(bond)
    context.insert(cash)
    if additionalPlatform { context.insert(SchemaV2.Asset(name: "Outside", platform: "alpha")) }
    let category = SchemaV2.Category(name: "Reserve")
    category.minimumBalanceAmount = 50
    category.minimumBalanceCurrency = "TWD"
    stock.category = category
    let snapshot = SchemaV2.Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    let value = SchemaV2.SnapshotAssetValue(marketValue: Decimal(string: "123.456789")!)
    value.asset = stock
    value.snapshot = snapshot
    context.insert(category)
    context.insert(snapshot)
    context.insert(value)
    try context.save()
  }

  private func checkMigrated(at url: URL, assetID: UUID) throws -> UUID {
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, migrationPlan: AssetFlowMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let platforms = try context.fetch(FetchDescriptor<Platform>())
    let assets = try context.fetch(FetchDescriptor<Asset>())
    #expect(platforms.count == 1)
    #expect(platforms.first?.normalizedName == "broker one")
    #expect(assets.filter { $0.platformRecord != nil }.count == 2)
    #expect(assets.first { $0.name == "Cash" }?.platformRecord == nil)
    let stock = try #require(assets.first { $0.id == assetID })
    #expect(stock.currency == "TWD")
    #expect(stock.category?.minimumBalanceAmount == 50)
    #expect(stock.snapshotAssetValues?.first?.marketValue == Decimal(string: "123.456789"))
    #expect(stock.platformRecord?.id == platforms.first?.id)
    return try #require(platforms.first?.id)
  }
}
