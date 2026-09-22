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

// MARK: - Column Mapping

extension CSVParsingService {

  /// Extracts header names from CSV data.
  nonisolated static func extractHeaders(from data: Data) -> [String] {
    (try? CSVRecordReader.read(data).headers) ?? []
  }

  nonisolated static func extractHeadersAsync(from data: Data) async throws -> [String] {
    do {
      return try await CSVRecordReader.readCancellable(data).headers
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return []
    }
  }

  /// Extracts data rows (excluding header) as raw string arrays.
  ///
  /// Pass `nil` for `count` to extract every data row.
  nonisolated static func extractSampleRows(from data: Data, count: Int? = 3) -> [[String]] {
    guard let document = try? CSVRecordReader.read(data) else { return [] }
    let records =
      count.map { Array(document.records.prefix($0)) }
      ?? document.records
    return records.map(\.fields)
  }

  nonisolated static func extractSampleRowsAsync(
    from data: Data,
    count: Int? = 3
  ) async throws -> [[String]] {
    do {
      let document = try await CSVRecordReader.readCancellable(data)
      let records =
        count.map { Array(document.records.prefix($0)) }
        ?? document.records
      return records.map(\.fields)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return []
    }
  }

  /// Attempts case-insensitive auto-detection of column mapping.
  ///
  /// Returns `.matched` if all required columns for the schema are found.
  /// Returns `.needsUserMapping` with a partial map of whatever was matched
  /// if any required column is missing.
  nonisolated static func autoDetectMapping(
    headers: [String],
    schema: CSVColumnSchema
  ) -> CSVAutoDetectResult {
    let normalized = headers.map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var columnMap: [CanonicalColumn: Int] = [:]

    for column in schema.allColumns {
      if let index = normalized.firstIndex(of: column.rawValue.lowercased()) {
        columnMap[column] = index
      }
    }

    let allRequiredFound = schema.requiredColumns.allSatisfy { columnMap[$0] != nil }

    if allRequiredFound {
      return .matched(
        CSVColumnMapping(
          schema: schema, columnMap: columnMap, rawHeaders: headers))
    } else {
      return .needsUserMapping(rawHeaders: headers, partialMap: columnMap)
    }
  }

  /// Parses asset CSV using a user-provided column mapping.
  ///
  /// Builds `AssetCSVHeaders` from the mapping and delegates to the
  /// existing row-parsing pipeline. The first line of data is skipped
  /// (assumed to be the original CSV header).
  nonisolated static func parseAssetCSV(
    data: Data,
    mapping: CSVColumnMapping,
    importPlatform: String?
  ) -> CSVParseResult<AssetCSVRow> {
    guard let nameIndex = mapping.columnMap[.assetName],
      let valueIndex = mapping.columnMap[.marketValue]
    else {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 0, column: nil,
            message: localizedImportMessage("Mapping missing required columns."))
        ],
        warnings: [])
    }

    let document: CSVDocument
    do {
      document = try CSVRecordReader.read(data)
    } catch let error as CSVRecordReaderError {
      return CSVParseResult(
        rows: [], errors: [csvError(from: error)], warnings: [])
    } catch {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 1, column: nil,
            message: localizedImportMessage("Unable to read CSV data."))
        ],
        warnings: [])
    }

    guard !document.headers.isEmpty else { return emptyFileResult() }
    guard !document.records.isEmpty else { return noDataRowsResult(warnings: []) }

    let headers = AssetCSVHeaders(
      nameIndex: nameIndex,
      valueIndex: valueIndex,
      platformIndex: mapping.columnMap[.platform],
      currencyIndex: mapping.columnMap[.currency],
      warnings: [])

    return parseAssetDataRows(
      records: document.records,
      headers: headers, importPlatform: importPlatform)
  }

  nonisolated static func parseAssetCSVAsync(
    data: Data,
    mapping: CSVColumnMapping,
    importPlatform: String?
  ) async throws -> CSVParseResult<AssetCSVRow> {
    guard let nameIndex = mapping.columnMap[.assetName],
      let valueIndex = mapping.columnMap[.marketValue]
    else {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 0, column: nil,
            message: localizedImportMessage("Mapping missing required columns."))
        ],
        warnings: [])
    }

    let document: CSVDocument
    do {
      document = try await CSVRecordReader.readCancellable(data)
    } catch let error as CSVRecordReaderError {
      return CSVParseResult(
        rows: [], errors: [csvError(from: error)], warnings: [])
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 1, column: nil,
            message: localizedImportMessage("Unable to read CSV data."))
        ],
        warnings: [])
    }

    guard !document.headers.isEmpty else { return emptyFileResult() }
    guard !document.records.isEmpty else {
      return noDataRowsResult(warnings: [])
    }

    let headers = AssetCSVHeaders(
      nameIndex: nameIndex,
      valueIndex: valueIndex,
      platformIndex: mapping.columnMap[.platform],
      currencyIndex: mapping.columnMap[.currency],
      warnings: [])
    return try await parseAssetDataRowsAsync(
      records: document.records,
      headers: headers,
      importPlatform: importPlatform)
  }

  /// Parses cash flow CSV using a user-provided column mapping.
  nonisolated static func parseCashFlowCSV(
    data: Data,
    mapping: CSVColumnMapping
  ) -> CSVParseResult<CashFlowCSVRow> {
    guard let descIndex = mapping.columnMap[.description],
      let amountIndex = mapping.columnMap[.amount]
    else {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 0, column: nil,
            message: localizedImportMessage("Mapping missing required columns."))
        ],
        warnings: [])
    }

    let document: CSVDocument
    do {
      document = try CSVRecordReader.read(data)
    } catch let error as CSVRecordReaderError {
      return CSVParseResult(
        rows: [], errors: [csvError(from: error)], warnings: [])
    } catch {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 1, column: nil,
            message: localizedImportMessage("Unable to read CSV data."))
        ],
        warnings: [])
    }

    guard !document.headers.isEmpty else { return emptyFileResult() }
    guard !document.records.isEmpty else { return noDataRowsResult(warnings: []) }

    let headers = CashFlowCSVHeaders(
      descIndex: descIndex,
      amountIndex: amountIndex,
      currencyIndex: mapping.columnMap[.currency],
      warnings: [])

    return parseCashFlowDataRows(
      records: document.records, headers: headers)
  }

  nonisolated static func parseCashFlowCSVAsync(
    data: Data,
    mapping: CSVColumnMapping
  ) async throws -> CSVParseResult<CashFlowCSVRow> {
    guard let descIndex = mapping.columnMap[.description],
      let amountIndex = mapping.columnMap[.amount]
    else {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 0, column: nil,
            message: localizedImportMessage("Mapping missing required columns."))
        ],
        warnings: [])
    }

    let document: CSVDocument
    do {
      document = try await CSVRecordReader.readCancellable(data)
    } catch let error as CSVRecordReaderError {
      return CSVParseResult(
        rows: [], errors: [csvError(from: error)], warnings: [])
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return CSVParseResult(
        rows: [],
        errors: [
          CSVError(
            row: 1, column: nil,
            message: localizedImportMessage("Unable to read CSV data."))
        ],
        warnings: [])
    }

    guard !document.headers.isEmpty else { return emptyFileResult() }
    guard !document.records.isEmpty else {
      return noDataRowsResult(warnings: [])
    }

    let headers = CashFlowCSVHeaders(
      descIndex: descIndex,
      amountIndex: amountIndex,
      currencyIndex: mapping.columnMap[.currency],
      warnings: [])
    return try await parseCashFlowDataRowsAsync(
      records: document.records, headers: headers)
  }
}
