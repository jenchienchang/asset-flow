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

@MainActor
enum CategoryGoalPresentation {
  /// Exact decimal text: ISO currency is explicit and no small amount rounds to zero.
  static func amount(_ value: Decimal, currency: String, locale: Locale = .current) -> String {
    "\(currency.uppercased()) \(number(value, locale: locale))"
  }

  /// Exact locale-aware numeric text shared by amounts and currency-labeled tables.
  static func number(_ value: Decimal, locale: Locale = .current) -> String {
    var decimal = value
    let raw = NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    let separator = formatter.decimalSeparator ?? "."
    let grouping = formatter.groupingSeparator ?? ","
    let negative = raw.hasPrefix("-")
    let parts = (negative ? String(raw.dropFirst()) : raw).components(separatedBy: ".")
    var integer = parts[0]
    var groups: [String] = []
    var size = max(1, formatter.groupingSize)
    while integer.count > size {
      groups.insert(String(integer.suffix(size)), at: 0)
      integer.removeLast(size)
      size = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : size
    }
    groups.insert(integer, at: 0)
    let number =
      (negative ? "-" : "") + groups.joined(separator: grouping)
      + (parts.count == 2 ? separator + parts[1] : "")
    return number
  }

  static func minimumStatus(_ status: MinimumBalanceStatus, currency: String) -> String {
    switch status {
    case .notSet: return String(localized: "No minimum balance", table: "Category")

    case .noSnapshot:
      return String(localized: "Add a snapshot to assess the minimum balance.", table: "Category")

    case .unavailable: return String(localized: "Minimum balance unavailable", table: "Category")
    case .met: return String(localized: "Minimum balance met", table: "Category")

    case .shortfall(let amount):
      return String(
        localized: "Minimum balance shortfall: \(Self.amount(amount, currency: currency))",
        table: "Category")
    }
  }

  static func diagnostic(
    _ plan: RebalancingPlan?, currency: String, formatAmount: ((Decimal) -> String)? = nil,
    bundle: Bundle = .main
  ) -> String? {
    guard let plan else { return nil }
    let formattedAmount = formatAmount ?? { Self.amount($0, currency: currency) }
    switch plan.status {
    case .feasible: return nil

    case .noGoals:
      return String(
        localized: "Set percentage targets or minimum balances on your categories.",
        table: "Rebalancing", bundle: bundle)

    case .invalidData:
      return String(
        localized:
          "Rebalancing is unavailable because the portfolio data or goal configuration is invalid.",
        table: "Rebalancing", bundle: bundle)

    case .invalidPercentageSum(let sum):
      return String(
        localized:
          "Percentage targets sum to \(sum.formattedPercentage()). Set their total to 100% to calculate rebalancing.",
        table: "Rebalancing", bundle: bundle)

    case .minimumsExceedPortfolio(let amount):
      return String(
        localized:
          "Minimum balances exceed the portfolio value by \(formattedAmount(amount)). Add funds or lower the minimums to meet all requirements.",
        table: "Rebalancing", bundle: bundle)

    case .insufficientAvailableFunds(let amount):
      return String(
        localized:
          "Protected balances leave a funding shortfall of \(formattedAmount(amount)). Add funds or change category goals to make funds available for rebalancing.",
        table: "Rebalancing", bundle: bundle)
    }
  }
}
