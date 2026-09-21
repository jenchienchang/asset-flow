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

@Suite("BackupService Currency Tests")
@MainActor
struct BackupServiceCurrencyTests {

  // MARK: - Test Helpers

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let settingsService: SettingsService
  }

  private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let settingsService = SettingsService.createForTesting()
    return TestContext(
      container: container, context: context,
      settingsService: settingsService)
  }

  private func tempZipURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "test-backup-currency-\(UUID().uuidString).zip")
  }

  private func extractFileContent(
    zipURL: URL, fileName: String
  ) throws -> String {
    let extractDir = FileManager.default.temporaryDirectory
      .appending(path: "extract-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: extractDir) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", zipURL.path, extractDir.path]
    try process.run()
    process.waitUntilExit()

    return try String(
      contentsOf: extractDir.appending(path: fileName),
      encoding: .utf8)
  }

  private func tamperAndRezip(
    zipURL: URL,
    tamper: (URL) throws -> Void
  ) throws {
    let extractDir = FileManager.default.temporaryDirectory
      .appending(path: "tamper-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: extractDir) }

    let dittoExtract = Process()
    dittoExtract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    dittoExtract.arguments = ["-x", "-k", zipURL.path, extractDir.path]
    try dittoExtract.run()
    dittoExtract.waitUntilExit()

    try tamper(extractDir)

    try FileManager.default.removeItem(at: zipURL)
    let dittoCreate = Process()
    dittoCreate.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    dittoCreate.arguments = [
      "-c", "-k", "--sequesterRsrc", extractDir.path, zipURL.path,
    ]
    try dittoCreate.run()
    dittoCreate.waitUntilExit()
  }

  // MARK: - Export Tests

  @Test("Export includes currency column in assets CSV")
  func exportIncludesCurrencyInAssets() throws {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Schwab")
    asset.currency = "USD"
    tc.context.insert(asset)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    let content = try extractFileContent(
      zipURL: zipURL, fileName: BackupCSV.Assets.fileName)
    let lines = content.components(separatedBy: "\n")
      .filter { !$0.isEmpty }
    #expect(lines[0] == "id,name,platform,categoryID,currency")
    #expect(lines[1].hasSuffix("USD"))
  }

  @Test("Export includes currency column in cash flow operations CSV")
  func exportIncludesCurrencyInCashFlows() throws {
    let tc = createTestContext()

    let snapshot = Snapshot(
      date: Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15))!)
    tc.context.insert(snapshot)

    let cf = CashFlowOperation(
      cashFlowDescription: "Salary", amount: 50000)
    cf.currency = "TWD"
    cf.snapshot = snapshot
    tc.context.insert(cf)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    let content = try extractFileContent(
      zipURL: zipURL, fileName: BackupCSV.CashFlowOperations.fileName)
    let lines = content.components(separatedBy: "\n")
      .filter { !$0.isEmpty }
    #expect(lines[0] == "id,snapshotID,description,amount,currency")
    #expect(lines[1].hasSuffix("TWD"))
  }

  @Test("Export includes exchange rates CSV")
  func exportIncludesExchangeRates() throws {
    let tc = createTestContext()

    let snapshot = Snapshot(
      date: Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15))!)
    tc.context.insert(snapshot)

    let ratesData = try JSONEncoder().encode([
      "twd": Decimal(string: "31.500000000000000000123456789")!,
      "eur": Decimal(string: "0.920000000000000000123456789")!,
    ])
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesData,
      fetchDate: snapshot.date,
      isFallback: false)
    exchangeRate.snapshot = snapshot
    tc.context.insert(exchangeRate)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    let content = try extractFileContent(
      zipURL: zipURL, fileName: BackupCSV.ExchangeRates.fileName)
    let lines = content.components(separatedBy: "\n")
      .filter { !$0.isEmpty }
    #expect(lines[0] == "snapshotID,baseCurrency,fetchDate,isFallback,ratesJSON")
    #expect(lines.count == 2)
    #expect(lines[1].contains("usd"))
  }

  @Test("Export manifest has formatVersion 3")
  func exportManifestVersion3() throws {
    let tc = createTestContext()
    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    let manifest = try BackupService.validateBackup(at: zipURL)
    #expect(manifest.formatVersion == 3)
  }

  // MARK: - Backward Compatibility Tests

  @Test("Restore v2 backup defaults currency to main currency")
  func restoreV2BackupDefaultsCurrency() throws {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Schwab")
    tc.context.insert(asset)

    let snapshot = Snapshot(
      date: Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15))!)
    tc.context.insert(snapshot)

    let sav = SnapshotAssetValue(marketValue: 15000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let cf = CashFlowOperation(
      cashFlowDescription: "Salary", amount: 50000)
    cf.snapshot = snapshot
    tc.context.insert(cf)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    // Tamper to v2 format (remove currency columns, set formatVersion 2)
    try tamperAndRezip(zipURL: zipURL) { dir in
      // Rewrite assets.csv without currency column
      let assetFile = dir.appending(path: BackupCSV.Assets.fileName)
      try "id,name,platform,categoryID\n\(asset.id.uuidString),AAPL,Schwab,\n"
        .write(to: assetFile, atomically: true, encoding: .utf8)

      // Rewrite cash_flow_operations.csv without currency column
      let cfFile = dir.appending(path: BackupCSV.CashFlowOperations.fileName)
      try
        "id,snapshotID,description,amount\n\(cf.id.uuidString),\(snapshot.id.uuidString),Salary,50000\n"
        .write(to: cfFile, atomically: true, encoding: .utf8)

      // Remove exchange_rates.csv if it exists
      let erFile = dir.appending(path: BackupCSV.ExchangeRates.fileName)
      try? FileManager.default.removeItem(at: erFile)

      // Rewrite manifest with formatVersion 2
      let manifestURL = dir.appending(path: BackupCSV.manifestFileName)
      let manifest = BackupManifest(
        formatVersion: 2,
        exportTimestamp: ISO8601DateFormatter().string(from: Date()),
        appVersion: "1.0.0"
      )
      try JSONEncoder().encode(manifest).write(to: manifestURL)
    }

    // Restore into fresh context
    let tc2 = createTestContext()
    tc2.settingsService.mainCurrency = "USD"
    try BackupService.restoreFromBackup(
      at: zipURL, modelContext: tc2.context,
      settingsService: tc2.settingsService)

    let assets = try tc2.context.fetch(FetchDescriptor<Asset>())
    #expect(assets.count == 1)
    // v2 backup has no currency — should restore as empty string (inherits display currency)
    #expect(assets[0].currency == "")

    let ops = try tc2.context.fetch(FetchDescriptor<CashFlowOperation>())
    #expect(ops.count == 1)
    #expect(ops[0].currency == "")
  }

  @Test("Restore v3 backup preserves currency")
  func restoreV3BackupPreservesCurrency() throws {
    let tc = createTestContext()

    let asset = Asset(name: "TSMC", platform: "Fubon")
    asset.currency = "TWD"
    tc.context.insert(asset)

    let snapshot = Snapshot(
      date: Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15))!)
    tc.context.insert(snapshot)

    let sav = SnapshotAssetValue(marketValue: 500000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let cf = CashFlowOperation(
      cashFlowDescription: "Dividend", amount: 5000)
    cf.currency = "TWD"
    cf.snapshot = snapshot
    tc.context.insert(cf)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    // Restore into fresh context
    let tc2 = createTestContext()
    try BackupService.restoreFromBackup(
      at: zipURL, modelContext: tc2.context,
      settingsService: tc2.settingsService)

    let assets = try tc2.context.fetch(FetchDescriptor<Asset>())
    #expect(assets.count == 1)
    #expect(assets[0].currency == "TWD")

    let ops = try tc2.context.fetch(FetchDescriptor<CashFlowOperation>())
    #expect(ops.count == 1)
    #expect(ops[0].currency == "TWD")
  }

  @Test("Round-trip preserves exchange rates")
  func roundTripExchangeRates() throws {
    let tc = createTestContext()

    let snapshot = Snapshot(
      date: Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15))!)
    tc.context.insert(snapshot)

    let ratesData = try JSONEncoder().encode([
      "twd": Decimal(string: "31.500000000000000000123456789")!,
      "eur": Decimal(string: "0.920000000000000000123456789")!,
    ])
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesData,
      fetchDate: snapshot.date,
      isFallback: false)
    exchangeRate.snapshot = snapshot
    tc.context.insert(exchangeRate)

    let zipURL = tempZipURL()
    defer { try? FileManager.default.removeItem(at: zipURL) }

    try BackupService.exportBackup(
      to: zipURL, modelContext: tc.context,
      settingsService: tc.settingsService)

    let tc2 = createTestContext()
    try BackupService.restoreFromBackup(
      at: zipURL, modelContext: tc2.context,
      settingsService: tc2.settingsService)

    let snapshots = try tc2.context.fetch(FetchDescriptor<Snapshot>())
    #expect(snapshots.count == 1)

    let restoredRate = snapshots[0].exchangeRate
    #expect(restoredRate != nil)
    #expect(restoredRate?.baseCurrency == "usd")
    #expect(restoredRate?.isFallback == false)
    #expect(
      restoredRate?.rates["twd"] == Decimal(string: "31.500000000000000000123456789")!
    )
    #expect(
      restoredRate?.rates["eur"] == Decimal(string: "0.920000000000000000123456789")!
    )
  }
}
