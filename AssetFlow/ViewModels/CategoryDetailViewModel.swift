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

/// Value history entry for a category's total value at a snapshot date.
struct CategoryValueHistoryEntry: Identifiable {
  var id: String { "\(date.timeIntervalSince1970)-\(totalValue)" }
  let date: Date
  let totalValue: Decimal
}

/// Allocation history entry for a category's allocation percentage at a snapshot date.
struct CategoryAllocationHistoryEntry: Identifiable {
  var id: String { "\(date.timeIntervalSince1970)-\(allocationPercentage)" }
  let date: Date
  let allocationPercentage: Decimal
}

/// ViewModel for the Category detail/edit screen.
///
/// Manages editing category properties (name, target allocation),
/// loading assets in the category with latest values,
/// computing value and allocation history across snapshots,
/// and deletion with validation.
@Observable
@MainActor
final class CategoryDetailViewModel {
  @ObservationIgnored private let refresh = ObservedRefresh()

  let category: Category
  private let modelContext: ModelContext
  private let fetcher: any ModelFetching
  private let settingsService: SettingsService

  var minimumEnabled = false
  var minimumBalanceText = ""
  var editedMinimumCurrency = "USD"
  var goalAssessment = CategoryGoalAssessment()

  var editedName: String
  var editedTargetAllocation: Decimal? {
    get { try? CategoryGoalValidator.parse(targetAllocationText) }
    set { targetAllocationText = newValue.map { Self.formText($0) } ?? "" }
  }
  var targetAllocationText: String

  private struct Draft: Equatable {
    var name = ""
    var percentage = ""
    var minimumEnabled = false
    var amount = ""
    var currency = ""
  }
  private var savedDraft = Draft()
  private var draft: Draft {
    Draft(
      name: editedName, percentage: targetAllocationText, minimumEnabled: minimumEnabled,
      amount: minimumBalanceText, currency: editedMinimumCurrency)
  }
  var hasUnsavedChanges: Bool { draft != savedDraft }

  func revertChanges() {
    applySavedDraft(savedFields())
  }

  private func savedFields() -> Draft {
    Draft(
      name: category.name,
      percentage: category.targetAllocationPercentage.map(Self.formText) ?? "",
      minimumEnabled: category.minimumBalanceAmount != nil,
      amount: category.minimumBalanceAmount.map(Self.formText) ?? "",
      currency: category.minimumBalanceCurrency
        ?? CategoryGoalValidator.defaultCurrency(
          assetCurrencies: (category.assets ?? []).map(\.currency),
          displayCurrency: settingsService.mainCurrency))
  }

  private func applySavedDraft(_ value: Draft) {
    editedName = value.name
    targetAllocationText = value.percentage
    minimumEnabled = value.minimumEnabled
    minimumBalanceText = value.amount
    editedMinimumCurrency = value.currency
    savedDraft = value
  }

  private static func formText(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(
      of: ".", with: Locale.current.decimalSeparator ?? ".")
  }

  struct MinimumHistoryEntry: Identifiable, ChartFilterable {
    let date: Date
    let amount: Decimal
    let segment: Int
    var id: Date { date }
    var chartDate: Date { date }
  }
  var minimumHistory: [MinimumHistoryEntry] = []

  var assets: [DetailAssetRowData] = []
  var valueHistory: [CategoryValueHistoryEntry] = []
  var allocationHistory: [CategoryAllocationHistoryEntry] = []
  var conversionStatus: CurrencyConversionStatus = .notNeeded
  var loadState: DataLoadState = .idle

  init(
    category: Category,
    modelContext: ModelContext,
    settingsService: SettingsService? = nil,
    fetcher: (any ModelFetching)? = nil
  ) {
    self.category = category
    self.modelContext = modelContext
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
    self.settingsService = settingsService ?? .shared
    self.editedName = category.name
    self.minimumEnabled = category.minimumBalanceAmount != nil
    self.minimumBalanceText = category.minimumBalanceAmount.map { Self.formText($0) } ?? ""
    self.editedMinimumCurrency =
      category.minimumBalanceCurrency
      ?? CategoryGoalValidator.defaultCurrency(
        assetCurrencies: (category.assets ?? []).map(\.currency),
        displayCurrency: (settingsService ?? .shared).mainCurrency)
    if let target = category.targetAllocationPercentage {
      self.targetAllocationText = Self.formText(target)
    } else {
      self.targetAllocationText = ""
    }
    self.savedDraft = draft
  }

  // MARK: - Computed Properties

  /// Whether the category can be deleted (has no assigned assets).
  var canDelete: Bool {
    (category.assets ?? []).isEmpty
  }

  /// Explanatory text for why the category cannot be deleted, or nil if deletion is allowed.
  var deleteExplanation: String? {
    guard !canDelete else { return nil }
    let assetCount = (category.assets ?? []).count
    return CategoryError.cannotDelete(assetCount: assetCount).errorDescription
  }

  /// Coalesces source-observation and query notifications before refreshing.
  func requestRefresh() {
    refresh.request { [weak self] in self?.loadData() }
  }

  // MARK: - Load Data

  /// Loads assets, value history, and allocation history for this category.
  ///
  /// Uses `ObservedRefresh` to track source reads and publish derived results. Any `@Observable`/`@Model`
  /// property change automatically triggers a reload.
  func loadData() {
    refresh.perform {
      performLoadData()
    } reload: { [weak self] in
      self?.loadData()
    }
  }

  private func performLoadData() {
    let committedDraft = savedFields()
    do {
      let allSnapshots = try SnapshotSummaryService.fetchSnapshots(using: fetcher)
      let display = settingsService.mainCurrency
      let loadedSummaries = SnapshotSummaryService.makeSummaries(
        for: allSnapshots, displayCurrency: display)
      let status = CurrencyConversionStatus.merged(loadedSummaries.map(\.conversionStatus))
      let allCategories = try fetchModels(
        FetchDescriptor<Category>(), from: fetcher, operation: "load category goals")
      let assessment = CategoryGoalAssessmentService.assess(
        snapshot: allSnapshots.last, categories: allCategories, displayCurrency: display)
      var history: [MinimumHistoryEntry] = []
      if let amount = category.minimumBalanceAmount, let currency = category.minimumBalanceCurrency,
        (try? CategoryGoalValidator.validate(
          percentage: category.targetAllocationPercentage, minimum: amount, currency: currency))
          != nil
      {
        var segment = 0
        for snapshot in allSnapshots {
          if let minimum = CategoryGoalAssessmentService.convertMinimum(
            amount: amount, currency: currency, snapshot: snapshot, displayCurrency: display)
          {
            history.append(
              MinimumHistoryEntry(date: snapshot.date, amount: minimum, segment: segment))
          } else {
            segment += 1
          }
        }
      }
      let loadedAssets = loadAssets(allSnapshots: allSnapshots)
      let histories = loadHistory(summaries: loadedSummaries)
      refresh.publish {
        if !self.hasUnsavedChanges { self.applySavedDraft(committedDraft) }
        self.goalAssessment = assessment
        self.conversionStatus = status
        self.minimumHistory = history
        self.assets = loadedAssets
        self.valueHistory = histories.0
        self.allocationHistory = histories.1
        self.loadState = .loaded
      }
    } catch {
      let message = error.localizedDescription
      refresh.publish { self.loadState = .failed(message) }
    }
  }

  // MARK: - Save

  /// Validates and saves edited properties to the category model.
  ///
  /// - Throws: `CategoryError.emptyName` if name is blank,
  ///   `CategoryError.invalidTargetAllocation` if target is outside 0-100,
  ///   `CategoryError.duplicateName` if name conflicts with another category.
  func save() throws {
    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw CategoryError.emptyName }

    let percentage = try CategoryGoalValidator.parse(targetAllocationText)
    let minimum = minimumEnabled ? try CategoryGoalValidator.parse(minimumBalanceText) : nil
    if minimumEnabled && minimum == nil { throw CategoryGoalValidationError.minimum }
    let currency =
      minimumEnabled
      ? editedMinimumCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() : nil
    var supported = Set(CurrencyService.shared.currencies.map { $0.code.uppercased() })
    if let previous = category.minimumBalanceCurrency { supported.insert(previous) }
    do {
      try CategoryGoalValidator.validate(
        percentage: percentage, minimum: minimum, currency: currency, supportedCurrencies: supported
      )
    } catch CategoryGoalValidationError.percentage { throw CategoryError.invalidTargetAllocation }

    // Check for conflicts with other categories (exclude self)
    let descriptor = FetchDescriptor<Category>()
    let allCategories = try fetchModels(
      descriptor,
      from: fetcher,
      operation: "validate category")

    let hasConflict = allCategories.contains { other in
      other.id != category.id
        && other.name.lowercased() == trimmed.lowercased()
    }

    if hasConflict {
      throw CategoryError.duplicateName(trimmed)
    }

    category.name = trimmed
    category.targetAllocationPercentage = percentage
    category.minimumBalanceAmount = minimum
    category.minimumBalanceCurrency = currency
    revertChanges()
    loadData()
  }

  // MARK: - Delete

  /// Deletes the category from the model context.
  /// Only call when `canDelete` is true.
  func deleteCategory() {
    modelContext.delete(category)
  }

  // MARK: - Private Helpers

  /// Loads assets in this category with their latest values.
  private func loadAssets(allSnapshots: [Snapshot]) -> [DetailAssetRowData] {
    let categoryAssets = category.assets ?? []
    let displayCurrency = settingsService.mainCurrency
    let latestExchangeRate = allSnapshots.last?.exchangeRate
    let latestSnapshotDate = allSnapshots.last?.date

    // Build latest value lookup from most recent snapshot
    var latestValueLookup: [UUID: Decimal] = [:]
    if let latestSnapshot = allSnapshots.last {
      for sav in latestSnapshot.assetValues ?? [] {
        guard let asset = sav.asset else { continue }
        latestValueLookup[asset.id] = sav.marketValue
      }
    }

    return categoryAssets.map { asset in
      let value = latestValueLookup[asset.id]
      let assetCurrency = asset.currency
      let effectiveCurrency = assetCurrency.isEmpty ? displayCurrency : assetCurrency
      let converted: Decimal? =
        if let value, let snapshotDate = latestSnapshotDate,
          effectiveCurrency != displayCurrency
        {
          CurrencyConversionService.convert(
            value: value,
            from: effectiveCurrency,
            to: displayCurrency,
            using: latestExchangeRate,
            forSnapshotDate: snapshotDate)
        } else {
          nil
        }
      return DetailAssetRowData(
        asset: asset,
        latestValue: value,
        convertedValue: converted
      )
    }
    .sorted {
      $0.asset.name.localizedCaseInsensitiveCompare($1.asset.name) == .orderedAscending
    }
  }

  /// Computes value and allocation history across all snapshots.
  ///
  /// **Note:** Values reflect **current** category membership applied retroactively.
  /// The data model does not track historical category assignments, so an asset
  /// moved between categories will appear in its current category for all past snapshots.
  private func loadHistory(summaries: [SnapshotSummary]) -> (
    [CategoryValueHistoryEntry], [CategoryAllocationHistoryEntry]
  ) {
    var valueEntries: [CategoryValueHistoryEntry] = []
    var allocationEntries: [CategoryAllocationHistoryEntry] = []

    for summary in summaries {
      let categoryValue = summary.categoryValues[category.name] ?? 0
      valueEntries.append(
        CategoryValueHistoryEntry(date: summary.date, totalValue: categoryValue))

      let allocation = CalculationService.categoryAllocation(
        categoryValue: categoryValue, totalValue: summary.totalValue)
      allocationEntries.append(
        CategoryAllocationHistoryEntry(date: summary.date, allocationPercentage: allocation))
    }

    return (valueEntries, allocationEntries)
  }
}

/// Retains a category draft while navigation awaits Save, Discard, or Cancel.
@Observable
@MainActor
final class CategoryEditingSession {
  var editor: CategoryDetailViewModel?
  var pendingNavigation: (() -> Void)?
  var needsConfirmation: Bool { pendingNavigation != nil }

  func requestNavigation(_ action: @escaping () -> Void) {
    guard !needsConfirmation else { return }
    if editor?.hasUnsavedChanges == true { pendingNavigation = action } else { action() }
  }
  /// Release an editor only after its category is no longer visible.
  func updateVisibleCategory(_ category: Category?) {
    guard editor?.category !== category else { return }
    editor = nil
    pendingNavigation = nil
  }

  func cancelNavigation() { pendingNavigation = nil }
  func saveAndNavigate() throws {
    try editor?.save()
    finishNavigation()
  }
  func discardAndNavigate() {
    editor?.revertChanges()
    finishNavigation()
  }
  private func finishNavigation() {
    let action = pendingNavigation
    pendingNavigation = nil
    action?()
  }
}
