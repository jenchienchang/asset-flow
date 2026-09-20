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

/// Import type selector: Assets or Cash Flows.
enum ImportType: String, CaseIterable {
  case assets
  case cashFlows
}

/// User-facing feedback produced by a CSV import attempt.
///
/// Bulk Entry uses this model for asset and cash-flow parse, read, and
/// successful import outcomes so both import targets are presented
/// consistently.
struct CSVImportFeedback: Equatable {
  enum Severity: Equatable {
    case success
    case warning
    case error
  }

  let severity: Severity
  let message: String

  var title: String {
    switch severity {
    case .success:
      String(localized: "CSV Import", table: "Snapshot")

    case .warning:
      String(localized: "Import Warning", table: "Snapshot")

    case .error:
      String(localized: "Import Error", table: "Snapshot")
    }
  }

  static func failure(_ message: String) -> Self {
    Self(severity: .error, message: message)
  }
}

/// How the import-level platform is applied to CSV rows.
enum PlatformApplyMode: String, CaseIterable {
  /// Override all rows with the selected platform.
  case overrideAll
  /// Only fill rows that have no platform in the CSV.
  case fillEmptyOnly
}

/// How the import-level category is applied to CSV rows.
enum CategoryApplyMode: String, CaseIterable {
  /// Override all rows with the selected category.
  case overrideAll
  /// Only fill rows whose existing asset has no category.
  case fillEmptyOnly
}

/// A preview row for an asset CSV import, with inclusion state and category warning.
struct AssetPreviewRow: Identifiable {
  let id: UUID
  let csvRow: AssetCSVRow
  var isIncluded: Bool
  var categoryWarning: String?
  var currencyWarning: String?
  var currencyError: String?
  var effectiveCurrency: String
  var effectiveCategory: String
  var duplicateError: String?
  var snapshotDuplicateError: String?
  var marketValueWarning: String?
}

/// A preview row for a cash flow CSV import, with inclusion state.
struct CashFlowPreviewRow: Identifiable {
  let id: UUID
  let csvRow: CashFlowCSVRow
  var isIncluded: Bool
  var duplicateError: String?
  var snapshotDuplicateError: String?
  var amountWarning: String?
}
