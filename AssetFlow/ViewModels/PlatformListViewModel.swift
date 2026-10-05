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

/// Data for a single platform row in the list.
struct PlatformRowData: Identifiable {
  /// Platform name serves as the stable identifier (unique, case-insensitive).
  var id: String { name }
  let name: String
  let assetCount: Int
  let totalValue: Decimal
}

/// ViewModel for the Platforms list screen.
///
/// Derives platform data from assets — platforms are not model objects,
/// they are distinct non-empty `Asset.platform` values.
@Observable
@MainActor
final class PlatformListViewModel {
  @ObservationIgnored private let refresh = ObservedRefresh()

  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  var platformRows: [PlatformRowData] = []
  var loadState: DataLoadState = .idle
  var conversionStatus: CurrencyConversionStatus = .notNeeded

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
    refresh.request { [weak self] in self?.loadPlatforms() }
  }

  // MARK: - Loading

  /// Fetches all assets, computes platform totals from the latest snapshot,
  /// and builds sorted row data.
  ///
  /// Uses `ObservedRefresh` to track source reads and publish derived results. Any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadPlatforms() {
    refresh.perform {
      performLoadPlatforms()
    } reload: { [weak self] in
      self?.loadPlatforms()
    }
  }

  private func performLoadPlatforms() {
    do {
      let allAssets = try fetchAllAssets()

      // Group assets by non-empty platform
      let assetsByPlatform = Dictionary(
        grouping: allAssets.filter { !$0.platform.isEmpty },
        by: { $0.platform }
      )

      // Build platform → total value lookup from latest snapshot
      let latestSnapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      let status =
        latestSnapshot.map {
          CurrencyConversionService.totalValueReport(
            for: $0,
            displayCurrency: settingsService.mainCurrency,
            exchangeRate: $0.exchangeRate
          ).status
        } ?? .notNeeded
      let platformValues = buildPlatformValueLookup(latestSnapshot: latestSnapshot)

      let rows =
        assetsByPlatform.map { platform, assets in
          PlatformRowData(
            name: platform,
            assetCount: assets.count,
            totalValue: platformValues[platform] ?? 0
          )
        }

      // Sort by stored order; unknown platforms go to the end alphabetically
      let storedOrder = settingsService.platformOrder
      let orderLookup = Dictionary(
        uniqueKeysWithValues: storedOrder.enumerated().map { ($1, $0) }
      )

      let loadedRows = rows.sorted { lhs, rhs in
        let lhsIndex = orderLookup[lhs.name]
        let rhsIndex = orderLookup[rhs.name]
        switch (lhsIndex, rhsIndex) {
        case (.some(let lhsOrder), .some(let rhsOrder)):
          return lhsOrder < rhsOrder

        case (.some, .none):
          return true

        case (.none, .some):
          return false

        case (.none, .none):
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
      }

      // Sync stored order: prune removed platforms, append new ones
      let currentNames = Set(loadedRows.map(\.name))
      var updatedOrder = storedOrder.filter { currentNames.contains($0) }
      let knownNames = Set(updatedOrder)
      for row in loadedRows where !knownNames.contains(row.name) {
        updatedOrder.append(row.name)
      }
      if updatedOrder != storedOrder {
        settingsService.platformOrder = updatedOrder
      }
      refresh.publish {
        self.conversionStatus = status
        self.platformRows = loadedRows
        self.loadState = .loaded
      }
    } catch {
      let message = error.localizedDescription
      refresh.publish { self.loadState = .failed(message) }
    }
  }

  // MARK: - Move

  /// Reorders platforms by moving items at the given offsets to the target position.
  func movePlatforms(from source: IndexSet, to destination: Int) {
    var names = platformRows.map(\.name)
    let adjustedDestination = destination - source.filter { $0 < destination }.count
    let moved = source.sorted().map { names[$0] }
    for index in source.sorted().reversed() {
      names.remove(at: index)
    }
    let insertAt = min(adjustedDestination, names.count)
    names.insert(contentsOf: moved, at: insertAt)
    settingsService.platformOrder = names
    loadPlatforms()
  }

  // MARK: - Rename

  /// Renames a platform by updating all assets with the old platform name.
  ///
  /// - Parameters:
  ///   - oldName: The current platform name to rename.
  ///   - newName: The desired new platform name.
  /// - Returns: The trimmed new platform name.
  /// - Throws: `PlatformError.emptyName` if new name is blank after trimming,
  ///   `PlatformError.duplicateName` if new name conflicts with an existing platform.
  @discardableResult
  func renamePlatform(from oldName: String, to newName: String) throws -> String {
    let trimmed = newName.collapsingWhitespace

    guard !trimmed.isEmpty else { throw PlatformError.emptyName }

    let allAssets = try fetchAllAssets()

    // Check for duplicate (case-insensitive), allowing self-rename with different casing
    let normalizedNew = trimmed.lowercased()
    let normalizedOld = oldName.lowercased()

    if normalizedNew != normalizedOld {
      let existingPlatforms = Set(
        allAssets
          .map { $0.platform.lowercased() }
          .filter { !$0.isEmpty }
      )

      if existingPlatforms.contains(normalizedNew) {
        throw PlatformError.duplicateName(trimmed)
      }
    }

    // Update all assets with the old platform name
    for asset in allAssets where asset.platform == oldName {
      asset.platform = trimmed
    }

    return trimmed
  }

  // MARK: - Private Helpers

  private func fetchAllAssets() throws -> [Asset] {
    let descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)])
    return try fetchModels(descriptor, from: fetcher, operation: "fetch assets")
  }

  /// Builds a lookup of platform name → total market value from the latest snapshot.
  private func buildPlatformValueLookup(
    latestSnapshot: Snapshot?
  ) -> [String: Decimal] {
    guard let latestSnapshot else { return [:] }

    let assetValues = latestSnapshot.assetValues ?? []
    let displayCurrency = settingsService.mainCurrency
    let exchangeRate = latestSnapshot.exchangeRate

    let report = CurrencyConversionService.totalValueReport(
      for: latestSnapshot,
      displayCurrency: displayCurrency,
      exchangeRate: exchangeRate
    )
    guard report.status.isComplete else { return [:] }

    var lookup: [String: Decimal] = [:]
    for sav in assetValues {
      guard let asset = sav.asset, !asset.platform.isEmpty else { continue }
      let assetCurrency = asset.currency
      let effectiveCurrency = assetCurrency.isEmpty ? displayCurrency : assetCurrency
      let converted = CurrencyConversionService.convert(
        value: sav.marketValue,
        from: effectiveCurrency,
        to: displayCurrency,
        using: exchangeRate,
        forSnapshotDate: latestSnapshot.date)
      lookup[asset.platform, default: 0] += converted ?? 0
    }
    return lookup
  }
}
