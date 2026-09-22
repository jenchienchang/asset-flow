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

/// Service for exporting and restoring full database backups as ZIP archives.
///
/// Each archive contains a `manifest.json`, 6 required CSV files covering all entities
/// and settings, and 1 optional CSV file (`exchange_rates.csv`). Uses `/usr/bin/ditto`
/// for ZIP operations (built into macOS).
nonisolated enum BackupService {

  // MARK: - Export

  /// Exports all data to a ZIP archive at the given URL.
  ///
  /// - Parameters:
  ///   - url: Destination file URL for the `.zip` archive.
  ///   - modelContext: The model context to query data from.
  ///   - settingsService: The settings service to export settings from.
  @MainActor
  static func exportBackup(
    to url: URL,
    modelContext: ModelContext,
    settingsService: SettingsService
  ) async throws {
    let payload = try makeExportPayload(
      modelContext: modelContext, settingsService: settingsService)
    try await writeArchive(payload: payload, to: url)
  }

  @MainActor
  private static func makeExportPayload(
    modelContext: ModelContext,
    settingsService: SettingsService
  ) throws -> BackupExportPayload {
    let categories = try modelContext.fetch(FetchDescriptor<Category>())
    let assets = try modelContext.fetch(FetchDescriptor<Asset>())
    let snapshots = try modelContext.fetch(FetchDescriptor<Snapshot>())
    let assetValues = try modelContext.fetch(
      FetchDescriptor<SnapshotAssetValue>())
    let cashFlows = try modelContext.fetch(
      FetchDescriptor<CashFlowOperation>())
    let exchangeRates = try modelContext.fetch(
      FetchDescriptor<ExchangeRate>())

    let categoryRecords = categories.map { category in
      BackupCategoryRecord(
        id: category.id,
        name: category.name,
        targetAllocationPercentage: category.targetAllocationPercentage,
        displayOrder: category.displayOrder)
    }
    let assetRecords = assets.map { asset in
      BackupAssetRecord(
        id: asset.id,
        name: asset.name,
        platform: asset.platform,
        categoryID: asset.category?.id,
        currency: asset.currency)
    }
    let snapshotRecords = snapshots.map { snapshot in
      BackupSnapshotRecord(
        id: snapshot.id, date: snapshot.date, createdAt: snapshot.createdAt)
    }
    let snapshotAssetValueRecords = assetValues.compactMap {
      value -> BackupSnapshotAssetValueRecord? in
      guard let snapshot = value.snapshot, let asset = value.asset else { return nil }
      return BackupSnapshotAssetValueRecord(
        snapshotID: snapshot.id, assetID: asset.id, marketValue: value.marketValue)
    }
    let cashFlowRecords = cashFlows.compactMap { operation -> BackupCashFlowRecord? in
      guard let snapshot = operation.snapshot else { return nil }
      return BackupCashFlowRecord(
        id: operation.id,
        snapshotID: snapshot.id,
        description: operation.cashFlowDescription,
        amount: operation.amount,
        currency: operation.currency)
    }
    let exchangeRateRecords = exchangeRates.compactMap {
      exchangeRate -> BackupExchangeRateRecord? in
      guard let snapshot = exchangeRate.snapshot else { return nil }
      return BackupExchangeRateRecord(
        snapshotID: snapshot.id,
        baseCurrency: exchangeRate.baseCurrency,
        fetchDate: exchangeRate.fetchDate,
        isFallback: exchangeRate.isFallback,
        ratesJSON: exchangeRate.ratesJSON)
    }

    let manifest = BackupManifest(
      formatVersion: BackupFormatVersion.current.rawValue,
      exportTimestamp: ISO8601DateFormatter().string(from: Date()),
      appVersion: Constants.AppInfo.version)
    let settings = BackupSettingsRecord(
      mainCurrency: settingsService.mainCurrency,
      dateFormat: settingsService.dateFormat,
      defaultPlatform: settingsService.defaultPlatform)

    return BackupExportPayload(
      manifest: manifest,
      categories: categoryRecords,
      assets: assetRecords,
      snapshots: snapshotRecords,
      snapshotAssetValues: snapshotAssetValueRecords,
      cashFlowOperations: cashFlowRecords,
      exchangeRates: exchangeRateRecords,
      settings: settings)
  }

  private nonisolated static func writeArchive(
    payload: BackupExportPayload,
    to url: URL
  ) async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowBackup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    let temporaryArchive = url.deletingLastPathComponent()
      .appending(path: ".AssetFlowBackup-\(UUID().uuidString).zip")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
      try? FileManager.default.removeItem(at: temporaryArchive)
    }

    let manifestData = try JSONEncoder().encode(payload.manifest)
    try manifestData.write(
      to: tempDir.appending(path: BackupCSV.manifestFileName))
    try writeCategoriesCSV(payload.categories, to: tempDir)
    try writeAssetsCSV(payload.assets, to: tempDir)
    try writeSnapshotsCSV(payload.snapshots, to: tempDir)
    try writeSnapshotAssetValuesCSV(payload.snapshotAssetValues, to: tempDir)
    try writeCashFlowOperationsCSV(payload.cashFlowOperations, to: tempDir)
    try writeExchangeRatesCSV(payload.exchangeRates, to: tempDir)
    try writeSettingsCSV(payload.settings, to: tempDir)

    try await createZip(from: tempDir, to: temporaryArchive)
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryArchive)
    } else {
      try FileManager.default.moveItem(at: temporaryArchive, to: url)
    }
  }

  // MARK: - Validate

  /// Validates a backup archive without modifying any data.
  ///
  /// - Parameter url: Path to the `.zip` archive.
  /// - Returns: The parsed `BackupManifest` on success.
  /// - Throws: `BackupError` if the archive is invalid.
  static func validateBackup(at url: URL) async throws -> BackupManifest {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowValidate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try await extractZip(from: url, to: tempDir)
    let backupRoot = try resolveBackupRoot(at: tempDir)
    return try validateExtractedBackup(at: backupRoot)
  }

  // MARK: - Restore

  /// Restores all data from a backup archive, replacing existing data.
  ///
  /// - Parameters:
  ///   - url: Path to the `.zip` archive.
  ///   - modelContext: The model context to restore data into.
  ///   - settingsService: The settings service to restore settings into.
  @MainActor
  static func restoreFromBackup(
    at url: URL,
    modelContext: ModelContext,
    settingsService: SettingsService,
    checkpoint: ((BackupRestoreCheckpoint) throws -> Void)? = nil
  ) async throws {
    // Extract once and validate
    let backup = try await loadValidatedBackupArchive(at: url)
    try Task.checkCancellation()
    try checkpoint?(.afterValidation)
    try Task.checkCancellation()

    // Establish a clean rollback point before the destructive transaction.
    // If this save fails, no restore mutation has occurred.
    if modelContext.hasChanges {
      try Task.checkCancellation()
      try modelContext.save()
    }

    let wasAutosaveEnabled = modelContext.autosaveEnabled
    modelContext.autosaveEnabled = false
    defer { modelContext.autosaveEnabled = wasAutosaveEnabled }

    try Task.checkCancellation()
    do {
      try modelContext.transaction {
        try deleteAllData(modelContext: modelContext)
        try checkpoint?(.afterDeletion)

        let categoryIDMap = restoreCategories(
          backup.categories, modelContext: modelContext)
        try checkpoint?(.afterCategoryInsertion)
        let assetIDMap = try restoreAssets(
          backup.assets, modelContext: modelContext,
          categoryIDMap: categoryIDMap)
        let snapshotIDMap = restoreSnapshots(
          backup.snapshots, modelContext: modelContext)
        try restoreSnapshotAssetValues(
          backup.snapshotAssetValues, modelContext: modelContext,
          snapshotIDMap: snapshotIDMap, assetIDMap: assetIDMap)
        try restoreCashFlowOperations(
          backup.cashFlowOperations, modelContext: modelContext,
          snapshotIDMap: snapshotIDMap)
        try restoreExchangeRates(
          backup.exchangeRates, modelContext: modelContext,
          snapshotIDMap: snapshotIDMap)
      }
    } catch {
      modelContext.rollback()
      if let backupError = error as? BackupError {
        throw backupError
      }
      throw BackupError.restoreFailed(error.localizedDescription)
    }

    restoreSettings(backup.settings, settingsService: settingsService)
  }

  private nonisolated static func loadValidatedBackupArchive(
    at url: URL
  ) async throws -> ValidatedBackup {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowRestore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try await extractZip(from: url, to: tempDir)
    let backupRoot = try resolveBackupRoot(at: tempDir)
    let backup = try loadValidatedBackup(at: backupRoot)
    try Task.checkCancellation()
    return backup
  }
}
