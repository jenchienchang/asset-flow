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
import Testing

@testable import AssetFlow

@Suite("Model Query Revision Tests")
@MainActor
struct ModelQueryRevisionTests {

  @Test("Revision changes when each queried model's data changes")
  func revisionTracksModelPropertyChanges() {
    let container = TestDataManager.createInMemoryContainer()
    let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_000))
    let asset = Asset(name: "Fund", platform: "Broker")
    let category = Category(name: "Equities")
    let snapshotAssetValue = SnapshotAssetValue(marketValue: 100)
    let cashFlow = CashFlowOperation(cashFlowDescription: "Dividend", amount: 5)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd", ratesJSON: Data("{}".utf8),
      fetchDate: Date(timeIntervalSince1970: 1_000))
    snapshotAssetValue.snapshot = snapshot
    snapshotAssetValue.asset = asset
    cashFlow.snapshot = snapshot
    exchangeRate.snapshot = snapshot
    container.mainContext.insert(snapshot)
    container.mainContext.insert(asset)
    container.mainContext.insert(category)
    container.mainContext.insert(snapshotAssetValue)
    container.mainContext.insert(cashFlow)
    container.mainContext.insert(exchangeRate)

    let originalSnapshot = ModelQueryRevision(snapshots: [snapshot])
    snapshot.date = Date(timeIntervalSince1970: 1_001)
    #expect(ModelQueryRevision(snapshots: [snapshot]) != originalSnapshot)

    let originalAsset = ModelQueryRevision(assets: [asset])
    asset.platform = "Changed Broker"
    #expect(ModelQueryRevision(assets: [asset]) != originalAsset)

    let originalCategory = ModelQueryRevision(categories: [category])
    category.name = "Fixed Income"
    #expect(ModelQueryRevision(categories: [category]) != originalCategory)

    let originalValue = ModelQueryRevision(snapshotAssetValues: [snapshotAssetValue])
    snapshotAssetValue.marketValue = 125
    #expect(
      ModelQueryRevision(snapshotAssetValues: [snapshotAssetValue]) != originalValue)

    let originalCashFlow = ModelQueryRevision(cashFlowOperations: [cashFlow])
    cashFlow.amount = 8
    #expect(ModelQueryRevision(cashFlowOperations: [cashFlow]) != originalCashFlow)

    let originalRate = ModelQueryRevision(exchangeRates: [exchangeRate])
    exchangeRate.ratesJSON = Data("{\"eur\": 0.9}".utf8)
    #expect(ModelQueryRevision(exchangeRates: [exchangeRate]) != originalRate)
  }

  @Test("Revision changes when a query's membership changes")
  func revisionTracksMembershipChanges() {
    let first = Snapshot(date: Date(timeIntervalSince1970: 1_000))
    let second = Snapshot(date: Date(timeIntervalSince1970: 2_000))
    let asset = Asset(name: "Fund", platform: "Broker")

    let original = ModelQueryRevision(snapshots: [first], assets: [asset])
    let changed = ModelQueryRevision(snapshots: [first, second], assets: [asset])

    #expect(changed != original)
  }
}
