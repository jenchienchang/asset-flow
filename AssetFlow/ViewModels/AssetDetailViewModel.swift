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

/// Value history entry for an asset's recorded market value at a snapshot date.
struct AssetValueHistoryEntry: Identifiable {
  let id: PersistentIdentifier
  let date: Date
  let marketValue: Decimal
  let convertedMarketValue: Decimal?
  let snapshotAssetValue: SnapshotAssetValue
}

/// ViewModel for the Asset detail/edit screen.
///
/// Manages editing asset properties (name, platform, category),
/// loading value history from snapshots, and deletion with validation.
@Observable
@MainActor
final class AssetDetailViewModel {
  let asset: Asset
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching

  var editedName: String
  var editedPlatform: String
  var editedCategory: Category?
  var editedCurrency: String
  var valueHistory: [AssetValueHistoryEntry] = []

  /// Whether the asset uses a currency different from the global display currency.
  ///
  /// Stored (not computed) so it updates in the async `loadValueHistory()` cycle,
  /// preventing synchronous view structural changes during picker callbacks
  /// that would crash SwiftUI's AttributeGraph.
  private(set) var isDifferentCurrency = false

  init(asset: Asset, modelContext: ModelContext, fetcher: (any ModelFetching)? = nil) {
    self.asset = asset
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.editedName = asset.name
    self.editedPlatform = asset.platform
    self.editedCategory = asset.category
    self.editedCurrency =
      asset.currency.isEmpty ? SettingsService.shared.mainCurrency : asset.currency
    let effectiveCurrency =
      asset.currency.isEmpty ? SettingsService.shared.mainCurrency : asset.currency
    self.isDifferentCurrency =
      effectiveCurrency.lowercased() != SettingsService.shared.mainCurrency.lowercased()
  }

  // MARK: - Computed Properties

  /// Whether the asset can be deleted (has no snapshot values).
  var canDelete: Bool {
    (asset.snapshotAssetValues?.count ?? 0) == 0
  }

  /// Explanatory text for why the asset cannot be deleted, or nil if deletion is allowed.
  var deleteExplanation: String? {
    guard !canDelete else { return nil }
    return AssetError.cannotDelete(snapshotCount: snapshotCount).errorDescription
  }

  /// Number of distinct snapshots this asset appears in.
  var snapshotCount: Int {
    let savs = asset.snapshotAssetValues ?? []
    let snapshotIDs = Set(savs.compactMap { $0.snapshot?.id })
    return snapshotIDs.count
  }

  // MARK: - Value History

  /// Loads the value history from directly recorded snapshot asset values (no carry-forward).
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadValueHistory() {
    withObservationTracking {
      performLoadValueHistory()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadValueHistory()
      }
    }
  }

  private func performLoadValueHistory() {
    let savs = asset.snapshotAssetValues ?? []
    let displayCurrency = SettingsService.shared.mainCurrency
    let assetCurrency = asset.currency.isEmpty ? displayCurrency : asset.currency
    let needsConversion = assetCurrency.lowercased() != displayCurrency.lowercased()
    isDifferentCurrency = needsConversion

    valueHistory = savs.compactMap { sav in
      guard let snapshotDate = sav.snapshot?.date else { return nil }
      let converted: Decimal?
      if needsConversion,
        CurrencyConversionService.canConvert(
          from: assetCurrency,
          to: displayCurrency,
          using: sav.snapshot?.exchangeRate,
          forSnapshotDate: snapshotDate
        )
      {
        converted = CurrencyConversionService.convert(
          value: sav.marketValue,
          from: assetCurrency,
          to: displayCurrency,
          using: sav.snapshot?.exchangeRate,
          forSnapshotDate: snapshotDate
        )
      } else if needsConversion {
        converted = nil
      } else {
        converted = nil
      }
      return AssetValueHistoryEntry(
        id: sav.persistentModelID,
        date: snapshotDate,
        marketValue: sav.marketValue,
        convertedMarketValue: converted,
        snapshotAssetValue: sav
      )
    }
    .sorted { $0.date < $1.date }
  }

  // MARK: - Edit Asset Value

  /// Updates the market value of a snapshot asset value and refreshes the value history.
  func editAssetValue(_ sav: SnapshotAssetValue, newValue: Decimal) {
    sav.marketValue = newValue
    loadValueHistory()
  }

  // MARK: - Queries

  /// Returns all distinct, non-empty platforms from existing assets.
  func existingPlatforms() throws -> [String] {
    let descriptor = FetchDescriptor<Asset>()
    let allAssets = try fetchModels(
      descriptor,
      from: fetcher,
      operation: "load existing platforms")
    let platforms = Set(allAssets.map(\.platform).filter { !$0.isEmpty })
    return platforms.sorted()
  }

  /// Returns all existing categories sorted by display order, then by name.
  func existingCategories() throws -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return try fetchModels(
      descriptor,
      from: fetcher,
      operation: "load existing categories")
  }

  /// Resolves a category by name, reusing existing (case-insensitive) or creating new.
  func resolveCategory(name: String) throws -> Category? {
    try modelContext.resolveCategory(name: name, fetcher: fetcher)
  }

  // MARK: - Save

  /// Validates and saves edited properties to the asset model.
  ///
  /// - Throws: `AssetError.duplicateIdentity` if the new (name, platform) conflicts
  ///   with another existing asset.
  func save() throws {
    let newNormalizedName = editedName.normalizedForIdentity
    let newNormalizedPlatform = editedPlatform.normalizedForIdentity

    // Check for conflicts with other assets (exclude self)
    let descriptor = FetchDescriptor<Asset>()
    let allAssets = try fetchModels(
      descriptor,
      from: fetcher,
      operation: "validate asset")

    let hasConflict = allAssets.contains { other in
      other.id != asset.id
        && other.normalizedName == newNormalizedName
        && other.normalizedPlatform == newNormalizedPlatform
    }

    if hasConflict {
      throw AssetError.duplicateIdentity(name: editedName, platform: editedPlatform)
    }

    // Apply changes to the asset model (retroactive update)
    asset.name = editedName
    asset.platform = editedPlatform
    asset.category = editedCategory
    asset.currency = editedCurrency
  }

  // MARK: - Delete

  /// Deletes the asset from the model context.
  /// Only call when `canDelete` is true.
  func deleteAsset() {
    modelContext.delete(asset)
  }
}
