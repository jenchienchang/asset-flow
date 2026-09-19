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

@Suite("Model Resolution Lookup Tests")
@MainActor
struct ModelResolutionLookupTests {

  @Test("Asset lookup preserves normalized first-match behavior")
  func assetLookupPreservesNormalizedFirstMatch() {
    let container = TestDataManager.createInMemoryContainer()
    let first = Asset(name: "AAPL", platform: "Interactive Brokers")
    let second = Asset(name: " aapl ", platform: "interactive  brokers")
    var lookup = AssetResolutionLookup(assets: [first, second])

    #expect(lookup.asset(named: "  AAPL  ", platform: "INTERACTIVE BROKERS") === first)

    let resolved = lookup.resolve(
      name: "AAPL", platform: "Interactive Brokers", in: container.mainContext)
    #expect(resolved === first)
  }

  @Test("Asset lookup indexes newly created assets for later rows")
  func assetLookupIndexesNewAssets() {
    let container = TestDataManager.createInMemoryContainer()
    var lookup = AssetResolutionLookup(assets: [])

    let first = lookup.resolve(name: "New Fund", platform: "Fidelity", in: container.mainContext)
    let second = lookup.resolve(
      name: " new  fund ", platform: "fidelity", in: container.mainContext)

    #expect(first === second)
  }

  @Test("Category lookup reuses normalized names and assigns the next display order")
  func categoryLookupReusesAndOrdersCategories() {
    let container = TestDataManager.createInMemoryContainer()
    let existing = Category(name: "Equities")
    existing.displayOrder = 4
    container.mainContext.insert(existing)
    var lookup = CategoryResolutionLookup(categories: [existing])

    #expect(lookup.category(named: "EQUITIES") === existing)
    let reused = lookup.resolve(name: " equities ", in: container.mainContext)
    let created = lookup.resolve(name: "Crypto", in: container.mainContext)
    let reusedAgain = lookup.resolve(name: "CRYPTO", in: container.mainContext)

    #expect(reused === existing)
    #expect(created?.displayOrder == 5)
    #expect(reusedAgain === created)
  }

  @Test("Snapshot value lookup preserves identity and indexes inserted values")
  func snapshotValueLookupPreservesIdentity() {
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    let existing = SnapshotAssetValue(marketValue: 0)
    existing.asset = asset
    var lookup = SnapshotAssetValueLookup(values: [existing])

    #expect(lookup.value(forAssetNamed: " aapl ", platform: "interactive brokers") === existing)
    #expect(lookup.value(for: asset) === existing)

    let otherAsset = Asset(name: "VTI", platform: "Schwab")
    let inserted = SnapshotAssetValue(marketValue: 100)
    inserted.asset = otherAsset
    lookup.register(inserted)

    #expect(lookup.value(for: otherAsset) === inserted)
  }

  @Test("Cash flow lookup is case-insensitive and trims surrounding whitespace")
  func cashFlowLookupNormalizesDescriptions() {
    let operation = CashFlowOperation(cashFlowDescription: " Salary deposit ", amount: 100)
    let lookup = CashFlowDescriptionLookup(operations: [operation])

    #expect(lookup.contains("salary deposit"))
    #expect(lookup.contains("  SALARY DEPOSIT  "))
    #expect(lookup.contains("Bonus") == false)
  }
}
