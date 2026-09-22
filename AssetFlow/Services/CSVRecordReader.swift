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
import TabularData

struct CSVRecord: Sendable {
  let row: Int
  let fields: [String]
}

struct CSVDocument: Sendable {
  let headers: [String]
  let records: [CSVRecord]
}

enum CSVRecordReaderError: Error, Sendable {
  enum Reason: Sendable {
    case badEncoding
    case unsupportedEncoding
    case misplacedQuote
    case wrongNumberOfColumns(expected: Int, actual: Int)
    case failedToParse
    case missingColumn
    case outOfBounds
    case unknown
  }

  case invalidCSV(row: Int, column: Int?, reason: Reason)

  var row: Int {
    switch self {
    case .invalidCSV(let row, _, _): row
    }
  }

  var column: Int? {
    switch self {
    case .invalidCSV(_, let column, _): column
    }
  }

  var reason: Reason {
    switch self {
    case .invalidCSV(_, _, let reason): reason
    }
  }

}

/// Reads CSV records using Apple's built-in TabularData parser.
///
/// The first pass discovers the header names and validates CSV structure. The
/// second pass forces every column to `String` so callers retain exact field
/// text and can apply AssetFlow-specific Decimal and validation rules.
nonisolated enum CSVRecordReader {

  nonisolated static func read(_ data: Data) throws -> CSVDocument {
    let data = stripUTF8BOM(from: data)
    guard !data.isEmpty else {
      return CSVDocument(headers: [], records: [])
    }

    let discovered = try readDataFrame(data)
    let headers = discovered.columns.map(\.name)
    let stringTypes = Dictionary(
      uniqueKeysWithValues: headers.map { ($0, CSVType.string) })
    let frame = try readDataFrame(data, types: stringTypes)

    let records = (0..<frame.shape.rows).map { rowIndex in
      CSVRecord(
        row: rowIndex + 2,
        fields: frame.columns.map { column in
          frame[row: rowIndex][column.name] as? String ?? ""
        })
    }
    return CSVDocument(headers: headers, records: records)
  }

  /// Reads CSV records with cooperative cancellation checks between the
  /// synchronous TabularData passes and while materializing records.
  nonisolated static func readCancellable(_ data: Data) async throws -> CSVDocument {
    try Task.checkCancellation()
    let data = stripUTF8BOM(from: data)
    guard !data.isEmpty else {
      return CSVDocument(headers: [], records: [])
    }

    let discovered = try readDataFrame(data)
    try Task.checkCancellation()
    let headers = discovered.columns.map(\.name)
    let stringTypes = Dictionary(
      uniqueKeysWithValues: headers.map { ($0, CSVType.string) })
    let frame = try readDataFrame(data, types: stringTypes)
    try Task.checkCancellation()

    var records: [CSVRecord] = []
    records.reserveCapacity(frame.shape.rows)
    for rowIndex in 0..<frame.shape.rows {
      try Task.checkCancellation()
      records.append(
        CSVRecord(
          row: rowIndex + 2,
          fields: frame.columns.map { column in
            frame[row: rowIndex][column.name] as? String ?? ""
          }))
    }
    return CSVDocument(headers: headers, records: records)
  }

  private nonisolated static func readDataFrame(
    _ data: Data,
    types: [String: CSVType] = [:]
  ) throws -> DataFrame {
    do {
      return try DataFrame(
        csvData: data,
        types: types,
        options: CSVReadingOptions(
          hasHeaderRow: true,
          nilEncodings: [""],
          ignoresEmptyLines: true,
          usesQuoting: true,
          usesEscaping: false,
          delimiter: ","))
    } catch let error as CSVReadingError {
      throw CSVRecordReaderError.invalidCSV(
        row: max(error.row + 1, 1),
        column: error.column.map { $0 + 1 },
        reason: reason(for: error))
    } catch {
      throw CSVRecordReaderError.invalidCSV(
        row: 1, column: nil, reason: .unknown)
    }
  }

  private nonisolated static func reason(
    for error: CSVReadingError
  ) -> CSVRecordReaderError.Reason {
    switch error {
    case .badEncoding:
      .badEncoding

    case .unsupportedEncoding:
      .unsupportedEncoding

    case .misplacedQuote:
      .misplacedQuote

    case .wrongNumberOfColumns(_, let columns, let expected):
      .wrongNumberOfColumns(expected: expected, actual: columns)

    case .failedToParse:
      .failedToParse

    case .missingColumn:
      .missingColumn

    case .outOfBounds:
      .outOfBounds

    default:
      .unknown
    }
  }

  private nonisolated static func stripUTF8BOM(from data: Data) -> Data {
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    guard data.starts(with: bom) else { return data }
    return Data(data.dropFirst(bom.count))
  }
}
