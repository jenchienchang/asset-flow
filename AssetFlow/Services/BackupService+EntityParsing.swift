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

// MARK: - Entity Parsing

extension BackupService {

  static func parseCategories(
    _ document: BackupCSVDocument?,
    version: BackupFormatVersion,
    issues: inout [BackupValidationIssue]
  ) -> [BackupCategoryRecord] {
    let file = BackupCSV.Categories.fileName
    let expectedCount = version == .v1 ? 3 : 4
    var result: [BackupCategoryRecord] = []
    var ids: Set<UUID> = []
    var identities: Set<String> = []

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: expectedCount,
          file: file,
          issues: &issues
        )
      else {
        continue
      }
      let id = parseUUID(
        record.fields[0], file: file, record: record,
        column: "id", issues: &issues)

      let name = record.fields[1]
      let normalizedName = name.normalizedForIdentity
      if normalizedName.isEmpty {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "name",
            detail: localizedBackupMessage(
              "The name must not be empty.")))
      } else if !identities.insert(normalizedName).inserted {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "name",
            detail: localizedBackupMessage(
              "Duplicate normalized category name.")))
      }

      let rawTarget = scalar(record.fields[2])
      let target: Decimal?
      if rawTarget.isEmpty {
        target = nil
      } else if let parsed = strictDecimal(rawTarget),
        parsed >= 0, parsed <= 100
      {
        target = parsed
      } else {
        target = nil
        issues.append(
          issue(
            file: file,
            record: record,
            column: "targetAllocationPercentage",
            detail: localizedBackupMessage(
              "Expected a decimal from 0 through 100, or an empty value."
            )))
      }

      let displayOrder: Int
      if version == .v1 {
        displayOrder = 0
      } else if let parsed = Int(scalar(record.fields[3])), parsed >= 0 {
        displayOrder = parsed
      } else {
        displayOrder = 0
        issues.append(
          issue(
            file: file,
            record: record,
            column: "displayOrder",
            detail: localizedBackupMessage(
              "Expected a nonnegative integer.")))
      }

      guard let id else { continue }
      validateUniqueID(
        id,
        ids: &ids,
        file: file,
        record: record,
        issues: &issues)
      result.append(
        BackupCategoryRecord(
          id: id, name: name, targetAllocationPercentage: target,
          displayOrder: displayOrder))
    }
    return result
  }

  static func parseAssets(
    _ document: BackupCSVDocument?,
    version: BackupFormatVersion,
    issues: inout [BackupValidationIssue]
  ) -> [BackupAssetRecord] {
    let file = BackupCSV.Assets.fileName
    let expectedCount = version == .v3 ? 5 : 4
    var result: [BackupAssetRecord] = []
    var ids: Set<UUID> = []
    var identities: Set<String> = []

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: expectedCount,
          file: file,
          issues: &issues
        )
      else {
        continue
      }
      let id = parseUUID(
        record.fields[0], file: file, record: record,
        column: "id", issues: &issues)

      let name = record.fields[1]
      let platform = record.fields[2]
      let identity = "\(name.normalizedForIdentity)|\(platform.normalizedForIdentity)"
      if name.normalizedForIdentity.isEmpty {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "name",
            detail: localizedBackupMessage(
              "The name must not be empty.")))
      } else if !identities.insert(identity).inserted {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "name",
            detail: localizedBackupMessage(
              "Duplicate normalized asset identity.")))
      }

      let categoryID = parseOptionalUUID(
        record.fields[3], file: file, record: record,
        column: "categoryID", issues: &issues)
      let currency = version == .v3 ? record.fields[4] : ""
      guard let id else { continue }
      validateUniqueID(
        id,
        ids: &ids,
        file: file,
        record: record,
        issues: &issues)
      result.append(
        BackupAssetRecord(
          id: id, name: name, platform: platform,
          categoryID: categoryID, currency: currency))
    }
    return result
  }

  static func parseSnapshots(
    _ document: BackupCSVDocument?,
    issues: inout [BackupValidationIssue]
  ) -> [BackupSnapshotRecord] {
    let file = BackupCSV.Snapshots.fileName
    var result: [BackupSnapshotRecord] = []
    var ids: Set<UUID> = []
    var dates: Set<Date> = []

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: 3,
          file: file,
          issues: &issues
        )
      else { continue }
      let id = parseUUID(
        record.fields[0], file: file, record: record,
        column: "id", issues: &issues)
      let date = parseDate(
        record.fields[1], file: file,
        record: record, column: "date", issues: &issues)
      let createdAt = parseDate(
        record.fields[2], file: file,
        record: record, column: "createdAt", issues: &issues)
      if let id {
        validateUniqueID(
          id,
          ids: &ids,
          file: file,
          record: record,
          issues: &issues)
      }
      guard let id, let date, let createdAt else { continue }

      let normalizedDate = Calendar.current.startOfDay(for: date)
      if !dates.insert(normalizedDate).inserted {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "date",
            detail: localizedBackupMessage(
              "Duplicate normalized snapshot date.")))
      }
      result.append(
        BackupSnapshotRecord(
          id: id,
          date: date,
          createdAt: createdAt))
    }
    return result
  }

  static func parseSnapshotAssetValues(
    _ document: BackupCSVDocument?,
    issues: inout [BackupValidationIssue]
  ) -> [BackupSnapshotAssetValueRecord] {
    let file = BackupCSV.SnapshotAssetValues.fileName
    var result: [BackupSnapshotAssetValueRecord] = []
    var identities: Set<String> = []

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: 3,
          file: file,
          issues: &issues
        )
      else { continue }
      let snapshotID = parseUUID(
        record.fields[0], file: file, record: record,
        column: "snapshotID", issues: &issues)
      let assetID = parseUUID(
        record.fields[1], file: file, record: record,
        column: "assetID", issues: &issues)
      let marketValue = parseDecimal(
        record.fields[2], file: file, record: record,
        column: "marketValue", issues: &issues)
      guard let snapshotID, let assetID, let marketValue else { continue }

      let identity = "\(snapshotID.uuidString)|\(assetID.uuidString)"
      if !identities.insert(identity).inserted {
        issues.append(
          issue(
            file: file,
            record: record,
            detail: localizedBackupMessage(
              "Duplicate snapshot and asset relationship.")))
      }
      result.append(
        BackupSnapshotAssetValueRecord(
          snapshotID: snapshotID, assetID: assetID, marketValue: marketValue))
    }
    return result
  }
}
