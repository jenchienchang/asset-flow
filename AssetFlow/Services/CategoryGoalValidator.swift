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

enum CategoryGoalValidationError: LocalizedError, Equatable {
  case percentage
  case minimum
  case currency
  case number

  var errorDescription: String? {
    switch self {
    case .percentage:
      String(localized: "Target allocation must be between 0% and 100%.", table: "Category")

    case .minimum:
      String(localized: "Minimum balance must be a finite nonnegative amount.", table: "Category")

    case .currency:
      String(localized: "Choose a currency for the minimum balance.", table: "Category")

    case .number:
      String(
        localized: "Enter a complete valid number using your locale's separators.",
        table: "Category")
    }
  }
}

/// Shared validation for persisted goals and fully consumed, locale-aware form input.
enum CategoryGoalValidator {
  nonisolated static func validate(
    percentage: Decimal?, minimum: Decimal?, currency: String?,
    supportedCurrencies: Set<String>? = nil
  ) throws {
    if let percentage, !percentage.isFinite || percentage < 0 || percentage > 100 {
      throw CategoryGoalValidationError.percentage
    }
    if let minimum, !minimum.isFinite || minimum < 0 {
      throw CategoryGoalValidationError.minimum
    }
    guard (minimum == nil) == (currency == nil) else {
      throw CategoryGoalValidationError.currency
    }
    if let currency {
      let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      guard !code.isEmpty, code.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil,
        supportedCurrencies.map({ $0.contains(code) }) ?? true
      else { throw CategoryGoalValidationError.currency }
    }
  }

  static func parse(_ text: String, locale: Locale = .current) throws -> Decimal? {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    let separator = formatter.decimalSeparator ?? "."
    let grouping = formatter.groupingSeparator ?? ","
    var sign = ""
    if text.hasPrefix("-") || text.hasPrefix("+") {
      sign = text.hasPrefix("-") ? "-" : ""
      text.removeFirst()
    }
    let parts = text.components(separatedBy: separator)
    guard parts.count <= 2, !parts[0].isEmpty,
      parts.count == 1 || !parts[1].isEmpty
    else { throw CategoryGoalValidationError.number }
    let groups = parts[0].components(separatedBy: grouping)
    let digits: (String) -> Bool = { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
    guard groups.allSatisfy(digits), parts.count == 1 || digits(parts[1]) else {
      throw CategoryGoalValidationError.number
    }
    if groups.count > 1 {
      let primary = max(1, formatter.groupingSize)
      let secondary =
        formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
      guard groups.last?.count == primary, groups[0].count <= secondary,
        groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary })
      else { throw CategoryGoalValidationError.number }
    }
    let normalized = sign + groups.joined() + (parts.count == 2 ? "." + parts[1] : "")
    let significant = normalized.filter { $0 >= "0" && $0 <= "9" }.drop(while: { $0 == "0" })
    guard significant.reversed().drop(while: { $0 == "0" }).count <= 38,
      let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
      value.isFinite
    else { throw CategoryGoalValidationError.number }
    var decimal = value
    let represented = NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))
    guard canonical(normalized) == canonical(represented) else {
      throw CategoryGoalValidationError.number
    }
    return value
  }

  private static func canonical(_ text: String) -> String {
    let negative = text.hasPrefix("-")
    let unsigned = negative ? String(text.dropFirst()) : text
    let parts = unsigned.components(separatedBy: ".")
    let integer = String(parts[0].drop(while: { $0 == "0" }))
    let fraction =
      parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
    let number = (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)
    return negative && number != "0" ? "-" + number : number
  }

  static func defaultCurrency(assetCurrencies: [String], displayCurrency: String) -> String {
    let codes = Set(
      assetCurrencies.map {
        let code = $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? displayCurrency.uppercased() : code
      })
    return codes.count == 1
      ? (codes.first ?? displayCurrency.uppercased()) : displayCurrency.uppercased()
  }
}
