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

/// A parsed row from an asset CSV import.
struct AssetCSVRow {
  let assetName: String
  let marketValue: Decimal
  let platform: String
  let currency: String
  let rowNumber: Int?

  init(
    assetName: String,
    marketValue: Decimal,
    platform: String,
    currency: String = "",
    rowNumber: Int? = nil
  ) {
    self.assetName = assetName
    self.marketValue = marketValue
    self.platform = platform
    self.currency = currency
    self.rowNumber = rowNumber
  }
}

/// A parsed row from a cash flow CSV import.
struct CashFlowCSVRow {
  let description: String
  let amount: Decimal
  let currency: String
  let rowNumber: Int?

  init(
    description: String,
    amount: Decimal,
    currency: String = "",
    rowNumber: Int? = nil
  ) {
    self.description = description
    self.amount = amount
    self.currency = currency
    self.rowNumber = rowNumber
  }
}

/// A CSV parsing error with row and column context.
struct CSVError: Error, Equatable {
  let row: Int
  let column: String?
  let message: String
}

/// A CSV parsing warning with row and column context.
struct CSVWarning: Equatable {
  let row: Int
  let column: String?
  let message: String
}

/// Result of parsing a CSV file.
struct CSVParseResult<T> {
  let rows: [T]
  let parsingErrors: [CSVError]
  let warnings: [CSVWarning]
  let duplicateErrors: [CSVError]

  init(
    rows: [T],
    errors: [CSVError],
    warnings: [CSVWarning],
    duplicateErrors: [CSVError] = []
  ) {
    self.rows = rows
    self.parsingErrors = errors
    self.warnings = warnings
    self.duplicateErrors = duplicateErrors
  }

  /// All errors found while parsing or validating the raw CSV rows.
  var errors: [CSVError] { parsingErrors + duplicateErrors }

  var hasErrors: Bool { !errors.isEmpty }
  var isValid: Bool { errors.isEmpty }
}

/// Validated header indices for asset CSV parsing.
struct AssetCSVHeaders {
  let nameIndex: Int
  let valueIndex: Int
  let platformIndex: Int?
  let currencyIndex: Int?
  let warnings: [CSVWarning]
}

/// Validated header indices for cash flow CSV parsing.
struct CashFlowCSVHeaders {
  let descIndex: Int
  let amountIndex: Int
  let currencyIndex: Int?
  let warnings: [CSVWarning]
}

/// Error wrapper for header validation, containing all missing column errors.
struct CSVHeaderValidationError: Error {
  let errors: [CSVError]
}

/// Result of parsing a single CSV data row.
enum RowParseResult<T> {
  case row(T, [CSVWarning])
  case error(CSVError)
}

// MARK: - Column Mapping

/// Canonical column identifiers for CSV mapping.
///
/// Used to map arbitrary CSV column headers to the columns expected
/// by `CSVParsingService`. Raw values are the canonical header names.
enum CanonicalColumn: String, CaseIterable, Identifiable {
  case assetName = "Asset Name"
  case marketValue = "Market Value"
  case platform = "Platform"
  case currency = "Currency"
  case description = "Description"
  case amount = "Amount"

  var id: String { rawValue }
}

/// Defines the required and optional columns for a CSV schema.
enum CSVColumnSchema: CaseIterable {
  case asset
  case assetWithoutPlatform
  case cashFlow

  var requiredColumns: [CanonicalColumn] {
    switch self {
    case .asset, .assetWithoutPlatform: [.assetName, .marketValue]
    case .cashFlow: [.description, .amount]
    }
  }

  var optionalColumns: [CanonicalColumn] {
    switch self {
    case .asset: [.platform, .currency]
    case .assetWithoutPlatform: [.currency]
    case .cashFlow: [.currency]
    }
  }

  var allColumns: [CanonicalColumn] {
    requiredColumns + optionalColumns
  }
}

/// A confirmed mapping from canonical columns to CSV column indices.
struct CSVColumnMapping {
  let schema: CSVColumnSchema
  let columnMap: [CanonicalColumn: Int]
  let rawHeaders: [String]

  func index(for column: CanonicalColumn) -> Int? {
    columnMap[column]
  }
}

/// Result of attempting auto-detection of column mapping.
enum CSVAutoDetectResult {
  /// All required (and any matching optional) columns found.
  case matched(CSVColumnMapping)
  /// At least one required column could not be matched. User must map manually.
  case needsUserMapping(rawHeaders: [String], partialMap: [CanonicalColumn: Int])
}
