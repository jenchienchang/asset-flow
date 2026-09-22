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

// MARK: - Graph Validation

extension BackupService {

  nonisolated static func validateRelationships(
    categories: [BackupCategoryRecord],
    assets: [BackupAssetRecord],
    snapshots: [BackupSnapshotRecord],
    snapshotAssetValues: [BackupSnapshotAssetValueRecord],
    cashFlowOperations: [BackupCashFlowRecord],
    exchangeRates: [BackupExchangeRateRecord],
    issues: inout [BackupValidationIssue]
  ) {
    let categoryIDs = Set(categories.map(\.id))
    let assetIDs = Set(assets.map(\.id))
    let snapshotIDs = Set(snapshots.map(\.id))

    for asset in assets {
      if let categoryID = asset.categoryID, !categoryIDs.contains(categoryID) {
        issues.append(
          issue(
            file: BackupCSV.Assets.fileName,
            column: "categoryID",
            detail: localizedBackupMessage(
              "Category ID '\(categoryID.uuidString)' was not found.")))
      }
    }
    for value in snapshotAssetValues {
      if !snapshotIDs.contains(value.snapshotID) {
        issues.append(
          issue(
            file: BackupCSV.SnapshotAssetValues.fileName,
            column: "snapshotID",
            detail: localizedBackupMessage(
              "Snapshot ID '\(value.snapshotID.uuidString)' was not found.")))
      }
      if !assetIDs.contains(value.assetID) {
        issues.append(
          issue(
            file: BackupCSV.SnapshotAssetValues.fileName,
            column: "assetID",
            detail: localizedBackupMessage(
              "Asset ID '\(value.assetID.uuidString)' was not found.")))
      }
    }
    for operation in cashFlowOperations where !snapshotIDs.contains(operation.snapshotID) {
      issues.append(
        issue(
          file: BackupCSV.CashFlowOperations.fileName,
          column: "snapshotID",
          detail: localizedBackupMessage(
            "Snapshot ID '\(operation.snapshotID.uuidString)' was not found.")))
    }
    for rate in exchangeRates where !snapshotIDs.contains(rate.snapshotID) {
      issues.append(
        issue(
          file: BackupCSV.ExchangeRates.fileName,
          column: "snapshotID",
          detail: localizedBackupMessage(
            "Snapshot ID '\(rate.snapshotID.uuidString)' was not found.")))
    }
  }
}
