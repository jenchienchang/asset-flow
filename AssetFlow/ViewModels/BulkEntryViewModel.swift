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

@Observable
@MainActor
final class BulkEntryViewModel {

  var snapshotDate: Date
  private(set) var rows: [BulkEntryRow]
  private(set) var cashFlowRows: [BulkEntryCashFlowRow] = []
  private(set) var toolbarStats = BulkEntryToolbarStats()
  var savedSnapshot: Snapshot?
  var pendingFocusRowID: UUID?
  var pendingCashFlowFocusRowID: UUID?

  // MARK: - Cash Flow Column Mapping State

  var showCashFlowColumnMappingSheet: Bool = false
  var pendingCashFlowRawHeaders: [String] = []
  var pendingCashFlowSampleRows: [[String]] = []
  var pendingCashFlowPartialMapping: [CanonicalColumn: Int] = [:]
  var pendingCashFlowCSVData: Data?
  var lastImportFeedback: CSVImportFeedback?

  private let modelContext: ModelContext

  // MARK: - Structural Caches (observation-ignored)

  @ObservationIgnored private var _platformGrouping: [(platform: String, rowIndices: [Int])] = []
  @ObservationIgnored private var _rowIDToIndex: [UUID: Int] = [:]
  @ObservationIgnored private var _cashFlowRowIDToIndex: [UUID: Int] = [:]

  // MARK: - Pending Commit Buffers (observation-ignored)

  /// Local text field values written on every keystroke.  The parent section's
  /// `onChange(of: focusedRowID)` calls `flushRowCommit` / `flushCashFlowCommit`
  /// to push pending values into `rows` / `cashFlowRows` in a single mutation.
  @ObservationIgnored private var _pendingValues: [UUID: String] = [:]
  @ObservationIgnored private var _pendingNames: [UUID: String] = [:]
  @ObservationIgnored private var _pendingCashFlowAmounts: [UUID: String] = [:]
  @ObservationIgnored private var _pendingCashFlowDescriptions: [UUID: String] = [:]

  var platformGroups: [(platform: String, rows: [BulkEntryRow])] {
    _platformGrouping.map { group in
      (platform: group.platform, rows: group.rowIndices.map { rows[$0] })
    }
  }

  var cashFlowCount: Int {
    cashFlowRows.filter(\.isIncluded).count
  }

  var includedCashFlowNetByCurrency: [(currency: String, total: Decimal)] {
    var totals: [String: Decimal] = [:]
    for row in cashFlowRows where row.isIncluded {
      guard let amount = row.amount else { continue }
      totals[row.currency, default: 0] += amount
    }
    return totals.sorted { $0.key < $1.key }.map { (currency: $0.key, total: $0.value) }
  }

  // MARK: - Column Mapping State

  var showColumnMappingSheet: Bool = false
  var pendingRawHeaders: [String] = []
  var pendingSampleRows: [[String]] = []
  var pendingPartialMapping: [CanonicalColumn: Int] = [:]
  var pendingCSVData: Data?
  var pendingCSVPlatform: String = ""

  var hasUnsavedChanges: Bool {
    rows.contains { !$0.newValueText.isEmpty }
      || rows.contains { !$0.isIncluded }
      || rows.contains { $0.source == .manualNew }
      || !cashFlowRows.isEmpty
  }

  init(modelContext: ModelContext, date: Date) {
    self.modelContext = modelContext
    self.snapshotDate = Calendar.current.startOfDay(for: date)
    self.rows = []
    loadRowsFromLatestSnapshot()
    rebuildStructuralCaches()
    recomputeToolbarStats()
  }

  // MARK: - Pending Buffer Setters (called from row views on every keystroke)

  func setPendingValue(_ rowID: UUID, to value: String) {
    _pendingValues[rowID] = value
  }

  func setPendingName(_ rowID: UUID, to name: String) {
    _pendingNames[rowID] = name
  }

  func setPendingCashFlowAmount(_ rowID: UUID, to amount: String) {
    _pendingCashFlowAmounts[rowID] = amount
  }

  func setPendingCashFlowDescription(_ rowID: UUID, to description: String) {
    _pendingCashFlowDescriptions[rowID] = description
  }

  /// Flushes any pending local values for the given asset row into `rows`.
  /// Called by the parent section's `onChange(of: focusedRowID)` when focus
  /// leaves a row.
  func flushRowCommit(for rowID: UUID) {
    if let value = _pendingValues[rowID] {
      updateRowValue(rowID, to: value)
    }
    if let name = _pendingNames[rowID] {
      updateRowAssetName(rowID, to: name)
    }
  }

  /// Flushes any pending local values for the given cash flow row.
  func flushCashFlowCommit(for rowID: UUID) {
    if let amount = _pendingCashFlowAmounts[rowID] {
      updateCashFlowAmount(rowID, to: amount)
    }
    if let description = _pendingCashFlowDescriptions[rowID] {
      updateCashFlowDescription(rowID, to: description)
    }
  }

  // MARK: - Centralized Row Mutations

  func updateRowValue(_ rowID: UUID, to newValueText: String) {
    _pendingValues.removeValue(forKey: rowID)
    guard let index = _rowIDToIndex[rowID],
      rows[index].newValueText != newValueText
    else { return }
    let old = rows[index]
    rows[index].newValueText = newValueText
    applyAssetRowDelta(old: old, new: rows[index])
  }

  func fillWithPreviousValue(_ rowID: UUID) {
    guard let index = _rowIDToIndex[rowID],
      let previousValue = rows[index].previousValue
    else { return }
    updateRowValue(rowID, to: "\(previousValue)")
  }

  func updateRowAssetName(_ rowID: UUID, to name: String) {
    _pendingNames.removeValue(forKey: rowID)
    guard let index = _rowIDToIndex[rowID],
      rows[index].assetName != name
    else { return }
    let old = rows[index]
    rows[index].assetName = name
    applyAssetRowDelta(old: old, new: rows[index])
  }

  /// Currency does not affect any toolbar stat contribution — no delta update needed.
  func updateRowCurrency(_ rowID: UUID, to currency: String) {
    guard let index = _rowIDToIndex[rowID],
      rows[index].currency != currency
    else { return }
    rows[index].currency = currency
  }

  func updateRowCategoryName(_ rowID: UUID, to name: String?) {
    guard let index = _rowIDToIndex[rowID],
      rows[index].categoryName != name
    else { return }
    rows[index].categoryName = name
  }

  // MARK: - Centralized Cash Flow Mutations

  func updateCashFlowDescription(_ rowID: UUID, to description: String) {
    _pendingCashFlowDescriptions.removeValue(forKey: rowID)
    guard let index = _cashFlowRowIDToIndex[rowID],
      cashFlowRows[index].cashFlowDescription != description
    else { return }
    let old = cashFlowRows[index]
    cashFlowRows[index].cashFlowDescription = description
    applyCashFlowRowDelta(old: old, new: cashFlowRows[index])
  }

  func updateCashFlowAmount(_ rowID: UUID, to amountText: String) {
    _pendingCashFlowAmounts.removeValue(forKey: rowID)
    guard let index = _cashFlowRowIDToIndex[rowID],
      cashFlowRows[index].amountText != amountText
    else { return }
    let old = cashFlowRows[index]
    cashFlowRows[index].amountText = amountText
    applyCashFlowRowDelta(old: old, new: cashFlowRows[index])
  }

  /// Currency does not affect any toolbar stat contribution — no delta update needed.
  func updateCashFlowCurrency(_ rowID: UUID, to currency: String) {
    guard let index = _cashFlowRowIDToIndex[rowID],
      cashFlowRows[index].currency != currency
    else { return }
    cashFlowRows[index].currency = currency
  }

  /// Returns the ID of the next included row in visual (platform-grouped) order
  /// after the row with the given ID, or `nil` if already at the last included row.
  func nextFocusRowID(after currentRowID: UUID) -> UUID? {
    var found = false
    for group in _platformGrouping {
      for index in group.rowIndices where rows[index].isIncluded {
        if found { return rows[index].id }
        if rows[index].id == currentRowID { found = true }
      }
    }
    return nil
  }

  func advanceFocus(from currentRowID: UUID) {
    pendingFocusRowID = nextFocusRowID(after: currentRowID)
  }

  func nextCashFlowFocusRowID(after currentRowID: UUID) -> UUID? {
    var found = false
    for row in cashFlowRows where row.isIncluded {
      if found { return row.id }
      if row.id == currentRowID { found = true }
    }
    return nil
  }

  func advanceCashFlowFocus(from currentRowID: UUID) {
    pendingCashFlowFocusRowID = nextCashFlowFocusRowID(after: currentRowID)
  }

  func toggleInclude(rowID: UUID) {
    guard let index = _rowIDToIndex[rowID] else { return }
    let old = rows[index]
    rows[index].isIncluded.toggle()
    applyAssetRowDelta(old: old, new: rows[index])
  }

  @discardableResult
  func addManualRow(forPlatform platform: String) -> UUID {
    let row = BulkEntryRow(
      id: UUID(),
      asset: nil,
      assetName: "",
      platform: platform,
      currency: SettingsService.shared.mainCurrency,
      previousValue: nil,
      newValueText: "",
      isIncluded: true,
      source: .manualNew,
      categoryName: nil
    )
    rows.append(row)
    rebuildStructuralCaches()
    addAssetRowToStats(row)
    return row.id
  }

  @discardableResult
  func addPlatform(name: String) -> UUID? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    let existing = Set(rows.map { $0.platform.normalizedForIdentity })
    guard !existing.contains(trimmed.normalizedForIdentity) else { return nil }
    return addManualRow(forPlatform: trimmed)
  }

  func removeManualRow(rowID: UUID) {
    if let row = rows.first(where: { $0.id == rowID && $0.source == .manualNew }) {
      removeAssetRowFromStats(row)
    }
    _pendingValues.removeValue(forKey: rowID)
    _pendingNames.removeValue(forKey: rowID)
    rows.removeAll { $0.id == rowID && $0.source == .manualNew }
    rebuildStructuralCaches()
  }

  // MARK: - Cash Flow Row Management

  @discardableResult
  func addManualCashFlowRow() -> UUID {
    let row = BulkEntryCashFlowRow(
      id: UUID(), cashFlowDescription: "", amountText: "",
      currency: SettingsService.shared.mainCurrency,
      isIncluded: true, source: .manualNew)
    cashFlowRows.append(row)
    rebuildStructuralCaches()
    addCashFlowRowToStats(row)
    pendingCashFlowFocusRowID = row.id
    return row.id
  }

  func removeCashFlowRow(rowID: UUID) {
    if let row = cashFlowRows.first(where: { $0.id == rowID && $0.source == .manualNew }) {
      removeCashFlowRowFromStats(row)
    }
    _pendingCashFlowAmounts.removeValue(forKey: rowID)
    _pendingCashFlowDescriptions.removeValue(forKey: rowID)
    cashFlowRows.removeAll { $0.id == rowID && $0.source == .manualNew }
    rebuildStructuralCaches()
  }

  func toggleCashFlowInclude(rowID: UUID) {
    guard let index = _cashFlowRowIDToIndex[rowID] else { return }
    let old = cashFlowRows[index]
    cashFlowRows[index].isIncluded.toggle()
    applyCashFlowRowDelta(old: old, new: cashFlowRows[index])
  }

  // MARK: - Cash Flow CSV Import

  @discardableResult
  func importCashFlowCSV(data: Data) -> CashFlowCSVImportResult {
    let parseResult = CSVParsingService.parseCashFlowCSV(data: data)
    let result = importCashFlowCSVFromParsedRows(parseResult)
    lastImportFeedback = result.feedback
    return result
  }

  func loadCashFlowCSVForMapping(data: Data) {
    lastImportFeedback = nil
    let headers = CSVParsingService.extractHeaders(from: data)
    guard !headers.isEmpty else {
      lastImportFeedback = importCashFlowCSV(data: data).feedback
      return
    }
    let detectResult = CSVParsingService.autoDetectMapping(headers: headers, schema: .cashFlow)
    switch detectResult {
    case .matched:
      lastImportFeedback = importCashFlowCSV(data: data).feedback

    case .needsUserMapping(let rawHeaders, let partialMap):
      pendingCashFlowCSVData = data
      pendingCashFlowRawHeaders = rawHeaders
      pendingCashFlowSampleRows = CSVParsingService.extractSampleRows(from: data, count: nil)
      pendingCashFlowPartialMapping = partialMap
      showCashFlowColumnMappingSheet = true
    }
  }

  @discardableResult
  func confirmCashFlowColumnMapping(_ mapping: CSVColumnMapping) -> CashFlowCSVImportResult? {
    showCashFlowColumnMappingSheet = false
    guard let data = pendingCashFlowCSVData else { return nil }
    let parseResult = CSVParsingService.parseCashFlowCSV(data: data, mapping: mapping)
    let result = importCashFlowCSVFromParsedRows(parseResult)
    lastImportFeedback = result.feedback
    pendingCashFlowCSVData = nil
    pendingCashFlowRawHeaders = []
    pendingCashFlowSampleRows = []
    pendingCashFlowPartialMapping = [:]
    return result
  }

  /// Stores a file-loading failure for the view to present to the user.
  func reportImportFailure(_ message: String) {
    lastImportFeedback = .failure(message)
  }

  func saveSnapshot() throws -> Snapshot {
    let includedRows = rows.filter(\.isIncluded)
    guard !includedRows.isEmpty else {
      throw SnapshotError.noAssetsIncluded
    }

    // Guard against duplicate date (race condition: another snapshot may have
    // been created for this date while the user was editing values)
    let targetDate = snapshotDate
    var dateCheckDescriptor = FetchDescriptor<Snapshot>(
      predicate: #Predicate { $0.date == targetDate }
    )
    dateCheckDescriptor.fetchLimit = 1
    if ((try? modelContext.fetch(dateCheckDescriptor)) ?? []).first != nil {
      throw SnapshotError.dateAlreadyExists(snapshotDate)
    }

    // Validate asset name uniqueness within each platform before creating anything
    // (avoids expensive normalizedForIdentity on every keystroke during editing)
    for (platform, platformRows) in Dictionary(grouping: includedRows, by: \.platform) {
      var seenNames = [String: String]()
      for row in platformRows {
        let key = row.assetName.normalizedForIdentity
        guard !key.isEmpty else { continue }
        if seenNames[key] != nil {
          throw SnapshotError.duplicateAssetName(row.assetName, platform)
        }
        seenNames[key] = row.assetName
      }
    }

    // Validate cash flow description uniqueness before creating anything
    // (avoids expensive normalizedForIdentity on every keystroke during editing)
    let includedCashFlows = cashFlowRows.filter(\.isIncluded)
    var seenDescriptions = [String: String]()
    for cfRow in includedCashFlows {
      let key = cfRow.cashFlowDescription.normalizedForIdentity
      if let existing = seenDescriptions[key] {
        throw SnapshotError.duplicateCashFlowDescription(existing)
      }
      seenDescriptions[key] = cfRow.cashFlowDescription
    }

    let hasNewAssets = includedRows.contains { $0.asset == nil }
    let existingAssets: [Asset]
    if hasNewAssets {
      let assetDescriptor = FetchDescriptor<Asset>()
      existingAssets = (try? modelContext.fetch(assetDescriptor)) ?? []
    } else {
      existingAssets = []
    }
    var assetLookup = AssetResolutionLookup(
      assets: existingAssets)

    let hasNewAssetCategories = includedRows.contains { row in
      guard row.asset == nil, let categoryName = row.categoryName else { return false }
      return !categoryName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var categoryLookup: CategoryResolutionLookup
    if hasNewAssetCategories {
      let categoryDescriptor = FetchDescriptor<Category>()
      let categories = (try? modelContext.fetch(categoryDescriptor)) ?? []
      categoryLookup = CategoryResolutionLookup(categories: categories)
    } else {
      categoryLookup = CategoryResolutionLookup(categories: [])
    }

    let snapshot = Snapshot(date: snapshotDate)
    modelContext.insert(snapshot)

    for row in includedRows {
      let asset: Asset
      if let existingAsset = row.asset {
        asset = existingAsset
      } else {
        asset = assetLookup.resolve(
          name: row.assetName, platform: row.platform, in: modelContext)
        asset.currency = row.currency
        if let categoryName = row.categoryName?.trimmingCharacters(in: .whitespaces),
          !categoryName.isEmpty
        {
          asset.category = categoryLookup.resolve(name: categoryName, in: modelContext)
        }
      }

      let marketValue = row.newValue ?? Decimal(0)
      let sav = SnapshotAssetValue(marketValue: marketValue)
      sav.snapshot = snapshot
      sav.asset = asset
      modelContext.insert(sav)
    }

    for cfRow in includedCashFlows {
      let amount = cfRow.amount ?? Decimal(0)
      let operation = CashFlowOperation(
        cashFlowDescription: cfRow.cashFlowDescription, amount: amount)
      operation.currency = cfRow.currency
      operation.snapshot = snapshot
      modelContext.insert(operation)
    }

    savedSnapshot = snapshot
    return snapshot
  }

  @discardableResult
  func importCSV(data: Data, forPlatform platform: String) -> CSVImportResult {
    let result = CSVParsingService.parseAssetCSV(data: data, importPlatform: nil)
    let importResult = importCSVFromParsedRows(result, forPlatform: platform)
    lastImportFeedback = importResult.feedback
    return importResult
  }

  // MARK: - Column Mapping

  /// Loads CSV data with auto-detection. Shows mapping sheet if headers don't match.
  ///
  /// If headers match, calls `importCSV` directly. Otherwise, populates
  /// mapping state and sets `showColumnMappingSheet = true`.
  func loadCSVForMapping(data: Data, forPlatform platform: String) {
    lastImportFeedback = nil
    let headers = CSVParsingService.extractHeaders(from: data)

    // Empty/invalid files — import directly to get proper error reporting
    guard !headers.isEmpty else {
      lastImportFeedback = importCSV(data: data, forPlatform: platform).feedback
      return
    }

    let detectResult = CSVParsingService.autoDetectMapping(
      headers: headers, schema: .assetWithoutPlatform)

    switch detectResult {
    case .matched:
      lastImportFeedback = importCSV(data: data, forPlatform: platform).feedback

    case .needsUserMapping(let rawHeaders, let partialMap):
      pendingCSVData = data
      pendingCSVPlatform = platform
      pendingRawHeaders = rawHeaders
      pendingSampleRows = CSVParsingService.extractSampleRows(from: data, count: nil)
      pendingPartialMapping = partialMap
      showColumnMappingSheet = true
    }
  }

  /// Confirms a user-provided column mapping and imports the pending CSV data.
  @discardableResult
  func confirmColumnMapping(_ mapping: CSVColumnMapping) -> CSVImportResult? {
    showColumnMappingSheet = false
    guard let data = pendingCSVData else { return nil }
    let platform = pendingCSVPlatform

    let parseResult = CSVParsingService.parseAssetCSV(
      data: data, mapping: mapping, importPlatform: nil)
    let result = importCSVFromParsedRows(parseResult, forPlatform: platform)
    lastImportFeedback = result.feedback

    pendingCSVData = nil
    pendingCSVPlatform = ""
    pendingRawHeaders = []
    pendingSampleRows = []
    pendingPartialMapping = [:]

    return result
  }

  /// Imports already-parsed CSV rows into the bulk entry rows.
  private func importCSVFromParsedRows(
    _ parseResult: CSVParseResult<AssetCSVRow>,
    forPlatform platform: String
  ) -> CSVImportResult {
    let parserWarnings = parseResult.warnings.map(\.message)
    let resolved = CSVParsingService.resolveAssetRowsForPlatform(
      rows: parseResult.rows, platform: platform)
    let duplicateErrors = CSVParsingService.detectAssetDuplicates(rows: resolved.rows)
    let errors = (parseResult.parsingErrors + duplicateErrors).map(\.message)

    // Any parser or effective duplicate error rejects the replacement before
    // existing CSV values are changed or rows are applied.
    guard errors.isEmpty else {
      return CSVImportResult(
        matchedCount: 0,
        newCount: 0,
        errors: errors,
        parserWarnings: parserWarnings,
        platformMismatches: resolved.mismatches,
        currencyMismatches: [])
    }

    // Clear previous CSV values for this platform
    for index in rows.indices
    where rows[index].platform == platform && rows[index].source == .csv {
      if rows[index].asset != nil {
        rows[index].newValueText = ""
        rows[index].source = .manual
      }
    }
    rows.removeAll { $0.platform == platform && $0.source == .csv && $0.asset == nil }

    let mainCurrency = SettingsService.shared.mainCurrency

    // Pre-build lookup: normalizedName → row index for the target platform.
    // Avoids O(m×n) repeated normalization inside the CSV row loop.
    var nameIndex: [String: Int] = [:]
    for (idx, row) in rows.enumerated() where row.platform == platform {
      nameIndex[row.assetName.normalizedForIdentity] = idx
    }

    var matchedCount = 0
    var newCount = 0
    var currencyMismatches: [String] = []

    for csvRow in resolved.rows {
      let normalizedCSVName = csvRow.assetName.normalizedForIdentity
      if let index = nameIndex[normalizedCSVName] {
        if !csvRow.currency.isEmpty,
          csvRow.currency.uppercased() != rows[index].currency.uppercased()
        {
          currencyMismatches.append(csvRow.assetName)
          continue
        }
        rows[index].newValueText = "\(csvRow.marketValue)"
        rows[index].source = .csv
        matchedCount += 1
      } else {
        let newRow = BulkEntryRow(
          id: UUID(),
          asset: nil,
          assetName: csvRow.assetName,
          platform: platform,
          currency: csvRow.currency.isEmpty ? mainCurrency : csvRow.currency,
          previousValue: nil,
          newValueText: "\(csvRow.marketValue)",
          isIncluded: true,
          source: .csv,
          categoryName: nil
        )
        nameIndex[normalizedCSVName] = rows.count
        rows.append(newRow)
        newCount += 1
      }
    }

    rebuildStructuralCaches()
    recomputeToolbarStats()
    return CSVImportResult(
      matchedCount: matchedCount,
      newCount: newCount,
      errors: errors,
      parserWarnings: parserWarnings,
      platformMismatches: resolved.mismatches,
      currencyMismatches: currencyMismatches
    )
  }

  // MARK: - Private

  private func importCashFlowCSVFromParsedRows(
    _ parseResult: CSVParseResult<CashFlowCSVRow>
  ) -> CashFlowCSVImportResult {
    let errors = parseResult.errors.map(\.message)
    let parserWarnings = parseResult.warnings.map(\.message)

    // Any parser error rejects the replacement before existing CSV rows are
    // changed, so a mixed-validity file cannot partially update the import.
    guard !parseResult.hasErrors else {
      return CashFlowCSVImportResult(
        matchedCount: 0, newCount: 0,
        errors: errors, parserWarnings: parserWarnings)
    }

    // Clear previous CSV cash flow rows: revert CSV-sourced to manual, remove empty ones
    for index in cashFlowRows.indices where cashFlowRows[index].source == .csv {
      cashFlowRows[index].amountText = ""
      cashFlowRows[index].source = .manualNew
    }
    cashFlowRows.removeAll {
      $0.source == .manualNew && $0.cashFlowDescription.trimmingCharacters(in: .whitespaces).isEmpty
        && $0.amountText.isEmpty
    }

    let mainCurrency = SettingsService.shared.mainCurrency

    // Pre-build lookup: normalizedDescription → row index.
    // Avoids O(m×c) repeated normalization inside the CSV row loop.
    var descIndex: [String: Int] = [:]
    for (idx, row) in cashFlowRows.enumerated() {
      descIndex[row.cashFlowDescription.normalizedForIdentity] = idx
    }

    var matchedCount = 0
    var newCount = 0

    for csvRow in parseResult.rows {
      let normalizedDesc = csvRow.description.normalizedForIdentity
      if let index = descIndex[normalizedDesc] {
        cashFlowRows[index].amountText = "\(csvRow.amount)"
        cashFlowRows[index].source = .csv
        if !csvRow.currency.isEmpty {
          cashFlowRows[index].currency = csvRow.currency
        }
        matchedCount += 1
      } else {
        let newRow = BulkEntryCashFlowRow(
          id: UUID(), cashFlowDescription: csvRow.description,
          amountText: "\(csvRow.amount)",
          currency: csvRow.currency.isEmpty ? mainCurrency : csvRow.currency,
          isIncluded: true, source: .csv)
        descIndex[normalizedDesc] = cashFlowRows.count
        cashFlowRows.append(newRow)
        newCount += 1
      }
    }

    rebuildStructuralCaches()
    recomputeToolbarStats()
    return CashFlowCSVImportResult(
      matchedCount: matchedCount, newCount: newCount,
      errors: errors, parserWarnings: parserWarnings)
  }

  private func loadRowsFromLatestSnapshot() {
    let targetDate = snapshotDate
    guard
      let latestBefore = SnapshotSummaryService.fetchLatestSnapshot(
        before: targetDate,
        modelContext: modelContext),
      let assetValues = latestBefore.assetValues
    else { return }

    rows =
      assetValues.compactMap { sav in
        guard let asset = sav.asset else { return nil }
        // Intentionally uses asset.id (not UUID()) for stable identity across
        // SwiftUI re-renders. Collision with CSV-imported rows (which use UUID())
        // cannot occur because importCSV() matches by normalizedName within the
        // platform group before deciding match vs. new row.
        return BulkEntryRow(
          id: asset.id,
          asset: asset,
          assetName: asset.name,
          platform: asset.platform,
          currency: asset.currency,
          previousValue: sav.marketValue,
          newValueText: "",
          isIncluded: true,
          source: .manual,
          categoryName: nil
        )
      }.sorted { ($0.platform, $0.assetName) < ($1.platform, $1.assetName) }
  }

  // MARK: - Structural Caches Maintenance

  private func rebuildStructuralCaches() {
    let grouped = Dictionary(grouping: rows.indices, by: { rows[$0].platform })
    _platformGrouping = grouped.keys.sorted().map { platform in
      (platform: platform, rowIndices: grouped[platform]!)
    }
    _rowIDToIndex = Dictionary(
      uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
    _cashFlowRowIDToIndex = Dictionary(
      uniqueKeysWithValues: cashFlowRows.enumerated().map { ($1.id, $0) })
  }

  // MARK: - Toolbar Stats Maintenance

  private func recomputeToolbarStats() {
    var stats = BulkEntryToolbarStats()
    for row in rows {
      if row.isIncluded {
        stats.includedCount += 1
        if row.isUpdated { stats.updatedCount += 1 }
        if row.isPending { stats.pendingCount += 1 }
        if row.hasZeroValueError { stats.zeroValueCount += 1 }
        if row.hasEmptyName { stats.invalidNewRowCount += 1 }
        if row.hasValidationError { stats.validationErrorCount += 1 }
      } else {
        stats.excludedCount += 1
      }
    }
    for cfRow in cashFlowRows {
      if cfRow.hasEmptyAmount { stats.emptyCashFlowAmountCount += 1 }
      guard cfRow.isIncluded else { continue }
      if cfRow.hasValidationError { stats.cashFlowValidationErrorCount += 1 }
      if cfRow.hasEmptyDescription { stats.emptyCashFlowDescriptionCount += 1 }
    }
    toolbarStats = stats
  }

  private static func assetRowContribution(_ row: BulkEntryRow) -> BulkEntryToolbarStats {
    var c = BulkEntryToolbarStats()
    if row.isIncluded {
      c.includedCount = 1
      if row.isUpdated { c.updatedCount = 1 }
      if row.isPending { c.pendingCount = 1 }
      if row.hasZeroValueError { c.zeroValueCount = 1 }
      if row.hasEmptyName { c.invalidNewRowCount = 1 }
      if row.hasValidationError { c.validationErrorCount = 1 }
    } else {
      c.excludedCount = 1
    }
    return c
  }

  private static func cashFlowRowContribution(
    _ row: BulkEntryCashFlowRow
  ) -> BulkEntryToolbarStats {
    var c = BulkEntryToolbarStats()
    if row.hasEmptyAmount { c.emptyCashFlowAmountCount = 1 }
    guard row.isIncluded else { return c }
    if row.hasValidationError { c.cashFlowValidationErrorCount = 1 }
    if row.hasEmptyDescription { c.emptyCashFlowDescriptionCount = 1 }
    return c
  }

  private func applyAssetRowDelta(old: BulkEntryRow, new: BulkEntryRow) {
    applyStatsDelta(
      oldContribution: Self.assetRowContribution(old),
      newContribution: Self.assetRowContribution(new))
  }

  private func applyCashFlowRowDelta(
    old: BulkEntryCashFlowRow, new: BulkEntryCashFlowRow
  ) {
    applyStatsDelta(
      oldContribution: Self.cashFlowRowContribution(old),
      newContribution: Self.cashFlowRowContribution(new))
  }

  private func applyStatsDelta(
    oldContribution oldC: BulkEntryToolbarStats,
    newContribution newC: BulkEntryToolbarStats
  ) {
    var stats = toolbarStats
    stats.updatedCount += newC.updatedCount - oldC.updatedCount
    stats.pendingCount += newC.pendingCount - oldC.pendingCount
    stats.excludedCount += newC.excludedCount - oldC.excludedCount
    stats.includedCount += newC.includedCount - oldC.includedCount
    stats.zeroValueCount += newC.zeroValueCount - oldC.zeroValueCount
    stats.invalidNewRowCount += newC.invalidNewRowCount - oldC.invalidNewRowCount
    stats.validationErrorCount += newC.validationErrorCount - oldC.validationErrorCount
    stats.emptyCashFlowAmountCount +=
      newC.emptyCashFlowAmountCount - oldC.emptyCashFlowAmountCount
    stats.emptyCashFlowDescriptionCount +=
      newC.emptyCashFlowDescriptionCount - oldC.emptyCashFlowDescriptionCount
    stats.cashFlowValidationErrorCount +=
      newC.cashFlowValidationErrorCount - oldC.cashFlowValidationErrorCount
    if stats != toolbarStats { toolbarStats = stats }
  }

  private func addAssetRowToStats(_ row: BulkEntryRow) {
    applyStatsDelta(
      oldContribution: BulkEntryToolbarStats(),
      newContribution: Self.assetRowContribution(row))
  }

  private func removeAssetRowFromStats(_ row: BulkEntryRow) {
    applyStatsDelta(
      oldContribution: Self.assetRowContribution(row),
      newContribution: BulkEntryToolbarStats())
  }

  private func addCashFlowRowToStats(_ row: BulkEntryCashFlowRow) {
    applyStatsDelta(
      oldContribution: BulkEntryToolbarStats(),
      newContribution: Self.cashFlowRowContribution(row))
  }

  private func removeCashFlowRowFromStats(_ row: BulkEntryCashFlowRow) {
    applyStatsDelta(
      oldContribution: Self.cashFlowRowContribution(row),
      newContribution: BulkEntryToolbarStats())
  }
}
