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

@Suite("ExchangeRate Model Tests")
@MainActor
struct ExchangeRateModelTests {

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
  }

  private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    return TestContext(container: container, context: context)
  }

  // MARK: - Conversion Tests

  @Test("Converting same currency returns original value")
  func testExchangeRateConvertSameCurrency() throws {
    let rates: [String: Decimal] = ["eur": 0.92, "twd": 31.5]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let result = exchangeRate.convert(value: Decimal(100), from: "usd", to: "usd")
    #expect(result == Decimal(100))
  }

  @Test("Converting base currency to target currency")
  func testExchangeRateConvertBaseToTarget() throws {
    let rates: [String: Decimal] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let result = exchangeRate.convert(value: Decimal(100), from: "usd", to: "twd")
    let expected = Decimal(3150)
    #expect(result == expected)
  }

  @Test("Converting target currency to base currency")
  func testExchangeRateConvertTargetToBase() throws {
    let rates: [String: Decimal] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let result = exchangeRate.convert(value: Decimal(3150), from: "twd", to: "usd")
    #expect(result == Decimal(100))
  }

  @Test("Conversion preserves high-precision decimal exchange rates")
  func testExchangeRateConversionPreservesPrecision() {
    let ratesJSON = Data(
      #"{"twd":31.500000000000000000123456789}"#.utf8)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )
    let expected = Decimal(string: "31.500000000000000000123456789")!

    let result = exchangeRate.convert(value: Decimal(1), from: "usd", to: "twd")

    #expect(result == expected)
  }

  @Test("Converting cross-rate between two non-base currencies")
  func testExchangeRateConvertCrossRate() throws {
    // EUR → TWD: value / rates["eur"] * rates["twd"]
    // 100 EUR → 100 / 0.92 * 31.5 = 3423.913...
    let rates: [String: Decimal] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let result = exchangeRate.convert(value: Decimal(100), from: "eur", to: "twd")
    #expect(result != nil)
    // 100 / 0.92 * 31.5 ≈ 3423.91
    // We just verify it's in the right ballpark and not nil
    if let result {
      #expect(result > Decimal(3400))
      #expect(result < Decimal(3450))
    }
  }

  @Test("Converting with missing currency returns nil")
  func testExchangeRateConvertMissingCurrency() throws {
    let rates: [String: Decimal] = ["twd": 31.5]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let result = exchangeRate.convert(value: Decimal(100), from: "usd", to: "gbp")
    #expect(result == nil)
  }

  @Test("Rates JSON encode/decode roundtrip")
  func testExchangeRateRatesDecoding() throws {
    let originalRates: [String: Decimal] = ["twd": 31.5, "eur": 0.92, "jpy": 149.5]
    let ratesJSON = try JSONEncoder().encode(originalRates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )

    let decodedRates = exchangeRate.rates
    #expect(decodedRates["twd"] == 31.5)
    #expect(decodedRates["eur"] == 0.92)
    #expect(decodedRates["jpy"] == 149.5)
    #expect(decodedRates.count == 3)
  }

  // MARK: - updateRates Tests

  @Test("updateRates updates all fields and clears cache")
  func testUpdateRatesClearsCacheAndUpdatesFields() throws {
    let oldRates: [String: Decimal] = ["twd": 31.5]
    let oldJSON = try JSONEncoder().encode(oldRates)
    let oldDate = Date(timeIntervalSince1970: 1_000_000)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: oldJSON,
      fetchDate: oldDate,
      isFallback: true
    )

    // Access rates to populate cache
    _ = exchangeRate.rates

    let newRates: [String: Decimal] = ["eur": 0.92, "jpy": 149.5]
    let newJSON = try JSONEncoder().encode(newRates)
    let newDate = Date(timeIntervalSince1970: 2_000_000)

    exchangeRate.updateRates(baseCurrency: "eur", ratesJSON: newJSON, fetchDate: newDate)

    #expect(exchangeRate.baseCurrency == "eur")
    #expect(exchangeRate.fetchDate == newDate)
    #expect(exchangeRate.isFallback == false)
    // Cache should be cleared — decoded rates should reflect new JSON
    let decoded = exchangeRate.rates
    #expect(decoded["eur"] == 0.92)
    #expect(decoded["jpy"] == 149.5)
    #expect(decoded["twd"] == nil)
  }

  // MARK: - Model Field Tests

  @Test("Asset has currency field")
  func testAssetHasCurrencyField() {
    let tc = createTestContext()
    let asset = Asset(name: "Test Stock", platform: "Broker")
    asset.currency = "twd"
    tc.context.insert(asset)

    #expect(asset.currency == "twd")
  }

  @Test("Asset currency defaults to empty string")
  func testAssetCurrencyDefaultsToEmpty() {
    let asset = Asset(name: "Test Stock")
    #expect(asset.currency == "")
  }

  @Test("CashFlowOperation has currency field")
  func testCashFlowOperationHasCurrencyField() {
    let tc = createTestContext()
    let op = CashFlowOperation(cashFlowDescription: "Deposit", amount: Decimal(1000))
    op.currency = "twd"
    tc.context.insert(op)

    #expect(op.currency == "twd")
  }

  @Test("CashFlowOperation currency defaults to empty string")
  func testCashFlowOperationCurrencyDefaultsToEmpty() {
    let op = CashFlowOperation(cashFlowDescription: "Deposit", amount: Decimal(1000))
    #expect(op.currency == "")
  }

  // MARK: - Relationship Tests

  @Test("Snapshot has exchangeRate relationship")
  func testSnapshotHasExchangeRateRelationship() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let rates: [String: Decimal] = ["twd": 31.5]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )
    exchangeRate.snapshot = snapshot
    tc.context.insert(exchangeRate)

    #expect(snapshot.exchangeRate != nil)
    #expect(snapshot.exchangeRate?.baseCurrency == "usd")
  }

  @Test("Deleting snapshot cascades to exchangeRate")
  func testSnapshotDeleteCascadesToExchangeRate() throws {
    let tc = createTestContext()
    let snapshot = Snapshot(date: Date())
    tc.context.insert(snapshot)

    let rates: [String: Decimal] = ["twd": 31.5]
    let ratesJSON = try JSONEncoder().encode(rates)
    let exchangeRate = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date()
    )
    exchangeRate.snapshot = snapshot
    tc.context.insert(exchangeRate)

    tc.context.delete(snapshot)

    let descriptor = FetchDescriptor<ExchangeRate>()
    let remaining = try tc.context.fetch(descriptor)
    #expect(remaining.isEmpty)
  }

  // MARK: - Schema Tests

  @Test("SchemaV1 contains all 6 model types")
  func testSchemaV1ContainsAllModels() {
    let models = SchemaV1.models
    #expect(models.count == 6)

    let typeNames = models.map { String(describing: $0) }
    #expect(typeNames.contains(where: { $0.contains("Category") }))
    #expect(typeNames.contains(where: { $0.contains("Asset") }))
    #expect(typeNames.contains(where: { $0.contains("Snapshot") }))
    #expect(typeNames.contains(where: { $0.contains("SnapshotAssetValue") }))
    #expect(typeNames.contains(where: { $0.contains("CashFlowOperation") }))
    #expect(typeNames.contains(where: { $0.contains("ExchangeRate") }))
  }
}
