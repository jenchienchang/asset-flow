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

@Suite("PlatformDetailViewModel Currency Tests")
@MainActor
struct PlatformDetailViewModelCurrencyTests {

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

  @Test("Platform total value converts to display currency")
  func testPlatformTotalValueConvertsToDisplayCurrency() throws {
    let tc = createTestContext()

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let assetUSD = Asset(name: "US Stock")
    assetUSD.currency = "usd"
    assetUSD.platform = "Broker A"
    tc.context.insert(assetUSD)

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    assetTWD.platform = "Broker A"
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

    let vm = PlatformDetailViewModel(
      platformName: "Broker A", modelContext: tc.context, settingsService: settings)
    vm.loadData()

    // 1000 USD + 31500/31.5 USD = 2000 USD
    #expect(vm.totalValue == Decimal(2000))
  }

  @Test("Platform value history converts to display currency")
  func testPlatformValueHistoryConvertsToDisplayCurrency() throws {
    let tc = createTestContext()

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    assetTWD.platform = "Broker A"
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

    let vm = PlatformDetailViewModel(
      platformName: "Broker A", modelContext: tc.context, settingsService: settings)
    vm.loadData()

    #expect(vm.valueHistory.count == 1)
    // 31500 TWD / 31.5 = 1000 USD
    #expect(vm.valueHistory[0].totalValue == Decimal(1000))
  }
}
