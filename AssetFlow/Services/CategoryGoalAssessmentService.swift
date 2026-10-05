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
import SwiftData

enum MinimumBalanceStatus: Equatable {
  case notSet
  case noSnapshot
  case unavailable
  case met
  case shortfall(Decimal)
}

struct CategoryGoalAssessment {
  var totalValue: Decimal?
  var values: [UUID: Decimal] = [:]
  var minimums: [UUID: Decimal] = [:]
  var statuses: [UUID: MinimumBalanceStatus] = [:]
  var assetConversion: CurrencyConversionStatus = .notNeeded
  var goalConversion: CurrencyConversionStatus = .notNeeded
  var plan: RebalancingPlan?
}

@MainActor
enum CategoryGoalAssessmentService {
  static func assess(snapshot: Snapshot?, categories: [Category], displayCurrency: String)
    -> CategoryGoalAssessment
  {
    var result = CategoryGoalAssessment()
    for category in categories {
      result.statuses[category.id] = category.minimumBalanceAmount == nil ? .notSet : .noSnapshot
    }
    guard let snapshot else { return result }
    let report = CurrencyConversionService.totalValueReport(
      for: snapshot, displayCurrency: displayCurrency, exchangeRate: snapshot.exchangeRate)
    result.totalValue = report.convertedTotal
    result.assetConversion = report.status
    var missing: Set<String> = []
    var invalidConfiguration = false
    for category in categories {
      do {
        try CategoryGoalValidator.validate(
          percentage: category.targetAllocationPercentage, minimum: category.minimumBalanceAmount,
          currency: category.minimumBalanceCurrency)
      } catch {
        invalidConfiguration = true
        if category.minimumBalanceAmount != nil { result.statuses[category.id] = .unavailable }
        continue
      }
      if let minimum = category.minimumBalanceAmount, let currency = category.minimumBalanceCurrency
      {
        if let converted = convertMinimum(
          amount: minimum, currency: currency, snapshot: snapshot, displayCurrency: displayCurrency)
        {
          result.minimums[category.id] = converted
        } else {
          missing.insert(currency.lowercased())
          result.statuses[category.id] = .unavailable
        }
      }
    }
    result.goalConversion =
      missing.isEmpty
      ? (requiredCurrencies(categories: categories, displayCurrency: displayCurrency).isEmpty
        ? .notNeeded : .applied) : .missingRates(missing.sorted())
    guard let total = result.totalValue else {
      for category in categories where category.minimumBalanceAmount != nil {
        result.statuses[category.id] = .unavailable
      }
      return result
    }
    var uncategorized: Decimal = 0
    // Match the stable asset order used for the independent portfolio total.
    let assetValues = (snapshot.assetValues ?? []).sorted {
      ($0.asset?.id.uuidString ?? "") < ($1.asset?.id.uuidString ?? "")
    }
    for value in assetValues {
      guard let asset = value.asset,
        let converted = CurrencyConversionService.convert(
          value: value.marketValue, from: asset.currency.isEmpty ? displayCurrency : asset.currency,
          to: displayCurrency, using: snapshot.exchangeRate, forSnapshotDate: snapshot.date)
      else {
        invalidConfiguration = true
        continue
      }
      if let category = asset.category {
        result.values[category.id, default: 0] += converted
      } else {
        uncategorized += converted
      }
    }
    for category in categories {
      if let minimum = result.minimums[category.id] {
        let shortfall = max(0, minimum - (result.values[category.id] ?? 0))
        result.statuses[category.id] = shortfall > 0 ? .shortfall(shortfall) : .met
      }
    }
    guard result.goalConversion.isComplete else { return result }
    if invalidConfiguration {
      result.plan = RebalancingPlan(status: .invalidData)
      return result
    }
    result.plan = RebalancingCalculator.calculate(
      categories: categories.map {
        CategoryGoalAllocation(
          id: $0.id, name: $0.name, currentValue: result.values[$0.id] ?? 0,
          percentage: $0.targetAllocationPercentage, minimum: result.minimums[$0.id])
      }, totalValue: total, uncategorizedValue: uncategorized)
    return result
  }

  /// The historical overlay needs a denomination conversion, not a portfolio plan.
  static func convertMinimum(
    amount: Decimal, currency: String, snapshot: Snapshot, displayCurrency: String
  ) -> Decimal? {
    let rate = snapshot.exchangeRate
    let validBase =
      currency.caseInsensitiveCompare(displayCurrency) == .orderedSame
      || rate?.baseCurrency.caseInsensitiveCompare(displayCurrency) == .orderedSame
    guard validBase,
      let converted = CurrencyConversionService.convert(
        value: amount, from: currency, to: displayCurrency, using: rate,
        forSnapshotDate: snapshot.date), converted.isFinite
    else { return nil }
    return converted
  }

  static func requiredCurrencies(categories: [Category], displayCurrency: String) -> Set<String> {
    Set(
      categories.compactMap {
        guard $0.minimumBalanceAmount != nil, let currency = $0.minimumBalanceCurrency else {
          return nil
        }
        let code = currency.lowercased()
        return code == displayCurrency.lowercased() ? nil : code
      })
  }
}
