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

@Suite("CurrencyConversion Service Tests")
@MainActor
struct CurrencyConversionServiceTests {

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
    rates: [String: Double],
    fetchDate: Date = Date()
  ) throws -> ExchangeRate {
    let ratesJSON = try JSONEncoder().encode(rates)
    return ExchangeRate(baseCurrency: base, ratesJSON: ratesJSON, fetchDate: fetchDate)
  }

  // MARK: - Convert Tests

  @Test("Convert same currency returns original value")
  func testConvertSameCurrency() throws {
    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let result = CurrencyConversionService.convert(
      value: Decimal(100),
      from: "usd",
      to: "usd",
      using: er,
      forSnapshotDate: er.fetchDate
    )
    #expect(result == Decimal(100))
  }

  @Test("Convert with nil exchange rate is unavailable")
  func testConvertWithNilExchangeRate() {
    let result = CurrencyConversionService.convert(
      value: Decimal(100),
      from: "usd",
      to: "twd",
      using: nil,
      forSnapshotDate: Date()
    )
    #expect(result == nil)
  }

  @Test("Incomplete total reports native totals and no converted total")
  func testIncompleteTotalReportsNativeTotals() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let assetUSD = Asset(name: "US Stock")
    assetUSD.currency = "usd"
    tc.context.insert(assetUSD)

    let assetEUR = Asset(name: "EU Stock")
    assetEUR.currency = "eur"
    tc.context.insert(assetEUR)

    let usdValue = SnapshotAssetValue(marketValue: Decimal(1000))
    usdValue.snapshot = snapshot
    usdValue.asset = assetUSD
    tc.context.insert(usdValue)

    let eurValue = SnapshotAssetValue(marketValue: Decimal(850))
    eurValue.snapshot = snapshot
    eurValue.asset = assetEUR
    tc.context.insert(eurValue)

    let report = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: "usd",
      exchangeRate: nil
    )

    #expect(report.convertedTotal == nil)
    #expect(report.nativeTotals["usd"] == Decimal(1000))
    #expect(report.nativeTotals["eur"] == Decimal(850))
    #expect(report.status == .missingRates(["eur"]))
  }

  @Test("Complete total reports one converted display-currency value")
  func testCompleteTotalReportsConvertedValue() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let assetEUR = Asset(name: "EU Stock")
    assetEUR.currency = "eur"
    tc.context.insert(assetEUR)

    let eurValue = SnapshotAssetValue(marketValue: Decimal(850))
    eurValue.snapshot = snapshot
    eurValue.asset = assetEUR
    tc.context.insert(eurValue)

    let ratesJSON = try JSONEncoder().encode(["eur": 0.85])
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: snapshot.date
    )

    let report = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: "usd",
      exchangeRate: exchangeRate
    )

    #expect(report.convertedTotal == Decimal(1000))
    #expect(report.status == .applied)
  }

  @Test("Wrong-date exchange rates are unavailable for historical conversion")
  func testWrongDateExchangeRateIsUnavailable() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let asset = Asset(name: "EU Stock")
    asset.currency = "eur"
    tc.context.insert(asset)

    let value = SnapshotAssetValue(marketValue: Decimal(850))
    value.snapshot = snapshot
    value.asset = asset
    tc.context.insert(value)

    let ratesJSON = try JSONEncoder().encode(["eur": 0.85])
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date(timeIntervalSince1970: 0)
    )

    let report = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: "usd",
      exchangeRate: exchangeRate
    )

    #expect(report.convertedTotal == nil)
    #expect(report.status == .missingRates(["eur"]))
    #expect(
      CurrencyConversionService.convert(
        value: Decimal(850),
        from: "eur",
        to: "usd",
        using: exchangeRate,
        forSnapshotDate: snapshot.date
      ) == nil
    )
    #expect(
      !CurrencyConversionService.canConvert(
        from: "eur",
        to: "usd",
        using: exchangeRate,
        forSnapshotDate: snapshot.date
      )
    )
  }

  @Test("Mismatched exchange-rate base is unavailable")
  func testMismatchedExchangeRateBaseIsUnavailable() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let asset = Asset(name: "EU Stock")
    asset.currency = "eur"
    tc.context.insert(asset)
    let value = SnapshotAssetValue(marketValue: Decimal(850))
    value.snapshot = snapshot
    value.asset = asset
    tc.context.insert(value)

    let exchangeRate = try makeExchangeRate(base: "eur", rates: ["usd": 1.08])
    let report = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: "usd",
      exchangeRate: exchangeRate
    )

    #expect(report.convertedTotal == nil)
    #expect(report.status == .missingRates(["eur"]))
  }

  @Test("Convert base to target currency")
  func testConvertBaseToTarget() throws {
    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let result = CurrencyConversionService.convert(
      value: Decimal(100),
      from: "usd",
      to: "twd",
      using: er,
      forSnapshotDate: er.fetchDate
    )
    #expect(result == Decimal(3150))
  }

  @Test("Convert target to base currency")
  func testConvertTargetToBase() throws {
    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let result = CurrencyConversionService.convert(
      value: Decimal(3150),
      from: "twd",
      to: "usd",
      using: er,
      forSnapshotDate: er.fetchDate
    )
    #expect(result == Decimal(100))
  }

  // MARK: - Total Value Tests

  @Test("Total value with single currency needs no conversion")
  func testTotalValueSingleCurrency() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let asset1 = Asset(name: "Stock A")
    asset1.currency = "usd"
    tc.context.insert(asset1)

    let asset2 = Asset(name: "Stock B")
    asset2.currency = "usd"
    tc.context.insert(asset2)

    let sav1 = SnapshotAssetValue(marketValue: Decimal(1000))
    sav1.snapshot = snapshot
    sav1.asset = asset1
    tc.context.insert(sav1)

    let sav2 = SnapshotAssetValue(marketValue: Decimal(2000))
    sav2.snapshot = snapshot
    sav2.asset = asset2
    tc.context.insert(sav2)

    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let total = CurrencyConversionService.totalValue(
      for: snapshot, displayCurrency: "usd", exchangeRate: er)

    #expect(total == Decimal(3000))
  }

  @Test("Total value with multiple currencies converts correctly")
  func testTotalValueMultiCurrency() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let assetUSD = Asset(name: "US Stock")
    assetUSD.currency = "usd"
    tc.context.insert(assetUSD)

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    tc.context.insert(assetTWD)

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
    let total = CurrencyConversionService.totalValue(
      for: snapshot, displayCurrency: "usd", exchangeRate: er)

    // 1000 USD + 31500/31.5 USD = 1000 + 1000 = 2000
    #expect(total == Decimal(2000))
  }

  // MARK: - Net Cash Flow Tests

  @Test("Net cash flow with different currencies")
  func testNetCashFlowConversion() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let cf1 = CashFlowOperation(cashFlowDescription: "USD Deposit", amount: Decimal(1000))
    cf1.currency = "usd"
    cf1.snapshot = snapshot
    tc.context.insert(cf1)

    let cf2 = CashFlowOperation(cashFlowDescription: "TWD Deposit", amount: Decimal(31500))
    cf2.currency = "twd"
    cf2.snapshot = snapshot
    tc.context.insert(cf2)

    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let netCF = CurrencyConversionService.netCashFlow(
      for: snapshot, displayCurrency: "usd", exchangeRate: er)

    // 1000 USD + 31500/31.5 USD = 2000
    #expect(netCF == Decimal(2000))
  }

  // MARK: - Category Values Tests

  @Test("Category values grouping with conversion")
  func testCategoryValuesGrouping() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let category = Category(name: "Stocks")
    tc.context.insert(category)

    let assetUSD = Asset(name: "US Stock")
    assetUSD.currency = "usd"
    assetUSD.category = category
    tc.context.insert(assetUSD)

    let assetTWD = Asset(name: "TW Stock")
    assetTWD.currency = "twd"
    assetTWD.category = category
    tc.context.insert(assetTWD)

    let sav1 = SnapshotAssetValue(marketValue: Decimal(1000))
    sav1.snapshot = snapshot
    sav1.asset = assetUSD
    tc.context.insert(sav1)

    let sav2 = SnapshotAssetValue(marketValue: Decimal(31500))
    sav2.snapshot = snapshot
    sav2.asset = assetTWD
    tc.context.insert(sav2)

    let er = try makeExchangeRate(rates: ["twd": 31.5])
    let values = CurrencyConversionService.categoryValues(
      for: snapshot, displayCurrency: "usd", exchangeRate: er)

    #expect(values?["Stocks"] == Decimal(2000))
  }

  // MARK: - canConvert Tests

  @Test("canConvert returns true when rates available")
  func testCanConvertAvailable() throws {
    let er = try makeExchangeRate(rates: ["twd": 31.5, "eur": 0.92])
    #expect(
      CurrencyConversionService.canConvert(
        from: "usd", to: "twd", using: er, forSnapshotDate: er.fetchDate)
    )
    #expect(
      CurrencyConversionService.canConvert(
        from: "eur", to: "twd", using: er, forSnapshotDate: er.fetchDate)
    )
  }

  @Test("canConvert returns false when rate missing")
  func testCanConvertMissing() throws {
    let er = try makeExchangeRate(rates: ["twd": 31.5])
    #expect(
      !CurrencyConversionService.canConvert(
        from: "usd", to: "gbp", using: er, forSnapshotDate: er.fetchDate)
    )
  }

  @Test("canConvert returns false with nil exchange rate")
  func testCanConvertNilExchangeRate() {
    #expect(
      !CurrencyConversionService.canConvert(
        from: "usd", to: "twd", using: nil, forSnapshotDate: Date())
    )
  }
}
