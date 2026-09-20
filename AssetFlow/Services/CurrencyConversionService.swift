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

enum CurrencyConversionStatus: Equatable, Sendable {
  case notNeeded
  case applied
  case missingRates([String])

  var missingCurrencies: [String] {
    if case .missingRates(let currencies) = self {
      return currencies
    }
    return []
  }

  var isComplete: Bool {
    switch self {
    case .notNeeded, .applied:
      return true

    case .missingRates:
      return false
    }
  }

  static func merged(_ statuses: [CurrencyConversionStatus]) -> CurrencyConversionStatus {
    let missing = Set(statuses.flatMap(\.missingCurrencies)).sorted()
    if !missing.isEmpty { return .missingRates(missing) }
    return statuses.contains(.applied) ? .applied : .notNeeded
  }

  var unavailableMessage: String? {
    guard case .missingRates(let currencies) = self else { return nil }
    let formattedCurrencies = currencies.map { $0.uppercased() }.joined(separator: ", ")
    return String(
      localized: "Not available due to missing exchange rates: \(formattedCurrencies).",
      table: "Services"
    )
  }
}

struct CurrencyConversionReport: Equatable, Sendable {
  let convertedTotal: Decimal?
  let nativeTotals: [String: Decimal]
  let status: CurrencyConversionStatus
}

/// Stateless service for currency conversion using exchange rates.
///
/// Conversion methods return an optional converted value. Callers must preserve native
/// currency totals and surface `CurrencyConversionStatus` when a required rate is absent.
enum CurrencyConversionService {

  static func totalValueReport(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> CurrencyConversionReport {
    let display = displayCurrency.lowercased()
    let assetValues = snapshot.assetValues ?? []
    var nativeTotals: [String: Decimal] = [:]
    var requiredCurrencies = Set<String>()

    for assetValue in assetValues {
      let currency = effectiveCurrency(
        assetValue.asset?.currency,
        displayCurrency: display)
      nativeTotals[currency, default: 0] += assetValue.marketValue
      if currency != display { requiredCurrencies.insert(currency) }
    }

    let status = conversionStatus(
      requiredCurrencies: requiredCurrencies,
      displayCurrency: display,
      exchangeRate: exchangeRate,
      snapshotDate: snapshot.date
    )
    guard status.isComplete else {
      return CurrencyConversionReport(
        convertedTotal: nil,
        nativeTotals: nativeTotals,
        status: status
      )
    }

    let convertedTotal = assetValues.reduce(Decimal(0)) { total, assetValue in
      let currency = effectiveCurrency(
        assetValue.asset?.currency,
        displayCurrency: display)
      let converted =
        convert(
          value: assetValue.marketValue,
          from: currency,
          to: display,
          using: exchangeRate,
          forSnapshotDate: snapshot.date
        ) ?? 0
      return total + converted
    }

    return CurrencyConversionReport(
      convertedTotal: convertedTotal,
      nativeTotals: nativeTotals,
      status: status
    )
  }

  static func netCashFlowReport(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> CurrencyConversionReport {
    let display = displayCurrency.lowercased()
    let operations = snapshot.cashFlowOperations ?? []
    var nativeTotals: [String: Decimal] = [:]
    var requiredCurrencies = Set<String>()

    for operation in operations {
      let currency = effectiveCurrency(operation.currency, displayCurrency: display)
      nativeTotals[currency, default: 0] += operation.amount
      if currency != display { requiredCurrencies.insert(currency) }
    }

    let status = conversionStatus(
      requiredCurrencies: requiredCurrencies,
      displayCurrency: display,
      exchangeRate: exchangeRate,
      snapshotDate: snapshot.date
    )
    guard status.isComplete else {
      return CurrencyConversionReport(
        convertedTotal: nil,
        nativeTotals: nativeTotals,
        status: status
      )
    }

    let convertedTotal = operations.reduce(Decimal(0)) { total, operation in
      let currency = effectiveCurrency(operation.currency, displayCurrency: display)
      let converted =
        convert(
          value: operation.amount,
          from: currency,
          to: display,
          using: exchangeRate,
          forSnapshotDate: snapshot.date
        ) ?? 0
      return total + converted
    }

    return CurrencyConversionReport(
      convertedTotal: convertedTotal,
      nativeTotals: nativeTotals,
      status: status
    )
  }

  static func status(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> CurrencyConversionStatus {
    CurrencyConversionStatus.merged([
      totalValueReport(
        for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate
      ).status,
      netCashFlowReport(
        for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate
      ).status,
    ])
  }

  static func nativeTotals(
    for snapshot: Snapshot,
    displayCurrency: String
  ) -> [String: Decimal] {
    totalValueReport(for: snapshot, displayCurrency: displayCurrency, exchangeRate: nil)
      .nativeTotals
  }

  private static func conversionStatus(
    requiredCurrencies: Set<String>,
    displayCurrency: String,
    exchangeRate: ExchangeRate?,
    snapshotDate: Date
  ) -> CurrencyConversionStatus {
    guard !requiredCurrencies.isEmpty else { return .notNeeded }
    guard let exchangeRate else {
      return .missingRates(requiredCurrencies.sorted())
    }
    guard exchangeRate.baseCurrency.lowercased() == displayCurrency else {
      return .missingRates(requiredCurrencies.sorted())
    }
    guard exchangeRate.matchesDate(snapshotDate) else {
      return .missingRates(requiredCurrencies.sorted())
    }
    let missing = exchangeRate.missingCurrencies(requiredCurrencies)
    return missing.isEmpty ? .applied : .missingRates(missing)
  }

  private static func effectiveCurrency(_ currency: String?, displayCurrency: String) -> String {
    let normalized = currency?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return normalized.isEmpty ? displayCurrency : normalized
  }

  /// Converts a value from one currency to another.
  ///
  /// Returns nil when a required exchange rate is unavailable.
  /// The exchange rate must match the date of the snapshot being converted.
  static func convert(
    value: Decimal,
    from: String,
    to: String,
    using exchangeRate: ExchangeRate?,
    forSnapshotDate snapshotDate: Date
  ) -> Decimal? {
    let fromLower = from.lowercased()
    let toLower = to.lowercased()

    guard fromLower != toLower else { return value }
    guard let exchangeRate else { return nil }
    guard exchangeRate.matchesDate(snapshotDate) else {
      return nil
    }
    return exchangeRate.convert(value: value, from: fromLower, to: toLower)
  }

  /// Computes total portfolio value for a snapshot, converting each asset's value
  /// from its native currency to the display currency.
  static func totalValue(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> Decimal? {
    totalValueReport(
      for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate
    ).convertedTotal
  }

  /// Computes net cash flow for a snapshot, converting each operation's amount
  /// from its currency to the display currency.
  static func netCashFlow(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> Decimal? {
    netCashFlowReport(
      for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate
    ).convertedTotal
  }

  /// Groups asset values by category name, converting each to display currency.
  ///
  /// Assets without a category are grouped under an empty string key.
  static func categoryValues(
    for snapshot: Snapshot,
    displayCurrency: String,
    exchangeRate: ExchangeRate?
  ) -> [String: Decimal]? {
    guard
      totalValueReport(
        for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate
      ).status.isComplete
    else { return nil }

    let assetValues = snapshot.assetValues ?? []
    var result: [String: Decimal] = [:]
    for assetValue in assetValues {
      let categoryName = assetValue.asset?.category?.name ?? ""
      let currency = effectiveCurrency(assetValue.asset?.currency, displayCurrency: displayCurrency)
      let converted =
        convert(
          value: assetValue.marketValue,
          from: currency,
          to: displayCurrency,
          using: exchangeRate,
          forSnapshotDate: snapshot.date
        ) ?? 0
      result[categoryName, default: 0] += converted
    }
    return result
  }

  /// Checks whether conversion is possible between two currencies.
  static func canConvert(
    from: String,
    to: String,
    using exchangeRate: ExchangeRate?,
    forSnapshotDate snapshotDate: Date
  ) -> Bool {
    let fromLower = from.lowercased()
    let toLower = to.lowercased()

    guard fromLower != toLower else { return true }
    guard let exchangeRate else { return false }
    guard exchangeRate.matchesDate(snapshotDate) else {
      return false
    }
    return exchangeRate.convert(value: Decimal(1), from: fromLower, to: toLower) != nil
  }
}
