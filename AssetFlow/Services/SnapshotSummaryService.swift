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

/// Precomputed converted totals for a single snapshot.
struct SnapshotSummary {
  let snapshot: Snapshot
  let date: Date
  let assetCount: Int
  let totalValue: Decimal
  let categoryValues: [String: Decimal]
  let platformValues: [String: Decimal]
  let conversionStatus: CurrencyConversionStatus
  let nativeCurrencyTotals: [String: Decimal]
}

/// Shared helpers for snapshot fetching and one-pass aggregate computation.
@MainActor
enum SnapshotSummaryService {
  static func fetchSnapshots(modelContext: ModelContext) -> [Snapshot] {
    let descriptor = FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.date)])
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  static func fetchLatestSnapshot(modelContext: ModelContext) -> Snapshot? {
    var descriptor = FetchDescriptor<Snapshot>(
      sortBy: [SortDescriptor(\.date, order: .reverse)])
    descriptor.fetchLimit = 1
    return (try? modelContext.fetch(descriptor))?.first
  }

  static func fetchSnapshot(on date: Date, modelContext: ModelContext) -> Snapshot? {
    var descriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == date }
    )
    descriptor.fetchLimit = 1
    return (try? modelContext.fetch(descriptor))?.first
  }

  static func fetchLatestSnapshot(
    before date: Date,
    modelContext: ModelContext
  ) -> Snapshot? {
    var descriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date < date },
      sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    return (try? modelContext.fetch(descriptor))?.first
  }

  static func makeSummaries(
    for snapshots: [Snapshot],
    displayCurrency: String
  ) -> [SnapshotSummary] {
    snapshots.map { makeSummary(for: $0, displayCurrency: displayCurrency) }
  }

  static func makeSummary(
    for snapshot: Snapshot,
    displayCurrency: String
  ) -> SnapshotSummary {
    let assetValues = snapshot.assetValues ?? []
    let exchangeRate = snapshot.exchangeRate
    let report = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: displayCurrency,
      exchangeRate: exchangeRate
    )
    var totalValue: Decimal = 0
    var categoryValues: [String: Decimal] = [:]
    var platformValues: [String: Decimal] = [:]

    if let convertedTotal = report.convertedTotal {
      totalValue = convertedTotal
      if let convertedCategoryValues = CurrencyConversionService.categoryValues(
        for: snapshot,
        displayCurrency: displayCurrency,
        exchangeRate: exchangeRate
      ) {
        categoryValues = convertedCategoryValues
      }

      for sav in assetValues {
        if let platform = sav.asset?.platform, !platform.isEmpty,
          let asset = sav.asset,
          let converted = CurrencyConversionService.convert(
            value: sav.marketValue,
            from: asset.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? displayCurrency : asset.currency,
            to: displayCurrency,
            using: exchangeRate,
            forSnapshotDate: snapshot.date
          )
        {
          platformValues[platform, default: 0] += converted
        }
      }
    }

    return SnapshotSummary(
      snapshot: snapshot,
      date: snapshot.date,
      assetCount: assetValues.count,
      totalValue: totalValue,
      categoryValues: categoryValues,
      platformValues: platformValues,
      conversionStatus: report.status,
      nativeCurrencyTotals: report.nativeTotals
    )
  }
}
