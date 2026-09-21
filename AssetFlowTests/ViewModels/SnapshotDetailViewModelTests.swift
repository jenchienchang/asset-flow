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

@Suite("SnapshotDetailViewModel Tests")
@MainActor
struct SnapshotDetailViewModelTests {

  // MARK: - Test Helpers

  /// Holds the ModelContainer, ModelContext, and Snapshot for test isolation.
  /// Retaining the container prevents SwiftData from resetting the backing store.
  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let snapshot: Snapshot
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  private func createAssetWithValue(
    name: String,
    platform: String,
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: platform)
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  private func createSnapshotWithContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 15))
    context.insert(snapshot)
    return TestContext(container: container, context: context, snapshot: snapshot)
  }

  // MARK: - Asset Values

  @Test("Loads direct asset values for the snapshot")
  func loadsAssetValues() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.assetValues.count == 2)
  }

  @Test("Total value sums direct asset values only")
  func totalValueSumsDirectValues() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.totalValue == Decimal(65000))
  }

  @Test("Missing rates keep native totals and mark converted total unavailable")
  func missingRatesKeepNativeTotals() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)
    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let (usdAsset, _) = createAssetWithValue(
      name: "US Stock", platform: "Broker", marketValue: 1000,
      snapshot: snapshot, context: context)
    usdAsset.currency = "usd"
    let (eurAsset, _) = createAssetWithValue(
      name: "EU Stock", platform: "Broker", marketValue: 850,
      snapshot: snapshot, context: context)
    eurAsset.currency = "eur"

    let viewModel = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, settingsService: settings)
    viewModel.loadData()

    #expect(viewModel.totalValue == 0)
    #expect(viewModel.totalConversionStatus == .missingRates(["eur"]))
    #expect(viewModel.nativeCurrencyTotals.contains { $0.code == "usd" && $0.value == 1000 })
    #expect(viewModel.nativeCurrencyTotals.contains { $0.code == "eur" && $0.value == 850 })
  }

  // MARK: - Add Asset: Existing

  @Test("Adds existing asset to snapshot with market value")
  func addExistingAssetToSnapshot() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let asset = Asset(name: "AAPL", platform: "Firstrade")
    context.insert(asset)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.addExistingAsset(asset, marketValue: 15000)

    let values = snapshot.assetValues ?? []
    #expect(values.count == 1)
    #expect(values.first?.marketValue == Decimal(15000))
    #expect(values.first?.asset?.name == "AAPL")
  }

  @Test("Rejects adding existing asset if already in snapshot")
  func rejectsAddExistingAssetDuplicate() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (asset, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)

    #expect(throws: SnapshotError.self) {
      try viewModel.addExistingAsset(asset, marketValue: 16000)
    }
  }

  // MARK: - Add Asset: New

  @Test("Creates new asset record and adds to snapshot")
  func addNewAssetCreatesRecord() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.addNewAsset(
      name: "AAPL", platform: "Firstrade", category: nil, marketValue: 15000)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try context.fetch(assetDescriptor)
    #expect(assets.count == 1)
    #expect(assets.first?.name == "AAPL")
    #expect(assets.first?.platform == "Firstrade")

    let values = snapshot.assetValues ?? []
    #expect(values.count == 1)
    #expect(values.first?.marketValue == Decimal(15000))
  }

  @Test("Rejects new asset if name+platform already in snapshot")
  func rejectsNewAssetDuplicateInSnapshot() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)

    #expect(throws: SnapshotError.self) {
      try viewModel.addNewAsset(
        name: "AAPL", platform: "Firstrade", category: nil, marketValue: 16000)
    }
  }

  @Test("Rejects new asset using case-insensitive matching")
  func rejectsNewAssetCaseInsensitiveDuplicate() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)

    #expect(throws: SnapshotError.self) {
      try viewModel.addNewAsset(
        name: "  aapl  ", platform: "firstrade", category: nil, marketValue: 16000)
    }
  }

  @Test("New Category with matching name reuses existing category")
  func newCategoryReusesExisting() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let existingCategory = Category(name: "Equities", targetAllocationPercentage: 60)
    context.insert(existingCategory)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    let resolved = try viewModel.resolveCategory(name: "equities")

    #expect(resolved?.id == existingCategory.id)
    #expect(resolved?.name == "Equities")

    // No duplicate created
    let catDescriptor = FetchDescriptor<AssetFlow.Category>()
    let allCategories = try context.fetch(catDescriptor)
    #expect(allCategories.count == 1)
  }

  @Test("New Category with genuinely new name creates category with nil target")
  func newCategoryCreatesNew() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    let resolved = try viewModel.resolveCategory(name: "Crypto")

    #expect(resolved?.name == "Crypto")
    #expect(resolved?.targetAllocationPercentage == nil)

    let catDescriptor = FetchDescriptor<AssetFlow.Category>()
    let allCategories = try context.fetch(catDescriptor)
    #expect(allCategories.count == 1)
  }

  @Test("New asset reuses existing asset record if name+platform matches")
  func newAssetReusesExistingRecord() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    // Pre-existing asset (not in this snapshot)
    let existingAsset = Asset(name: "AAPL", platform: "Firstrade")
    context.insert(existingAsset)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.addNewAsset(
      name: "AAPL", platform: "Firstrade", category: nil, marketValue: 15000)

    // Should reuse existing asset, not create duplicate
    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try context.fetch(assetDescriptor)
    #expect(assets.count == 1)
    #expect(assets.first?.id == existingAsset.id)
  }

  // MARK: - Edit Asset Value

  @Test("Updates market value of direct SnapshotAssetValue")
  func editAssetValueUpdates() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, sav) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.editAssetValue(sav, newValue: 16000)

    #expect(sav.marketValue == Decimal(16000))
  }

  @Test("editAssetValue persists change immediately without separate save")
  func editAssetValuePersistsImmediately() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, sav) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.editAssetValue(sav, newValue: 20000)

    // Fetch from context to verify persistence
    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let fetched = try context.fetch(savDescriptor)
    #expect(fetched.first?.marketValue == Decimal(20000))
  }

  // MARK: - Remove Asset

  @Test("Removes SnapshotAssetValue from snapshot")
  func removeAssetFromSnapshot() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, sav) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.removeAsset(sav)

    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let remaining = try context.fetch(savDescriptor)
    #expect(remaining.isEmpty)
  }

  @Test("Remove asset preserves the Asset record itself")
  func removeAssetPreservesAssetRecord() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, sav) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.removeAsset(sav)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try context.fetch(assetDescriptor)
    #expect(assets.count == 1)
    #expect(assets.first?.name == "AAPL")
  }

  // MARK: - Cash Flow Operations

  @Test("Adds cash flow with description and amount")
  func addCashFlow() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.addCashFlow(description: "Salary deposit", amount: 50000)

    let operations = snapshot.cashFlowOperations ?? []
    #expect(operations.count == 1)
    #expect(operations.first?.cashFlowDescription == "Salary deposit")
    #expect(operations.first?.amount == Decimal(50000))
  }

  @Test("Rejects duplicate cash flow description within snapshot (case-insensitive)")
  func rejectsDuplicateCashFlowDescription() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.addCashFlow(description: "Salary deposit", amount: 50000)

    #expect(throws: SnapshotError.self) {
      try viewModel.addCashFlow(description: "salary deposit", amount: 30000)
    }
  }

  @Test("Edits cash flow description and amount")
  func editCashFlow() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf.snapshot = snapshot
    context.insert(cf)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.editCashFlow(cf, newDescription: "Monthly salary", newAmount: 55000)

    #expect(cf.cashFlowDescription == "Monthly salary")
    #expect(cf.amount == Decimal(55000))
  }

  @Test("Edit cash flow rejects duplicate description")
  func editCashFlowRejectsDuplicate() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf1 = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf1.snapshot = snapshot
    context.insert(cf1)
    let cf2 = CashFlowOperation(cashFlowDescription: "Bonus", amount: 10000)
    cf2.snapshot = snapshot
    context.insert(cf2)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)

    #expect(throws: SnapshotError.self) {
      try viewModel.editCashFlow(cf2, newDescription: "salary", newAmount: 10000)
    }
  }

  @Test("Edit cash flow allows keeping same description")
  func editCashFlowAllowsSameDescription() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf.snapshot = snapshot
    context.insert(cf)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    try viewModel.editCashFlow(cf, newDescription: "Salary", newAmount: 55000)

    #expect(cf.amount == Decimal(55000))
  }

  @Test("Removes cash flow operation")
  func removeCashFlow() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf.snapshot = snapshot
    context.insert(cf)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.removeCashFlow(cf)

    let cfDescriptor = FetchDescriptor<CashFlowOperation>()
    let remaining = try context.fetch(cfDescriptor)
    #expect(remaining.isEmpty)
  }

  @Test("loadAssetValues also loads cash flow operations")
  func loadAssetValuesLoadsCashFlows() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf.snapshot = snapshot
    context.insert(cf)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.cashFlowOperations.count == 1)
    #expect(viewModel.cashFlowOperations.first?.amount == Decimal(50000))
  }

  @Test("sortedCashFlowOperations reads from loaded operations, not relationship")
  func sortedCashFlowsUsesStoredProperty() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf1 = CashFlowOperation(cashFlowDescription: "Bonus", amount: 10000)
    cf1.snapshot = snapshot
    context.insert(cf1)
    let cf2 = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf2.snapshot = snapshot
    context.insert(cf2)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)

    // Before loading, should be empty
    #expect(viewModel.sortedCashFlowOperations.isEmpty)

    // After loading, should return sorted operations
    viewModel.loadData()
    #expect(viewModel.sortedCashFlowOperations.count == 2)
    #expect(viewModel.sortedCashFlowOperations[0].cashFlowDescription == "Bonus")
    #expect(viewModel.sortedCashFlowOperations[1].cashFlowDescription == "Salary")
  }

  @Test("Net cash flow with mixed positive and negative amounts")
  func netCashFlowMixed() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf1 = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf1.snapshot = snapshot
    context.insert(cf1)
    let cf2 = CashFlowOperation(cashFlowDescription: "Rent", amount: -2000)
    cf2.snapshot = snapshot
    context.insert(cf2)
    let cf3 = CashFlowOperation(cashFlowDescription: "Dividends", amount: 1500)
    cf3.snapshot = snapshot
    context.insert(cf3)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()
    #expect(viewModel.netCashFlow == Decimal(49500))
  }

  @Test("Net cash flow with no operations returns zero")
  func netCashFlowZeroWhenEmpty() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()
    #expect(viewModel.netCashFlow == Decimal(0))
  }

  @Test("Net cash flow includes zero-amount operations correctly")
  func netCashFlowWithZeroAmount() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let cf1 = CashFlowOperation(cashFlowDescription: "Salary", amount: 50000)
    cf1.snapshot = snapshot
    context.insert(cf1)
    let cf2 = CashFlowOperation(cashFlowDescription: "Adjustment", amount: 0)
    cf2.snapshot = snapshot
    context.insert(cf2)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()
    #expect(viewModel.netCashFlow == Decimal(50000))
  }

  // MARK: - Category Allocation

  @Test("Category allocation summary computed for snapshot")
  func categoryAllocationSummary() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    context.insert(equities)
    context.insert(bonds)

    let apple = Asset(name: "AAPL", platform: "Firstrade")
    apple.category = equities
    context.insert(apple)
    let bond = Asset(name: "Treasury", platform: "Firstrade")
    bond.category = bonds
    context.insert(bond)

    let sav1 = SnapshotAssetValue(marketValue: 75000)
    sav1.snapshot = snapshot
    sav1.asset = apple
    context.insert(sav1)
    let sav2 = SnapshotAssetValue(marketValue: 25000)
    sav2.snapshot = snapshot
    sav2.asset = bond
    context.insert(sav2)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()

    let allocations = viewModel.categoryAllocations

    let equityAlloc = allocations.first { $0.categoryName == "Equities" }
    #expect(equityAlloc?.percentage == 75)

    let bondAlloc = allocations.first { $0.categoryName == "Bonds" }
    #expect(bondAlloc?.percentage == 25)
  }

  // MARK: - Used Currency Rates

  @Test("usedCurrencyRates returns foreign currencies only")
  func usedCurrencyRatesExcludesDisplayCurrency() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let apple = Asset(name: "AAPL", platform: "Firstrade")
    apple.currency = "usd"
    context.insert(apple)
    let sav1 = SnapshotAssetValue(marketValue: 15000)
    sav1.snapshot = snapshot
    sav1.asset = apple
    context.insert(sav1)

    let twStock = Asset(name: "2330", platform: "Fubon")
    twStock.currency = "twd"
    context.insert(twStock)
    let sav2 = SnapshotAssetValue(marketValue: 500000)
    sav2.snapshot = snapshot
    sav2.asset = twStock
    context.insert(sav2)

    let rates: [String: Double] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let er = ExchangeRate(baseCurrency: "usd", ratesJSON: ratesJSON, fetchDate: Date())
    er.snapshot = snapshot
    context.insert(er)

    let viewModel = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, settingsService: settings)
    viewModel.loadData()
    viewModel.exchangeRate = er

    let result = viewModel.usedCurrencyRates
    // Only TWD should appear (EUR is not used by any asset)
    #expect(result.count == 1)
    #expect(result[0].code == "twd")
    // Inverse rate: 1 / 31.5
    #expect(abs(result[0].rate - (1.0 / 31.5)) < 0.0001)
  }

  @Test("usedCurrencyRates is empty when all assets use display currency")
  func usedCurrencyRatesEmptyForSingleCurrency() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let rates: [String: Double] = ["twd": 31.5]
    let ratesJSON = try JSONEncoder().encode(rates)
    let er = ExchangeRate(baseCurrency: "usd", ratesJSON: ratesJSON, fetchDate: Date())
    er.snapshot = snapshot
    context.insert(er)

    let viewModel = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, settingsService: settings)
    viewModel.loadData()
    viewModel.exchangeRate = er

    #expect(viewModel.usedCurrencyRates.isEmpty)
  }

  @Test("usedCurrencyRates includes cash flow currencies")
  func usedCurrencyRatesIncludesCashFlowCurrencies() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let cf = CashFlowOperation(cashFlowDescription: "Transfer", amount: 100000)
    cf.currency = "twd"
    cf.snapshot = snapshot
    context.insert(cf)

    let rates: [String: Double] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let er = ExchangeRate(baseCurrency: "usd", ratesJSON: ratesJSON, fetchDate: Date())
    er.snapshot = snapshot
    context.insert(er)

    let viewModel = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, settingsService: settings)
    viewModel.loadData()
    viewModel.exchangeRate = er

    let result = viewModel.usedCurrencyRates
    #expect(result.count == 1)
    #expect(result[0].code == "twd")
  }

  @Test("usedCurrencyRates sorted alphabetically by code")
  func usedCurrencyRatesSortedAlphabetically() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "usd"

    let twStock = Asset(name: "2330", platform: "Fubon")
    twStock.currency = "twd"
    context.insert(twStock)
    let sav1 = SnapshotAssetValue(marketValue: 500000)
    sav1.snapshot = snapshot
    sav1.asset = twStock
    context.insert(sav1)

    let euStock = Asset(name: "SAP", platform: "IBKR")
    euStock.currency = "eur"
    context.insert(euStock)
    let sav2 = SnapshotAssetValue(marketValue: 10000)
    sav2.snapshot = snapshot
    sav2.asset = euStock
    context.insert(sav2)

    let rates: [String: Double] = ["twd": 31.5, "eur": 0.92]
    let ratesJSON = try JSONEncoder().encode(rates)
    let er = ExchangeRate(baseCurrency: "usd", ratesJSON: ratesJSON, fetchDate: Date())
    er.snapshot = snapshot
    context.insert(er)

    let viewModel = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, settingsService: settings)
    viewModel.loadData()
    viewModel.exchangeRate = er

    let result = viewModel.usedCurrencyRates
    #expect(result.count == 2)
    #expect(result[0].code == "eur")
    #expect(result[1].code == "twd")
  }

  // MARK: - Sorted Asset Display

  @Test("Asset values sorted by platform then asset name")
  func assetValuesSortedByPlatformThenName() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    // Insert in non-alphabetical order
    let (_, _) = createAssetWithValue(
      name: "VTI", platform: "Firstrade", marketValue: 28000,
      snapshot: snapshot, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: snapshot, context: context)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)
    let (_, _) = createAssetWithValue(
      name: "ETH", platform: "Binance", marketValue: 3000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.loadData()

    let sorted = viewModel.sortedAssetValues
    #expect(sorted.count == 4)
    // Binance comes before Firstrade alphabetically
    #expect(sorted[0].asset?.platform == "Binance")
    #expect(sorted[0].asset?.name == "BTC")
    #expect(sorted[1].asset?.platform == "Binance")
    #expect(sorted[1].asset?.name == "ETH")
    #expect(sorted[2].asset?.platform == "Firstrade")
    #expect(sorted[2].asset?.name == "AAPL")
    #expect(sorted[3].asset?.platform == "Firstrade")
    #expect(sorted[3].asset?.name == "VTI")
  }

  // MARK: - Delete Snapshot

  @Test("Confirmation data includes correct date, asset count, and cash flow count")
  func deleteSnapshotConfirmationData() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)
    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 5000)
    cf.snapshot = snapshot
    context.insert(cf)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    let data = viewModel.deleteConfirmationData()

    #expect(data.date == snapshot.date)
    #expect(data.assetCount == 1)
    #expect(data.cashFlowCount == 1)
  }

  @Test("deleteSnapshot removes snapshot from context")
  func deleteSnapshotRemovesFromContext() throws {
    let tc = createSnapshotWithContext()
    let (context, snapshot) = (tc.context, tc.snapshot)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snapshot, context: context)

    let viewModel = SnapshotDetailViewModel(snapshot: snapshot, modelContext: context)
    viewModel.deleteSnapshot()

    let descriptor = FetchDescriptor<Snapshot>()
    let remaining = try context.fetch(descriptor)
    #expect(remaining.isEmpty)
  }
}
