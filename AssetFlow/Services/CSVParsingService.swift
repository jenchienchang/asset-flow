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

/// Reads imported files without tying the file operation to the main actor.
enum CSVFileReader {

  /// Reads a security-scoped file URL and returns its contents.
  nonisolated static func read(from url: URL) async throws -> Data {
    try Task.checkCancellation()

    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    try Task.checkCancellation()
    return data
  }
}

/// Performs file-independent CSV preparation on the generic executor.
enum CSVImportPreparationService {

  nonisolated static func prepare(
    data: Data,
    schema: CSVColumnSchema
  ) async throws -> CSVImportPreparation {
    try Task.checkCancellation()
    let headers = try await CSVParsingService.extractHeadersAsync(from: data)

    guard !headers.isEmpty else {
      let preparation = try await parsedPreparation(
        data: data, schema: schema, mapping: nil)
      try Task.checkCancellation()
      return preparation
    }

    switch CSVParsingService.autoDetectMapping(headers: headers, schema: schema) {
    case .matched:
      let preparation = try await parsedPreparation(
        data: data, schema: schema, mapping: nil)
      try Task.checkCancellation()
      return preparation

    case .needsUserMapping(let rawHeaders, let partialMap):
      let sampleRows = try await CSVParsingService.extractSampleRowsAsync(from: data)
      try Task.checkCancellation()
      return .needsMapping(
        data: data,
        schema: schema,
        rawHeaders: rawHeaders,
        sampleRows: sampleRows,
        partialMapping: partialMap)
    }
  }

  nonisolated static func prepare(
    data: Data,
    mapping: CSVColumnMapping
  ) async throws -> CSVImportPreparation {
    try Task.checkCancellation()
    let preparation = try await parsedPreparation(
      data: data, schema: mapping.schema, mapping: mapping)
    try Task.checkCancellation()
    return preparation
  }

  private nonisolated static func parsedPreparation(
    data: Data,
    schema: CSVColumnSchema,
    mapping: CSVColumnMapping?
  ) async throws -> CSVImportPreparation {
    switch schema {
    case .asset, .assetWithoutPlatform:
      let result: CSVParseResult<AssetCSVRow>
      if let mapping {
        result = try await CSVParsingService.parseAssetCSVAsync(
          data: data, mapping: mapping, importPlatform: nil)
      } else {
        result = try await CSVParsingService.parseAssetCSVAsync(
          data: data, importPlatform: nil)
      }
      return .parsedAsset(data: data, result: result)

    case .cashFlow:
      let result: CSVParseResult<CashFlowCSVRow>
      if let mapping {
        result = try await CSVParsingService.parseCashFlowCSVAsync(
          data: data, mapping: mapping)
      } else {
        result = try await CSVParsingService.parseCashFlowCSVAsync(data: data)
      }
      return .parsedCashFlow(data: data, result: result)
    }
  }
}

/// CSV parsing service for asset and cash flow imports.
///
/// Handles parsing, validation, and duplicate detection per SPEC Sections 4.2-4.6.
/// Takes raw `Data` as input -- file I/O is the caller's responsibility.
///
/// Duplicate detection against existing snapshot data is NOT handled here; it
/// requires ModelContext access and will be performed by the Import ViewModel.
/// Within-CSV duplicate errors are kept separate from parsing errors so import
/// flows can validate them after applying their platform-resolution rules.
nonisolated enum CSVParsingService {

  // MARK: - Asset CSV Parsing

  /// Parses asset CSV data.
  ///
  /// - Parameters:
  ///   - data: Raw CSV file data (UTF-8, BOM-tolerant).
  ///   - importPlatform: Optional import-level platform override.
  /// - Returns: Parse result with rows, errors, and warnings.
  nonisolated static func parseAssetCSV(
    data: Data,
    importPlatform: String?
  ) -> CSVParseResult<AssetCSVRow> {
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

    guard !document.headers.isEmpty else {
      return emptyFileResult()
    }

    let validated = validateAssetHeaders(document.headers)

    switch validated {
    case .failure(let validationError):
      return CSVParseResult(rows: [], errors: validationError.errors, warnings: [])

    case .success(let hdr):
      return parseAssetDataRows(
        records: document.records,
        headers: hdr, importPlatform: importPlatform)
    }
  }

  /// Parses asset CSV data with cooperative cancellation checks during
  /// record materialization and row validation.
  nonisolated static func parseAssetCSVAsync(
    data: Data,
    importPlatform: String?
  ) async throws -> CSVParseResult<AssetCSVRow> {
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

    guard !document.headers.isEmpty else {
      return emptyFileResult()
    }

    switch validateAssetHeaders(document.headers) {
    case .failure(let validationError):
      return CSVParseResult(rows: [], errors: validationError.errors, warnings: [])

    case .success(let headers):
      return try await parseAssetDataRowsAsync(
        records: document.records,
        headers: headers,
        importPlatform: importPlatform)
    }
  }

  // MARK: - Cash Flow CSV Parsing

  /// Parses cash flow CSV data.
  ///
  /// - Parameter data: Raw CSV file data (UTF-8, BOM-tolerant).
  /// - Returns: Parse result with rows, errors, and warnings.
  nonisolated static func parseCashFlowCSV(
    data: Data
  ) -> CSVParseResult<CashFlowCSVRow> {
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

    guard !document.headers.isEmpty else {
      return emptyFileResult()
    }

    let validated = validateCashFlowHeaders(document.headers)

    switch validated {
    case .failure(let validationError):
      return CSVParseResult(rows: [], errors: validationError.errors, warnings: [])

    case .success(let hdr):
      return parseCashFlowDataRows(
        records: document.records, headers: hdr)
    }
  }

  /// Parses cash-flow CSV data with cooperative cancellation checks during
  /// record materialization and row validation.
  nonisolated static func parseCashFlowCSVAsync(
    data: Data
  ) async throws -> CSVParseResult<CashFlowCSVRow> {
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

    guard !document.headers.isEmpty else {
      return emptyFileResult()
    }

    switch validateCashFlowHeaders(document.headers) {
    case .failure(let validationError):
      return CSVParseResult(rows: [], errors: validationError.errors, warnings: [])

    case .success(let headers):
      return try await parseCashFlowDataRowsAsync(
        records: document.records, headers: headers)
    }
  }
}

// MARK: - Header Validation

extension CSVParsingService {

  private nonisolated static func validateAssetHeaders(
    _ headers: [String]
  ) -> Result<AssetCSVHeaders, CSVHeaderValidationError> {
    let normalized = headers.map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var errors: [CSVError] = []
    let nameIndex = normalized.firstIndex(of: "asset name")
    let valueIndex = normalized.firstIndex(of: "market value")

    if nameIndex == nil {
      errors.append(
        CSVError(
          row: 1, column: "Asset Name",
          message: localizedImportMessage("Missing required column: Asset Name")))
    }
    if valueIndex == nil {
      errors.append(
        CSVError(
          row: 1, column: "Market Value",
          message: localizedImportMessage("Missing required column: Market Value")))
    }

    guard errors.isEmpty, let nameIndex, let valueIndex else {
      return .failure(CSVHeaderValidationError(errors: errors))
    }

    let knownColumns: Set<String> = [
      "asset name", "market value", "platform", "currency",
    ]

    return .success(
      AssetCSVHeaders(
        nameIndex: nameIndex,
        valueIndex: valueIndex,
        platformIndex: normalized.firstIndex(of: "platform"),
        currencyIndex: normalized.firstIndex(of: "currency"),
        warnings: unrecognizedColumnWarnings(
          headers: headers, normalized: normalized,
          knownColumns: knownColumns)))
  }

  private nonisolated static func validateCashFlowHeaders(
    _ headers: [String]
  ) -> Result<CashFlowCSVHeaders, CSVHeaderValidationError> {
    let normalized = headers.map {
      $0.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var errors: [CSVError] = []
    let descIndex = normalized.firstIndex(of: "description")
    let amountIndex = normalized.firstIndex(of: "amount")

    if descIndex == nil {
      errors.append(
        CSVError(
          row: 1, column: "Description",
          message: localizedImportMessage("Missing required column: Description")))
    }
    if amountIndex == nil {
      errors.append(
        CSVError(
          row: 1, column: "Amount",
          message: localizedImportMessage("Missing required column: Amount")))
    }

    guard errors.isEmpty, let descIndex, let amountIndex else {
      return .failure(CSVHeaderValidationError(errors: errors))
    }

    let knownColumns: Set<String> = ["description", "amount", "currency"]

    return .success(
      CashFlowCSVHeaders(
        descIndex: descIndex,
        amountIndex: amountIndex,
        currencyIndex: normalized.firstIndex(of: "currency"),
        warnings: unrecognizedColumnWarnings(
          headers: headers, normalized: normalized,
          knownColumns: knownColumns)))
  }

  private nonisolated static func unrecognizedColumnWarnings(
    headers: [String],
    normalized: [String],
    knownColumns: Set<String>
  ) -> [CSVWarning] {
    var warnings: [CSVWarning] = []
    for (idx, header) in normalized.enumerated()
    where !knownColumns.contains(header) {
      warnings.append(
        CSVWarning(
          row: 0, column: headers[idx],
          message: String(
            localized: "Unrecognized column: \(headers[idx]) (will be ignored)",
            table: "Import")))
    }
    return warnings
  }
}

// MARK: - Data Row Parsing

extension CSVParsingService {

  nonisolated static func parseAssetDataRows(
    records: [CSVRecord],
    headers: AssetCSVHeaders,
    importPlatform: String?
  ) -> CSVParseResult<AssetCSVRow> {
    if records.isEmpty {
      return noDataRowsResult(warnings: headers.warnings)
    }

    var rows: [AssetCSVRow] = []
    var errors: [CSVError] = []
    var warnings = headers.warnings

    for record in records {
      let fields = record.fields
      if isEmptyRow(fields) { continue }

      switch parseAssetRow(
        fields: fields, rowNumber: record.row,
        headers: headers, importPlatform: importPlatform)
      {
      case .error(let err):
        errors.append(err)

      case .row(let row, let rowWarnings):
        rows.append(row)
        warnings.append(contentsOf: rowWarnings)
      }
    }

    let duplicateErrors = detectAssetDuplicates(rows: rows)
    return CSVParseResult(
      rows: rows, errors: errors, warnings: warnings,
      duplicateErrors: duplicateErrors)
  }

  nonisolated static func parseCashFlowDataRows(
    records: [CSVRecord],
    headers: CashFlowCSVHeaders
  ) -> CSVParseResult<CashFlowCSVRow> {
    if records.isEmpty {
      return noDataRowsResult(warnings: headers.warnings)
    }

    var rows: [CashFlowCSVRow] = []
    var errors: [CSVError] = []
    var warnings = headers.warnings

    for record in records {
      let fields = record.fields
      if isEmptyRow(fields) { continue }

      switch parseCashFlowRow(
        fields: fields, rowNumber: record.row,
        headers: headers)
      {
      case .error(let err):
        errors.append(err)

      case .row(let row, let rowWarnings):
        rows.append(row)
        warnings.append(contentsOf: rowWarnings)
      }
    }

    let duplicateErrors = detectCashFlowDuplicates(rows: rows)
    return CSVParseResult(
      rows: rows, errors: errors, warnings: warnings,
      duplicateErrors: duplicateErrors)
  }

  nonisolated static func parseAssetDataRowsAsync(
    records: [CSVRecord],
    headers: AssetCSVHeaders,
    importPlatform: String?
  ) async throws -> CSVParseResult<AssetCSVRow> {
    if records.isEmpty {
      return noDataRowsResult(warnings: headers.warnings)
    }

    var rows: [AssetCSVRow] = []
    var errors: [CSVError] = []
    var warnings = headers.warnings

    for record in records {
      try Task.checkCancellation()
      let fields = record.fields
      if isEmptyRow(fields) { continue }

      switch parseAssetRow(
        fields: fields, rowNumber: record.row,
        headers: headers, importPlatform: importPlatform)
      {
      case .error(let err):
        errors.append(err)

      case .row(let row, let rowWarnings):
        rows.append(row)
        warnings.append(contentsOf: rowWarnings)
      }
    }

    let duplicateErrors = try await detectAssetDuplicatesAsync(rows: rows)
    return CSVParseResult(
      rows: rows, errors: errors, warnings: warnings,
      duplicateErrors: duplicateErrors)
  }

  nonisolated static func parseCashFlowDataRowsAsync(
    records: [CSVRecord],
    headers: CashFlowCSVHeaders
  ) async throws -> CSVParseResult<CashFlowCSVRow> {
    if records.isEmpty {
      return noDataRowsResult(warnings: headers.warnings)
    }

    var rows: [CashFlowCSVRow] = []
    var errors: [CSVError] = []
    var warnings = headers.warnings

    for record in records {
      try Task.checkCancellation()
      let fields = record.fields
      if isEmptyRow(fields) { continue }

      switch parseCashFlowRow(
        fields: fields, rowNumber: record.row,
        headers: headers)
      {
      case .error(let err):
        errors.append(err)

      case .row(let row, let rowWarnings):
        rows.append(row)
        warnings.append(contentsOf: rowWarnings)
      }
    }

    let duplicateErrors = try await detectCashFlowDuplicatesAsync(rows: rows)
    return CSVParseResult(
      rows: rows, errors: errors, warnings: warnings,
      duplicateErrors: duplicateErrors)
  }
}

// MARK: - Single Row Parsing

extension CSVParsingService {

  private nonisolated static func parseAssetRow(
    fields: [String],
    rowNumber: Int,
    headers: AssetCSVHeaders,
    importPlatform: String?
  ) -> RowParseResult<AssetCSVRow> {
    let name = fieldValue(fields: fields, index: headers.nameIndex)
    if name.isEmpty {
      return .error(
        CSVError(
          row: rowNumber, column: "Asset Name",
          message: localizedImportMessage("Asset name is empty.")))
    }

    let raw = fieldValue(fields: fields, index: headers.valueIndex)
    guard let marketValue = parseDecimalValue(raw) else {
      return .error(
        CSVError(
          row: rowNumber, column: "Market Value",
          message: localizedImportMessage(
            "Cannot parse '\(raw)' as a number.")))
    }

    let platform = resolveAssetPlatform(
      fields: fields, headers: headers,
      importPlatform: importPlatform)

    let currency =
      headers.currencyIndex.map {
        fieldValue(fields: fields, index: $0)
      } ?? ""

    return .row(
      AssetCSVRow(
        assetName: name, marketValue: marketValue,
        platform: platform, currency: currency, rowNumber: rowNumber),
      marketValueWarnings(
        value: marketValue, name: name,
        rowNumber: rowNumber))
  }

  private nonisolated static func parseCashFlowRow(
    fields: [String],
    rowNumber: Int,
    headers: CashFlowCSVHeaders
  ) -> RowParseResult<CashFlowCSVRow> {
    let desc = fieldValue(
      fields: fields, index: headers.descIndex)
    if desc.isEmpty {
      return .error(
        CSVError(
          row: rowNumber, column: "Description",
          message: localizedImportMessage("Description is empty.")))
    }

    let raw = fieldValue(
      fields: fields, index: headers.amountIndex)
    guard let amount = parseDecimalValue(raw) else {
      return .error(
        CSVError(
          row: rowNumber, column: "Amount",
          message: localizedImportMessage(
            "Cannot parse '\(raw)' as a number.")))
    }

    var warnings: [CSVWarning] = []
    if amount == 0 {
      warnings.append(
        CSVWarning(
          row: rowNumber, column: "Amount",
          message: localizedImportMessage("Amount is zero for '\(desc)'.")))
    }

    let currency =
      headers.currencyIndex.map {
        fieldValue(fields: fields, index: $0)
      } ?? ""

    return .row(
      CashFlowCSVRow(
        description: desc, amount: amount, currency: currency, rowNumber: rowNumber),
      warnings)
  }

  private nonisolated static func resolveAssetPlatform(
    fields: [String],
    headers: AssetCSVHeaders,
    importPlatform: String?
  ) -> String {
    if let importPlatform = importPlatform {
      return importPlatform
    } else if let idx = headers.platformIndex {
      return fieldValue(fields: fields, index: idx)
    }
    return ""
  }

  private nonisolated static func marketValueWarnings(
    value: Decimal, name: String, rowNumber: Int
  ) -> [CSVWarning] {
    let col = "Market Value"
    if value == 0 {
      let msg = localizedImportMessage("Market value is zero for '\(name)'.")
      return [CSVWarning(row: rowNumber, column: col, message: msg)]
    } else if value < 0 {
      let msg = localizedImportMessage("Market value is negative for '\(name)'.")
      return [CSVWarning(row: rowNumber, column: col, message: msg)]
    }
    return []
  }
}

// MARK: - Private Helpers

extension CSVParsingService {

  nonisolated static func localizedImportMessage(
    _ value: String.LocalizationValue
  ) -> String {
    String(localized: value, table: "Import")
  }

  nonisolated static func csvError(from error: CSVRecordReaderError) -> CSVError {
    CSVError(
      row: error.row,
      column: error.column.map(String.init),
      message: localizedCSVReaderMessage(error))
  }

  nonisolated static func localizedCSVReaderMessage(
    _ error: CSVRecordReaderError
  ) -> String {
    switch error.reason {
    case .badEncoding, .unsupportedEncoding:
      localizedImportMessage("Expected UTF-8 encoded text.")

    case .misplacedQuote:
      localizedImportMessage("Malformed CSV quoting.")

    case .wrongNumberOfColumns(let expected, let actual):
      localizedImportMessage(
        "Expected \(expected) fields but found \(actual).")

    case .failedToParse:
      localizedImportMessage("The CSV value could not be parsed.")

    case .missingColumn:
      localizedImportMessage("The CSV file is missing a column.")

    case .outOfBounds:
      localizedImportMessage("The CSV row is out of bounds.")

    case .unknown:
      localizedImportMessage("Unable to read CSV data.")
    }
  }

  private nonisolated static func fieldValue(
    fields: [String], index: Int
  ) -> String {
    guard index < fields.count else { return "" }
    return fields[index].trimmingCharacters(in: .whitespaces)
  }

  private nonisolated static func isEmptyRow(_ fields: [String]) -> Bool {
    fields.allSatisfy {
      $0.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  nonisolated static func emptyFileResult<T>() -> CSVParseResult<T> {
    let err = CSVError(
      row: 0, column: nil,
      message: localizedImportMessage("File is empty or contains no data."))
    return CSVParseResult(rows: [], errors: [err], warnings: [])
  }

  nonisolated static func noDataRowsResult<T>(
    warnings: [CSVWarning]
  ) -> CSVParseResult<T> {
    let err = CSVError(
      row: 0, column: nil,
      message: localizedImportMessage("File contains no data rows."))
    return CSVParseResult(
      rows: [], errors: [err], warnings: warnings)
  }

  nonisolated static func parseDecimalValue(_ raw: String) -> Decimal? {
    var cleaned = raw.trimmingCharacters(in: .whitespaces)
    cleaned = String(cleaned.filter { !Constants.Parsing.currencySymbols.contains($0) })
    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
    cleaned = cleaned.trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty else { return nil }
    return Decimal(string: cleaned)
  }

  nonisolated static func detectAssetDuplicates(
    rows: [AssetCSVRow]
  ) -> [CSVError] {
    var seen: [String: Int] = [:]
    var errors: [CSVError] = []
    for (index, row) in rows.enumerated() {
      let identity = normalizedAssetIdentity(row: row)
      let rowNumber = row.rowNumber ?? index + 2
      if let firstRow = seen[identity] {
        errors.append(
          CSVError(
            row: rowNumber, column: nil,
            message: localizedImportMessage(
              "Duplicate asset '\(row.assetName)' (platform: '\(row.platform)') — first appeared in row \(firstRow)."
            )
          ))
      } else {
        seen[identity] = rowNumber
      }
    }
    return errors
  }

  private nonisolated static func detectAssetDuplicatesAsync(
    rows: [AssetCSVRow]
  ) async throws -> [CSVError] {
    var seen: [String: Int] = [:]
    var errors: [CSVError] = []
    for (index, row) in rows.enumerated() {
      try Task.checkCancellation()
      let identity = normalizedAssetIdentity(row: row)
      let rowNumber = row.rowNumber ?? index + 2
      if let firstRow = seen[identity] {
        errors.append(
          CSVError(
            row: rowNumber, column: nil,
            message: localizedImportMessage(
              "Duplicate asset '\(row.assetName)' (platform: '\(row.platform)') — first appeared in row \(firstRow)."
            )
          ))
      } else {
        seen[identity] = rowNumber
      }
    }
    return errors
  }

  nonisolated static func detectCashFlowDuplicates(
    rows: [CashFlowCSVRow]
  ) -> [CSVError] {
    var seen: [String: Int] = [:]
    var errors: [CSVError] = []
    for (index, row) in rows.enumerated() {
      let normalized = row.description.lowercased()
        .trimmingCharacters(in: .whitespaces)
      let rowNumber = row.rowNumber ?? index + 2
      if let firstRow = seen[normalized] {
        errors.append(
          CSVError(
            row: rowNumber, column: nil,
            message: localizedImportMessage(
              "Duplicate description '\(row.description)' — first appeared in row \(firstRow).")
          ))
      } else {
        seen[normalized] = rowNumber
      }
    }
    return errors
  }

  private nonisolated static func detectCashFlowDuplicatesAsync(
    rows: [CashFlowCSVRow]
  ) async throws -> [CSVError] {
    var seen: [String: Int] = [:]
    var errors: [CSVError] = []
    for (index, row) in rows.enumerated() {
      try Task.checkCancellation()
      let normalized = row.description.lowercased()
        .trimmingCharacters(in: .whitespaces)
      let rowNumber = row.rowNumber ?? index + 2
      if let firstRow = seen[normalized] {
        errors.append(
          CSVError(
            row: rowNumber, column: nil,
            message: localizedImportMessage(
              "Duplicate description '\(row.description)' — first appeared in row \(firstRow)."
            )
          ))
      } else {
        seen[normalized] = rowNumber
      }
    }
    return errors
  }

  nonisolated static func normalizedAssetIdentity(
    row: AssetCSVRow
  ) -> String {
    "\(row.assetName.normalizedForIdentity)|\(row.platform.normalizedForIdentity)"
  }

  /// Resolves asset rows for a Bulk Entry platform import.
  ///
  /// Rows without a platform, or rows whose platform matches the target,
  /// are assigned the target platform. Rows for another platform are left
  /// out and reported as mismatches so they can be shown as warnings.
  nonisolated static func resolveAssetRowsForPlatform(
    rows: [AssetCSVRow],
    platform: String
  ) -> (rows: [AssetCSVRow], mismatches: [String]) {
    let normalizedPlatform = platform.normalizedForIdentity
    var resolvedRows: [AssetCSVRow] = []
    var mismatches: [String] = []

    for row in rows {
      if !row.platform.isEmpty,
        row.platform.normalizedForIdentity != normalizedPlatform
      {
        mismatches.append(row.assetName)
        continue
      }

      resolvedRows.append(
        AssetCSVRow(
          assetName: row.assetName,
          marketValue: row.marketValue,
          platform: platform,
          currency: row.currency,
          rowNumber: row.rowNumber))
    }

    return (rows: resolvedRows, mismatches: mismatches)
  }
}
