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

/// Information about a platform available for copy-forward during import.
struct CopyForwardPlatformInfo: Identifiable {
  let platformName: String
  let assetCount: Int
  let sourceSnapshotDate: Date
  var isSelected: Bool

  var id: String { platformName }
}

/// ViewModel for the CSV Import screen.
///
/// Manages import type selection, file loading, CSV parsing (via CSVParsingService),
/// validation, duplicate detection against existing snapshot data, preview row management,
/// and import execution per SPEC Section 4.
@Observable
@MainActor
class ImportViewModel {
  let modelContext: ModelContext
  private let settingsService: SettingsService

  // MARK: - State

  /// Selected import type (Assets or Cash Flows).
  var importType: ImportType = .assets {
    didSet {
      guard importType != oldValue else { return }
      clearLoadedData()
    }
  }

  /// Selected file URL (for display purposes).
  var selectedFileURL: URL?

  /// Display name for a selected file, including files supplied as drop data.
  var selectedFileName: String?

  /// Cached file data from the last successful file load.
  /// Used by the View to re-parse CSV when import settings change,
  /// avoiding re-reads that fail after security-scoped resource access ends.
  var selectedFileData: Data?

  /// Snapshot date for the import (defaults to today).
  var snapshotDate: Date = Date() {
    didSet {
      guard snapshotDate != oldValue else { return }
      revalidate()
      computeCopyForwardPlatforms()
    }
  }

  /// Whether to copy assets from other platforms during import.
  var copyForwardEnabled: Bool = true

  /// Platforms available for copy-forward, computed from prior snapshots.
  var copyForwardPlatforms: [CopyForwardPlatformInfo] = []

  /// How the import-level platform is applied to preview rows.
  var platformApplyMode: PlatformApplyMode = .overrideAll {
    didSet {
      guard platformApplyMode != oldValue else { return }
      rebuildPreviewIfNeeded()
    }
  }

  /// Import-level platform override (nil = use CSV per-row values).
  var selectedPlatform: String? {
    didSet {
      guard selectedPlatform != oldValue else { return }
      rebuildPreviewIfNeeded()
    }
  }

  /// How the import-level category is applied to preview rows.
  var categoryApplyMode: CategoryApplyMode = .overrideAll {
    didSet {
      guard categoryApplyMode != oldValue else { return }
      rebuildPreviewIfNeeded()
    }
  }

  /// Import-level category assignment (nil = uncategorized).
  var selectedCategory: Category? {
    didSet {
      guard selectedCategory?.id != oldValue?.id else { return }
      rebuildPreviewIfNeeded()
    }
  }

  /// Whether existing assets have a mix of categorized and uncategorized states,
  /// making the category apply mode toggle meaningful.
  var hasMixedCategories: Bool = false

  /// Preview rows for asset CSV import.
  var assetPreviewRows: [AssetPreviewRow] = []

  /// Preview rows for cash flow CSV import.
  var cashFlowPreviewRows: [CashFlowPreviewRow] = []

  /// Cached platform options for the import toolbar picker.
  var availablePlatforms: [String] = []

  /// Cached category options for the import toolbar picker.
  var availableCategories: [Category] = []

  /// Validation errors (block import).
  var validationErrors: [CSVError] = []

  /// Validation warnings (allow import with acknowledgment).
  var validationWarnings: [CSVWarning] = []

  /// Error from import execution (e.g., future date).
  var importError: String?

  /// Whether a file has been loaded but not yet imported.
  var hasUnsavedChanges: Bool = false

  /// Snapshot created or updated by the last successful import, for navigation.
  var importedSnapshot: Snapshot?

  /// Parsing errors from the initial CSV load (empty names, unparseable values).
  /// Stored separately so revalidation can preserve them alongside re-computed duplicate errors.
  var parsingErrors: [CSVError] = []

  // MARK: - Column Mapping State

  /// Whether the column mapping sheet should be shown.
  var showColumnMappingSheet: Bool = false

  /// Raw headers from the current file (for the mapping sheet).
  var pendingRawHeaders: [String] = []

  /// Sample rows from the current file (for preview in mapping sheet).
  var pendingSampleRows: [[String]] = []

  /// Partial auto-detect mapping (pre-fills dropdowns).
  var pendingPartialMapping: [CanonicalColumn: Int] = [:]

  // MARK: - Base Parse State (for rebuild without re-parsing)

  /// Base asset rows from the last CSV parse (no platform override applied).
  var baseAssetRows: [AssetCSVRow] = []

  /// Parsing errors from the base parse (excludes within-CSV duplicate errors).
  var baseAssetParsingErrors: [CSVError] = []

  /// Warnings from the base asset parse.
  var baseAssetWarnings: [CSVWarning] = []

  /// Warnings from the base cash flow parse.
  var baseCashFlowWarnings: [CSVWarning] = []

  /// Indices of rows excluded by the user (via minus button).
  var excludedAssetIndices: Set<Int> = []

  // MARK: - Computed Properties

  /// Whether the Import button should be disabled.
  var isImportDisabled: Bool {
    let hasIncludedRows: Bool
    let hasPerRowErrors: Bool
    switch importType {
    case .assets:
      hasIncludedRows = assetPreviewRows.contains { $0.isIncluded }
      hasPerRowErrors = assetPreviewRows.contains {
        $0.isIncluded
          && ($0.duplicateError != nil || $0.snapshotDuplicateError != nil
            || $0.currencyError != nil)
      }

    case .cashFlows:
      hasIncludedRows = cashFlowPreviewRows.contains { $0.isIncluded }
      hasPerRowErrors = cashFlowPreviewRows.contains {
        $0.isIncluded && ($0.duplicateError != nil || $0.snapshotDuplicateError != nil)
      }
    }
    return !hasIncludedRows || !validationErrors.isEmpty || hasPerRowErrors
  }

  // MARK: - Init

  init(modelContext: ModelContext, settingsService: SettingsService? = nil) {
    self.modelContext = modelContext
    let resolvedService = settingsService ?? SettingsService.shared
    self.settingsService = resolvedService

    let defaultPlatform = resolvedService.defaultPlatform
    if !defaultPlatform.isEmpty {
      self.selectedPlatform = defaultPlatform
    }
    refreshPickerOptions()
  }

  // MARK: - File Loading

  /// Loads and parses CSV data based on the current import type.
  ///
  /// If the CSV headers match the expected columns (case-insensitive),
  /// parsing proceeds immediately. Otherwise, column mapping state is
  /// populated and the mapping sheet is shown.
  ///
  /// - Parameter data: Raw CSV file data (UTF-8).
  func loadCSVData(_ data: Data) {
    importError = nil
    selectedFileData = data

    let schema: CSVColumnSchema = importType == .assets ? .asset : .cashFlow
    let headers = CSVParsingService.extractHeaders(from: data)

    // Empty/invalid files bypass mapping and fall through to the existing
    // parser which reports appropriate errors (empty file, no data rows).
    guard !headers.isEmpty else {
      switch importType {
      case .assets: loadAssetCSVData(data)
      case .cashFlows: loadCashFlowCSVData(data)
      }
      hasUnsavedChanges = true
      return
    }

    let detectResult = CSVParsingService.autoDetectMapping(headers: headers, schema: schema)

    switch detectResult {
    case .matched:
      // Headers match — parse immediately using existing flow
      switch importType {
      case .assets: loadAssetCSVData(data)
      case .cashFlows: loadCashFlowCSVData(data)
      }
      hasUnsavedChanges = true

    case .needsUserMapping(let rawHeaders, let partialMap):
      // Headers don't match — show mapping sheet
      pendingRawHeaders = rawHeaders
      pendingSampleRows = CSVParsingService.extractSampleRows(from: data)
      pendingPartialMapping = partialMap
      showColumnMappingSheet = true
    }
  }

  /// Loads a CSV file from a URL.
  func loadFile(_ url: URL) {
    selectedFileURL = url
    selectedFileName = url.lastPathComponent
    selectedFileData = nil
    guard let data = try? Data(contentsOf: url) else {
      reportFileLoadFailure()
      return
    }
    loadCSVData(data)
  }

  /// Loads CSV data supplied by a drag-and-drop provider.
  func loadDroppedData(_ data: Data, fileName: String?) {
    selectedFileURL = nil
    selectedFileName = fileName ?? String(localized: "Dropped CSV", table: "Import")
    loadCSVData(data)
  }

  /// Records a user-visible failure when a dropped or selected file cannot be read.
  func reportFileLoadFailure() {
    selectedFileData = nil
    assetPreviewRows = []
    cashFlowPreviewRows = []
    validationWarnings = []
    parsingErrors = []
    baseAssetRows = []
    baseAssetParsingErrors = []
    baseAssetWarnings = []
    baseCashFlowWarnings = []
    copyForwardPlatforms = []
    validationErrors = [
      CSVError(
        row: 0, column: nil,
        message: String(
          localized: "Could not open file. Please check the file is a valid CSV.",
          table: "Import"))
    ]
    hasUnsavedChanges = false
  }

  // MARK: - Row Removal

  /// Removes (excludes) an asset preview row at the given index.
  func removeAssetPreviewRow(at index: Int) {
    guard index >= 0 && index < assetPreviewRows.count else { return }
    excludedAssetIndices.insert(index)
    assetPreviewRows[index].isIncluded = false
    revalidate()
  }

  /// Removes (excludes) a cash flow preview row at the given index.
  func removeCashFlowPreviewRow(at index: Int) {
    guard index >= 0 && index < cashFlowPreviewRows.count else { return }
    cashFlowPreviewRows[index].isIncluded = false
    revalidate()
  }

  // MARK: - Category Resolution

  /// Resolves a category by name, reusing existing (case-insensitive) or creating new.
  func resolveCategory(name: String) -> Category? {
    modelContext.resolveCategory(name: name)
  }

  // MARK: - Queries

  /// Returns all distinct, non-empty platforms from existing assets.
  func existingPlatforms() -> [String] {
    fetchExistingPlatforms()
  }

  /// Returns all existing categories.
  func existingCategories() -> [Category] {
    fetchExistingCategories()
  }

  /// Refreshes cached picker options outside SwiftUI body evaluation.
  func refreshPickerOptions() {
    availablePlatforms = fetchExistingPlatforms()
    availableCategories = fetchExistingCategories()
  }

  private func fetchExistingPlatforms() -> [String] {
    let descriptor = FetchDescriptor<Asset>()
    let allAssets = (try? modelContext.fetch(descriptor)) ?? []

    let platforms = Set(
      allAssets
        .map { $0.platform }
        .filter { !$0.isEmpty }
    )

    return platforms.sorted()
  }

  private func fetchExistingCategories() -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return (try? modelContext.fetch(descriptor)) ?? []
  }

  // MARK: - Import Execution

  /// Executes the import, creating or updating a snapshot.
  ///
  /// - Returns: The created/updated Snapshot on success, or nil on failure (see `importError`).
  @discardableResult
  func executeImport() -> Snapshot? {
    importError = nil

    // Validate date
    let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)
    let today = Calendar.current.startOfDay(for: Date())

    guard normalizedDate <= today else {
      importError = String(
        localized: "Snapshot date cannot be in the future.", table: "Import")
      return nil
    }

    guard !isImportDisabled else { return nil }

    // Find or create snapshot for this date
    let snapshot = findOrCreateSnapshot(date: normalizedDate)

    switch importType {
    case .assets:
      executeAssetImport(snapshot: snapshot)

    case .cashFlows:
      executeCashFlowImport(snapshot: snapshot)
    }

    hasUnsavedChanges = false
    importedSnapshot = snapshot
    refreshPickerOptions()
    return snapshot
  }

  // MARK: - Reset

  /// Clears all import state.
  func reset() {
    clearLoadedData()
    snapshotDate = Date()
    let defaultPlatform = settingsService.defaultPlatform
    selectedPlatform = defaultPlatform.isEmpty ? nil : defaultPlatform
    selectedCategory = nil
    copyForwardEnabled = true
    importError = nil
    hasUnsavedChanges = false
    importedSnapshot = nil
    refreshPickerOptions()
  }

  // MARK: - Column Mapping

  /// Confirms a user-provided column mapping and parses the pending CSV data.
  func confirmColumnMapping(_ mapping: CSVColumnMapping) {
    showColumnMappingSheet = false
    guard let data = selectedFileData else { return }

    switch importType {
    case .assets:
      loadAssetCSVDataWithMapping(data, mapping: mapping)

    case .cashFlows:
      loadCashFlowCSVDataWithMapping(data, mapping: mapping)
    }

    pendingRawHeaders = []
    pendingSampleRows = []
    pendingPartialMapping = [:]
    hasUnsavedChanges = true
  }

  // MARK: - Copy-Forward Computation

  /// Computes which platforms from prior snapshots can be copied forward.
  ///
  /// Examines the most recent prior snapshot (before `snapshotDate`) and identifies
  /// platforms that are NOT present in the current import's resolved preview rows.
  func computeCopyForwardPlatforms() {
    guard importType == .assets else {
      copyForwardPlatforms = []
      return
    }

    let normalizedDate = Calendar.current.startOfDay(for: snapshotDate)

    // No copy-forward when importing into an existing snapshot
    if SnapshotSummaryService.fetchSnapshot(on: normalizedDate, modelContext: modelContext) != nil {
      copyForwardPlatforms = []
      return
    }

    guard
      let latestPrior = SnapshotSummaryService.fetchLatestSnapshot(
        before: normalizedDate,
        modelContext: modelContext)
    else {
      copyForwardPlatforms = []
      return
    }

    let priorValues = latestPrior.assetValues ?? []

    // Collect platforms from the resolved preview rows.
    // These are the platforms that will have assets in the new snapshot.
    // The preview rows already reflect any import-level platform override
    // (applied during CSV parsing), so no separate handling is needed.
    var snapshotPlatforms = Set<String>()
    for row in assetPreviewRows where row.isIncluded {
      let platform = row.csvRow.platform
      if !platform.isEmpty {
        snapshotPlatforms.insert(platform.lowercased())
      }
    }

    // Group prior snapshot values by platform
    var platformAssets: [String: [SnapshotAssetValue]] = [:]
    for sav in priorValues {
      guard let platform = sav.asset?.platform, !platform.isEmpty else { continue }
      platformAssets[platform, default: []].append(sav)
    }

    // Build copy-forward info for platforms not already in the new snapshot
    var infos: [CopyForwardPlatformInfo] = []
    for (platform, assets) in platformAssets {
      if !snapshotPlatforms.contains(platform.lowercased()) {
        infos.append(
          CopyForwardPlatformInfo(
            platformName: platform,
            assetCount: assets.count,
            sourceSnapshotDate: latestPrior.date,
            isSelected: true
          ))
      }
    }

    copyForwardPlatforms = infos.sorted { $0.platformName < $1.platformName }
  }

  // MARK: - Private: Asset CSV Loading

  private func loadAssetCSVData(_ data: Data) {
    // Parse with no platform override — get base rows
    let result = CSVParsingService.parseAssetCSV(data: data, importPlatform: nil)
    baseAssetRows = result.rows

    // Store parsing-only errors (not within-CSV duplicates, which depend on effective platform)
    let withinCSVDuplicates = CSVParsingService.detectAssetDuplicates(rows: result.rows)
    let duplicateMessages = Set(withinCSVDuplicates.map { $0.message })
    baseAssetParsingErrors = result.errors.filter { !duplicateMessages.contains($0.message) }
    baseAssetWarnings = result.warnings

    excludedAssetIndices = []
    cashFlowPreviewRows = []

    rebuildAssetPreviewRows()
  }

  /// Rebuilds asset preview rows from base parse data, applying current
  /// platform/category settings and preserving exclusion state.
  func rebuildAssetPreviewRows() {
    let assetLookup = AssetResolutionLookup(assets: fetchAllAssets())
    var hasAnyCategorized = false
    var hasAnyUncategorized = false

    assetPreviewRows = baseAssetRows.enumerated().map { index, baseRow in
      let effectiveRow = effectiveAssetRow(baseRow: baseRow)
      let existingAsset = assetLookup.asset(
        named: effectiveRow.assetName, platform: effectiveRow.platform)

      let effectiveCurrency: String
      if !effectiveRow.currency.isEmpty {
        effectiveCurrency = effectiveRow.currency
      } else if let existing = existingAsset, !existing.currency.isEmpty {
        effectiveCurrency = existing.currency
      } else {
        effectiveCurrency = ""
      }

      let existingCategoryName = existingAsset?.category?.name
      let effectiveCategory = effectiveCategoryName(existingCategoryName: existingCategoryName)

      // Track mixed state for the toggle
      if existingCategoryName != nil {
        hasAnyCategorized = true
      } else {
        hasAnyUncategorized = true
      }

      let currError = currencyValidationError(for: effectiveRow)
      return AssetPreviewRow(
        id: UUID(),
        csvRow: effectiveRow,
        isIncluded: !excludedAssetIndices.contains(index),
        categoryWarning: categoryWarning(
          for: effectiveRow, existingAsset: existingAsset),
        currencyWarning: currError == nil
          ? currencyWarning(for: effectiveRow, existingAsset: existingAsset) : nil,
        currencyError: currError,
        effectiveCurrency: effectiveCurrency,
        effectiveCategory: effectiveCategory,
        marketValueWarning: marketValueWarning(for: effectiveRow)
      )
    }

    hasMixedCategories = hasAnyCategorized && hasAnyUncategorized

    parsingErrors = baseAssetParsingErrors
    validationWarnings = baseAssetWarnings
    revalidate()
    computeCopyForwardPlatforms()
  }

  /// Triggers a preview rebuild when base rows have been loaded.
  private func rebuildPreviewIfNeeded() {
    guard !baseAssetRows.isEmpty else { return }
    rebuildAssetPreviewRows()
  }

  private func currencyValidationError(for row: AssetCSVRow) -> String? {
    let code = row.currency
    guard !code.isEmpty else { return nil }
    if CurrencyService.shared.currency(for: code) == nil {
      return String(
        localized: "Unsupported currency '\(code)'.",
        table: "Import")
    }
    return nil
  }

  private func currencyWarning(for row: AssetCSVRow, existingAsset: Asset?) -> String? {
    let csvCurrency = row.currency
    guard !csvCurrency.isEmpty else { return nil }

    guard let existingAsset else { return nil }
    let existingCurrency = existingAsset.currency
    guard !existingCurrency.isEmpty else { return nil }

    if existingCurrency != csvCurrency {
      return String(
        localized:
          "This asset's currency is currently '\(existingCurrency)'. Importing will change it to '\(csvCurrency)'.",
        table: "Import")
    }

    return nil
  }

  /// Computes the effective category name for a row based on apply mode and existing state.
  private func effectiveCategoryName(existingCategoryName: String?) -> String {
    guard let selected = selectedCategory else {
      return existingCategoryName ?? ""
    }
    switch categoryApplyMode {
    case .overrideAll:
      return selected.name

    case .fillEmptyOnly:
      return existingCategoryName ?? selected.name
    }
  }

  private func marketValueWarning(for row: AssetCSVRow) -> String? {
    if row.marketValue == 0 {
      return String(
        localized: "Market value is zero for '\(row.assetName)'.",
        table: "Import")
    } else if row.marketValue < 0 {
      return String(
        localized: "Market value is negative for '\(row.assetName)'.",
        table: "Import")
    }
    return nil
  }

  private func cashFlowAmountWarning(for row: CashFlowCSVRow) -> String? {
    if row.amount == 0 {
      return String(
        localized: "Amount is zero for '\(row.description)'.",
        table: "Import")
    }
    return nil
  }

  private func categoryWarning(for row: AssetCSVRow, existingAsset: Asset?) -> String? {
    guard let selectedCategory = selectedCategory else { return nil }
    guard let existingAsset else { return nil }
    guard let existingCategory = existingAsset.category else { return nil }

    // In fillEmptyOnly mode, assets that already have a category won't be overridden
    if categoryApplyMode == .fillEmptyOnly {
      return nil
    }

    if existingCategory.name.lowercased() != selectedCategory.name.lowercased() {
      return String(
        localized:
          "This asset is currently assigned to \(existingCategory.name). Importing will reassign it to \(selectedCategory.name).",
        table: "Import")
    }

    return nil
  }

  /// Resolves the effective platform for a base row based on the current
  /// platform selection and apply mode.
  private func effectiveAssetRow(baseRow: AssetCSVRow) -> AssetCSVRow {
    guard let platform = selectedPlatform,
      platformApplyMode == .overrideAll || baseRow.platform.isEmpty
    else { return baseRow }

    return AssetCSVRow(
      assetName: baseRow.assetName, marketValue: baseRow.marketValue, platform: platform,
      currency: baseRow.currency)
  }

  /// Whether the loaded CSV has a mix of empty and non-empty platform values,
  /// making the apply mode toggle meaningful.
  var hasMixedPlatforms: Bool {
    let hasEmpty = baseAssetRows.contains { $0.platform.isEmpty }
    let hasNonEmpty = baseAssetRows.contains { !$0.platform.isEmpty }
    return hasEmpty && hasNonEmpty
  }

  // MARK: - Private: Cash Flow CSV Loading

  private func loadCashFlowCSVData(_ data: Data) {
    let result = CSVParsingService.parseCashFlowCSV(data: data)

    cashFlowPreviewRows = result.rows.map { row in
      CashFlowPreviewRow(
        id: UUID(),
        csvRow: row,
        isIncluded: true,
        amountWarning: cashFlowAmountWarning(for: row)
      )
    }

    assetPreviewRows = []

    // Separate parsing errors from duplicate errors
    let withinCSVDuplicates = CSVParsingService.detectCashFlowDuplicates(rows: result.rows)
    let duplicateMessages = Set(withinCSVDuplicates.map { $0.message })
    parsingErrors = result.errors.filter { !duplicateMessages.contains($0.message) }

    baseCashFlowWarnings = result.warnings
    revalidate()
  }

  // MARK: - Private: Mapping-Based CSV Loading

  private func loadAssetCSVDataWithMapping(_ data: Data, mapping: CSVColumnMapping) {
    let result = CSVParsingService.parseAssetCSV(
      data: data, mapping: mapping, importPlatform: nil)
    baseAssetRows = result.rows

    let withinCSVDuplicates = CSVParsingService.detectAssetDuplicates(rows: result.rows)
    let duplicateMessages = Set(withinCSVDuplicates.map { $0.message })
    baseAssetParsingErrors = result.errors.filter { !duplicateMessages.contains($0.message) }
    baseAssetWarnings = result.warnings

    excludedAssetIndices = []
    cashFlowPreviewRows = []

    rebuildAssetPreviewRows()
  }

  private func loadCashFlowCSVDataWithMapping(_ data: Data, mapping: CSVColumnMapping) {
    let result = CSVParsingService.parseCashFlowCSV(data: data, mapping: mapping)

    cashFlowPreviewRows = result.rows.map { row in
      CashFlowPreviewRow(
        id: UUID(),
        csvRow: row,
        isIncluded: true,
        amountWarning: cashFlowAmountWarning(for: row)
      )
    }

    assetPreviewRows = []

    let withinCSVDuplicates = CSVParsingService.detectCashFlowDuplicates(rows: result.rows)
    let duplicateMessages = Set(withinCSVDuplicates.map { $0.message })
    parsingErrors = result.errors.filter { !duplicateMessages.contains($0.message) }

    baseCashFlowWarnings = result.warnings
    revalidate()
  }

}
