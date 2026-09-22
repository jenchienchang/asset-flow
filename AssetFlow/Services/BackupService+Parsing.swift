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

// MARK: - Typed Backup Loading

extension BackupService {

  private nonisolated static let maximumManifestSize = 1 * 1_024 * 1_024
  private nonisolated static let maximumCSVSize = 128 * 1_024 * 1_024

  nonisolated static func loadValidatedBackup(at dir: URL) throws -> ValidatedBackup {
    var issues: [BackupValidationIssue] = []
    let manifest = try loadManifest(from: dir, issues: &issues)

    guard let version = BackupFormatVersion(rawValue: manifest.formatVersion) else {
      throw BackupError.unsupportedFormatVersion(manifest.formatVersion)
    }

    var documents: [String: BackupCSVDocument] = [:]
    for fileName in BackupCSV.requiredCSVFileNames {
      let fileURL = dir.appending(path: fileName)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        throw BackupError.missingFile(fileName)
      }
      documents[fileName] = try loadCSVDocument(
        at: fileURL,
        fileName: fileName,
        expectedHeaders: expectedHeaders(for: fileName, version: version)
      )
    }

    let exchangeRateURL = dir.appending(path: BackupCSV.ExchangeRates.fileName)
    let hasExchangeRates = FileManager.default.fileExists(
      atPath: exchangeRateURL.path)
    if hasExchangeRates {
      if version == .v3 {
        documents[BackupCSV.ExchangeRates.fileName] = try loadCSVDocument(
          at: exchangeRateURL,
          fileName: BackupCSV.ExchangeRates.fileName,
          expectedHeaders: BackupCSV.ExchangeRates.headers
        )
      } else {
        issues.append(
          issue(
            file: BackupCSV.ExchangeRates.fileName,
            detail: localizedBackupMessage(
              "This file is not supported by backup format version \(version.rawValue)."
            )
          ))
      }
    }

    let categories = parseCategories(
      documents[BackupCSV.Categories.fileName], version: version, issues: &issues)
    let assets = parseAssets(
      documents[BackupCSV.Assets.fileName], version: version, issues: &issues)
    let snapshots = parseSnapshots(
      documents[BackupCSV.Snapshots.fileName], issues: &issues)
    let snapshotAssetValues = parseSnapshotAssetValues(
      documents[BackupCSV.SnapshotAssetValues.fileName], issues: &issues)
    let cashFlowOperations = parseCashFlowOperations(
      documents[BackupCSV.CashFlowOperations.fileName],
      version: version,
      issues: &issues)
    let exchangeRates = parseExchangeRates(
      documents[BackupCSV.ExchangeRates.fileName], issues: &issues)
    let settings = parseSettings(
      documents[BackupCSV.Settings.fileName], issues: &issues)

    validateRelationships(
      categories: categories,
      assets: assets,
      snapshots: snapshots,
      snapshotAssetValues: snapshotAssetValues,
      cashFlowOperations: cashFlowOperations,
      exchangeRates: exchangeRates,
      issues: &issues
    )

    guard issues.isEmpty, let settings else {
      throw BackupError.validationFailed(issues)
    }

    return ValidatedBackup(
      manifest: manifest,
      categories: categories,
      assets: assets,
      snapshots: snapshots,
      snapshotAssetValues: snapshotAssetValues,
      cashFlowOperations: cashFlowOperations,
      exchangeRates: exchangeRates,
      settings: settings
    )
  }

  private nonisolated static func loadManifest(
    from dir: URL,
    issues: inout [BackupValidationIssue]
  ) throws -> BackupManifest {
    let fileName = BackupCSV.manifestFileName
    let url = dir.appending(path: fileName)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw BackupError.missingFile(fileName)
    }

    let data = try readRegularFile(
      at: url, fileName: fileName, maximumSize: maximumManifestSize)
    let manifest: BackupManifest
    do {
      manifest = try JSONDecoder().decode(BackupManifest.self, from: data)
    } catch {
      throw BackupError.corruptedData(
        localizedBackupMessage(
          "Invalid manifest.json: \(error.localizedDescription)"))
    }

    if strictISO8601Date(manifest.exportTimestamp) == nil {
      issues.append(
        issue(
          file: fileName, column: "exportTimestamp",
          detail: localizedBackupMessage(
            "Expected a valid ISO 8601 timestamp.")))
    }
    if manifest.appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        issue(
          file: fileName, column: "appVersion",
          detail: localizedBackupMessage(
            "The app version must not be empty.")))
    }
    return manifest
  }

  private nonisolated static func expectedHeaders(
    for fileName: String,
    version: BackupFormatVersion
  ) -> [String] {
    switch fileName {
    case BackupCSV.Categories.fileName:
      version == .v1 ? BackupCSV.Categories.v1Headers : BackupCSV.Categories.headers

    case BackupCSV.Assets.fileName:
      version == .v3 ? BackupCSV.Assets.headers : BackupCSV.Assets.v2Headers

    case BackupCSV.Snapshots.fileName:
      BackupCSV.Snapshots.headers

    case BackupCSV.SnapshotAssetValues.fileName:
      BackupCSV.SnapshotAssetValues.headers

    case BackupCSV.CashFlowOperations.fileName:
      version == .v3
        ? BackupCSV.CashFlowOperations.headers
        : BackupCSV.CashFlowOperations.v2Headers

    case BackupCSV.Settings.fileName:
      BackupCSV.Settings.headers

    default:
      []
    }
  }

  private nonisolated static func loadCSVDocument(
    at url: URL,
    fileName: String,
    expectedHeaders: [String]
  ) throws -> BackupCSVDocument {
    let data = try readRegularFile(
      at: url, fileName: fileName, maximumSize: maximumCSVSize)
    let records = try parseCSVRecords(data, fileName: fileName)
    guard let header = records.first else {
      throw BackupError.invalidCSVHeaders(
        file: fileName, expected: expectedHeaders, got: [])
    }
    guard header.fields == expectedHeaders else {
      throw BackupError.invalidCSVHeaders(
        file: fileName, expected: expectedHeaders, got: header.fields)
    }
    return BackupCSVDocument(records: Array(records.dropFirst()))
  }

  private nonisolated static func readRegularFile(
    at url: URL,
    fileName: String,
    maximumSize: Int
  ) throws -> Data {
    let values = try url.resourceValues(
      forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw BackupError.validationFailed([
        issue(
          file: fileName,
          detail: localizedBackupMessage("Expected a regular file."))
      ])
    }
    guard (values.fileSize ?? 0) <= maximumSize else {
      throw BackupError.validationFailed([
        issue(
          file: fileName,
          detail: localizedBackupMessage(
            "The file exceeds the supported size limit."))
      ])
    }
    return try Data(contentsOf: url)
  }
}
