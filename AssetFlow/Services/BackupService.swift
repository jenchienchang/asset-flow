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
@MainActor
enum BackupService {

  // MARK: - Export

  /// Exports all data to a ZIP archive at the given URL.
  ///
  /// - Parameters:
  ///   - url: Destination file URL for the `.zip` archive.
  ///   - modelContext: The model context to query data from.
  ///   - settingsService: The settings service to export settings from.
  static func exportBackup(
    to url: URL,
    modelContext: ModelContext,
    settingsService: SettingsService
  ) throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowBackup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Query all entities
    let categories = try modelContext.fetch(FetchDescriptor<Category>())
    let assets = try modelContext.fetch(FetchDescriptor<Asset>())
    let snapshots = try modelContext.fetch(FetchDescriptor<Snapshot>())
    let assetValues = try modelContext.fetch(
      FetchDescriptor<SnapshotAssetValue>())
    let cashFlows = try modelContext.fetch(
      FetchDescriptor<CashFlowOperation>())

    // Write manifest
    let manifest = BackupManifest(
      formatVersion: BackupFormatVersion.current.rawValue,
      exportTimestamp: ISO8601DateFormatter().string(from: Date()),
      appVersion: Constants.AppInfo.version
    )
    let manifestData = try JSONEncoder().encode(manifest)
    try manifestData.write(
      to: tempDir.appending(path: BackupCSV.manifestFileName))

    // Write CSVs
    try writeCategoriesCSV(categories, to: tempDir)
    try writeAssetsCSV(assets, to: tempDir)
    try writeSnapshotsCSV(snapshots, to: tempDir)
    try writeSnapshotAssetValuesCSV(assetValues, to: tempDir)
    try writeCashFlowOperationsCSV(cashFlows, to: tempDir)
    let exchangeRates = try modelContext.fetch(
      FetchDescriptor<ExchangeRate>())
    try writeExchangeRatesCSV(exchangeRates, to: tempDir)
    try writeSettingsCSV(settingsService: settingsService, to: tempDir)

    // ZIP via ditto
    try createZip(from: tempDir, to: url)
  }

  // MARK: - Validate

  /// Validates a backup archive without modifying any data.
  ///
  /// - Parameter url: Path to the `.zip` archive.
  /// - Returns: The parsed `BackupManifest` on success.
  /// - Throws: `BackupError` if the archive is invalid.
  static func validateBackup(at url: URL) throws -> BackupManifest {
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowValidate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try extractZip(from: url, to: tempDir)
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
  static func restoreFromBackup(
    at url: URL,
    modelContext: ModelContext,
    settingsService: SettingsService,
    checkpoint: ((BackupRestoreCheckpoint) throws -> Void)? = nil
  ) throws {
    // Extract once and validate
    let tempDir = FileManager.default.temporaryDirectory
      .appending(path: "AssetFlowRestore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try extractZip(from: url, to: tempDir)
    let backupRoot = try resolveBackupRoot(at: tempDir)
    let backup = try loadValidatedBackup(at: backupRoot)

    // Establish a clean rollback point before the destructive transaction.
    // If this save fails, no restore mutation has occurred.
    if modelContext.hasChanges {
      try modelContext.save()
    }

    let wasAutosaveEnabled = modelContext.autosaveEnabled
    modelContext.autosaveEnabled = false
    defer { modelContext.autosaveEnabled = wasAutosaveEnabled }

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
}
