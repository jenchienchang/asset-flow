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

/// Value projection used by `.onChange` when a view's cached state depends on
/// several SwiftData queries. It compares model fields as well as membership,
/// since the query arrays can contain the same model instances after an edit.
struct ModelQueryRevision: Equatable {
  private struct SnapshotRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let id: UUID
    let date: Date
    let createdAt: Date
  }

  private struct AssetRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let id: UUID
    let name: String
    let platform: String
    let currency: String
    let categoryID: UUID?
  }

  private struct CategoryRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let id: UUID
    let name: String
    let targetAllocationPercentage: Decimal?
    let displayOrder: Int
  }

  private struct SnapshotAssetValueRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let snapshotID: UUID?
    let assetID: UUID?
    let marketValue: Decimal
  }

  private struct CashFlowOperationRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let id: UUID
    let snapshotID: UUID?
    let cashFlowDescription: String
    let amount: Decimal
    let currency: String
  }

  private struct ExchangeRateRevision: Equatable {
    let persistenceID: PersistentIdentifier
    let snapshotID: UUID?
    let baseCurrency: String
    let ratesJSON: Data
    let fetchDate: Date
    let isFallback: Bool
  }

  private let snapshots: [SnapshotRevision]
  private let assets: [AssetRevision]
  private let categories: [CategoryRevision]
  private let snapshotAssetValues: [SnapshotAssetValueRevision]
  private let cashFlowOperations: [CashFlowOperationRevision]
  private let exchangeRates: [ExchangeRateRevision]

  init(
    snapshots: [Snapshot] = [],
    assets: [Asset] = [],
    categories: [Category] = [],
    snapshotAssetValues: [SnapshotAssetValue] = [],
    cashFlowOperations: [CashFlowOperation] = [],
    exchangeRates: [ExchangeRate] = []
  ) {
    self.snapshots = snapshots.map {
      SnapshotRevision(
        persistenceID: $0.persistentModelID,
        id: $0.id,
        date: $0.date,
        createdAt: $0.createdAt)
    }
    self.assets = assets.map {
      AssetRevision(
        persistenceID: $0.persistentModelID,
        id: $0.id,
        name: $0.name,
        platform: $0.platform,
        currency: $0.currency,
        categoryID: $0.category?.id)
    }
    self.categories = categories.map {
      CategoryRevision(
        persistenceID: $0.persistentModelID,
        id: $0.id,
        name: $0.name,
        targetAllocationPercentage: $0.targetAllocationPercentage,
        displayOrder: $0.displayOrder)
    }
    self.snapshotAssetValues = snapshotAssetValues.map {
      SnapshotAssetValueRevision(
        persistenceID: $0.persistentModelID,
        snapshotID: $0.snapshot?.id,
        assetID: $0.asset?.id,
        marketValue: $0.marketValue)
    }
    self.cashFlowOperations = cashFlowOperations.map {
      CashFlowOperationRevision(
        persistenceID: $0.persistentModelID,
        id: $0.id,
        snapshotID: $0.snapshot?.id,
        cashFlowDescription: $0.cashFlowDescription,
        amount: $0.amount,
        currency: $0.currency)
    }
    self.exchangeRates = exchangeRates.map {
      ExchangeRateRevision(
        persistenceID: $0.persistentModelID,
        snapshotID: $0.snapshot?.id,
        baseCurrency: $0.baseCurrency,
        ratesJSON: $0.ratesJSON,
        fetchDate: $0.fetchDate,
        isFallback: $0.isFallback)
    }
  }
}
