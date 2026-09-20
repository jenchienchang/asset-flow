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

typealias BackupCSVRecord = CSVRecord

struct BackupCSVDocument {
  let records: [BackupCSVRecord]
}

// MARK: - Record-Aware CSV Parsing

extension BackupService {

  static func parseCSVRecords(
    _ data: Data,
    fileName: String
  ) throws -> [BackupCSVRecord] {
    do {
      let document = try CSVRecordReader.read(data)
      guard !document.headers.isEmpty else { return [] }
      return [
        BackupCSVRecord(row: 1, fields: document.headers)
      ] + document.records
    } catch let error as CSVRecordReaderError {
      throw BackupError.validationFailed([
        BackupValidationIssue(
          file: fileName,
          row: error.row,
          column: error.column.map(String.init),
          detail: localizedCSVReaderMessage(error))
      ])
    } catch {
      throw BackupError.validationFailed([
        BackupValidationIssue(
          file: fileName,
          row: 1,
          column: nil,
          detail: localizedBackupMessage("Unable to read CSV data."))
      ])
    }
  }

  private static func localizedCSVReaderMessage(
    _ error: CSVRecordReaderError
  ) -> String {
    switch error.reason {
    case .badEncoding, .unsupportedEncoding:
      localizedBackupMessage("Expected UTF-8 encoded text.")

    case .misplacedQuote:
      localizedBackupMessage("Malformed CSV quoting.")

    case .wrongNumberOfColumns(let expected, let actual):
      localizedBackupMessage(
        "Expected \(expected) fields but found \(actual).")

    case .failedToParse:
      localizedBackupMessage("The CSV value could not be parsed.")

    case .missingColumn:
      localizedBackupMessage("The CSV file is missing a column.")

    case .outOfBounds:
      localizedBackupMessage("The CSV row is out of bounds.")

    case .unknown:
      localizedBackupMessage("Unable to read CSV data.")
    }
  }
}
