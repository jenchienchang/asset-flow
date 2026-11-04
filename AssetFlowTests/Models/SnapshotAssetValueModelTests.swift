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

@Suite("SnapshotAssetValue Model Tests")
@MainActor
struct SnapshotAssetValueModelTests {

  // MARK: - Creation and Properties

  @Test("SnapshotAssetValue initializes with market value")
  func testInitializesWithMarketValue() {
    let value = SnapshotAssetValue(marketValue: Decimal(50000))
    #expect(value.marketValue == Decimal(50000))
    #expect(value.snapshot == nil)
    #expect(value.asset == nil)
  }

  @Test("SnapshotAssetValue persists in SwiftData context")
  func testPersistsInContext() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let value = SnapshotAssetValue(marketValue: Decimal(75000))
    context.insert(value)

    let descriptor = FetchDescriptor<SnapshotAssetValue>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 1)
    #expect(fetched.first?.marketValue == Decimal(75000))
  }

  // MARK: - Decimal Precision

  @Test("Market value preserves Decimal precision")
  func testMarketValuePreservesDecimalPrecision() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let preciseValue = try #require(Decimal(string: "123456.789012345"))
    let value = SnapshotAssetValue(marketValue: preciseValue)
    context.insert(value)

    let descriptor = FetchDescriptor<SnapshotAssetValue>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.first?.marketValue == preciseValue)
  }

  @Test("Market value supports very large amounts")
  func testMarketValueSupportsLargeAmounts() {
    let largeValue = Decimal(string: "999999999999.99")!
    let value = SnapshotAssetValue(marketValue: largeValue)
    #expect(value.marketValue == largeValue)
  }

  @Test("Market value supports very small amounts")
  func testMarketValueSupportsSmallAmounts() throws {
    let smallValue = try #require(Decimal(string: "0.00000001"))
    let value = SnapshotAssetValue(marketValue: smallValue)
    #expect(value.marketValue == smallValue)
  }

  // MARK: - Uniqueness

  @Test("SnapshotAssetValue enforces (snapshot, asset) uniqueness via #Unique — duplicate upserts")
  func testSnapshotAssetValueEnforcesUniqueness() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snapshot = Snapshot(date: Date())
    let asset = Asset(name: "AAPL")
    context.insert(snapshot)
    context.insert(asset)

    let value1 = SnapshotAssetValue(marketValue: Decimal(10000))
    value1.snapshot = snapshot
    value1.asset = asset
    context.insert(value1)

    let value2 = SnapshotAssetValue(marketValue: Decimal(20000))
    value2.snapshot = snapshot
    value2.asset = asset
    context.insert(value2)
    try context.save()

    let descriptor = FetchDescriptor<SnapshotAssetValue>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 1)
  }

  // MARK: - Relationships

  @Test("SnapshotAssetValue links to snapshot and asset")
  func testLinksToSnapshotAndAsset() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snapshot = Snapshot(date: Date())
    let asset = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: context))
    let value = SnapshotAssetValue(marketValue: Decimal(15000))

    context.insert(snapshot)
    context.insert(asset)
    context.insert(value)

    value.snapshot = snapshot
    value.asset = asset

    #expect(value.snapshot === snapshot)
    #expect(value.asset === asset)
    #expect(snapshot.assetValues?.contains(where: { $0.marketValue == Decimal(15000) }) == true)
    #expect(
      asset.snapshotAssetValues?.contains(where: { $0.marketValue == Decimal(15000) }) == true)
  }

  @Test("Multiple asset values in the same snapshot")
  func testMultipleAssetValuesInSameSnapshot() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let snapshot = Snapshot(date: Date())
    let asset1 = Asset(name: "AAPL")
    let asset2 = Asset(name: "GOOGL")

    context.insert(snapshot)
    context.insert(asset1)
    context.insert(asset2)

    let value1 = SnapshotAssetValue(marketValue: Decimal(10000))
    let value2 = SnapshotAssetValue(marketValue: Decimal(20000))

    context.insert(value1)
    context.insert(value2)

    value1.snapshot = snapshot
    value1.asset = asset1
    value2.snapshot = snapshot
    value2.asset = asset2

    #expect(snapshot.assetValues?.count == 2)
  }
}
