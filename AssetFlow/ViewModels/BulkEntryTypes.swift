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

/// Aggregated toolbar statistics for bulk entry, maintained incrementally
/// via delta updates rather than recomputed from scratch on every mutation.
/// Using counts (not booleans) so delta subtraction works correctly.
struct BulkEntryToolbarStats: Equatable {
  var updatedCount = 0
  var pendingCount = 0
  var excludedCount = 0
  var includedCount = 0
  var zeroValueCount = 0
  var invalidNewRowCount = 0
  var validationErrorCount = 0
  var emptyCashFlowAmountCount = 0
  var emptyCashFlowDescriptionCount = 0
  var cashFlowValidationErrorCount = 0

  var hasInvalidNewRows: Bool { invalidNewRowCount > 0 }
  var hasEmptyCashFlowAmounts: Bool { emptyCashFlowAmountCount > 0 }
  var hasEmptyCashFlowDescriptions: Bool { emptyCashFlowDescriptionCount > 0 }
  var hasCashFlowValidationErrors: Bool { cashFlowValidationErrorCount > 0 }

  var canSave: Bool {
    includedCount > 0
      && zeroValueCount == 0
      && invalidNewRowCount == 0
      && validationErrorCount == 0
      && emptyCashFlowAmountCount == 0
      && cashFlowValidationErrorCount == 0
      && emptyCashFlowDescriptionCount == 0
  }
}

/// Result of a CSV import operation in bulk entry.
struct CSVImportResult {
  let matchedCount: Int
  let newCount: Int
  let errors: [String]
  let parserWarnings: [String]
  let platformMismatches: [String]
  let currencyMismatches: [String]

  var totalImported: Int { matchedCount + newCount }
  var hasErrors: Bool { !errors.isEmpty }
  var hasWarnings: Bool {
    !parserWarnings.isEmpty || !platformMismatches.isEmpty || !currencyMismatches.isEmpty
  }

  var feedback: CSVImportFeedback {
    let formatted = formattedResult()
    let severity: CSVImportFeedback.Severity
    if hasErrors {
      severity = .error
    } else if hasWarnings {
      severity = .warning
    } else {
      severity = .success
    }
    return CSVImportFeedback(severity: severity, message: formatted.message)
  }

  /// Formats the import result into a user-facing title and message.
  func formattedResult() -> (title: String, message: String) {
    let title: String
    if hasErrors {
      title = String(localized: "Import Error", table: "Snapshot")
    } else if hasWarnings {
      title = String(localized: "Import Warning", table: "Snapshot")
    } else {
      title = String(localized: "CSV Import", table: "Snapshot")
    }

    var lines: [String] = []

    if matchedCount > 0 {
      lines.append(
        String(
          localized: "\(matchedCount) existing assets updated.",
          table: "Snapshot"))
    }
    if newCount > 0 {
      lines.append(
        String(
          localized: "\(newCount) new assets added.",
          table: "Snapshot"))
    }
    if totalImported == 0 && !hasErrors {
      lines.append(
        String(
          localized: "No assets were imported.",
          table: "Snapshot"))
    }

    for error in errors {
      lines.append(error)
    }
    for warning in parserWarnings {
      lines.append(warning)
    }

    if !platformMismatches.isEmpty {
      let names = platformMismatches.joined(separator: ", ")
      lines.append(
        String(
          localized:
            "\(platformMismatches.count) assets skipped (platform mismatch): \(names)",
          table: "Snapshot"))
    }
    if !currencyMismatches.isEmpty {
      let names = currencyMismatches.joined(separator: ", ")
      lines.append(
        String(
          localized:
            "\(currencyMismatches.count) assets skipped (currency mismatch): \(names)",
          table: "Snapshot"))
    }

    return (title: title, message: lines.joined(separator: "\n\n"))
  }
}

/// Which CSV import context is active.  SwiftUI on macOS silently drops
/// duplicate `.fileImporter` modifiers attached to the same view, so we
/// use a single modifier and dispatch on this value.
enum CSVImportTarget {
  case asset(platform: String)
  case cashFlow
}

/// Source of a bulk entry row's value.
enum ValueSource: Equatable {
  case manual
  case csv
  case manualNew
}

/// A single row in the bulk entry table, representing one asset to update.
struct BulkEntryRow: Identifiable, Equatable {
  let id: UUID
  let asset: Asset?
  var assetName: String
  let platform: String
  var currency: String
  let previousValue: Decimal?
  var newValueText: String
  var isIncluded: Bool
  var source: ValueSource
  var categoryName: String?

  var newValue: Decimal? { Decimal.parse(newValueText) }
  var isUpdated: Bool { isIncluded && newValue != nil && !hasZeroValueError }
  var isPending: Bool { isIncluded && (newValueText.isEmpty || newValue == nil) }
  var hasValidationError: Bool { !newValueText.isEmpty && newValue == nil }
  var hasZeroValueError: Bool { isIncluded && newValue == Decimal(0) }
  var isNewRow: Bool { source == .manualNew }
  var hasEmptyName: Bool { isNewRow && assetName.trimmingCharacters(in: .whitespaces).isEmpty }
  var isNewAsset: Bool { asset == nil }

  static func == (lhs: BulkEntryRow, rhs: BulkEntryRow) -> Bool {
    lhs.id == rhs.id
      && lhs.asset === rhs.asset
      && lhs.assetName == rhs.assetName
      && lhs.platform == rhs.platform
      && lhs.currency == rhs.currency
      && lhs.previousValue == rhs.previousValue
      && lhs.newValueText == rhs.newValueText
      && lhs.isIncluded == rhs.isIncluded
      && lhs.source == rhs.source
      && lhs.categoryName == rhs.categoryName
  }
}

/// A single row in the bulk entry cash flow section.
struct BulkEntryCashFlowRow: Identifiable, Equatable {
  let id: UUID
  var cashFlowDescription: String
  var amountText: String
  var currency: String
  var isIncluded: Bool
  var source: ValueSource

  var amount: Decimal? { Decimal.parse(amountText) }
  var hasValidationError: Bool { !amountText.isEmpty && amount == nil }
  var hasEmptyAmount: Bool { isIncluded && amountText.trimmingCharacters(in: .whitespaces).isEmpty }
  var hasEmptyDescription: Bool {
    cashFlowDescription.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

/// Result of a cash flow CSV import operation in bulk entry.
struct CashFlowCSVImportResult {
  let matchedCount: Int
  let newCount: Int
  let errors: [String]
  let parserWarnings: [String]

  var totalImported: Int { matchedCount + newCount }
  var hasErrors: Bool { !errors.isEmpty }
  var hasWarnings: Bool { !parserWarnings.isEmpty }

  var feedback: CSVImportFeedback {
    let formatted = formattedResult()
    let severity: CSVImportFeedback.Severity
    if hasErrors {
      severity = .error
    } else if hasWarnings {
      severity = .warning
    } else {
      severity = .success
    }
    return CSVImportFeedback(severity: severity, message: formatted.message)
  }

  /// Formats the import result into a user-facing title and message.
  func formattedResult() -> (title: String, message: String) {
    let title: String
    if hasErrors {
      title = String(localized: "Import Error", table: "Snapshot")
    } else if hasWarnings {
      title = String(localized: "Import Warning", table: "Snapshot")
    } else {
      title = String(localized: "CSV Import", table: "Snapshot")
    }

    var lines: [String] = []

    if matchedCount > 0 {
      lines.append(
        String(
          localized: "\(matchedCount) existing cash flows updated.",
          table: "Snapshot"))
    }
    if newCount > 0 {
      lines.append(
        String(
          localized: "\(newCount) new cash flows added.",
          table: "Snapshot"))
    }
    if totalImported == 0 && !hasErrors {
      lines.append(
        String(
          localized: "No cash flows were imported.",
          table: "Snapshot"))
    }

    for error in errors {
      lines.append(error)
    }
    for warning in parserWarnings {
      lines.append(warning)
    }

    return (title: title, message: lines.joined(separator: "\n\n"))
  }
}
