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

/// Metadata stored in `manifest.json` inside a backup archive.
struct BackupManifest: Codable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case formatVersion
    case exportTimestamp
    case appVersion
  }

  let formatVersion: Int
  let exportTimestamp: String
  let appVersion: String

  nonisolated init(formatVersion: Int, exportTimestamp: String, appVersion: String) {
    self.formatVersion = formatVersion
    self.exportTimestamp = exportTimestamp
    self.appVersion = appVersion
  }

  nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    formatVersion = try container.decode(Int.self, forKey: .formatVersion)
    exportTimestamp = try container.decode(String.self, forKey: .exportTimestamp)
    appVersion = try container.decode(String.self, forKey: .appVersion)
  }

  nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(formatVersion, forKey: .formatVersion)
    try container.encode(exportTimestamp, forKey: .exportTimestamp)
    try container.encode(appVersion, forKey: .appVersion)
  }
}

enum BackupFormatVersion: Int, CaseIterable, Sendable {
  case v1 = 1
  case v2 = 2
  case v3 = 3

  nonisolated static let current = BackupFormatVersion.v3
}

struct BackupValidationIssue: Sendable {
  let file: String
  let row: Int?
  let column: String?
  let detail: String

  nonisolated init(file: String, row: Int? = nil, column: String? = nil, detail: String) {
    self.file = file
    self.row = row
    self.column = column
    self.detail = detail
  }

  nonisolated var formattedDescription: String {
    var location = file
    if let row { location += ":\(row)" }
    if let column { location += " [\(column)]" }
    return "\(location): \(detail)"
  }
}

/// Errors that can occur during backup export, validation, or restore.
enum BackupError: LocalizedError, Sendable {
  case invalidArchive
  case invalidArchiveLayout
  case missingFile(String)
  case invalidCSVHeaders(file: String, expected: [String], got: [String])
  case invalidForeignKey(file: String, column: String, value: String)
  case unsupportedFormatVersion(Int)
  case validationFailed([BackupValidationIssue])
  case restoreFailed(String)
  case corruptedData(String)

  nonisolated var errorDescription: String? {
    switch self {
    case .invalidArchive:
      String(localized: "The file is not a valid backup archive.", table: "Services")

    case .invalidArchiveLayout:
      String(
        localized:
          "The backup files must be at the ZIP root or inside one enclosing folder.",
        table: "Services")

    case .missingFile(let name):
      String(
        localized: "Missing required file: \(name)", table: "Services")

    case .invalidCSVHeaders(let file, let expected, let got):
      String(
        localized:
          "Invalid headers in \(file). Expected: \(expected.joined(separator: ", ")). Got: \(got.joined(separator: ", ")).",
        table: "Services")

    case .invalidForeignKey(let file, let column, let value):
      String(
        localized:
          "Invalid reference in \(file): \(column) '\(value)' not found.",
        table: "Services")

    case .unsupportedFormatVersion(let version):
      String(
        localized: "Unsupported backup format version: \(version).",
        table: "Services")

    case .validationFailed(let issues):
      String(
        localized:
          "Backup validation failed:\n\(issues.map(\.formattedDescription).joined(separator: "\n"))",
        table: "Services")

    case .restoreFailed(let detail):
      String(
        localized: "The backup could not be restored: \(detail)",
        table: "Services")

    case .corruptedData(let detail):
      String(
        localized: "Corrupted data: \(detail)", table: "Services")
    }
  }
}

// MARK: - Validated Transfer Types

struct ValidatedBackup: Sendable {
  let manifest: BackupManifest
  let categories: [BackupCategoryRecord]
  let assets: [BackupAssetRecord]
  let snapshots: [BackupSnapshotRecord]
  let snapshotAssetValues: [BackupSnapshotAssetValueRecord]
  let cashFlowOperations: [BackupCashFlowRecord]
  let exchangeRates: [BackupExchangeRateRecord]
  let settings: BackupSettingsRecord
}

/// Immutable snapshot of the SwiftData graph used by background export work.
struct BackupExportPayload: Sendable {
  let manifest: BackupManifest
  let categories: [BackupCategoryRecord]
  let assets: [BackupAssetRecord]
  let snapshots: [BackupSnapshotRecord]
  let snapshotAssetValues: [BackupSnapshotAssetValueRecord]
  let cashFlowOperations: [BackupCashFlowRecord]
  let exchangeRates: [BackupExchangeRateRecord]
  let settings: BackupSettingsRecord
}

struct BackupCategoryRecord: Sendable {
  let id: UUID
  let name: String
  let targetAllocationPercentage: Decimal?
  let displayOrder: Int
}

struct BackupAssetRecord: Sendable {
  let id: UUID
  let name: String
  let platform: String
  let categoryID: UUID?
  let currency: String
}

struct BackupSnapshotRecord: Sendable {
  let id: UUID
  let date: Date
  let createdAt: Date
}

struct BackupSnapshotAssetValueRecord: Sendable {
  let snapshotID: UUID
  let assetID: UUID
  let marketValue: Decimal
}

struct BackupCashFlowRecord: Sendable {
  let id: UUID
  let snapshotID: UUID
  let description: String
  let amount: Decimal
  let currency: String
}

struct BackupExchangeRateRecord: Sendable {
  let snapshotID: UUID
  let baseCurrency: String
  let fetchDate: Date
  let isFallback: Bool
  let ratesJSON: Data
}

struct BackupSettingsRecord: Sendable {
  let mainCurrency: String
  let dateFormat: DateFormatStyle
  let defaultPlatform: String
}

enum BackupRestoreCheckpoint: Sendable {
  case afterValidation
  case afterDeletion
  case afterCategoryInsertion
}

// MARK: - CSV Column Constants

enum BackupCSV {
  enum Categories {
    nonisolated static let fileName = "categories.csv"
    nonisolated static let headers = ["id", "name", "targetAllocationPercentage", "displayOrder"]
    nonisolated static let v1Headers = ["id", "name", "targetAllocationPercentage"]
  }

  enum Assets {
    nonisolated static let fileName = "assets.csv"
    nonisolated static let headers = ["id", "name", "platform", "categoryID", "currency"]
    nonisolated static let v2Headers = ["id", "name", "platform", "categoryID"]
  }

  enum Snapshots {
    nonisolated static let fileName = "snapshots.csv"
    nonisolated static let headers = ["id", "date", "createdAt"]
  }

  enum SnapshotAssetValues {
    nonisolated static let fileName = "snapshot_asset_values.csv"
    nonisolated static let headers = ["snapshotID", "assetID", "marketValue"]
  }

  enum CashFlowOperations {
    nonisolated static let fileName = "cash_flow_operations.csv"
    nonisolated static let headers = ["id", "snapshotID", "description", "amount", "currency"]
    nonisolated static let v2Headers = ["id", "snapshotID", "description", "amount"]
  }

  enum ExchangeRates {
    nonisolated static let fileName = "exchange_rates.csv"
    nonisolated static let headers = [
      "snapshotID", "baseCurrency", "fetchDate", "isFallback", "ratesJSON",
    ]
  }

  enum Settings {
    nonisolated static let fileName = "settings.csv"
    nonisolated static let headers = ["key", "value"]
  }

  nonisolated static let manifestFileName = "manifest.json"

  nonisolated static let allCSVFileNames = [
    Categories.fileName,
    Assets.fileName,
    Snapshots.fileName,
    SnapshotAssetValues.fileName,
    CashFlowOperations.fileName,
    Settings.fileName,
  ]

  /// CSV files required in all backup versions.
  nonisolated static let requiredCSVFileNames = allCSVFileNames

  /// CSV files that are optional (may not exist in older backups).
  nonisolated static let optionalCSVFileNames = [
    ExchangeRates.fileName
  ]
}
