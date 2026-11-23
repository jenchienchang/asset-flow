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

/// Grouping mode for the asset list.
enum AssetGroupingMode: CaseIterable {
  case byPlatform
  case byCategory
}

/// Data for a single asset row in the list.
struct AssetRowData {
  let asset: Asset
  let latestValue: Decimal?
  let portfolioPercentage: Decimal?
}

/// A group of assets with a header name.
struct AssetGroup: Identifiable {
  enum ID: Hashable {
    case platform(UUID?)
    case category(UUID?)

    var isMissing: Bool {
      switch self {
      case .platform(nil), .category(nil): true
      default: false
      }
    }
  }

  let id: ID
  let name: String
  let assets: [AssetRowData]
}

/// ViewModel for the Assets list screen.
///
/// Manages asset listing with grouping (by platform or category),
/// latest values and portfolio shares from the most recent snapshot,
/// and asset deletion with validation.
@Observable
@MainActor
final class AssetListViewModel {
  @ObservationIgnored private let refresh = ObservedRefresh()

  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  var groupingMode: AssetGroupingMode = .byPlatform
  var groups: [AssetGroup] = []
  var loadState: DataLoadState = .idle

  /// Whether the most recent load hid at least one stale asset due to the
  /// "Hide Stale Assets" filter. Drives the empty-state messaging in
  /// `AssetListView` so users know assets are filtered, not absent.
  var hasHiddenStaleAssets: Bool = false

  init(
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.settingsService = settingsService ?? .shared
  }

  /// Coalesces source-observation and query notifications before refreshing.
  func requestRefresh() {
    refresh.request { [weak self] in self?.loadAssets() }
  }

  // MARK: - Loading

  /// Fetches all assets, computes latest values and shares from the most recent snapshot,
  /// and groups them by the current grouping mode.
  ///
  /// Uses `ObservedRefresh` to track source reads and publish derived results. Any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadAssets() {
    refresh.perform {
      performLoadAssets()
    } reload: { [weak self] in
      self?.loadAssets()
    }
  }

  private func performLoadAssets() {
    do {
      let allAssets = try fetchAllAssets()
      let latestSnapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      let latestValues = buildLatestValueLookup(latestSnapshot: latestSnapshot)

      // Build row data for each asset
      let allRows = allAssets.map { asset in
        let values = latestValues[asset.id]
        return AssetRowData(
          asset: asset,
          latestValue: values?.nativeValue,
          portfolioPercentage: values?.portfolioPercentage
        )
      }

      // Apply the "Hide Stale Assets" filter — stale = no value in the latest snapshot.
      let hideStale = settingsService.hideStaleAssets
      let visibleRows = hideStale ? allRows.filter { $0.latestValue != nil } : allRows
      let hidden = hideStale && visibleRows.count < allRows.count

      // Group and sort
      let loadedGroups = buildGroups(from: visibleRows)
      refresh.publish {
        self.hasHiddenStaleAssets = hidden
        self.groups = loadedGroups
        self.loadState = .loaded
      }
    } catch {
      let message = error.localizedDescription
      refresh.publish { self.loadState = .failed(message) }
    }
  }

  // MARK: - Deletion

  /// Deletes an asset if it has no snapshot values.
  ///
  /// - Throws: `AssetError.cannotDelete` if the asset has snapshot values.
  func deleteAsset(_ asset: Asset) throws {
    let savs = asset.snapshotAssetValues ?? []
    guard savs.isEmpty else {
      let snapshotCount = Set(savs.compactMap { $0.snapshot?.id }).count
      throw AssetError.cannotDelete(snapshotCount: snapshotCount)
    }
    modelContext.delete(asset)
  }

  // MARK: - Private Helpers

  private func fetchAllAssets() throws -> [Asset] {
    let descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)])
    return try fetchModels(descriptor, from: fetcher, operation: "fetch assets")
  }

  /// Looks up native values and shares of the full snapshot total by asset ID.
  private func buildLatestValueLookup(
    latestSnapshot: Snapshot?
  ) -> [UUID: (nativeValue: Decimal, portfolioPercentage: Decimal?)] {
    guard let latestSnapshot else { return [:] }

    let displayCurrency = settingsService.mainCurrency
    let exchangeRate = latestSnapshot.exchangeRate
    let total = CurrencyConversionService.totalValue(
      for: latestSnapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate)

    var lookup: [UUID: (nativeValue: Decimal, portfolioPercentage: Decimal?)] = [:]
    for assetValue in latestSnapshot.assetValues ?? [] {
      guard let asset = assetValue.asset else { continue }
      let nativeValue = assetValue.marketValue
      let portfolioPercentage: Decimal? = total.flatMap { total in
        guard total > 0 else { return nil }
        let currency = asset.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
          let convertedValue = CurrencyConversionService.convert(
            value: nativeValue,
            from: currency.isEmpty ? displayCurrency : currency,
            to: displayCurrency,
            using: exchangeRate,
            forSnapshotDate: latestSnapshot.date)
        else { return nil }
        return convertedValue / total * 100
      }
      lookup[asset.id] = (nativeValue, portfolioPercentage)
    }
    return lookup
  }

  /// Groups row data by the current grouping mode, sorts groups alphabetically
  /// with the "missing" group last, and sorts assets within each group alphabetically.
  private func buildGroups(from rowDataList: [AssetRowData]) -> [AssetGroup] {
    let noPlatformName = String(localized: "(No Platform)", table: "Asset")
    let uncategorizedName = String(localized: "(Uncategorized)", table: "Asset")

    let grouped = Dictionary(grouping: rowDataList) { row -> AssetGroup.ID in
      switch groupingMode {
      case .byPlatform: .platform(row.asset.platformRecord?.id)
      case .byCategory: .category(row.asset.category?.id)
      }
    }

    return
      grouped
      .map { key, rows in
        let name: String
        switch key {
        case .platform: name = rows.first?.asset.platformRecord?.name ?? noPlatformName
        case .category: name = rows.first?.asset.category?.name ?? uncategorizedName
        }
        return AssetGroup(
          id: key,
          name: name,
          assets: rows.sorted {
            $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
          }
        )
      }
      .sorted { lhs, rhs in
        // Missing group always last
        if lhs.id.isMissing { return false }
        if rhs.id.isMissing { return true }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
  }
}
