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

/// Data for category allocation display.
struct CategoryAllocationData: Sendable, Equatable {
  let categoryName: String
  let value: Decimal
  let percentage: Decimal
}

/// ViewModel for the Snapshot detail screen.
///
/// Manages asset add/edit/remove, cash flow add/edit/remove,
/// and category allocation summary.
@Observable
@MainActor
class SnapshotDetailViewModel {
  let snapshot: Snapshot
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  /// Direct asset values in this snapshot.
  var assetValues: [SnapshotAssetValue] = []

  /// Cash flow operations in this snapshot.
  var cashFlowOperations: [CashFlowOperation] = []

  /// Exchange rate data for currency conversion.
  var exchangeRate: ExchangeRate?

  /// Whether exchange rates are currently being fetched.
  var isFetchingRates = false

  /// Error message from exchange rate fetch.
  var ratesFetchError: String?

  init(
    snapshot: Snapshot,
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.snapshot = snapshot
    self.modelContext = modelContext
    self.settingsService = settingsService ?? .shared
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
  }

  // MARK: - Computed Properties

  /// Display currency for this snapshot.
  private var displayCurrency: String {
    settingsService.mainCurrency
  }

  /// Total portfolio value when every required exchange rate is available.
  /// The value is zero while conversion is incomplete; the view must use
  /// `conversionStatus` and `nativeCurrencyTotals` to render that state.
  var totalValue: Decimal = 0

  /// Asset totals grouped by their original currency when conversion is incomplete.
  var nativeCurrencyTotals: [(code: String, value: Decimal)] = []

  /// Net cash flow when every required exchange rate is available.
  var netCashFlow: Decimal = 0

  /// Cash-flow totals grouped by their original currency when conversion is incomplete.
  var nativeCashFlowTotals: [(code: String, value: Decimal)] = []

  /// Combined conversion status for asset and cash-flow values in this snapshot.
  var conversionStatus: CurrencyConversionStatus = .notNeeded

  /// Conversion status for asset totals.
  var totalConversionStatus: CurrencyConversionStatus = .notNeeded

  /// Conversion status for cash-flow totals.
  var cashFlowConversionStatus: CurrencyConversionStatus = .notNeeded

  /// Asset values sorted by platform (alphabetical), then asset name (alphabetical).
  var sortedAssetValues: [SnapshotAssetValue] = []

  /// Cash flow operations sorted by description for stable display order.
  var sortedCashFlowOperations: [CashFlowOperation] = []

  /// Category allocation summary for this snapshot, with currency conversion.
  var categoryAllocations: [CategoryAllocationData] = []

  /// Exchange rates filtered to only currencies used in this snapshot.
  ///
  /// Returns `(code, rate)` pairs where `rate` is the inverse rate (1 foreign = X base),
  /// sorted alphabetically by currency code.
  var usedCurrencyRates: [(code: String, rate: Double)] = []

  /// All foreign currencies used by this snapshot, including currencies whose
  /// rates are currently unavailable.
  var usedCurrencyCodes: [String] = []

  // MARK: - Load Data

  /// Loads (or reloads) asset values and cash flow operations for the snapshot.
  ///
  /// Wraps the load in `withObservationTracking` so that any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadData() {
    withObservationTracking {
      performLoadData()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.loadData()
      }
    }
  }

  private func performLoadData() {
    assetValues = snapshot.assetValues ?? []
    cashFlowOperations = snapshot.cashFlowOperations ?? []
    exchangeRate = snapshot.exchangeRate

    let totalReport = CurrencyConversionService.totalValueReport(
      for: snapshot,
      displayCurrency: displayCurrency,
      exchangeRate: exchangeRate
    )
    let cashFlowReport = CurrencyConversionService.netCashFlowReport(
      for: snapshot,
      displayCurrency: displayCurrency,
      exchangeRate: exchangeRate
    )
    totalValue = totalReport.convertedTotal ?? 0
    totalConversionStatus = totalReport.status
    nativeCurrencyTotals = totalReport.nativeTotals
      .sorted { $0.key < $1.key }
      .map { (code: $0.key, value: $0.value) }
    netCashFlow = cashFlowReport.convertedTotal ?? 0
    cashFlowConversionStatus = cashFlowReport.status
    nativeCashFlowTotals = cashFlowReport.nativeTotals
      .sorted { $0.key < $1.key }
      .map { (code: $0.key, value: $0.value) }
    conversionStatus = CurrencyConversionStatus.merged([
      totalReport.status,
      cashFlowReport.status,
    ])

    computeSortedAssetValues()
    computeSortedCashFlowOperations()
    computeCategoryAllocations(totalReport: totalReport)
    computeUsedCurrencyRates()
  }

  private func computeSortedAssetValues() {
    sortedAssetValues =
      assetValues
      .filter { $0.asset != nil }
      .sorted { lhs, rhs in
        let lhsAsset = lhs.asset!
        let rhsAsset = rhs.asset!
        if lhsAsset.platform != rhsAsset.platform {
          return lhsAsset.platform.localizedCaseInsensitiveCompare(rhsAsset.platform)
            == .orderedAscending
        }
        return lhsAsset.name.localizedCaseInsensitiveCompare(rhsAsset.name) == .orderedAscending
      }
  }

  private func computeSortedCashFlowOperations() {
    sortedCashFlowOperations = cashFlowOperations.sorted {
      $0.cashFlowDescription < $1.cashFlowDescription
    }
  }

  private func computeCategoryAllocations(totalReport: CurrencyConversionReport) {
    let total = totalValue
    guard totalReport.status.isComplete, total > 0 else {
      categoryAllocations = []
      return
    }

    guard
      let catValues = CurrencyConversionService.categoryValues(
        for: snapshot, displayCurrency: displayCurrency, exchangeRate: exchangeRate)
    else {
      categoryAllocations = []
      return
    }

    categoryAllocations =
      catValues.map { name, value in
        let displayName = name.isEmpty ? "Uncategorized" : name
        return CategoryAllocationData(
          categoryName: displayName,
          value: value,
          percentage: CalculationService.categoryAllocation(
            categoryValue: value, totalValue: total)
        )
      }.sorted { $0.value > $1.value }
  }

  private func computeUsedCurrencyRates() {
    let display = displayCurrency.lowercased()

    var usedCodes = Set<String>()
    for sav in assetValues {
      let currency = sav.asset?.currency ?? ""
      if !currency.isEmpty && currency.lowercased() != display {
        usedCodes.insert(currency.lowercased())
      }
    }
    for cf in cashFlowOperations {
      if !cf.currency.isEmpty && cf.currency.lowercased() != display {
        usedCodes.insert(cf.currency.lowercased())
      }
    }

    usedCurrencyCodes = usedCodes.sorted()
    guard let er = exchangeRate else {
      usedCurrencyRates = []
      return
    }
    let rates = er.rates

    usedCurrencyRates =
      usedCodes.compactMap { code in
        if let rate = rates[code], rate.isFinite, rate > 0 {
          return (code: code, rate: 1.0 / rate)
        }
        return nil
      }.sorted { $0.code < $1.code }
  }

  /// Fetches exchange rates if not already attached to this snapshot.
  func fetchExchangeRatesIfNeeded() async {
    guard !isFetchingRates else { return }

    if let existing = snapshot.exchangeRate,
      CurrencyConversionService.status(
        for: snapshot,
        displayCurrency: displayCurrency,
        exchangeRate: existing
      ).isComplete
    {
      exchangeRate = existing
      return
    }

    isFetchingRates = true
    ratesFetchError = nil
    defer { isFetchingRates = false }

    let result = await ExchangeRateService().fetchMissingRates(
      snapshots: [snapshot], displayCurrency: displayCurrency, modelContext: modelContext
    ).first

    switch result?.status {
    case .cached, .fetched:
      exchangeRate = snapshot.exchangeRate

    case .failed(let message):
      ratesFetchError = message

    case .cancelled:
      break

    case .notNeeded, .none:
      break
    }
  }

  // MARK: - Add Asset: Existing

  /// Adds an existing asset to this snapshot with the given market value.
  ///
  /// - Throws: `SnapshotError.assetAlreadyInSnapshot` if the asset is already in this snapshot.
  func addExistingAsset(_ asset: Asset, marketValue: Decimal) throws {
    // Check if asset already exists in this snapshot
    let existingValues = snapshot.assetValues ?? []
    if existingValues.contains(where: { $0.asset?.id == asset.id }) {
      throw SnapshotError.assetAlreadyInSnapshot(asset.name)
    }

    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    modelContext.insert(sav)
  }

  // MARK: - Add Asset: New

  /// Creates a new asset (or reuses an existing one) and adds it to this snapshot.
  ///
  /// - Throws: `SnapshotError.assetAlreadyInSnapshot` if the (name, platform) already exists
  ///   in this snapshot.
  func addNewAsset(
    name: String,
    platform: String,
    category: Category?,
    marketValue: Decimal,
    currency: String = ""
  ) throws {
    // Normalize for matching
    let normalizedName = name.normalizedForIdentity
    let normalizedPlatform = platform.normalizedForIdentity

    // Check if this asset identity already exists in the snapshot
    let existingValues = snapshot.assetValues ?? []
    if existingValues.contains(where: { sav in
      guard let asset = sav.asset else { return false }
      return asset.normalizedName == normalizedName
        && asset.normalizedPlatform == normalizedPlatform
    }) {
      throw SnapshotError.assetAlreadyInSnapshot(name)
    }

    // Find or create the asset record
    let asset = try modelContext.findOrCreateAsset(
      name: name,
      platform: platform,
      fetcher: fetcher)

    // Assign currency if provided
    if !currency.isEmpty {
      asset.currency = currency
    }

    // Assign category if provided
    if let category = category {
      asset.category = category
    }

    // Create the SnapshotAssetValue
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    modelContext.insert(sav)
  }

  // MARK: - Edit Asset Value

  /// Updates the market value of a direct SnapshotAssetValue.
  func editAssetValue(_ sav: SnapshotAssetValue, newValue: Decimal) throws {
    sav.marketValue = newValue
  }

  // MARK: - Remove Asset

  /// Removes a SnapshotAssetValue from the snapshot. The Asset record is preserved.
  func removeAsset(_ sav: SnapshotAssetValue) {
    modelContext.delete(sav)
  }

  // MARK: - Cash Flow Operations

  /// Adds a new cash flow operation to this snapshot.
  ///
  /// - Throws: `SnapshotError.duplicateCashFlowDescription` if the description already exists.
  func addCashFlow(description: String, amount: Decimal, currency: String = "") throws {
    let operations = snapshot.cashFlowOperations ?? []
    let normalizedDesc = description.trimmingCharacters(in: .whitespaces).lowercased()

    if operations.contains(where: {
      $0.cashFlowDescription.trimmingCharacters(in: .whitespaces).lowercased()
        == normalizedDesc
    }) {
      throw SnapshotError.duplicateCashFlowDescription(description)
    }

    let operation = CashFlowOperation(cashFlowDescription: description, amount: amount)
    operation.currency = currency
    operation.snapshot = snapshot
    modelContext.insert(operation)
  }

  /// Edits an existing cash flow operation.
  ///
  /// - Throws: `SnapshotError.duplicateCashFlowDescription` if the new description conflicts
  ///   with another operation in this snapshot.
  func editCashFlow(
    _ operation: CashFlowOperation,
    newDescription: String,
    newAmount: Decimal
  ) throws {
    let operations = snapshot.cashFlowOperations ?? []
    let normalizedNew = newDescription.trimmingCharacters(in: .whitespaces).lowercased()
    let normalizedOld =
      operation.cashFlowDescription.trimmingCharacters(in: .whitespaces).lowercased()

    // Only check for duplicates if the description actually changed
    if normalizedNew != normalizedOld {
      if operations.contains(where: {
        $0.id != operation.id
          && $0.cashFlowDescription.trimmingCharacters(in: .whitespaces).lowercased()
            == normalizedNew
      }) {
        throw SnapshotError.duplicateCashFlowDescription(newDescription)
      }
    }

    operation.cashFlowDescription = newDescription
    operation.amount = newAmount
  }

  /// Removes a cash flow operation from the snapshot.
  func removeCashFlow(_ operation: CashFlowOperation) {
    modelContext.delete(operation)
  }

  // MARK: - Delete Snapshot

  /// Deletes this snapshot from the model context.
  func deleteSnapshot() {
    modelContext.delete(snapshot)
  }

  /// Returns data for the delete confirmation dialog.
  func deleteConfirmationData() -> SnapshotConfirmationData {
    SnapshotConfirmationData(
      date: snapshot.date,
      assetCount: snapshot.assetValues?.count ?? 0,
      cashFlowCount: snapshot.cashFlowOperations?.count ?? 0
    )
  }

  // MARK: - Category Resolution

  /// Resolves a category by name, reusing an existing one (case-insensitive) or creating a new one.
  func resolveCategory(name: String) throws -> Category? {
    try modelContext.resolveCategory(name: name, fetcher: fetcher)
  }

}
