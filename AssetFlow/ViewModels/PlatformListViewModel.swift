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
  let id: UUID
  let name: String
  let assetCount: Int
  let totalValue: Decimal
}

/// ViewModel for the Platforms list screen.
///
/// Presents persisted platforms that currently contain assets.
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

  /// Fetches persisted platforms, computes totals from the latest snapshot,
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
      let platforms = try fetchModels(
        FetchDescriptor<Platform>(), from: fetcher, operation: "fetch platforms")

      // Build platform → total value lookup from latest snapshot
      let latestSnapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      let summary = latestSnapshot.map {
        SnapshotSummaryService.makeSummary(for: $0, displayCurrency: settingsService.mainCurrency)
      }
      let status = summary?.conversionStatus ?? .notNeeded
      let platformValues = summary?.platformValuesByID ?? [:]

      PlatformService.reconcileDisplayOrder(platforms)
      let loadedRows = PlatformService.orderedForDisplay(
        platforms.filter { !($0.assets ?? []).isEmpty }
      )
      .map { platform in
        PlatformRowData(
          id: platform.id, name: platform.name, assetCount: (platform.assets ?? []).count,
          totalValue: platformValues[platform.id] ?? 0)
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
    var ids = platformRows.map(\.id)
    let adjustedDestination = destination - source.filter { $0 < destination }.count
    let moved = source.sorted().map { ids[$0] }
    for index in source.sorted().reversed() { ids.remove(at: index) }
    ids.insert(contentsOf: moved, at: min(adjustedDestination, ids.count))
    do {
      let platforms = try modelContext.fetch(FetchDescriptor<Platform>())
      let ordered = PlatformService.orderedForDisplay(platforms)
      let byID = Dictionary(uniqueKeysWithValues: platforms.map { ($0.id, $0) })
      let visibleIDs = Set(ids)
      var nextVisible = 0
      for (index, platform) in ordered.enumerated() {
        if visibleIDs.contains(platform.id) {
          byID[ids[nextVisible]]?.displayOrder = index
          nextVisible += 1
        } else {
          platform.displayOrder = index
        }
      }
    } catch {
      loadState = .failed(error.localizedDescription)
      return
    }
    loadPlatforms()
  }

  // MARK: - Rename

  /// Renames one platform while preserving its identity and relationships.
  ///
  /// - Parameters:
  ///   - id: The stable platform identifier.
  ///   - newName: The desired new platform name.
  /// - Returns: The trimmed new platform name.
  /// - Throws: `PlatformError.emptyName` if new name is blank after trimming,
  ///   `PlatformError.duplicateName` if new name conflicts with an existing platform.
  @discardableResult
  func renamePlatform(id: UUID, to newName: String) throws -> String {
    let platforms = try modelContext.fetch(FetchDescriptor<Platform>())
    guard let platform = platforms.first(where: { $0.id == id }) else {
      throw PlatformError.notFound
    }
    try PlatformService.rename(platform, to: newName, in: modelContext, settings: settingsService)
    return platform.name
  }

}
