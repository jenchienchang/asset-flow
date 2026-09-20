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

@Suite("ImportViewModel Tests")
@MainActor
struct ImportViewModelTests {

  // MARK: - Test Helpers

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
  }

  private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    return TestContext(container: container, context: context)
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  private func csvData(_ string: String) -> Data {
    string.data(using: .utf8)!
  }

  private func createTempCSVFile(_ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("test_\(UUID().uuidString).csv")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func validAssetCSVData() -> Data {
    csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      VTI,28000,Interactive Brokers
      Bitcoin,5000,Coinbase
      """)
  }

  private func validCashFlowCSVData() -> Data {
    csvData(
      """
      Description,Amount
      Salary deposit,50000
      Emergency fund transfer,-10000
      """)
  }

  // MARK: - Import Type Selection

  @Test("Default import type is assets")
  func defaultImportTypeIsAssets() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    #expect(viewModel.importType == .assets)
  }

  @Test("Switching import type clears loaded file and preview data")
  func switchingImportTypeClearsData() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Load an asset CSV
    viewModel.loadCSVData(validAssetCSVData())
    #expect(!viewModel.assetPreviewRows.isEmpty)

    // Switch to cash flows
    viewModel.importType = .cashFlows

    #expect(viewModel.assetPreviewRows.isEmpty)
    #expect(viewModel.cashFlowPreviewRows.isEmpty)
    #expect(viewModel.validationErrors.isEmpty)
    #expect(viewModel.validationWarnings.isEmpty)
    #expect(viewModel.selectedFileURL == nil)
  }

  // MARK: - File Loading: Asset CSV

  @Test("Loading valid asset CSV populates preview rows")
  func loadValidAssetCSV() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.assetPreviewRows.count == 3)
    #expect(viewModel.assetPreviewRows[0].csvRow.assetName == "AAPL")
    #expect(viewModel.assetPreviewRows[0].csvRow.marketValue == Decimal(15000))
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Interactive Brokers")
    #expect(viewModel.assetPreviewRows[0].isIncluded)
    #expect(viewModel.validationErrors.isEmpty)
  }

  @Test("Loading asset CSV with errors populates validation errors")
  func loadAssetCSVWithErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value
      ,15000
      AAPL,abc
      """)
    viewModel.loadCSVData(csv)

    #expect(!viewModel.validationErrors.isEmpty)
  }

  @Test("Loading asset CSV with warnings populates per-row parsing warnings")
  func loadAssetCSVWithWarnings() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,0
      VTI,-100
      """)
    viewModel.loadCSVData(csv)

    // Zero/negative market value warnings are now per-row
    #expect(viewModel.assetPreviewRows[0].marketValueWarning != nil)
    #expect(viewModel.assetPreviewRows[1].marketValueWarning != nil)
  }

  @Test("Loading empty file shows error")
  func loadEmptyFile() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(csvData(""))

    #expect(!viewModel.validationErrors.isEmpty)
    #expect(viewModel.assetPreviewRows.isEmpty)
  }

  @Test("Loading headers-only file shows no data rows error")
  func loadHeadersOnlyFile() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(csvData("Asset Name,Market Value\n"))

    #expect(!viewModel.validationErrors.isEmpty)
  }

  @Test("Loading dropped CSV data retains its name and surfaces parse errors")
  func loadDroppedCSVDataSurfacesParseErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData("Asset Name,Market Value\nA\"APL,15000\n")
    viewModel.loadDroppedData(csv, fileName: "malformed.csv")

    #expect(viewModel.selectedFileName == "malformed.csv")
    #expect(viewModel.selectedFileData != nil)
    #expect(!viewModel.validationErrors.isEmpty)
  }

  @Test("File load failure clears preview and exposes an error")
  func fileLoadFailureSurfacesError() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())
    #expect(!viewModel.assetPreviewRows.isEmpty)

    viewModel.reportFileLoadFailure()

    #expect(viewModel.assetPreviewRows.isEmpty)
    #expect(viewModel.cashFlowPreviewRows.isEmpty)
    #expect(!viewModel.validationErrors.isEmpty)
  }

  // MARK: - File Loading: Cash Flow CSV

  @Test("Loading valid cash flow CSV populates preview rows")
  func loadValidCashFlowCSV() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    viewModel.loadCSVData(validCashFlowCSVData())

    #expect(viewModel.cashFlowPreviewRows.count == 2)
    #expect(viewModel.cashFlowPreviewRows[0].csvRow.description == "Salary deposit")
    #expect(viewModel.cashFlowPreviewRows[0].csvRow.amount == Decimal(50000))
    #expect(viewModel.cashFlowPreviewRows[0].isIncluded)
    #expect(viewModel.validationErrors.isEmpty)
  }

  @Test("Loading cash flow CSV with errors populates validation errors")
  func loadCashFlowCSVWithErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    let csv = csvData(
      """
      Description,Amount
      ,50000
      Salary,abc
      """)
    viewModel.loadCSVData(csv)

    #expect(!viewModel.validationErrors.isEmpty)
  }

  // MARK: - Snapshot Date Validation

  @Test("Default snapshot date is today")
  func defaultSnapshotDateIsToday() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let today = Calendar.current.startOfDay(for: Date())
    let vmDate = Calendar.current.startOfDay(for: viewModel.snapshotDate)
    #expect(vmDate == today)
  }

  @Test("Future date produces validation error on import")
  func futureDateProducesError() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Set a future date
    let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    viewModel.snapshotDate = futureDate

    viewModel.loadCSVData(validAssetCSVData())

    // Import should fail with future date error
    let result = viewModel.executeImport()
    #expect(result == nil)
    #expect(viewModel.importError != nil)
  }

  @Test("Past date is valid for import")
  func pastDateIsValid() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.isImportDisabled == false)
  }

  // MARK: - Platform Handling

  @Test("Import-level platform overrides CSV platform values in preview")
  func importPlatformOverridesCSV() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.selectedPlatform = "Schwab"
    viewModel.loadCSVData(validAssetCSVData())

    // All rows should have the import-level platform
    for row in viewModel.assetPreviewRows {
      #expect(row.csvRow.platform == "Schwab")
    }
  }

  @Test("No import-level platform uses CSV per-row platforms")
  func noImportPlatformUsesCSVValues() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Interactive Brokers")
    #expect(viewModel.assetPreviewRows[2].csvRow.platform == "Coinbase")
  }

  @Test("New platform name is used as platform string")
  func newPlatformNameUsed() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.selectedPlatform = "My New Broker"
    viewModel.loadCSVData(validAssetCSVData())

    for row in viewModel.assetPreviewRows {
      #expect(row.csvRow.platform == "My New Broker")
    }
  }

  @Test("loadFile caches file data in selectedFileData")
  func loadFileCachesData() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let tempURL = try createTempCSVFile(
      "Asset Name,Market Value,Platform\nAAPL,15000,Fidelity\n")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    viewModel.loadFile(tempURL)

    #expect(viewModel.selectedFileData != nil)
    #expect(!viewModel.assetPreviewRows.isEmpty)
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Fidelity")
  }

  @Test("Changing platform rebuilds preview rows with new platform")
  func changePlatformWithCachedData() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let tempURL = try createTempCSVFile(
      "Asset Name,Market Value,Platform\nAAPL,15000,Fidelity\nVTI,28000,Fidelity\n")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Load file — simulates initial file import
    viewModel.loadFile(tempURL)
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Fidelity")

    // Change platform — didSet triggers rebuild automatically
    viewModel.selectedPlatform = "Schwab"

    for row in viewModel.assetPreviewRows {
      #expect(row.csvRow.platform == "Schwab")
    }
  }

  @Test("clearLoadedData clears selectedFileData")
  func clearLoadedDataClearsCachedData() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let tempURL = try createTempCSVFile("Asset Name,Market Value\nAAPL,15000\n")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    viewModel.loadFile(tempURL)
    #expect(viewModel.selectedFileData != nil)

    viewModel.clearLoadedData()
    #expect(viewModel.selectedFileData == nil)
  }

  @Test("reset clears selectedFileData")
  func resetClearsCachedData() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let tempURL = try createTempCSVFile("Asset Name,Market Value\nAAPL,15000\n")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    viewModel.loadFile(tempURL)
    #expect(viewModel.selectedFileData != nil)

    viewModel.reset()
    #expect(viewModel.selectedFileData == nil)
  }

  @Test("fillEmptyOnly applies platform only to empty-platform rows")
  func fillEmptyOnlyAppliesPlatformToEmptyRows() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // CSV with mixed platforms: some have values, some are empty
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Fidelity
      VTI,28000,
      Bitcoin,5000,Coinbase
      ETH,3000,
      """)
    viewModel.loadCSVData(csv)

    viewModel.selectedPlatform = "Schwab"
    viewModel.platformApplyMode = .fillEmptyOnly

    // Rows with CSV platforms should keep them
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Fidelity")
    #expect(viewModel.assetPreviewRows[2].csvRow.platform == "Coinbase")

    // Rows without CSV platforms should get the selected platform
    #expect(viewModel.assetPreviewRows[1].csvRow.platform == "Schwab")
    #expect(viewModel.assetPreviewRows[3].csvRow.platform == "Schwab")
  }

  @Test("overrideAll applies platform to all rows")
  func overrideAllAppliesPlatformToAllRows() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Fidelity
      VTI,28000,
      Bitcoin,5000,Coinbase
      """)
    viewModel.loadCSVData(csv)

    viewModel.selectedPlatform = "Schwab"
    viewModel.platformApplyMode = .overrideAll

    for row in viewModel.assetPreviewRows {
      #expect(row.csvRow.platform == "Schwab")
    }
  }

  @Test("Changing apply mode triggers rebuild")
  func changingApplyModeTriggersRebuild() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Fidelity
      VTI,28000,
      """)
    viewModel.loadCSVData(csv)
    viewModel.selectedPlatform = "Schwab"

    // Default is overrideAll — all rows should have Schwab
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Schwab")
    #expect(viewModel.assetPreviewRows[1].csvRow.platform == "Schwab")

    // Switch to fillEmptyOnly — Fidelity row should revert
    viewModel.platformApplyMode = .fillEmptyOnly

    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Fidelity")
    #expect(viewModel.assetPreviewRows[1].csvRow.platform == "Schwab")
  }

  @Test("fillEmptyOnly preserves exclusion state")
  func fillEmptyOnlyPreservesExclusionState() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Fidelity
      VTI,28000,
      Bitcoin,5000,Coinbase
      """)
    viewModel.loadCSVData(csv)

    // Exclude a row
    viewModel.removeAssetPreviewRow(at: 1)
    #expect(viewModel.assetPreviewRows[1].isIncluded == false)

    // Set platform and switch to fillEmptyOnly
    viewModel.selectedPlatform = "Schwab"
    viewModel.platformApplyMode = .fillEmptyOnly

    // Exclusion should be preserved
    #expect(viewModel.assetPreviewRows[1].isIncluded == false)
  }

  @Test("Excluded rows preserved after platform change")
  func excludedRowsPreservedAfterPlatformChange() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())
    #expect(viewModel.assetPreviewRows.count == 3)

    // Exclude row at index 1 (VTI)
    viewModel.removeAssetPreviewRow(at: 1)
    #expect(viewModel.assetPreviewRows[1].isIncluded == false)

    // Change platform
    viewModel.selectedPlatform = "Schwab"

    // Row 1 should still be excluded
    #expect(viewModel.assetPreviewRows[1].isIncluded == false)
    // Other rows should have the new platform
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Schwab")
    #expect(viewModel.assetPreviewRows[2].csvRow.platform == "Schwab")
  }

  @Test("Excluded rows preserved after clearing platform")
  func excludedRowsPreservedAfterClearingPlatform() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.selectedPlatform = "Schwab"
    viewModel.loadCSVData(validAssetCSVData())

    // Exclude row at index 0
    viewModel.removeAssetPreviewRow(at: 0)
    #expect(viewModel.assetPreviewRows[0].isIncluded == false)

    // Clear platform
    viewModel.selectedPlatform = nil

    // Row 0 should still be excluded
    #expect(viewModel.assetPreviewRows[0].isIncluded == false)
    // Platforms should revert to CSV values
    #expect(viewModel.assetPreviewRows[0].csvRow.platform == "Interactive Brokers")
    #expect(viewModel.assetPreviewRows[2].csvRow.platform == "Coinbase")
  }

  @Test("Excluded rows preserved after category change")
  func excludedRowsPreservedAfterCategoryChange() {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.loadCSVData(validAssetCSVData())

    // Exclude row at index 2 (Bitcoin)
    viewModel.removeAssetPreviewRow(at: 2)
    #expect(viewModel.assetPreviewRows[2].isIncluded == false)

    // Change category
    viewModel.selectedCategory = equities

    // Row 2 should still be excluded
    #expect(viewModel.assetPreviewRows[2].isIncluded == false)
    // Other rows should still be included
    #expect(viewModel.assetPreviewRows[0].isIncluded == true)
    #expect(viewModel.assetPreviewRows[1].isIncluded == true)
  }

  // MARK: - Category Handling

  @Test("Import-level category is recorded for import execution")
  func importCategoryRecorded() throws {
    let tc = createTestContext()
    let category = Category(name: "Equities", targetAllocationPercentage: 60)
    tc.context.insert(category)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = category
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // All created assets should have the selected category
    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    for asset in assets {
      #expect(asset.category?.id == category.id)
    }
  }

  @Test("New category with existing name reuses existing category")
  func newCategoryReusesExisting() {
    let tc = createTestContext()
    let existing = Category(name: "Equities", targetAllocationPercentage: 60)
    tc.context.insert(existing)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let resolved = viewModel.resolveCategory(name: "equities")

    #expect(resolved?.id == existing.id)
  }

  @Test("New category with genuinely new name creates category with nil target")
  func newCategoryCreatesNew() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    let resolved = viewModel.resolveCategory(name: "Crypto")

    #expect(resolved != nil)
    #expect(resolved?.name == "Crypto")
    #expect(resolved?.targetAllocationPercentage == nil)

    let catDescriptor = FetchDescriptor<AssetFlow.Category>()
    let allCategories = try tc.context.fetch(catDescriptor)
    #expect(allCategories.count == 1)
  }

  @Test("Category reassignment warning when asset has different existing category")
  func categoryReassignmentWarning() {
    let tc = createTestContext()

    // Create an existing asset with category "Bonds"
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.category = bonds
    tc.context.insert(asset)

    // Import with different category
    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.loadCSVData(validAssetCSVData())

    // The AAPL row should have a category warning
    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.categoryWarning != nil)
  }

  // MARK: - Row Removal

  @Test("Removing a row from preview excludes it from import")
  func removeRowExcludesFromImport() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())
    #expect(viewModel.assetPreviewRows.count == 3)

    viewModel.removeAssetPreviewRow(at: 0)

    let included = viewModel.assetPreviewRows.filter { $0.isIncluded }
    #expect(included.count == 2)
  }

  @Test("Removing all rows disables import")
  func removeAllRowsDisablesImport() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())

    for i in 0..<viewModel.assetPreviewRows.count {
      viewModel.removeAssetPreviewRow(at: i)
    }

    #expect(viewModel.isImportDisabled)
  }

  @Test("Removing row that was part of duplicate pair clears duplicate error")
  func removeRowClearsDuplicateError() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // CSV with duplicate assets
    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,15000
      AAPL,20000
      """)
    viewModel.loadCSVData(csv)

    // Second row should have per-row duplicate error
    #expect(viewModel.assetPreviewRows[1].duplicateError != nil)

    // Remove the duplicate row
    viewModel.removeAssetPreviewRow(at: 1)

    // After removing the duplicate, per-row errors should be cleared on remaining rows
    #expect(viewModel.assetPreviewRows[0].duplicateError == nil)
  }

  // MARK: - Duplicate Detection (CSV vs Existing Snapshot)

  @Test("Duplicate asset between CSV and existing snapshot produces per-row error")
  func duplicateAssetWithExistingSnapshot() {
    let tc = createTestContext()

    // Create existing snapshot with AAPL
    let date = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date)
    tc.context.insert(snapshot)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: 10000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = date
    viewModel.loadCSVData(validAssetCSVData())

    // Should detect per-row snapshot duplicate error on AAPL row
    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.snapshotDuplicateError != nil)
  }

  @Test("Zero-value snapshot placeholders are overwritten in place")
  func zeroValuePlaceholderIsOverwrittenInPlace() throws {
    let tc = createTestContext()
    let date = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    let placeholder = SnapshotAssetValue(marketValue: 0)
    placeholder.snapshot = snapshot
    placeholder.asset = asset
    tc.context.insert(snapshot)
    tc.context.insert(asset)
    tc.context.insert(placeholder)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = date
    viewModel.copyForwardEnabled = false
    viewModel.loadCSVData(
      csvData(
        """
        Asset Name,Market Value,Platform
        aapl,15000,interactive brokers
        """))

    #expect(viewModel.assetPreviewRows[0].snapshotDuplicateError == nil)
    let importedSnapshot = viewModel.executeImport()
    let values = importedSnapshot?.assetValues ?? []

    #expect(values.count == 1)
    #expect(values[0] === placeholder)
    #expect(values[0].marketValue == Decimal(15000))
  }

  @Test("Duplicate cash flow between CSV and existing snapshot produces per-row error")
  func duplicateCashFlowWithExistingSnapshot() {
    let tc = createTestContext()

    // Create existing snapshot with a cash flow
    let date = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date)
    tc.context.insert(snapshot)
    let cf = CashFlowOperation(cashFlowDescription: "Salary deposit", amount: 50000)
    cf.snapshot = snapshot
    tc.context.insert(cf)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows
    viewModel.snapshotDate = date
    viewModel.loadCSVData(validCashFlowCSVData())

    let salaryRow = viewModel.cashFlowPreviewRows.first {
      $0.csvRow.description == "Salary deposit"
    }
    #expect(salaryRow?.snapshotDuplicateError != nil)
  }

  @Test("Loading cash flow CSV with zero amount populates per-row amount warning")
  func loadCashFlowWithZeroAmountWarning() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    let csv = csvData(
      """
      Description,Amount
      Salary deposit,0
      Rent payment,-2000
      """)
    viewModel.loadCSVData(csv)

    // Zero amount gets a per-row warning
    let salaryRow = viewModel.cashFlowPreviewRows.first {
      $0.csvRow.description == "Salary deposit"
    }
    #expect(salaryRow?.amountWarning != nil)

    // Non-zero amount has no warning (negative is valid for cash flows)
    let rentRow = viewModel.cashFlowPreviewRows.first {
      $0.csvRow.description == "Rent payment"
    }
    #expect(rentRow?.amountWarning == nil)
  }

  @Test("Cash flow zero-amount warning does not appear in file-level validationWarnings")
  func cashFlowZeroAmountWarningIsPerRowOnly() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    let csv = csvData(
      """
      Description,Amount
      Salary deposit,0
      """)
    viewModel.loadCSVData(csv)

    // Row-level warnings are filtered out of validationWarnings
    #expect(viewModel.validationWarnings.isEmpty)
    // But per-row warning is set
    #expect(viewModel.cashFlowPreviewRows[0].amountWarning != nil)
  }

  @Test("No duplicates when snapshot is new")
  func noDuplicatesForNewSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    // No per-row duplicate errors
    #expect(viewModel.assetPreviewRows.allSatisfy { $0.duplicateError == nil })
    #expect(viewModel.assetPreviewRows.allSatisfy { $0.snapshotDuplicateError == nil })
  }

  @Test("Excluded rows do not participate in duplicate detection with snapshot")
  func excludedRowsSkipDuplicateDetection() {
    let tc = createTestContext()

    // Create existing snapshot with AAPL
    let date = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date)
    tc.context.insert(snapshot)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: 10000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = date

    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      VTI,28000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Initially AAPL should have a snapshot duplicate error
    #expect(viewModel.assetPreviewRows[0].snapshotDuplicateError != nil)

    // Remove the AAPL row
    viewModel.removeAssetPreviewRow(at: 0)

    // Per-row error should be cleared on excluded row
    #expect(viewModel.assetPreviewRows[0].snapshotDuplicateError == nil)
    // VTI should have no errors
    #expect(viewModel.assetPreviewRows[1].snapshotDuplicateError == nil)
  }

  // MARK: - Import Execution: Asset CSV

  @Test("Importing creates new snapshot if none exists for date")
  func importCreatesNewSnapshot() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let date = makeDate(year: 2025, month: 6, day: 15)
    viewModel.snapshotDate = date
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()

    #expect(snapshot != nil)
    #expect(snapshot?.date == Calendar.current.startOfDay(for: date))

    let snapshotDescriptor = FetchDescriptor<Snapshot>()
    let allSnapshots = try tc.context.fetch(snapshotDescriptor)
    #expect(allSnapshots.count == 1)
  }

  @Test("Importing adds to existing snapshot if one exists for date")
  func importAddsToExistingSnapshot() throws {
    let tc = createTestContext()

    // Create existing snapshot with one asset
    let date = makeDate(year: 2025, month: 6, day: 15)
    let existingSnapshot = Snapshot(date: date)
    tc.context.insert(existingSnapshot)
    let existingAsset = Asset(name: "GOOG", platform: "Schwab")
    tc.context.insert(existingAsset)
    let existingSav = SnapshotAssetValue(marketValue: 20000)
    existingSav.snapshot = existingSnapshot
    existingSav.asset = existingAsset
    tc.context.insert(existingSav)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = date

    // Import CSV with different assets (no overlap)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Firstrade
      """)
    viewModel.loadCSVData(csv)

    let snapshot = viewModel.executeImport()

    #expect(snapshot != nil)
    #expect(snapshot?.id == existingSnapshot.id)

    // Should now have 2 asset values on the same snapshot
    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let allSavs = try tc.context.fetch(savDescriptor)
    #expect(allSavs.count == 2)

    // Still just 1 snapshot
    let snapshotDescriptor = FetchDescriptor<Snapshot>()
    let allSnapshots = try tc.context.fetch(snapshotDescriptor)
    #expect(allSnapshots.count == 1)
  }

  @Test("Importing creates new Asset records for unknown assets")
  func importCreatesNewAssets() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    #expect(assets.count == 3)
  }

  @Test("Importing reuses existing Asset records for matching name and platform")
  func importReusesExistingAssets() throws {
    let tc = createTestContext()

    // Pre-create AAPL on Interactive Brokers
    let existingAsset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(existingAsset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // AAPL should be reused, not duplicated; VTI and Bitcoin are new
    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    #expect(assets.count == 3)

    let aaplAssets = assets.filter { $0.normalizedName == "aapl" }
    #expect(aaplAssets.count == 1)
    #expect(aaplAssets.first?.id == existingAsset.id)
  }

  @Test("Importing creates SnapshotAssetValues for each row")
  func importCreatesSnapshotAssetValues() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let allSavs = try tc.context.fetch(savDescriptor)
    #expect(allSavs.count == 3)

    // Verify values
    let aaplSav = allSavs.first { $0.asset?.normalizedName == "aapl" }
    #expect(aaplSav?.marketValue == Decimal(15000))
  }

  @Test("Large asset import preserves identity reuse and final counts")
  func largeAssetImportPreservesIdentityReuseAndCounts() throws {
    let tc = createTestContext()
    let existingCount = 60
    let importedCount = 120

    for index in 0..<existingCount {
      let asset = Asset(name: "Existing \(index)", platform: "Broker")
      tc.context.insert(asset)
    }

    var csvLines = ["Asset Name,Market Value,Platform"]
    for index in 0..<importedCount {
      let name = index < existingCount ? "existing \(index)" : "New \(index)"
      let platform = index < existingCount ? "BROKER" : "Exchange"
      csvLines.append("\(name),\(index + 1),\(platform)")
    }

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 7, day: 15)
    viewModel.copyForwardEnabled = false
    viewModel.loadCSVData(csvData(csvLines.joined(separator: "\n")))
    #expect(viewModel.assetPreviewRows.count == importedCount)
    #expect(viewModel.validationErrors.isEmpty)
    #expect(viewModel.isImportDisabled == false)
    let snapshot = viewModel.executeImport()

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    let valueDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let values = try tc.context.fetch(valueDescriptor)

    #expect(snapshot != nil)
    #expect(assets.count == importedCount)
    #expect(values.count == importedCount)
    #expect(assets.first(where: { $0.name == "Existing 0" })?.platform == "Broker")
    #expect(
      values.first(where: { $0.asset?.normalizedName == "new 119" })?.marketValue
        == Decimal(120))
  }

  @Test("Importing assigns category to all assets when category selected")
  func importAssignsCategory() throws {
    let tc = createTestContext()

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    for asset in assets {
      #expect(asset.category?.id == equities.id)
    }
  }

  @Test("Importing overrides existing category when import category is selected")
  func importOverridesCategory() throws {
    let tc = createTestContext()

    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    // Pre-create AAPL assigned to Bonds
    let existingAsset = Asset(name: "AAPL", platform: "Interactive Brokers")
    existingAsset.category = bonds
    tc.context.insert(existingAsset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // AAPL should now be in Equities
    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    let aapl = assets.first { $0.normalizedName == "aapl" }
    #expect(aapl?.category?.id == equities.id)
  }

  @Test("Import returns created snapshot for navigation")
  func importReturnsSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()

    #expect(snapshot != nil)
    #expect(
      snapshot?.date
        == Calendar.current.startOfDay(
          for: makeDate(year: 2025, month: 6, day: 15)))
  }

  // MARK: - Import Execution: Cash Flow CSV

  @Test("Importing cash flows creates CashFlowOperations on snapshot")
  func importCreatesCashFlowOperations() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validCashFlowCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let cfDescriptor = FetchDescriptor<CashFlowOperation>()
    let allOps = try tc.context.fetch(cfDescriptor)
    #expect(allOps.count == 2)

    let salary = allOps.first { $0.cashFlowDescription == "Salary deposit" }
    #expect(salary?.amount == Decimal(50000))

    let transfer = allOps.first { $0.cashFlowDescription == "Emergency fund transfer" }
    #expect(transfer?.amount == Decimal(-10000))
  }

  @Test("Importing cash flows to existing snapshot adds to it")
  func importCashFlowsToExistingSnapshot() throws {
    let tc = createTestContext()

    // Create existing snapshot
    let date = makeDate(year: 2025, month: 6, day: 15)
    let existingSnapshot = Snapshot(date: date)
    tc.context.insert(existingSnapshot)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows
    viewModel.snapshotDate = date
    viewModel.loadCSVData(validCashFlowCSVData())

    let snapshot = viewModel.executeImport()

    #expect(snapshot != nil)
    #expect(snapshot?.id == existingSnapshot.id)

    let cfDescriptor = FetchDescriptor<CashFlowOperation>()
    let allOps = try tc.context.fetch(cfDescriptor)
    #expect(allOps.count == 2)
  }

  // MARK: - State Management

  @Test("isImportDisabled is true when no rows loaded")
  func importDisabledWhenNoRows() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    #expect(viewModel.isImportDisabled)
  }

  @Test("isImportDisabled is true when validation errors exist")
  func importDisabledWhenErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Load CSV with errors
    let csv = csvData(
      """
      Asset Name,Market Value
      ,15000
      """)
    viewModel.loadCSVData(csv)

    #expect(viewModel.isImportDisabled)
  }

  @Test("isImportDisabled is false when valid rows and no errors")
  func importEnabledWhenValid() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)

    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.isImportDisabled == false)
  }

  @Test("hasUnsavedChanges is true when file loaded but not imported")
  func hasUnsavedChangesWhenFileLoaded() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.hasUnsavedChanges)
  }

  @Test("hasUnsavedChanges is false after import")
  func hasUnsavedChangesFalseAfterImport() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())
    _ = viewModel.executeImport()

    #expect(viewModel.hasUnsavedChanges == false)
  }

  @Test("Reset clears all state")
  func resetClearsState() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())
    #expect(!viewModel.assetPreviewRows.isEmpty)

    viewModel.reset()

    #expect(viewModel.assetPreviewRows.isEmpty)
    #expect(viewModel.cashFlowPreviewRows.isEmpty)
    #expect(viewModel.validationErrors.isEmpty)
    #expect(viewModel.validationWarnings.isEmpty)
    #expect(viewModel.selectedFileURL == nil)
    #expect(viewModel.selectedPlatform == nil)
    #expect(viewModel.selectedCategory == nil)
    #expect(viewModel.importError == nil)
    #expect(viewModel.hasUnsavedChanges == false)
  }

  // MARK: - Existing Platforms List

  @Test("Existing platforms list includes platforms from all assets")
  func existingPlatformsList() {
    let tc = createTestContext()

    let asset1 = Asset(name: "AAPL", platform: "Firstrade")
    let asset2 = Asset(name: "BTC", platform: "Coinbase")
    let asset3 = Asset(name: "VTI", platform: "Firstrade")
    tc.context.insert(asset1)
    tc.context.insert(asset2)
    tc.context.insert(asset3)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let platforms = viewModel.existingPlatforms()

    #expect(platforms.contains("Firstrade"))
    #expect(platforms.contains("Coinbase"))
    #expect(platforms.count == 2)
  }

  // MARK: - Existing Categories List

  @Test("Existing categories list includes all categories")
  func existingCategoriesList() throws {
    let tc = createTestContext()

    let cat1 = Category(name: "Equities")
    let cat2 = Category(name: "Bonds")
    tc.context.insert(cat1)
    tc.context.insert(cat2)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let categories = viewModel.existingCategories()

    #expect(categories.count == 2)
  }

  // MARK: - Only Included Rows Are Imported

  @Test("Only included asset rows are imported")
  func onlyIncludedAssetRowsImported() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    // Remove the first row (AAPL)
    viewModel.removeAssetPreviewRow(at: 0)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let allSavs = try tc.context.fetch(savDescriptor)
    #expect(allSavs.count == 2)

    // AAPL should not be in the snapshot
    let aaplSav = allSavs.first { $0.asset?.normalizedName == "aapl" }
    #expect(aaplSav == nil)
  }

  @Test("Only included cash flow rows are imported")
  func onlyIncludedCashFlowRowsImported() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validCashFlowCSVData())

    // Remove the first row
    viewModel.removeCashFlowPreviewRow(at: 0)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let cfDescriptor = FetchDescriptor<CashFlowOperation>()
    let allOps = try tc.context.fetch(cfDescriptor)
    #expect(allOps.count == 1)
    #expect(allOps.first?.cashFlowDescription == "Emergency fund transfer")
  }

  // MARK: - Import With No Category (Uncategorized)

  @Test("Import without category leaves assets uncategorized")
  func importWithoutCategoryLeavesUncategorized() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.selectedCategory = nil
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    for asset in assets {
      #expect(asset.category == nil)
    }
  }

  // MARK: - Snapshot Date Change Re-triggers Duplicate Detection

  @Test("Changing snapshot date re-triggers duplicate detection against existing snapshot")
  func changingSnapshotDateRetriggersDuplicateDetection() {
    let tc = createTestContext()

    // Create existing snapshot on June 15 with AAPL
    let date1 = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date1)
    tc.context.insert(snapshot)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: 10000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let viewModel = ImportViewModel(modelContext: tc.context)

    // Set date to June 16 (no existing snapshot) and load CSV with AAPL
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 16)
    viewModel.loadCSVData(validAssetCSVData())

    // No per-row snapshot duplicate error on June 16
    #expect(viewModel.assetPreviewRows.allSatisfy { $0.snapshotDuplicateError == nil })

    // Now change date to June 15 where AAPL already exists
    viewModel.snapshotDate = date1

    // Should detect per-row snapshot duplicate error on AAPL row
    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.snapshotDuplicateError != nil)
  }

  // MARK: - Revalidation Preserves Parsing Errors

  @Test("Removing a row preserves non-duplicate parsing errors from initial load")
  func removeRowPreservesParsingErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // CSV with: one empty-name error row, two AAPL duplicates, and one valid row
    // The empty-name row produces a parsing error but is NOT a preview row.
    // The two AAPLs are preview rows and produce a within-CSV duplicate error.
    let csv = csvData(
      """
      Asset Name,Market Value
      ,15000
      AAPL,20000
      AAPL,25000
      VTI,10000
      """)
    viewModel.loadCSVData(csv)

    // Should have: parsing error in validationErrors + per-row duplicate error on second AAPL
    #expect(!viewModel.validationErrors.isEmpty)
    let hasEmptyNameError = viewModel.validationErrors.contains {
      $0.message == CSVParsingService.localizedImportMessage("Asset name is empty.")
    }
    #expect(hasEmptyNameError)
    #expect(viewModel.assetPreviewRows[1].duplicateError != nil)

    // Preview rows: AAPL(0), AAPL(1), VTI(2) - 3 rows
    #expect(viewModel.assetPreviewRows.count == 3)

    // Remove one of the AAPL rows (index 1)
    viewModel.removeAssetPreviewRow(at: 1)

    // After revalidation:
    // - Per-row duplicate error should be gone (only one AAPL now)
    // - But the parsing error for empty name should still be present
    #expect(viewModel.assetPreviewRows[0].duplicateError == nil)
    let hasEmptyNameErrorAfter = viewModel.validationErrors.contains {
      $0.message == CSVParsingService.localizedImportMessage("Asset name is empty.")
    }
    #expect(hasEmptyNameErrorAfter)
  }

  // MARK: - Import Sets importedSnapshot for Navigation

  @Test("Successful import sets importedSnapshot for navigation")
  func successfulImportSetsImportedSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    #expect(viewModel.importedSnapshot == nil)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()

    #expect(snapshot != nil)
    #expect(viewModel.importedSnapshot != nil)
    #expect(viewModel.importedSnapshot?.id == snapshot?.id)
  }

  @Test("Unsuccessful import does not set importedSnapshot")
  func unsuccessfulImportDoesNotSetImportedSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Set future date to cause failure
    let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    viewModel.snapshotDate = futureDate
    viewModel.loadCSVData(validAssetCSVData())

    let result = viewModel.executeImport()

    #expect(result == nil)
    #expect(viewModel.importedSnapshot == nil)
  }

  @Test("Reset clears importedSnapshot")
  func resetClearsImportedSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())
    _ = viewModel.executeImport()
    #expect(viewModel.importedSnapshot != nil)

    viewModel.reset()
    #expect(viewModel.importedSnapshot == nil)
  }

  // MARK: - Default Platform from Settings

  @Test("Import pre-fills platform when default platform is set")
  func importPrefillsPlatformFromSettings() {
    let tc = createTestContext()
    let settingsService = SettingsService.createForTesting()
    settingsService.defaultPlatform = "Schwab"

    let viewModel = ImportViewModel(
      modelContext: tc.context, settingsService: settingsService)
    #expect(viewModel.selectedPlatform == "Schwab")
  }

  @Test("Import leaves platform nil when default platform is empty")
  func importLeavesPlatformNilWhenDefaultEmpty() {
    let tc = createTestContext()
    let settingsService = SettingsService.createForTesting()

    let viewModel = ImportViewModel(
      modelContext: tc.context, settingsService: settingsService)
    #expect(viewModel.selectedPlatform == nil)
  }

  // MARK: - Copy-Forward

  /// Helper: creates a prior snapshot with assets on the given platforms.
  private func createPriorSnapshot(
    date: Date,
    assets: [(name: String, platform: String, value: Decimal)],
    context: ModelContext
  ) -> Snapshot {
    let snapshot = Snapshot(date: Calendar.current.startOfDay(for: date))
    context.insert(snapshot)
    for a in assets {
      let asset = Asset(name: a.name, platform: a.platform)
      context.insert(asset)
      let sav = SnapshotAssetValue(marketValue: a.value)
      sav.snapshot = snapshot
      sav.asset = asset
      context.insert(sav)
    }
    return snapshot
  }

  @Test("Copy-forward platforms computed from prior snapshot")
  func copyForwardPlatformsComputedFromPriorSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Create prior snapshot with assets on Binance and Schwab
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [
        ("BTC", "Binance", 50000),
        ("ETH", "Binance", 3000),
        ("VTI", "Schwab", 28000),
      ],
      context: tc.context)

    // Load CSV with only Interactive Brokers assets
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Should offer Binance and Schwab for copy-forward
    let platformNames = viewModel.copyForwardPlatforms.map { $0.platformName }.sorted()
    #expect(platformNames == ["Binance", "Schwab"])

    let binance = viewModel.copyForwardPlatforms.first { $0.platformName == "Binance" }
    #expect(binance?.assetCount == 2)
    #expect(binance?.isSelected == true)
  }

  @Test("Copy-forward platforms empty when no prior snapshot")
  func copyForwardPlatformsEmptyWhenNoPriorSnapshot() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.copyForwardPlatforms.isEmpty)
  }

  @Test("Copy-forward platforms excludes platforms present in CSV")
  func copyForwardPlatformsExcludesCSVPlatforms() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot has Interactive Brokers and Binance
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [
        ("AAPL", "Interactive Brokers", 15000),
        ("BTC", "Binance", 50000),
      ],
      context: tc.context)

    // CSV also has Interactive Brokers
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      VTI,28000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Only Binance should be offered (Interactive Brokers is in CSV)
    let platformNames = viewModel.copyForwardPlatforms.map { $0.platformName }
    #expect(platformNames == ["Binance"])
  }

  @Test("Copy-forward platforms excludes import-level platform")
  func copyForwardPlatformsExcludesImportLevelPlatform() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot has Schwab and Binance
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [
        ("VTI", "Schwab", 28000),
        ("BTC", "Binance", 50000),
      ],
      context: tc.context)

    // Import-level platform set to Schwab
    viewModel.selectedPlatform = "Schwab"
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)

    // CSV has no Platform column, all go to Schwab
    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,15000
      """)
    viewModel.loadCSVData(csv)

    // Only Binance should be offered (Schwab is the import-level platform)
    let platformNames = viewModel.copyForwardPlatforms.map { $0.platformName }
    #expect(platformNames == ["Binance"])
  }

  @Test("Import with copy-forward creates SnapshotAssetValue records")
  func executeImportWithCopyForwardCreatesRecords() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot with Binance assets
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [
        ("BTC", "Binance", 50000),
        ("ETH", "Binance", 3000),
      ],
      context: tc.context)

    // Load CSV with Interactive Brokers
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Ensure copy-forward is enabled (default)
    #expect(viewModel.copyForwardEnabled == true)
    #expect(!viewModel.copyForwardPlatforms.isEmpty)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Should have 3 SAVs: 1 from CSV + 2 from copy-forward
    let values = snapshot?.assetValues ?? []
    #expect(values.count == 3)

    let totalValue = values.reduce(Decimal(0)) { $0 + $1.marketValue }
    #expect(totalValue == Decimal(68000))
  }

  @Test("Import with copy-forward disabled skips copy")
  func executeImportWithCopyForwardDisabledSkipsCopy() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot with Binance assets
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [("BTC", "Binance", 50000)],
      context: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Disable copy-forward
    viewModel.copyForwardEnabled = false

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Should have only 1 SAV from CSV
    let values = snapshot?.assetValues ?? []
    #expect(values.count == 1)
    #expect(values.first?.marketValue == Decimal(15000))
  }

  @Test("Import with partial copy-forward selection copies only selected platforms")
  func executeImportWithPartialCopyForwardSelection() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot with Binance and Schwab
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [
        ("BTC", "Binance", 50000),
        ("VTI", "Schwab", 28000),
      ],
      context: tc.context)

    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Deselect Schwab, keep Binance
    if let schwabIndex = viewModel.copyForwardPlatforms.firstIndex(where: {
      $0.platformName == "Schwab"
    }) {
      viewModel.copyForwardPlatforms[schwabIndex].isSelected = false
    }

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Should have 2 SAVs: 1 from CSV + 1 from Binance copy-forward
    let values = snapshot?.assetValues ?? []
    #expect(values.count == 2)

    let totalValue = values.reduce(Decimal(0)) { $0 + $1.marketValue }
    #expect(totalValue == Decimal(65000))
  }

  @Test("Copy-forward does not create duplicate SnapshotAssetValues")
  func copyForwardDoesNotCreateDuplicates() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot with AAPL on Interactive Brokers
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: priorDate,
      assets: [("AAPL", "Interactive Brokers", 12000)],
      context: tc.context)

    // CSV also has AAPL on Interactive Brokers (same asset)
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Interactive Brokers is in CSV, so it shouldn't be in copy-forward at all
    #expect(viewModel.copyForwardPlatforms.isEmpty)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Should have only 1 SAV from CSV
    let values = snapshot?.assetValues ?? []
    #expect(values.count == 1)
    #expect(values.first?.marketValue == Decimal(15000))
  }

  @Test("Copy-forward recomputes when snapshot date changes")
  func copyForwardRecomputesOnDateChange() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Prior snapshot on Jan 1
    let jan1 = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: jan1,
      assets: [("BTC", "Binance", 50000)],
      context: tc.context)

    // Load CSV for Feb 1
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Should have Binance available
    #expect(viewModel.copyForwardPlatforms.count == 1)

    // Change date to before the prior snapshot
    viewModel.snapshotDate = makeDate(year: 2024, month: 12, day: 1)

    // No prior snapshot before Dec 2024, so copy-forward should be empty
    #expect(viewModel.copyForwardPlatforms.isEmpty)
  }

  @Test("Copy-forward platforms empty when snapshot already exists for selected date")
  func copyForwardPlatformsEmptyWhenSnapshotExistsForDate() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Create snapshot on Jan 1 with Binance assets
    let jan1 = makeDate(year: 2025, month: 1, day: 1)
    _ = createPriorSnapshot(
      date: jan1,
      assets: [("BTC", "Binance", 50000)],
      context: tc.context)

    // Create snapshot on Feb 1 with Schwab assets (this is the existing snapshot)
    let feb1 = makeDate(year: 2025, month: 2, day: 1)
    _ = createPriorSnapshot(
      date: feb1,
      assets: [("VTI", "Schwab", 28000)],
      context: tc.context)

    // Import into Feb 1 (snapshot already exists)
    viewModel.snapshotDate = feb1
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      """)
    viewModel.loadCSVData(csv)

    // Copy-forward should NOT be offered since snapshot already exists for this date
    #expect(viewModel.copyForwardPlatforms.isEmpty)
  }

  // MARK: - Currency Preservation

  @Test("Import preserves existing asset currency when CSV has no currency column")
  func importPreservesExistingAssetCurrency() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Create existing asset with currency set
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "USD"
    tc.context.insert(asset)

    let asset2 = Asset(name: "Bitcoin", platform: "Coinbase")
    asset2.currency = "TWD"
    tc.context.insert(asset2)

    // Import CSV without currency column
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform
      AAPL,16000,Interactive Brokers
      Bitcoin,60000,Coinbase
      """)
    viewModel.loadCSVData(csv)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Currencies should remain unchanged
    #expect(asset.currency == "USD")
    #expect(asset2.currency == "TWD")
  }

  @Test("Import uses CSV currency when currency column is present")
  func importUsesCSVCurrencyWhenProvided() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Create existing asset with currency set
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "TWD"
    tc.context.insert(asset)

    // Import CSV with explicit currency column
    viewModel.snapshotDate = makeDate(year: 2025, month: 2, day: 1)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    // Currency should be updated to the CSV value
    #expect(asset.currency == "USD")
  }

  @Test("Import preserves cash flow currency when CSV has no currency column")
  func importPreservesCashFlowCurrencyWithoutColumn() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    // Create existing snapshot with a cash flow that has a currency
    let feb1 = makeDate(year: 2025, month: 2, day: 1)
    let snapshot = Snapshot(date: Calendar.current.startOfDay(for: feb1))
    tc.context.insert(snapshot)
    let existingOp = CashFlowOperation(cashFlowDescription: "Salary", amount: 5000)
    existingOp.currency = "USD"
    existingOp.snapshot = snapshot
    tc.context.insert(existingOp)

    // Import a new cash flow without currency column into a different date
    viewModel.importType = .cashFlows
    viewModel.snapshotDate = makeDate(year: 2025, month: 3, day: 1)
    let csv = csvData(
      """
      Description,Amount
      Bonus,2000
      """)
    viewModel.loadCSVData(csv)

    let importedSnapshot = viewModel.executeImport()
    #expect(importedSnapshot != nil)

    // The new cash flow should have empty currency (not overwritten with default)
    let newOps = importedSnapshot?.cashFlowOperations ?? []
    let bonus = newOps.first { $0.cashFlowDescription == "Bonus" }
    #expect(bonus != nil)
    #expect(bonus?.currency.isEmpty != false)
  }

  // MARK: - Currency Warning

  @Test("Currency warning when CSV currency differs from existing asset currency")
  func currencyWarningWhenDifferent() {
    let tc = createTestContext()

    // Create existing asset with currency "TWD"
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "TWD"
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyWarning != nil)
    #expect(aaplRow?.currencyWarning?.contains("TWD") == true)
    #expect(aaplRow?.currencyWarning?.contains("USD") == true)
  }

  @Test("No currency warning when CSV currency matches existing asset currency")
  func noCurrencyWarningWhenMatching() {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "USD"
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyWarning == nil)
  }

  @Test("No currency warning when CSV has no currency column")
  func noCurrencyWarningWithoutCurrencyColumn() {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "USD"
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.loadCSVData(validAssetCSVData())

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyWarning == nil)
  }

  @Test("No currency warning when existing asset has no currency")
  func noCurrencyWarningWhenExistingHasNoCurrency() {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyWarning == nil)
  }

  // MARK: - Effective Currency

  @Test("Effective currency uses CSV currency when provided")
  func effectiveCurrencyFromCSV() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.effectiveCurrency == "USD")
  }

  @Test("Effective currency falls back to existing asset currency")
  func effectiveCurrencyFallsBackToExisting() {
    let tc = createTestContext()

    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "TWD"
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.loadCSVData(validAssetCSVData())

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.effectiveCurrency == "TWD")
  }

  @Test("Effective currency is empty when no CSV currency and no existing asset")
  func effectiveCurrencyEmptyWhenNone() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    viewModel.loadCSVData(validAssetCSVData())

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.effectiveCurrency.isEmpty == true)
  }

  // MARK: - Currency Validation

  @Test("Unsupported currency code produces per-row error")
  func unsupportedCurrencyProducesError() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,XYZ
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyError != nil)
    #expect(viewModel.isImportDisabled)
  }

  @Test("Supported currency code produces no validation error")
  func supportedCurrencyProducesNoError() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyError == nil)
  }

  @Test("Case-insensitive currency codes are accepted")
  func caseInsensitiveCurrencyAccepted() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,usd
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.currencyError == nil)
  }

  @Test("Unsupported currency error suppresses currency change warning")
  func unsupportedCurrencyErrorSuppressesWarning() {
    let tc = createTestContext()

    // Create existing asset with currency "TWD"
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.currency = "TWD"
    tc.context.insert(asset)

    let viewModel = ImportViewModel(modelContext: tc.context)

    // CSV provides unsupported currency "XYZ" — different from existing "TWD"
    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,XYZ
      """)
    viewModel.loadCSVData(csv)

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    // Error should be set (unsupported currency)
    #expect(aaplRow?.currencyError != nil)
    // Warning should be suppressed (error takes precedence)
    #expect(aaplRow?.currencyWarning == nil)
  }

  // MARK: - Category Apply Mode

  @Test("Category apply mode overrideAll assigns category to all assets")
  func categoryApplyMode_overrideAll_assignsToAllAssets() throws {
    let tc = createTestContext()

    // Create existing asset with category
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let existingAsset = Asset(name: "AAPL", platform: "Interactive Brokers")
    existingAsset.category = bonds
    tc.context.insert(existingAsset)

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.categoryApplyMode = .overrideAll
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)
    for asset in assets {
      #expect(asset.category?.id == equities.id)
    }
  }

  @Test("Category apply mode fillEmptyOnly only assigns to uncategorized assets")
  func categoryApplyMode_fillEmptyOnly_onlyAssignsToUncategorized() throws {
    let tc = createTestContext()

    // Create existing asset with category
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let existingAsset = Asset(name: "AAPL", platform: "Interactive Brokers")
    existingAsset.category = bonds
    tc.context.insert(existingAsset)

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.categoryApplyMode = .fillEmptyOnly
    viewModel.snapshotDate = makeDate(year: 2025, month: 6, day: 15)
    viewModel.loadCSVData(validAssetCSVData())

    let snapshot = viewModel.executeImport()
    #expect(snapshot != nil)

    let assetDescriptor = FetchDescriptor<Asset>()
    let assets = try tc.context.fetch(assetDescriptor)

    // AAPL (existing with Bonds) should keep Bonds
    let aapl = assets.first { $0.name == "AAPL" }
    #expect(aapl?.category?.id == bonds.id)

    // VTI (new) should get Equities
    let vti = assets.first { $0.name == "VTI" }
    #expect(vti?.category?.id == equities.id)

    // Bitcoin (new) should get Equities
    let bitcoin = assets.first { $0.name == "Bitcoin" }
    #expect(bitcoin?.category?.id == equities.id)
  }

  @Test("hasMixedCategories is true when some existing assets have categories and some don't")
  func hasMixedCategories_trueWhenMixed() {
    let tc = createTestContext()

    // Create one asset with category, one without
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let aapl = Asset(name: "AAPL", platform: "Interactive Brokers")
    aapl.category = bonds
    tc.context.insert(aapl)
    let vti = Asset(name: "VTI", platform: "Interactive Brokers")
    tc.context.insert(vti)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.loadCSVData(validAssetCSVData())

    #expect(viewModel.hasMixedCategories)
  }

  @Test("effectiveCategory reflects apply mode correctly")
  func effectiveCategory_reflectsApplyMode() {
    let tc = createTestContext()

    // Create existing AAPL with Bonds category
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let existingAsset = Asset(name: "AAPL", platform: "Interactive Brokers")
    existingAsset.category = bonds
    tc.context.insert(existingAsset)

    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities

    // overrideAll: all rows show selected category
    viewModel.categoryApplyMode = .overrideAll
    viewModel.loadCSVData(validAssetCSVData())

    let aaplOverride = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplOverride?.effectiveCategory == "Equities")

    // fillEmptyOnly: AAPL keeps existing, new assets get selected
    viewModel.categoryApplyMode = .fillEmptyOnly

    let aaplFill = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplFill?.effectiveCategory == "Bonds")

    let bitcoinFill = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "Bitcoin"
    }
    #expect(bitcoinFill?.effectiveCategory == "Equities")
  }

  // MARK: - Per-Row Errors

  @Test("Per-row duplicate errors are set on revalidation")
  func perRowDuplicateErrors_setOnRevalidation() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,15000
      AAPL,20000
      """)
    viewModel.loadCSVData(csv)

    // First row should have no error
    #expect(viewModel.assetPreviewRows[0].duplicateError == nil)
    // Second row should have duplicate error
    #expect(viewModel.assetPreviewRows[1].duplicateError != nil)
  }

  @Test("Per-row snapshot duplicate errors are set on revalidation")
  func perRowSnapshotDuplicateErrors_setOnRevalidation() {
    let tc = createTestContext()

    // Create existing snapshot with AAPL
    let date = makeDate(year: 2025, month: 6, day: 15)
    let snapshot = Snapshot(date: date)
    tc.context.insert(snapshot)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    tc.context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: 10000)
    sav.snapshot = snapshot
    sav.asset = asset
    tc.context.insert(sav)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = date
    viewModel.loadCSVData(validAssetCSVData())

    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.snapshotDuplicateError != nil)

    // VTI and Bitcoin should have no snapshot duplicate error
    let vtiRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "VTI"
    }
    #expect(vtiRow?.snapshotDuplicateError == nil)
  }

  @Test("isImportDisabled is true when included rows have per-row errors")
  func isImportDisabled_trueWithPerRowErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,15000
      AAPL,20000
      """)
    viewModel.loadCSVData(csv)

    // Should be disabled due to per-row duplicate error
    #expect(viewModel.isImportDisabled)
  }

  @Test("Row exclusion clears per-row errors for that row")
  func rowExclusion_clearsPerRowErrors() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value
      AAPL,15000
      AAPL,20000
      VTI,10000
      """)
    viewModel.loadCSVData(csv)

    // Initially second AAPL has duplicate error
    #expect(viewModel.assetPreviewRows[1].duplicateError != nil)
    #expect(viewModel.isImportDisabled)

    // Exclude the second AAPL row
    viewModel.removeAssetPreviewRow(at: 1)

    // First AAPL should have no duplicate error anymore
    #expect(viewModel.assetPreviewRows[0].duplicateError == nil)
    // Import should be enabled again
    #expect(!viewModel.isImportDisabled)
  }

  @Test("Category reassignment warning not shown in fillEmptyOnly mode")
  func categoryWarningNotShownInFillEmptyOnly() {
    let tc = createTestContext()

    // Create an existing asset with category "Bonds"
    let bonds = Category(name: "Bonds")
    tc.context.insert(bonds)
    let asset = Asset(name: "AAPL", platform: "Interactive Brokers")
    asset.category = bonds
    tc.context.insert(asset)

    // Import with different category in fillEmptyOnly mode
    let equities = Category(name: "Equities")
    tc.context.insert(equities)

    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.selectedCategory = equities
    viewModel.categoryApplyMode = .fillEmptyOnly
    viewModel.loadCSVData(validAssetCSVData())

    // The AAPL row should NOT have a category warning (won't be overridden)
    let aaplRow = viewModel.assetPreviewRows.first {
      $0.csvRow.assetName == "AAPL"
    }
    #expect(aaplRow?.categoryWarning == nil)
  }

  @Test("Removing row with unsupported currency makes import possible")
  func removingRowWithUnsupportedCurrencyClearsError() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let csv = csvData(
      """
      Asset Name,Market Value,Platform,Currency
      AAPL,16000,Interactive Brokers,XYZ
      VTI,28000,Interactive Brokers,USD
      """)
    viewModel.loadCSVData(csv)

    // Should have a per-row currency error for XYZ
    #expect(viewModel.assetPreviewRows[0].currencyError != nil)
    #expect(viewModel.isImportDisabled)

    // Remove the row with unsupported currency
    viewModel.removeAssetPreviewRow(at: 0)

    // Import should now be possible (the excluded row's error doesn't block)
    #expect(!viewModel.isImportDisabled)
  }

  // MARK: - findOrCreateSnapshot

  @Test("findOrCreateSnapshot returns existing snapshot when date matches")
  func findOrCreateSnapshotReturnsExisting() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let date = makeDate(year: 2025, month: 6, day: 15)
    let existing = Snapshot(date: date)
    tc.context.insert(existing)

    let result = viewModel.findOrCreateSnapshot(date: date)
    #expect(result.id == existing.id)
  }

  @Test("findOrCreateSnapshot creates new snapshot when no match exists")
  func findOrCreateSnapshotCreatesNew() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let date = makeDate(year: 2025, month: 6, day: 15)
    let result = viewModel.findOrCreateSnapshot(date: date)

    #expect(result.date == date)

    let descriptor = FetchDescriptor<Snapshot>()
    let all = try tc.context.fetch(descriptor)
    #expect(all.count == 1)
  }

  @Test("findOrCreateSnapshot does not create duplicate when snapshot exists")
  func findOrCreateSnapshotNoDuplicate() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)

    let date = makeDate(year: 2025, month: 6, day: 15)
    let existing = Snapshot(date: date)
    tc.context.insert(existing)

    _ = viewModel.findOrCreateSnapshot(date: date)

    let descriptor = FetchDescriptor<Snapshot>()
    let all = try tc.context.fetch(descriptor)
    #expect(all.count == 1)
  }

  // MARK: - Column Mapping Integration

  @Test("loadCSVData with canonical headers does not show mapping sheet")
  func testLoadCSVDataCanonicalHeadersNoSheet() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    viewModel.loadCSVData(validAssetCSVData())

    #expect(!viewModel.showColumnMappingSheet)
    #expect(viewModel.assetPreviewRows.count == 3)
  }

  @Test("loadCSVData with canonical headers in different casing does not show mapping sheet")
  func testLoadCSVDataCaseInsensitiveCanonicalNoSheet() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("asset name,MARKET VALUE\nAAPL,15000")
    viewModel.loadCSVData(csv)

    #expect(!viewModel.showColumnMappingSheet)
    #expect(viewModel.assetPreviewRows.count == 1)
  }

  @Test("loadCSVData with non-matching headers shows mapping sheet")
  func testLoadCSVDataNonMatchingShowsSheet() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Symbol,Price,Account\nAAPL,15000,Schwab")
    viewModel.loadCSVData(csv)

    #expect(viewModel.showColumnMappingSheet)
    #expect(viewModel.assetPreviewRows.isEmpty)
    #expect(viewModel.pendingRawHeaders == ["Symbol", "Price", "Account"])
    #expect(!viewModel.pendingSampleRows.isEmpty)
  }

  @Test("loadCSVData with partially matching headers pre-populates partial mapping")
  func testLoadCSVDataPartialMatchPrePopulates() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Symbol,Price,Platform\nAAPL,15000,Schwab")
    viewModel.loadCSVData(csv)

    #expect(viewModel.showColumnMappingSheet)
    #expect(viewModel.pendingPartialMapping[.platform] == 2)
    #expect(viewModel.pendingPartialMapping[.assetName] == nil)
  }

  @Test("confirmColumnMapping populates preview rows and dismisses sheet")
  func testConfirmColumnMappingPopulatesPreview() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Symbol,Price,Account\nAAPL,15000,Schwab\nVTI,28000,Fidelity")
    viewModel.loadCSVData(csv)
    #expect(viewModel.showColumnMappingSheet)

    let mapping = CSVColumnMapping(
      schema: .asset,
      columnMap: [.assetName: 0, .marketValue: 1, .platform: 2],
      rawHeaders: ["Symbol", "Price", "Account"])
    viewModel.confirmColumnMapping(mapping)

    #expect(!viewModel.showColumnMappingSheet)
    let rows = viewModel.assetPreviewRows
    #expect(rows.count == 2)
    let first = try #require(rows.first)
    #expect(first.csvRow.assetName == "AAPL")
    #expect(first.csvRow.platform == "Schwab")
  }

  @Test("loadCSVData with non-matching cash flow headers shows mapping sheet")
  func testLoadCSVDataCashFlowNonMatchingShowsSheet() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Label,Value\nDeposit,5000\nWithdrawal,-2000")
    viewModel.loadCSVData(csv)

    #expect(viewModel.showColumnMappingSheet)
    #expect(viewModel.cashFlowPreviewRows.isEmpty)
  }

  @Test("confirmColumnMapping for cash flow populates preview rows")
  func testConfirmColumnMappingCashFlow() throws {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.importType = .cashFlows
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Label,Value\nDeposit,5000")
    viewModel.loadCSVData(csv)

    let mapping = CSVColumnMapping(
      schema: .cashFlow,
      columnMap: [.description: 0, .amount: 1],
      rawHeaders: ["Label", "Value"])
    viewModel.confirmColumnMapping(mapping)

    #expect(!viewModel.showColumnMappingSheet)
    let cfRows = viewModel.cashFlowPreviewRows
    #expect(cfRows.count == 1)
    let firstCF = try #require(cfRows.first)
    #expect(firstCF.csvRow.description == "Deposit")
  }

  @Test("clearLoadedData clears mapping state")
  func testClearLoadedDataClearsMappingState() {
    let tc = createTestContext()
    let viewModel = ImportViewModel(modelContext: tc.context)
    viewModel.snapshotDate = makeDate(year: 2025, month: 1, day: 1)

    let csv = csvData("Symbol,Price\nAAPL,15000")
    viewModel.loadCSVData(csv)
    #expect(viewModel.showColumnMappingSheet)

    viewModel.clearLoadedData()

    #expect(!viewModel.showColumnMappingSheet)
    #expect(viewModel.pendingRawHeaders.isEmpty)
    #expect(viewModel.pendingSampleRows.isEmpty)
    #expect(viewModel.pendingPartialMapping.isEmpty)
  }
}
