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

// MARK: - CSV Writing

extension BackupService {

  nonisolated static func writeCategoriesCSV(
    _ categories: [BackupCategoryRecord], to dir: URL
  ) throws {
    var lines = [BackupCSV.Categories.headers.joined(separator: ",")]
    for cat in categories {
      lines.append(
        csvLine([
          cat.id.uuidString,
          csvEscape(cat.name),
          cat.targetAllocationPercentage.map { "\($0)" } ?? "",
          "\(cat.displayOrder)",
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(path: BackupCSV.Categories.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeAssetsCSV(
    _ assets: [BackupAssetRecord], to dir: URL
  ) throws {
    var lines = [BackupCSV.Assets.headers.joined(separator: ",")]
    for asset in assets {
      lines.append(
        csvLine([
          asset.id.uuidString,
          csvEscape(asset.name),
          csvEscape(asset.platform),
          asset.categoryID?.uuidString ?? "",
          csvEscape(asset.currency),
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(path: BackupCSV.Assets.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeSnapshotsCSV(
    _ snapshots: [BackupSnapshotRecord], to dir: URL
  ) throws {
    let dateFormatter = ISO8601DateFormatter()
    var lines = [BackupCSV.Snapshots.headers.joined(separator: ",")]
    for snapshot in snapshots {
      lines.append(
        csvLine([
          snapshot.id.uuidString,
          dateFormatter.string(from: snapshot.date),
          dateFormatter.string(from: snapshot.createdAt),
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(path: BackupCSV.Snapshots.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeSnapshotAssetValuesCSV(
    _ values: [BackupSnapshotAssetValueRecord], to dir: URL
  ) throws {
    var lines = [
      BackupCSV.SnapshotAssetValues.headers.joined(separator: ",")
    ]
    for sav in values {
      lines.append(
        csvLine([
          sav.snapshotID.uuidString,
          sav.assetID.uuidString,
          "\(sav.marketValue)",
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(
          path: BackupCSV.SnapshotAssetValues.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeCashFlowOperationsCSV(
    _ operations: [BackupCashFlowRecord], to dir: URL
  ) throws {
    var lines = [
      BackupCSV.CashFlowOperations.headers.joined(separator: ",")
    ]
    for op in operations {
      lines.append(
        csvLine([
          op.id.uuidString,
          op.snapshotID.uuidString,
          csvEscape(op.description),
          "\(op.amount)",
          csvEscape(op.currency),
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(
          path: BackupCSV.CashFlowOperations.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeExchangeRatesCSV(
    _ exchangeRates: [BackupExchangeRateRecord], to dir: URL
  ) throws {
    let dateFormatter = ISO8601DateFormatter()
    var lines = [BackupCSV.ExchangeRates.headers.joined(separator: ",")]
    for er in exchangeRates {
      // Encode ratesJSON as base64 to avoid CSV escaping issues with JSON
      let ratesBase64 = er.ratesJSON.base64EncodedString()
      lines.append(
        csvLine([
          er.snapshotID.uuidString,
          csvEscape(er.baseCurrency),
          dateFormatter.string(from: er.fetchDate),
          er.isFallback ? "true" : "false",
          ratesBase64,
        ]))
    }
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(path: BackupCSV.ExchangeRates.fileName),
        atomically: true, encoding: .utf8)
  }

  nonisolated static func writeSettingsCSV(
    _ settings: BackupSettingsRecord, to dir: URL
  ) throws {
    var lines = [BackupCSV.Settings.headers.joined(separator: ",")]
    lines.append(
      csvLine(["displayCurrency", csvEscape(settings.mainCurrency)]))
    lines.append(
      csvLine([
        "dateFormat", csvEscape(settings.dateFormat.rawValue),
      ]))
    lines.append(
      csvLine([
        "defaultPlatform", csvEscape(settings.defaultPlatform),
      ]))
    try lines.joined(separator: "\n")
      .write(
        to: dir.appending(path: BackupCSV.Settings.fileName),
        atomically: true, encoding: .utf8)
  }
}

// MARK: - CSV Helpers

extension BackupService {

  private nonisolated static func csvLine(_ fields: [String]) -> String {
    fields.joined(separator: ",")
  }

  private nonisolated static func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n")
      || value.contains("\r")
    {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }
}
