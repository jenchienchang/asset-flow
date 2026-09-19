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

// MARK: - Scalar Validation Helpers

extension BackupService {

  static let backupDateFormatter = ISO8601DateFormatter()
  static let fractionalBackupDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func localizedBackupMessage(
    _ value: String.LocalizationValue
  ) -> String {
    String(localized: value, table: "Services")
  }

  static func scalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func validateArity(
    _ record: BackupCSVRecord,
    expected: Int,
    file: String,
    issues: inout [BackupValidationIssue]
  ) -> Bool {
    guard record.fields.count == expected else {
      issues.append(
        issue(
          file: file,
          record: record,
          detail: localizedBackupMessage(
            "Expected \(expected) fields but found \(record.fields.count)."
          )))
      return false
    }
    return true
  }

  static func parseUUID(
    _ value: String,
    file: String,
    record: BackupCSVRecord,
    column: String,
    issues: inout [BackupValidationIssue]
  ) -> UUID? {
    guard let id = UUID(uuidString: scalar(value)) else {
      issues.append(
        issue(
          file: file,
          record: record,
          column: column,
          detail: localizedBackupMessage("Expected a UUID.")))
      return nil
    }
    return id
  }

  static func parseOptionalUUID(
    _ value: String,
    file: String,
    record: BackupCSVRecord,
    column: String,
    issues: inout [BackupValidationIssue]
  ) -> UUID? {
    let trimmed = scalar(value)
    guard !trimmed.isEmpty else { return nil }
    return parseUUID(
      trimmed,
      file: file,
      record: record,
      column: column,
      issues: &issues)
  }

  static func validateUniqueID(
    _ id: UUID,
    ids: inout Set<UUID>,
    file: String,
    record: BackupCSVRecord,
    issues: inout [BackupValidationIssue]
  ) {
    if !ids.insert(id).inserted {
      issues.append(
        issue(
          file: file,
          record: record,
          column: "id",
          detail: localizedBackupMessage(
            "Duplicate entity ID '\(id.uuidString)'.")))
    }
  }

  static func parseDate(
    _ value: String,
    file: String,
    record: BackupCSVRecord,
    column: String,
    issues: inout [BackupValidationIssue]
  ) -> Date? {
    guard let date = strictISO8601Date(value) else {
      issues.append(
        issue(
          file: file,
          record: record,
          column: column,
          detail: localizedBackupMessage("Expected an ISO 8601 date.")))
      return nil
    }
    return date
  }

  static func strictISO8601Date(_ value: String) -> Date? {
    let text = scalar(value)
    let bytes = Array(text.utf8)
    guard bytes.count >= 20 else { return nil }

    let digitOffsets = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
    guard digitOffsets.allSatisfy({ bytes[$0].isASCIIDigit }),
      bytes[4] == 0x2D,
      bytes[7] == 0x2D,
      bytes[10] == 0x54,
      bytes[13] == 0x3A,
      bytes[16] == 0x3A
    else { return nil }

    var index = 19
    var hasFractionalSeconds = false
    if index < bytes.count, bytes[index] == 0x2E {
      hasFractionalSeconds = true
      index += 1
      let fractionStart = index
      while index < bytes.count, bytes[index].isASCIIDigit {
        index += 1
      }
      guard index > fractionStart else { return nil }
    }

    guard validateTimeZone(in: bytes, index: &index),
      index == bytes.count
    else { return nil }

    let formatter =
      hasFractionalSeconds
      ? fractionalBackupDateFormatter
      : backupDateFormatter
    return formatter.date(from: text)
  }

  private static func validateTimeZone(
    in bytes: [UInt8],
    index: inout Int
  ) -> Bool {
    guard index < bytes.count else { return false }
    if bytes[index] == 0x5A {
      index += 1
      return true
    }

    guard bytes[index] == 0x2B || bytes[index] == 0x2D,
      index + 6 == bytes.count,
      bytes[index + 1].isASCIIDigit,
      bytes[index + 2].isASCIIDigit,
      bytes[index + 3] == 0x3A,
      bytes[index + 4].isASCIIDigit,
      bytes[index + 5].isASCIIDigit
    else { return false }
    index += 6
    return true
  }

  static func parseDecimal(
    _ value: String,
    file: String,
    record: BackupCSVRecord,
    column: String,
    issues: inout [BackupValidationIssue]
  ) -> Decimal? {
    guard let decimal = strictDecimal(value) else {
      issues.append(
        issue(
          file: file,
          record: record,
          column: column,
          detail: localizedBackupMessage("Expected a decimal value.")))
      return nil
    }
    return decimal
  }

  static func strictDecimal(_ value: String) -> Decimal? {
    let text = scalar(value)
    let bytes = Array(text.utf8)
    guard !bytes.isEmpty else { return nil }

    var index = 0
    if bytes[index] == 0x2B || bytes[index] == 0x2D {
      index += 1
    }

    var digitCount = 0
    consumeDigits(in: bytes, index: &index, count: &digitCount)
    if index < bytes.count, bytes[index] == 0x2E {
      index += 1
      consumeDigits(in: bytes, index: &index, count: &digitCount)
    }
    guard digitCount > 0 else { return nil }

    if index < bytes.count, bytes[index] == 0x45 || bytes[index] == 0x65 {
      index += 1
      if index < bytes.count,
        bytes[index] == 0x2B || bytes[index] == 0x2D
      {
        index += 1
      }
      var exponentDigits = 0
      consumeDigits(
        in: bytes,
        index: &index,
        count: &exponentDigits)
      guard exponentDigits > 0 else { return nil }
    }

    guard index == bytes.count,
      let decimal = Decimal(
        string: text,
        locale: Locale(identifier: "en_US_POSIX")),
      decimal.isFinite,
      !decimal.isNaN
    else { return nil }
    return decimal
  }

  private static func consumeDigits(
    in bytes: [UInt8],
    index: inout Int,
    count: inout Int
  ) {
    while index < bytes.count, bytes[index].isASCIIDigit {
      count += 1
      index += 1
    }
  }

  static func issue(
    file: String,
    record: BackupCSVRecord? = nil,
    column: String? = nil,
    detail: String
  ) -> BackupValidationIssue {
    BackupValidationIssue(
      file: file,
      row: record?.row,
      column: column,
      detail: detail)
  }
}

extension UInt8 {
  fileprivate var isASCIIDigit: Bool {
    self >= 0x30 && self <= 0x39
  }
}
