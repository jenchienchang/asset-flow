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

struct BackupCSVRecord {
  let row: Int
  let fields: [String]
}

struct BackupCSVDocument {
  let records: [BackupCSVRecord]
}

// MARK: - Record-Aware CSV Parsing

extension BackupService {

  static func parseCSVRecords(
    _ data: Data,
    fileName: String
  ) throws -> [BackupCSVRecord] {
    var parser = try BackupCSVParser(data: data, fileName: fileName)
    return try parser.parse()
  }
}

@MainActor
private struct BackupCSVParser {
  private let fileName: String
  private var bytes: [UInt8]
  private var records: [BackupCSVRecord] = []
  private var fields: [String] = []
  private var field: [UInt8] = []
  private var inQuotes = false
  private var quoteClosed = false
  private var recordHasExplicitSyntax = false
  private var recordStartLine = 1
  private var line = 1
  private var index = 0

  init(data: Data, fileName: String) throws {
    var input = Array(data)
    if input.starts(with: [0xEF, 0xBB, 0xBF]) {
      input.removeFirst(3)
    }
    guard String(bytes: input, encoding: .utf8) != nil else {
      throw BackupError.validationFailed([
        BackupService.issue(
          file: fileName,
          detail: BackupService.localizedBackupMessage(
            "Expected UTF-8 encoded text."))
      ])
    }
    self.fileName = fileName
    self.bytes = input
  }

  mutating func parse() throws -> [BackupCSVRecord] {
    while index < bytes.count {
      if inQuotes {
        consumeQuotedByte()
      } else if quoteClosed {
        try consumeByteAfterClosingQuote()
      } else {
        try consumeUnquotedByte()
      }
    }
    try finishDocument()
    return records
  }

  private mutating func consumeQuotedByte() {
    let byte = bytes[index]
    if byte == 0x22 {
      if index + 1 < bytes.count, bytes[index + 1] == 0x22 {
        field.append(0x22)
        index += 2
      } else {
        inQuotes = false
        quoteClosed = true
        index += 1
      }
      return
    }

    field.append(byte)
    if byte == 0x0D {
      if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
        field.append(0x0A)
        index += 1
      }
      line += 1
    } else if byte == 0x0A {
      line += 1
    }
    index += 1
  }

  private mutating func consumeByteAfterClosingQuote() throws {
    let byte = bytes[index]
    if byte == 0x2C {
      finishField()
      quoteClosed = false
      index += 1
    } else if byte == 0x0A || byte == 0x0D {
      finishRecord(terminator: byte)
    } else {
      throw validationError(
        row: line,
        detail: BackupService.localizedBackupMessage(
          "Unexpected character after a closing quote."))
    }
  }

  private mutating func consumeUnquotedByte() throws {
    let byte = bytes[index]
    switch byte {
    case 0x22:
      guard field.isEmpty else {
        throw validationError(
          row: line,
          detail: BackupService.localizedBackupMessage(
            "Unexpected quote in an unquoted field."))
      }
      recordHasExplicitSyntax = true
      inQuotes = true
      index += 1

    case 0x2C:
      recordHasExplicitSyntax = true
      finishField()
      index += 1

    case 0x0A, 0x0D:
      finishRecord(terminator: byte)

    default:
      field.append(byte)
      index += 1
    }
  }

  private mutating func finishField() {
    fields.append(String(decoding: field, as: UTF8.self))
    field = []
  }

  private mutating func finishRecord(terminator: UInt8) {
    finishField()
    appendRecordUnlessBlank()
    fields = []
    quoteClosed = false
    recordHasExplicitSyntax = false

    if terminator == 0x0D,
      index + 1 < bytes.count,
      bytes[index + 1] == 0x0A
    {
      index += 1
    }
    line += 1
    recordStartLine = line
    index += 1
  }

  private mutating func appendRecordUnlessBlank() {
    guard !isBlankRecord else { return }
    records.append(
      BackupCSVRecord(
        row: recordStartLine,
        fields: fields))
  }

  private var isBlankRecord: Bool {
    !recordHasExplicitSyntax && fields.count == 1
      && fields[0].trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
  }

  private mutating func finishDocument() throws {
    guard !inQuotes else {
      throw validationError(
        row: recordStartLine,
        detail: BackupService.localizedBackupMessage(
          "Unterminated quoted field."))
    }
    if !fields.isEmpty || !field.isEmpty || quoteClosed {
      finishField()
      appendRecordUnlessBlank()
    }
  }

  private func validationError(
    row: Int,
    detail: String
  ) -> BackupError {
    BackupError.validationFailed([
      BackupValidationIssue(
        file: fileName,
        row: row,
        column: nil,
        detail: detail)
    ])
  }
}
