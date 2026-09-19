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
  let formatVersion: Int
  let exportTimestamp: String
  let appVersion: String
}

enum BackupFormatVersion: Int, CaseIterable, Sendable {
  case v1 = 1
  case v2 = 2
  case v3 = 3

  static let current = BackupFormatVersion.v3
}

struct BackupValidationIssue: Sendable {
  let file: String
  let row: Int?
  let column: String?
  let detail: String

  nonisolated var formattedDescription: String {
    var location = file
    if let row { location += ":\(row)" }
    if let column { location += " [\(column)]" }
    return "\(location): \(detail)"
  }
}

/// Errors that can occur during backup export, validation, or restore.
enum BackupError: LocalizedError {
  case invalidArchive
  case missingFile(String)
  case invalidCSVHeaders(file: String, expected: [String], got: [String])
  case invalidForeignKey(file: String, column: String, value: String)
  case unsupportedFormatVersion(Int)
  case validationFailed([BackupValidationIssue])
  case restoreFailed(String)
  case corruptedData(String)

  var errorDescription: String? {
    switch self {
    case .invalidArchive:
      String(localized: "The file is not a valid backup archive.", table: "Services")

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
  case afterDeletion
  case afterCategoryInsertion
}

// MARK: - CSV Column Constants

enum BackupCSV {
  enum Categories {
    static let fileName = "categories.csv"
    static let headers = ["id", "name", "targetAllocationPercentage", "displayOrder"]
    static let v1Headers = ["id", "name", "targetAllocationPercentage"]
  }

  enum Assets {
    static let fileName = "assets.csv"
    static let headers = ["id", "name", "platform", "categoryID", "currency"]
    static let v2Headers = ["id", "name", "platform", "categoryID"]
  }

  enum Snapshots {
    static let fileName = "snapshots.csv"
    static let headers = ["id", "date", "createdAt"]
  }

  enum SnapshotAssetValues {
    static let fileName = "snapshot_asset_values.csv"
    static let headers = ["snapshotID", "assetID", "marketValue"]
  }

  enum CashFlowOperations {
    static let fileName = "cash_flow_operations.csv"
    static let headers = ["id", "snapshotID", "description", "amount", "currency"]
    static let v2Headers = ["id", "snapshotID", "description", "amount"]
  }

  enum ExchangeRates {
    static let fileName = "exchange_rates.csv"
    static let headers = ["snapshotID", "baseCurrency", "fetchDate", "isFallback", "ratesJSON"]
  }

  enum Settings {
    static let fileName = "settings.csv"
    static let headers = ["key", "value"]
  }

  static let manifestFileName = "manifest.json"

  static let allCSVFileNames = [
    Categories.fileName,
    Assets.fileName,
    Snapshots.fileName,
    SnapshotAssetValues.fileName,
    CashFlowOperations.fileName,
    Settings.fileName,
  ]

  /// CSV files required in all backup versions.
  static let requiredCSVFileNames = allCSVFileNames

  /// CSV files that are optional (may not exist in older backups).
  static let optionalCSVFileNames = [
    ExchangeRates.fileName
  ]
}
