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

// MARK: - Restore Helpers

extension BackupService {

  static func deleteAllData(modelContext: ModelContext) throws {
    // Fetch and delete individually (batch delete not supported with .deny rules)
    let exchangeRates = try modelContext.fetch(FetchDescriptor<ExchangeRate>())
    for item in exchangeRates { modelContext.delete(item) }

    let cashFlows = try modelContext.fetch(FetchDescriptor<CashFlowOperation>())
    for item in cashFlows { modelContext.delete(item) }

    let savs = try modelContext.fetch(FetchDescriptor<SnapshotAssetValue>())
    for item in savs { modelContext.delete(item) }

    let snapshots = try modelContext.fetch(FetchDescriptor<Snapshot>())
    for item in snapshots { modelContext.delete(item) }

    let assets = try modelContext.fetch(FetchDescriptor<Asset>())
    for item in assets { modelContext.delete(item) }

    let categories = try modelContext.fetch(FetchDescriptor<Category>())
    for item in categories { modelContext.delete(item) }
  }

  static func restoreCategories(
    _ records: [BackupCategoryRecord],
    modelContext: ModelContext
  ) -> [UUID: Category] {
    var idMap: [UUID: Category] = [:]
    for record in records {
      let category = Category(
        name: record.name,
        targetAllocationPercentage: record.targetAllocationPercentage)
      category.id = record.id
      category.displayOrder = record.displayOrder
      modelContext.insert(category)
      idMap[record.id] = category
    }
    return idMap
  }

  static func restoreAssets(
    _ records: [BackupAssetRecord],
    modelContext: ModelContext,
    categoryIDMap: [UUID: Category]
  ) throws -> [UUID: Asset] {
    var idMap: [UUID: Asset] = [:]
    for record in records {
      let asset = Asset(name: record.name, platform: record.platform)
      asset.id = record.id
      asset.currency = record.currency
      if let categoryID = record.categoryID {
        guard let category = categoryIDMap[categoryID] else {
          throw BackupError.restoreFailed(
            localizedBackupMessage(
              "Validated category ID was not available during insertion."))
        }
        asset.category = category
      }
      modelContext.insert(asset)
      idMap[record.id] = asset
    }
    return idMap
  }

  static func restoreSnapshots(
    _ records: [BackupSnapshotRecord],
    modelContext: ModelContext
  ) -> [UUID: Snapshot] {
    var idMap: [UUID: Snapshot] = [:]
    for record in records {
      let snapshot = Snapshot(date: record.date)
      snapshot.id = record.id
      snapshot.createdAt = record.createdAt
      modelContext.insert(snapshot)
      idMap[record.id] = snapshot
    }
    return idMap
  }

  static func restoreSnapshotAssetValues(
    _ records: [BackupSnapshotAssetValueRecord],
    modelContext: ModelContext,
    snapshotIDMap: [UUID: Snapshot],
    assetIDMap: [UUID: Asset]
  ) throws {
    for record in records {
      guard let snapshot = snapshotIDMap[record.snapshotID] else {
        throw BackupError.restoreFailed(
          localizedBackupMessage(
            "Validated snapshot ID was not available during value insertion."))
      }
      guard let asset = assetIDMap[record.assetID] else {
        throw BackupError.restoreFailed(
          localizedBackupMessage(
            "Validated asset ID was not available during value insertion."))
      }
      let value = SnapshotAssetValue(marketValue: record.marketValue)
      value.snapshot = snapshot
      value.asset = asset
      modelContext.insert(value)
    }
  }

  static func restoreCashFlowOperations(
    _ records: [BackupCashFlowRecord],
    modelContext: ModelContext,
    snapshotIDMap: [UUID: Snapshot]
  ) throws {
    for record in records {
      guard let snapshot = snapshotIDMap[record.snapshotID] else {
        throw BackupError.restoreFailed(
          localizedBackupMessage(
            "Validated snapshot ID was not available during cash-flow insertion."
          ))
      }
      let operation = CashFlowOperation(
        cashFlowDescription: record.description,
        amount: record.amount)
      operation.id = record.id
      operation.currency = record.currency
      operation.snapshot = snapshot
      modelContext.insert(operation)
    }
  }

  static func restoreExchangeRates(
    _ records: [BackupExchangeRateRecord],
    modelContext: ModelContext,
    snapshotIDMap: [UUID: Snapshot]
  ) throws {
    for record in records {
      guard let snapshot = snapshotIDMap[record.snapshotID] else {
        throw BackupError.restoreFailed(
          localizedBackupMessage(
            "Validated snapshot ID was not available during exchange-rate insertion."
          ))
      }
      let exchangeRate = ExchangeRate(
        baseCurrency: record.baseCurrency,
        ratesJSON: record.ratesJSON,
        fetchDate: record.fetchDate,
        isFallback: record.isFallback)
      exchangeRate.snapshot = snapshot
      modelContext.insert(exchangeRate)
    }
  }

  static func restoreSettings(
    _ record: BackupSettingsRecord,
    settingsService: SettingsService
  ) {
    settingsService.mainCurrency = record.mainCurrency
    settingsService.dateFormat = record.dateFormat
    settingsService.defaultPlatform = record.defaultPlatform
  }
}
