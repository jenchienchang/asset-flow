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
/// Manages renaming a platform (updating all `Asset.platform` values),
/// loading assets on this platform with latest values, and computing
/// value history across snapshots.
///
/// **Note:** Platforms are not model objects — they are derived from distinct
/// non-empty `Asset.platform` string values. Rename mutates all Asset records.
@Observable
@MainActor
final class PlatformDetailViewModel {
  /// The current canonical platform name (updated after successful rename).
  private(set) var platformName: String
  private let modelContext: ModelContext
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
  private var summaries: [SnapshotSummary] = []

  init(platformName: String, modelContext: ModelContext, settingsService: SettingsService? = nil) {
    self.platformName = platformName
    self.modelContext = modelContext
    self.settingsService = settingsService ?? .shared
    self.editedName = platformName
  }

  // MARK: - Load Data

  /// Fetches all snapshots and loads assets and history.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadData() {
    withObservationTracking {
      performLoadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadData()
      }
    }
  }

  private func performLoadData() {
    let allSnapshots = SnapshotSummaryService.fetchSnapshots(modelContext: modelContext)
    summaries = SnapshotSummaryService.makeSummaries(
      for: allSnapshots,
      displayCurrency: settingsService.mainCurrency)
    conversionStatus = CurrencyConversionStatus.merged(
      summaries.map(\.conversionStatus))

    loadAssets(allSnapshots: allSnapshots)
    loadHistory()
  }

  // MARK: - Save (Rename)

  /// Validates the edited name and renames the platform by updating all matching Asset records.
  ///
  /// - Throws: `PlatformError.emptyName` if name is blank after trimming,
  ///   `PlatformError.duplicateName` if name conflicts with another existing platform.
  func save() throws {
    let trimmed = editedName.collapsingWhitespace

    guard !trimmed.isEmpty else { throw PlatformError.emptyName }

    let allAssets = fetchAllAssets()

    // Check for duplicate (case-insensitive), allowing self-rename with different casing
    let normalizedNew = trimmed.lowercased()
    let normalizedOld = platformName.lowercased()

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
    for asset in allAssets where asset.platform == platformName {
      asset.platform = trimmed
    }

    platformName = trimmed
    editedName = trimmed
  }

  // MARK: - Private Helpers

  private func fetchAllAssets() -> [Asset] {
    let descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)])
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  /// Loads assets on this platform with their latest values.
  private func loadAssets(allSnapshots: [Snapshot]) {
    // Build latest value lookup from most recent snapshot
    var latestValueLookup: [UUID: Decimal] = [:]
    if let latestSnapshot = allSnapshots.last {
      for sav in latestSnapshot.assetValues ?? [] {
        guard let asset = sav.asset, asset.platform == platformName else { continue }
        latestValueLookup[asset.id] = sav.marketValue
      }
    }

    // Collect all assets that belong to this platform
    let platformAssets = fetchAllAssets().filter { $0.platform == platformName }

    let displayCurrency = settingsService.mainCurrency
    let latestExchangeRate = allSnapshots.last?.exchangeRate
    let latestSnapshotDate = allSnapshots.last?.date

    assets =
      platformAssets.map { asset in
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
    totalValue =
      conversionStatus.isComplete
      ? assets.reduce(Decimal(0)) { sum, row in
        sum + (row.convertedValue ?? row.latestValue ?? 0)
      }
      : 0
  }

  /// Computes value history across all snapshots for this platform.
  private func loadHistory() {
    var entries: [PlatformValueHistoryEntry] = []

    for summary in summaries {
      entries.append(
        PlatformValueHistoryEntry(
          date: summary.date,
          totalValue: summary.platformValues[platformName] ?? 0))
    }

    valueHistory = entries
  }
}
