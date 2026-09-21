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

@Suite("CategoryDetailViewModel Currency Tests")
@MainActor
struct CategoryDetailViewModelCurrencyTests {

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
  }

  private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    return TestContext(container: container, context: context)
  }

  private func makeExchangeRate(
    base: String = "usd",
    rates: [String: Decimal]
  ) throws -> ExchangeRate {
    let ratesJSON = try JSONEncoder().encode(rates)
    return ExchangeRate(baseCurrency: base, ratesJSON: ratesJSON, fetchDate: Date())
  }

  @Test("Category value history converts to display currency")
  func testCategoryValueHistoryConvertsToDisplayCurrency() throws {
    let tc = createTestContext()

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let category = Category(name: "Stocks")
    tc.context.insert(category)

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    assetTWD.category = category
    tc.context.insert(assetTWD)

    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    // 31500 TWD → 1000 USD at rate 31.5
    let sav = SnapshotAssetValue(marketValue: Decimal(31500))
    sav.snapshot = snapshot
    sav.asset = assetTWD
    tc.context.insert(sav)

    let er = try makeExchangeRate(rates: ["twd": 31.5])
    er.snapshot = snapshot
    tc.context.insert(er)

    let vm = CategoryDetailViewModel(
      category: category, modelContext: tc.context, settingsService: settings)
    vm.loadData()

    #expect(vm.valueHistory.count == 1)
    // Category value should be 31500/31.5 = 1000 USD
    #expect(vm.valueHistory[0].totalValue == Decimal(1000))
  }

  @Test("Category allocation uses converted values")
  func testCategoryAllocationUsesConvertedValues() throws {
    let tc = createTestContext()

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let category = Category(name: "Stocks")
    tc.context.insert(category)

    let assetUSD = Asset(name: "US Stock")
    assetUSD.currency = "usd"
    tc.context.insert(assetUSD)

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    assetTWD.category = category
    tc.context.insert(assetTWD)

    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let sav1 = SnapshotAssetValue(marketValue: Decimal(1000))
    sav1.snapshot = snapshot
    sav1.asset = assetUSD
    tc.context.insert(sav1)

    // 31500 TWD → 1000 USD at rate 31.5
    let sav2 = SnapshotAssetValue(marketValue: Decimal(31500))
    sav2.snapshot = snapshot
    sav2.asset = assetTWD
    tc.context.insert(sav2)

    let er = try makeExchangeRate(rates: ["twd": 31.5])
    er.snapshot = snapshot
    tc.context.insert(er)

    let vm = CategoryDetailViewModel(
      category: category, modelContext: tc.context, settingsService: settings)
    vm.loadData()

    // Total = 1000 + 1000 = 2000 USD, category = 1000 USD → 50%
    #expect(vm.allocationHistory.count == 1)
    #expect(vm.allocationHistory[0].allocationPercentage == Decimal(50))
  }
}
