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

/// Error types for snapshot operations.
enum SnapshotError: LocalizedError, Equatable {
  case futureDateNotAllowed
  case dateAlreadyExists(Date)
  case assetAlreadyInSnapshot(String)
  case duplicateCashFlowDescription(String)
  case duplicateAssetName(String, String)
  case noAssetsIncluded

  var errorDescription: String? {
    switch self {
    case .futureDateNotAllowed:
      return String(
        localized: "Snapshot date cannot be in the future.", table: "Snapshot")

    case .dateAlreadyExists(let date):
      let formatted = MainActor.assumeIsolated { date.settingsFormatted() }
      return String(
        localized:
          "A snapshot already exists for \(formatted). Go to the Snapshots screen to view and edit it.",
        table: "Snapshot")

    case .assetAlreadyInSnapshot(let name):
      return String(
        localized:
          "'\(name)' already exists in this snapshot. Edit its value instead.",
        table: "Snapshot")

    case .duplicateCashFlowDescription(let description):
      return String(
        localized:
          "A cash flow operation with description '\(description)' already exists in this snapshot.",
        table: "Snapshot")

    case .duplicateAssetName(let name, let platform):
      return String(
        localized:
          "Duplicate asset name '\(name)' found in platform '\(platform)'. Each asset name must be unique within a platform.",
        table: "Snapshot")

    case .noAssetsIncluded:
      return String(
        localized: "At least one asset must be included in the snapshot.",
        table: "Snapshot")
    }
  }
}

/// Relative time bucket for grouping snapshots in the list.
///
/// Boundaries are based on calendar month starts relative to the reference date.
/// Empty buckets are hidden at the view layer.
enum SnapshotTimeBucket: Int, CaseIterable, Hashable {
  case thisMonth
  case past3Months
  case past6Months
  case pastYear
  case older

  var localizedName: String {
    switch self {
    case .thisMonth: return String(localized: "This Month", table: "Snapshot")
    case .past3Months: return String(localized: "Previous 3 Months", table: "Snapshot")
    case .past6Months: return String(localized: "Previous 6 Months", table: "Snapshot")
    case .pastYear: return String(localized: "Previous Year", table: "Snapshot")
    case .older: return String(localized: "Older", table: "Snapshot")
    }
  }

  static func bucket(for date: Date, relativeTo now: Date = Date()) -> SnapshotTimeBucket {
    let calendar = Calendar.current
    guard
      let startOfCurrentMonth = calendar.date(
        from: calendar.dateComponents([.year, .month], from: now)),
      let threeMonthsAgo = calendar.date(
        byAdding: .month, value: -3, to: startOfCurrentMonth),
      let sixMonthsAgo = calendar.date(
        byAdding: .month, value: -6, to: startOfCurrentMonth),
      let oneYearAgo = calendar.date(
        byAdding: .year, value: -1, to: startOfCurrentMonth)
    else { return .older }

    if date >= startOfCurrentMonth { return .thisMonth }
    if date >= threeMonthsAgo { return .past3Months }
    if date >= sixMonthsAgo { return .past6Months }
    if date >= oneYearAgo { return .pastYear }

    return .older
  }
}

/// Data for a snapshot list row.
struct SnapshotRowData {
  let date: Date
  let totalValue: Decimal
  let platforms: [String]
  let assetCount: Int
  let hasZeroValueAssets: Bool
}

/// Data for snapshot deletion confirmation dialog.
struct SnapshotConfirmationData {
  let date: Date
  let assetCount: Int
  let cashFlowCount: Int
}

/// ViewModel for the Snapshots list screen.
///
/// Manages snapshot creation (empty or copy-from-latest), deletion,
/// and row data computation.
@Observable
@MainActor
class SnapshotListViewModel {
  private let modelContext: ModelContext
  private let settingsService: SettingsService

  /// Pre-computed row data for all snapshots, keyed by snapshot ID.
  var rowDataMap: [UUID: SnapshotRowData] = [:]

  init(modelContext: ModelContext, settingsService: SettingsService? = nil) {
    self.modelContext = modelContext
    self.settingsService = settingsService ?? .shared
  }

  // MARK: - Row Data Loading

  /// Loads row data for all snapshots with observation tracking.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change (e.g. currency, asset values) automatically triggers a reload.
  func loadRowData(snapshots: [Snapshot]? = nil) {
    withObservationTracking {
      performLoadRowData(snapshots: snapshots)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        // Re-fetch the current collection instead of capturing SwiftData models
        // in the sendable task closure.
        self?.loadRowData()
      }
    }
  }

  private func performLoadRowData(snapshots: [Snapshot]?) {
    rowDataMap = loadAllSnapshotRowData(snapshots: snapshots)
  }

  // MARK: - Creation

  /// Creates a new snapshot at the given date.
  ///
  /// - Parameters:
  ///   - date: The snapshot date (must be today or earlier, must not already exist).
  ///   - copyFromLatest: If true, copies all direct asset values from the most
  ///     recent prior snapshot as new records.
  /// - Returns: The newly created Snapshot.
  /// - Throws: `SnapshotError.futureDateNotAllowed` or `SnapshotError.dateAlreadyExists`.
  @discardableResult
  func createSnapshot(date: Date, copyFromLatest: Bool) throws -> Snapshot {
    let normalizedDate = Calendar.current.startOfDay(for: date)
    let today = Calendar.current.startOfDay(for: Date())

    guard normalizedDate <= today else {
      throw SnapshotError.futureDateNotAllowed
    }

    // Check for existing snapshot on this date
    var dateCheckDescriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == normalizedDate }
    )
    dateCheckDescriptor.fetchLimit = 1
    if try modelContext.fetch(dateCheckDescriptor).first != nil {
      throw SnapshotError.dateAlreadyExists(normalizedDate)
    }

    let snapshot = Snapshot(date: normalizedDate)
    modelContext.insert(snapshot)

    if copyFromLatest {
      copyValuesFromLatest(to: snapshot)
    }

    return snapshot
  }

  /// Whether "Copy from latest" is available for the given date.
  ///
  /// Returns true if at least one snapshot exists with a date before the selected date.
  func canCopyFromLatest(for date: Date) -> Bool {
    let normalizedDate = Calendar.current.startOfDay(for: date)
    var descriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date < normalizedDate }
    )
    descriptor.fetchLimit = 1
    return ((try? modelContext.fetch(descriptor)) ?? []).first != nil
  }

  // MARK: - Deletion

  /// Deletes a snapshot and its cascaded relationships (asset values, cash flows).
  func deleteSnapshot(_ snapshot: Snapshot) {
    modelContext.delete(snapshot)
  }

  /// Returns confirmation data for the deletion dialog.
  func confirmationData(for snapshot: Snapshot) -> SnapshotConfirmationData {
    SnapshotConfirmationData(
      date: snapshot.date,
      assetCount: snapshot.assetValues?.count ?? 0,
      cashFlowCount: snapshot.cashFlowOperations?.count ?? 0
    )
  }

  // MARK: - Row Data

  /// Computes row data for all snapshots in a single batch.
  func loadAllSnapshotRowData(snapshots: [Snapshot]? = nil) -> [UUID: SnapshotRowData] {
    let allSnapshots = snapshots ?? fetchAllSnapshots()

    var result: [UUID: SnapshotRowData] = [:]
    for snapshot in allSnapshots {
      result[snapshot.id] = buildRowData(for: snapshot)
    }
    return result
  }

  /// Computes row data for a single snapshot.
  func snapshotRowData(for snapshot: Snapshot) -> SnapshotRowData {
    buildRowData(for: snapshot)
  }

  private func buildRowData(for snapshot: Snapshot) -> SnapshotRowData {
    let directValues = snapshot.assetValues ?? []

    let displayCurrency = settingsService.mainCurrency
    let totalValue = CurrencyConversionService.totalValue(
      for: snapshot, displayCurrency: displayCurrency,
      exchangeRate: snapshot.exchangeRate)

    let platforms = Array(
      Set(directValues.compactMap { $0.asset?.platform })
    ).sorted()

    let hasZeroValueAssets = directValues.contains { $0.marketValue == 0 }

    return SnapshotRowData(
      date: snapshot.date,
      totalValue: totalValue,
      platforms: platforms,
      assetCount: directValues.count,
      hasZeroValueAssets: hasZeroValueAssets
    )
  }

  // MARK: - Private Helpers

  private func fetchAllSnapshots() -> [Snapshot] {
    SnapshotSummaryService.fetchSnapshots(modelContext: modelContext)
  }

  /// Copies all direct asset values from the most recent prior snapshot to the new snapshot.
  private func copyValuesFromLatest(to snapshot: Snapshot) {
    // Find the most recent snapshot before the new snapshot's date
    let snapshotDate = snapshot.date
    var priorDescriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date < snapshotDate },
      sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    priorDescriptor.fetchLimit = 1

    guard let latestPrior = (try? modelContext.fetch(priorDescriptor))?.first else { return }

    let latestValues = latestPrior.assetValues ?? []

    for priorSAV in latestValues {
      guard let asset = priorSAV.asset else { continue }
      let sav = SnapshotAssetValue(marketValue: priorSAV.marketValue)
      sav.snapshot = snapshot
      sav.asset = asset
      modelContext.insert(sav)
    }
  }
}
