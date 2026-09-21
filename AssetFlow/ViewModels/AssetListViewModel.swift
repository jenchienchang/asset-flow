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
}

/// A group of assets with a header name.
struct AssetGroup {
  let name: String
  let assets: [AssetRowData]
}

/// ViewModel for the Assets list screen.
///
/// Manages asset listing with grouping (by platform or category),
/// latest value computation from the most recent composite snapshot,
/// and asset deletion with validation.
@Observable
@MainActor
final class AssetListViewModel {
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

  // MARK: - Loading

  /// Fetches all assets, computes latest values from the most recent snapshot,
  /// and groups them by the current grouping mode.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadAssets() {
    withObservationTracking {
      performLoadAssets()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadAssets()
      }
    }
  }

  private func performLoadAssets() {
    do {
      let allAssets = try fetchAllAssets()
      // Build latest value lookup from most recent snapshot
      let latestValueLookup = buildLatestValueLookup(
        latestSnapshot: try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher))

      // Build row data for each asset
      let allRows = allAssets.map { asset in
        AssetRowData(
          asset: asset,
          latestValue: latestValueLookup[asset.id]
        )
      }

      // Apply the "Hide Stale Assets" filter — stale = no value in the latest snapshot.
      let hideStale = settingsService.hideStaleAssets
      let visibleRows = hideStale ? allRows.filter { $0.latestValue != nil } : allRows
      hasHiddenStaleAssets = hideStale && visibleRows.count < allRows.count

      // Group and sort
      groups = buildGroups(from: visibleRows)
      loadState = .loaded
    } catch {
      loadState = .failed(error.localizedDescription)
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

  /// Builds a lookup of asset ID → latest market value from the most recent snapshot.
  private func buildLatestValueLookup(
    latestSnapshot: Snapshot?
  ) -> [UUID: Decimal] {
    guard let latestSnapshot else { return [:] }

    let assetValues = latestSnapshot.assetValues ?? []

    var lookup: [UUID: Decimal] = [:]
    for sav in assetValues {
      guard let asset = sav.asset else { continue }
      lookup[asset.id] = sav.marketValue
    }
    return lookup
  }

  /// Groups row data by the current grouping mode, sorts groups alphabetically
  /// with the "missing" group last, and sorts assets within each group alphabetically.
  private func buildGroups(from rowDataList: [AssetRowData]) -> [AssetGroup] {
    let noPlatformName = String(localized: "(No Platform)", table: "Asset")
    let uncategorizedName = String(localized: "(Uncategorized)", table: "Asset")

    let grouped: [String: [AssetRowData]]
    let missingGroupName: String

    switch groupingMode {
    case .byPlatform:
      missingGroupName = noPlatformName
      grouped = Dictionary(grouping: rowDataList) { row in
        row.asset.platform.isEmpty ? noPlatformName : row.asset.platform
      }

    case .byCategory:
      missingGroupName = uncategorizedName
      grouped = Dictionary(grouping: rowDataList) { row in
        row.asset.category?.name ?? uncategorizedName
      }
    }

    return
      grouped
      .map { key, rows in
        AssetGroup(
          name: key,
          assets: rows.sorted {
            $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
          }
        )
      }
      .sorted { lhs, rhs in
        // Missing group always last
        if lhs.name == missingGroupName { return false }
        if rhs.name == missingGroupName { return true }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
  }
}
