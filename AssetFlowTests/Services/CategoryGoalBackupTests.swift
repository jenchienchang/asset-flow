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

@Suite("CategoryGoalBackup Tests")
@MainActor
struct CategoryGoalBackupTests {
  @Test("V4 archive preserves minimum currency and full precision with all V3 entities")
  func roundTrip() async throws {
    let original = TestDataManager.createInMemoryContainer()
    let restored = TestDataManager.createInMemoryContainer()
    let settings = SettingsService.createForTesting()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = Decimal(string: "300000.123456789")!
    category.minimumBalanceCurrency = "TWD"
    original.mainContext.insert(category)
    let asset = Asset(name: "Account")
    asset.currency = "EUR"
    asset.category = category
    let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    let value = SnapshotAssetValue(marketValue: 500000)
    value.asset = asset
    value.snapshot = snapshot
    let flow = CashFlowOperation(cashFlowDescription: "Deposit", amount: 100)
    flow.currency = "EUR"
    flow.snapshot = snapshot
    let rate = ExchangeRate(
      baseCurrency: "USD",
      ratesJSON: try JSONEncoder().encode(["eur": Decimal(string: "0.9")!, "twd": Decimal(30)]),
      fetchDate: snapshot.date)
    rate.snapshot = snapshot
    for model: any PersistentModel in [asset, snapshot, value, flow, rate] {
      original.mainContext.insert(model)
    }
    let zip = FileManager.default.temporaryDirectory.appending(path: "goals-\(UUID()).zip")
    defer { try? FileManager.default.removeItem(at: zip) }
    try await BackupService.exportBackup(
      to: zip, modelContext: original.mainContext, settingsService: settings)
    #expect(try await BackupService.validateBackup(at: zip).formatVersion == 4)
    try await BackupService.restoreFromBackup(
      at: zip, modelContext: restored.mainContext, settingsService: settings)
    let copy = try #require(restored.mainContext.fetch(FetchDescriptor<AssetFlow.Category>()).first)
    #expect(copy.minimumBalanceAmount == Decimal(string: "300000.123456789")!)
    #expect(copy.minimumBalanceCurrency == "TWD")
    #expect(copy.id == category.id)
    #expect(copy.assets?.first?.currency == "EUR")
    let restoredSnapshot = try #require(
      restored.mainContext.fetch(FetchDescriptor<Snapshot>()).first)
    #expect(restoredSnapshot.cashFlowOperations?.first?.currency == "EUR")
    #expect(restoredSnapshot.exchangeRate?.rates["twd"] == 30)
    let before = CategoryGoalAssessmentService.assess(
      snapshot: snapshot, categories: [category], displayCurrency: "USD")
    let after = CategoryGoalAssessmentService.assess(
      snapshot: restoredSnapshot, categories: [copy], displayCurrency: "USD")
    #expect(before.plan == after.plan)

    // A persistence failure must preserve the original minimum fields and graph.
    struct ForcedFailure: Error {}
    await #expect(throws: BackupError.self) {
      try await BackupService.restoreFromBackup(
        at: zip, modelContext: original.mainContext, settingsService: settings,
        checkpoint: { point in
          if case .afterCategoryInsertion = point { throw ForcedFailure() }
        })
    }
    let retained = try #require(
      original.mainContext.fetch(FetchDescriptor<AssetFlow.Category>()).first)
    #expect(retained.minimumBalanceAmount == Decimal(string: "300000.123456789")!)
    #expect(retained.minimumBalanceCurrency == "TWD")

    // Turn a complete V4 archive into a real V3 layout and preserve V3 currency/rates.
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try await BackupService.extractZip(from: zip, to: dir)
    let legacyManifest = BackupManifest(
      formatVersion: 3, exportTimestamp: ISO8601DateFormatter().string(from: Date()),
      appVersion: "0.7.1")
    try JSONEncoder().encode(legacyManifest).write(
      to: dir.appending(path: BackupCSV.manifestFileName))
    try "id,name,targetAllocationPercentage,displayOrder\n\(category.id),Reserve,100,0\n".write(
      to: dir.appending(path: BackupCSV.Categories.fileName), atomically: true, encoding: .utf8)
    let legacyZip = FileManager.default.temporaryDirectory.appending(
      path: "legacy-goals-\(UUID()).zip")
    defer { try? FileManager.default.removeItem(at: legacyZip) }
    try await BackupService.createZip(from: dir, to: legacyZip)
    try await BackupService.restoreFromBackup(
      at: legacyZip, modelContext: restored.mainContext, settingsService: settings)
    let legacy = try #require(
      restored.mainContext.fetch(FetchDescriptor<AssetFlow.Category>()).first)
    #expect(legacy.minimumBalanceAmount == nil)
    #expect(legacy.minimumBalanceCurrency == nil)
    #expect(legacy.assets?.first?.currency == "EUR")
    #expect(
      try restored.mainContext.fetch(FetchDescriptor<Snapshot>()).first?.exchangeRate?.rates["twd"]
        == 30)

  }

  @Test("Malformed minimum fields reject restore while valid infeasible requirements are accepted")
  func parsing() throws {
    for fields in ["-1,USD", "NaN,USD", "1,", ",USD", "1,US$"] {
      var issues: [BackupValidationIssue] = []
      let text =
        "id,name,targetAllocationPercentage,displayOrder,minimumBalanceAmount,minimumBalanceCurrency\n\(UUID()),Reserve,100,0,\(fields)\n"
      let document = BackupCSVDocument(
        records: Array(
          try BackupService.parseCSVRecords(Data(text.utf8), fileName: "categories.csv").dropFirst()
        ))
      _ = BackupService.parseCategories(
        document, version: BackupFormatVersion.current, issues: &issues)
      #expect(!issues.isEmpty)
    }
  }
}
