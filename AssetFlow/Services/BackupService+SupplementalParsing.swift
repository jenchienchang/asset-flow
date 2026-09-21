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

// MARK: - Supplemental Entity Parsing

extension BackupService {

  static func parseCashFlowOperations(
    _ document: BackupCSVDocument?,
    version: BackupFormatVersion,
    issues: inout [BackupValidationIssue]
  ) -> [BackupCashFlowRecord] {
    let file = BackupCSV.CashFlowOperations.fileName
    let expectedCount = version == .v3 ? 5 : 4
    var result: [BackupCashFlowRecord] = []
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
      let snapshotID = parseUUID(
        record.fields[1], file: file, record: record,
        column: "snapshotID", issues: &issues)
      let amount = parseDecimal(
        record.fields[3], file: file, record: record,
        column: "amount", issues: &issues)
      if let id {
        validateUniqueID(
          id,
          ids: &ids,
          file: file,
          record: record,
          issues: &issues)
      }

      let description = record.fields[2]
      let normalizedDescription = description.normalizedForIdentity
      if normalizedDescription.isEmpty {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "description",
            detail: localizedBackupMessage(
              "The description must not be empty.")))
      }
      if let snapshotID {
        let identity = "\(snapshotID.uuidString)|\(normalizedDescription)"
        if !normalizedDescription.isEmpty, !identities.insert(identity).inserted {
          issues.append(
            issue(
              file: file,
              record: record,
              column: "description",
              detail: localizedBackupMessage(
                "Duplicate normalized cash-flow description for this snapshot."
              )))
        }
      }

      guard let id, let snapshotID, let amount else { continue }
      result.append(
        BackupCashFlowRecord(
          id: id, snapshotID: snapshotID, description: description,
          amount: amount, currency: version == .v3 ? record.fields[4] : ""))
    }
    return result
  }

  static func parseExchangeRates(
    _ document: BackupCSVDocument?,
    issues: inout [BackupValidationIssue]
  ) -> [BackupExchangeRateRecord] {
    let file = BackupCSV.ExchangeRates.fileName
    var result: [BackupExchangeRateRecord] = []
    var snapshotIDs: Set<UUID> = []

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: 5,
          file: file,
          issues: &issues
        )
      else { continue }
      let snapshotID = parseUUID(
        record.fields[0], file: file, record: record,
        column: "snapshotID", issues: &issues)
      let fetchDate = parseDate(
        record.fields[2], file: file,
        record: record, column: "fetchDate", issues: &issues)

      let baseCurrency = record.fields[1]
      if baseCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "baseCurrency",
            detail: localizedBackupMessage(
              "The base currency must not be empty.")))
      }

      let rawFallback = scalar(record.fields[3])
      let isFallback: Bool
      switch rawFallback {
      case "true": isFallback = true
      case "false": isFallback = false

      default:
        isFallback = false
        issues.append(
          issue(
            file: file,
            record: record,
            column: "isFallback",
            detail: localizedBackupMessage(
              "Expected 'true' or 'false'.")))
      }

      guard let ratesData = Data(base64Encoded: scalar(record.fields[4])) else {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "ratesJSON",
            detail: localizedBackupMessage(
              "Expected valid base64 data.")))
        continue
      }
      do {
        let rates = try JSONDecoder().decode([String: Decimal].self, from: ratesData)
        let hasInvalidRate = rates.contains {
          $0.key.isEmpty || !$0.value.isFinite || $0.value <= 0
        }
        if rates.isEmpty || hasInvalidRate {
          issues.append(
            issue(
              file: file,
              record: record,
              column: "ratesJSON",
              detail: localizedBackupMessage(
                "Rates must be a nonempty dictionary of positive finite values."
              )))
        }
      } catch {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "ratesJSON",
            detail: localizedBackupMessage(
              "Expected an encoded exchange-rate dictionary.")))
      }

      guard let snapshotID, let fetchDate else { continue }
      if !snapshotIDs.insert(snapshotID).inserted {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "snapshotID",
            detail: localizedBackupMessage(
              "Only one exchange-rate record is allowed per snapshot.")))
      }
      result.append(
        BackupExchangeRateRecord(
          snapshotID: snapshotID, baseCurrency: baseCurrency,
          fetchDate: fetchDate, isFallback: isFallback,
          ratesJSON: ratesData))
    }
    return result
  }

  static func parseSettings(
    _ document: BackupCSVDocument?,
    issues: inout [BackupValidationIssue]
  ) -> BackupSettingsRecord? {
    let file = BackupCSV.Settings.fileName
    let expectedKeys: Set<String> = [
      "displayCurrency", "dateFormat", "defaultPlatform",
    ]
    var values: [String: String] = [:]

    for record in document?.records ?? [] {
      guard
        validateArity(
          record,
          expected: 2,
          file: file,
          issues: &issues
        )
      else { continue }
      let key = scalar(record.fields[0])
      guard expectedKeys.contains(key) else {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "key",
            detail: localizedBackupMessage(
              "Unknown settings key '\(key)'.")))
        continue
      }
      guard values[key] == nil else {
        issues.append(
          issue(
            file: file,
            record: record,
            column: "key",
            detail: localizedBackupMessage(
              "Duplicate settings key '\(key)'.")))
        continue
      }
      values[key] = record.fields[1]
    }

    for key in expectedKeys where values[key] == nil {
      issues.append(
        issue(
          file: file,
          column: "key",
          detail: localizedBackupMessage(
            "Missing required settings key '\(key)'.")))
    }
    guard
      let mainCurrency = values["displayCurrency"],
      let rawDateFormat = values["dateFormat"],
      let defaultPlatform = values["defaultPlatform"]
    else { return nil }

    if mainCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        issue(
          file: file,
          column: "displayCurrency",
          detail: localizedBackupMessage(
            "The display currency must not be empty.")))
    }
    guard let dateFormat = DateFormatStyle(rawValue: scalar(rawDateFormat)) else {
      issues.append(
        issue(
          file: file,
          column: "dateFormat",
          detail: localizedBackupMessage(
            "Unknown date format '\(rawDateFormat)'.")))
      return nil
    }
    return BackupSettingsRecord(
      mainCurrency: mainCurrency,
      dateFormat: dateFormat,
      defaultPlatform: defaultPlatform)
  }
}
