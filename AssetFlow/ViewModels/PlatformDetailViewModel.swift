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

/// Value history entry for a platform's total value at a snapshot date.
struct PlatformValueHistoryEntry: Identifiable {
  var id: String { "\(date.timeIntervalSince1970)-\(totalValue)" }
  let date: Date
  let totalValue: Decimal
}

/// ViewModel for the Platform detail/edit screen.
///
/// Loads platform assets and history and validates edits through PlatformService.
@Observable
@MainActor
final class PlatformDetailViewModel {
  @ObservationIgnored private let refresh = ObservedRefresh()

  /// The current canonical platform name (updated after successful rename).
  private(set) var platformName: String
  let platform: Platform
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  /// Text field binding for the platform name.
  var editedName: String

  /// Assets on this platform with their latest composite values.
  var assets: [DetailAssetRowData] = []

  /// Sum of latest values for all assets on this platform.
  var totalValue: Decimal = 0

  /// Platform total value per snapshot across all snapshots.
  var valueHistory: [PlatformValueHistoryEntry] = []
  var conversionStatus: CurrencyConversionStatus = .notNeeded
  var loadState: DataLoadState = .idle

  init(
    platform: Platform,
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.platformName = platform.name
    self.platform = platform
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.settingsService = settingsService ?? .shared
    self.editedName = platform.name
  }

  /// Coalesces source-observation and query notifications before refreshing.
  func requestRefresh() {
    refresh.request { [weak self] in self?.loadData() }
  }

  // MARK: - Load Data

  /// Fetches all snapshots and loads assets and history.
  ///
  /// Uses `ObservedRefresh` to track source reads and publish derived results. Any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadData() {
    let wasClean = editedName == platformName
    refresh.perform {
      performLoadData(wasClean: wasClean)
    } reload: { [weak self] in
      self?.loadData()
    }
  }

  func reloadAfterStoreChange() {
    loadData()
  }

  private func performLoadData(wasClean: Bool) {
    do {
      let latestName = platform.name
      let allSnapshots = try SnapshotSummaryService.fetchSnapshots(using: fetcher)
      let summaries = SnapshotSummaryService.makeSummaries(
        for: allSnapshots,
        displayCurrency: settingsService.mainCurrency)
      let status = CurrencyConversionStatus.merged(
        summaries.map(\.conversionStatus))

      let rows = try loadAssets(allSnapshots: allSnapshots)
      let history = loadHistory(summaries: summaries)
      let total =
        status.isComplete
        ? rows.reduce(Decimal(0)) { $0 + ($1.convertedValue ?? $1.latestValue ?? 0) } : 0
      refresh.publish {
        self.platformName = latestName
        if wasClean { self.editedName = latestName }
        self.assets = rows
        self.valueHistory = history
        self.totalValue = total
        self.conversionStatus = status
        self.loadState = .loaded
      }
    } catch {
      let message = error.localizedDescription
      refresh.publish { self.loadState = .failed(message) }
    }
  }

  // MARK: - Save (Rename)

  /// Validates the edited name and renames the persisted platform.
  ///
  /// - Throws: `PlatformError.emptyName` if name is blank after trimming,
  ///   `PlatformError.duplicateName` if name conflicts with another existing platform.
  func save() throws {
    try PlatformService.rename(
      platform, to: editedName, in: modelContext, settings: settingsService)
    platformName = platform.name
    editedName = platform.name
  }

  // MARK: - Private Helpers

  private func fetchAllAssets() throws -> [Asset] {
    let descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)])
    return try fetchModels(descriptor, from: fetcher, operation: "fetch assets")
  }

  /// Loads assets on this platform with their latest values.
  private func loadAssets(allSnapshots: [Snapshot]) throws -> [DetailAssetRowData] {
    // Build latest value lookup from most recent snapshot
    var latestValueLookup: [UUID: Decimal] = [:]
    if let latestSnapshot = allSnapshots.last {
      for sav in latestSnapshot.assetValues ?? [] {
        guard let asset = sav.asset, asset.platformRecord?.id == platform.id else { continue }
        latestValueLookup[asset.id] = sav.marketValue
      }
    }

    // Collect all assets that belong to this platform
    let platformAssets = try fetchAllAssets().filter { $0.platformRecord?.id == platform.id }

    let displayCurrency = settingsService.mainCurrency
    let latestExchangeRate = allSnapshots.last?.exchangeRate
    let latestSnapshotDate = allSnapshots.last?.date

    return platformAssets.map { asset in
      let value = latestValueLookup[asset.id]
      let assetCurrency = asset.currency
      let effectiveCurrency = assetCurrency.isEmpty ? displayCurrency : assetCurrency
      let converted: Decimal? =
        if let value, let snapshotDate = latestSnapshotDate,
          effectiveCurrency != displayCurrency
        {
          CurrencyConversionService.convert(
            value: value,
            from: effectiveCurrency,
            to: displayCurrency,
            using: latestExchangeRate,
            forSnapshotDate: snapshotDate)
        } else {
          nil
        }
      return DetailAssetRowData(
        asset: asset,
        latestValue: value,
        convertedValue: converted
      )
    }
    .sorted {
      $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
    }

  }

  /// Computes value history across all snapshots for this platform.
  private func loadHistory(summaries: [SnapshotSummary]) -> [PlatformValueHistoryEntry] {
    var entries: [PlatformValueHistoryEntry] = []

    for summary in summaries {
      entries.append(
        PlatformValueHistoryEntry(
          date: summary.date,
          totalValue: summary.platformValuesByID[platform.id] ?? 0))
    }

    return entries
  }
}
