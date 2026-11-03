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

@Suite("CategoryDetailViewModel Tests")
@MainActor
struct CategoryDetailViewModelTests {

  // MARK: - Test Helpers

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let category: AssetFlow.Category
  }

  private func createTestContext(
    categoryName: String = "Equities",
    targetAllocation: Decimal? = nil
  ) -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = Category(
      name: categoryName, targetAllocationPercentage: targetAllocation)
    context.insert(category)
    return TestContext(container: container, context: context, category: category)
  }

  @discardableResult
  private func createAssetWithValue(
    name: String,
    platform: String,
    category: AssetFlow.Category?,
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: TestDataManager.platform(named: platform, in: context))
    asset.category = category
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  // MARK: - Asset Listing

  @Test("Lists assets in category sorted alphabetically")
  func listsAssetsInCategorySortedAlphabetically() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)

    createAssetWithValue(
      name: "MSFT", platform: "Firstrade", category: category,
      marketValue: 3000, snapshot: snap, context: context)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap, context: context)
    createAssetWithValue(
      name: "GOOG", platform: "Firstrade", category: category,
      marketValue: 2000, snapshot: snap, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.assets.count == 3)
    #expect(viewModel.assets[0].asset.name == "AAPL")
    #expect(viewModel.assets[1].asset.name == "GOOG")
    #expect(viewModel.assets[2].asset.name == "MSFT")
  }

  @Test("Asset list includes latest value from most recent snapshot")
  func assetListIncludesLatestValueFromMostRecentSnapshot() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)

    let (asset, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap1, context: context)

    let sav2 = SnapshotAssetValue(marketValue: 7000)
    sav2.snapshot = snap2
    sav2.asset = asset
    context.insert(sav2)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.assets.count == 1)
    #expect(viewModel.assets[0].latestValue == 7000)
  }

  // MARK: - Value History

  @Test("Value history computed across snapshots with direct values only")
  func valueHistoryComputedAcrossSnapshotsWithDirectValues() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    // Snapshot 1: AAPL on Firstrade = 5000
    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap1, context: context)

    // Snapshot 2: MSFT on Vanguard = 3000 (AAPL is NOT carried forward)
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    createAssetWithValue(
      name: "MSFT", platform: "Vanguard", category: category,
      marketValue: 3000, snapshot: snap2, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.valueHistory.count == 2)
    #expect(viewModel.valueHistory[0].date == snap1.date)
    #expect(viewModel.valueHistory[0].totalValue == 5000)
    // Snap2: only MSFT=3000 (direct), no carry-forward
    #expect(viewModel.valueHistory[1].date == snap2.date)
    #expect(viewModel.valueHistory[1].totalValue == 3000)
  }

  @Test("Value history includes only assets in this category")
  func valueHistoryIncludesOnlyAssetsInThisCategory() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let bonds = Category(name: "Bonds")
    context.insert(bonds)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap, context: context)
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: bonds,
      marketValue: 3000, snapshot: snap, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.valueHistory.count == 1)
    #expect(viewModel.valueHistory[0].totalValue == 5000)
  }

  // MARK: - Allocation History

  @Test("Allocation percentage history computed across snapshots")
  func allocationPercentageHistoryComputedAcrossSnapshots() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let bonds = Category(name: "Bonds")
    context.insert(bonds)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)

    // Equities: 7000, Bonds: 3000, Total: 10000 => Equities = 70%
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 7000, snapshot: snap, context: context)
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: bonds,
      marketValue: 3000, snapshot: snap, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.allocationHistory.count == 1)
    #expect(viewModel.allocationHistory[0].allocationPercentage == 70)
  }

  @Test("Allocation history uses direct snapshot values only")
  func allocationHistoryUsesDirectSnapshotValues() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let bonds = Category(name: "Bonds")
    context.insert(bonds)

    // Snapshot 1: Both platforms present
    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap1, context: context)
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: bonds,
      marketValue: 5000, snapshot: snap1, context: context)

    // Snapshot 2: Only Firstrade updated — Vanguard NOT carried forward
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 8000, snapshot: snap2, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    // Snap2 direct values only: AAPL=8000 => Total=8000
    // Equities allocation: 8000/8000 * 100 = 100%
    #expect(viewModel.allocationHistory.count == 2)
    let snap2Allocation = viewModel.allocationHistory[1].allocationPercentage
    let expectedAllocation = CalculationService.categoryAllocation(
      categoryValue: 8000, totalValue: 8000)
    #expect(snap2Allocation == expectedAllocation)
  }

  // MARK: - Edge Cases

  @Test("Empty category shows zero value at all snapshots")
  func emptyCategoryShowsZeroValueAtAllSnapshots() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let otherCategory = Category(name: "Bonds")
    context.insert(otherCategory)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)

    // Only bonds have values
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: otherCategory,
      marketValue: 5000, snapshot: snap, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.valueHistory.count == 1)
    #expect(viewModel.valueHistory[0].totalValue == 0)
  }

  @Test("Handles single snapshot correctly")
  func handlesSingleSnapshotCorrectly() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.valueHistory.count == 1)
    #expect(viewModel.allocationHistory.count == 1)
  }

  @Test("Handles multiple snapshots in chronological order")
  func handlesMultipleSnapshotsInChronologicalOrder() {
    let tc = createTestContext()
    let (context, category) = (tc.context, tc.category)

    let snap1 = Snapshot(date: makeDate(year: 2025, month: 3, day: 1))
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    let snap3 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap1)
    context.insert(snap2)
    context.insert(snap3)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 5000, snapshot: snap1, context: context)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 3000, snapshot: snap2, context: context)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: category,
      marketValue: 4000, snapshot: snap3, context: context)

    let viewModel = CategoryDetailViewModel(category: category, modelContext: context)
    viewModel.loadData()

    #expect(viewModel.valueHistory.count == 3)
    #expect(viewModel.valueHistory[0].date == snap2.date)
    #expect(viewModel.valueHistory[1].date == snap3.date)
    #expect(viewModel.valueHistory[2].date == snap1.date)
  }

  // MARK: - Editable Properties

  @Test("Editable properties initialized from category model")
  func editablePropertiesInitializedFromCategoryModel() {
    let tc = createTestContext(categoryName: "Equities", targetAllocation: 60)
    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: tc.context)

    #expect(viewModel.editedName == "Equities")
    #expect(viewModel.editedTargetAllocation == 60)
  }

  // MARK: - Save Validation

  @Test("Save rejects duplicate name (case-insensitive, excluding self)")
  func saveRejectsDuplicateNameExcludingSelf() throws {
    let tc = createTestContext(categoryName: "Equities")
    let context = tc.context

    let bonds = Category(name: "Bonds")
    context.insert(bonds)

    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: context)
    viewModel.editedName = "bonds"

    #expect(throws: CategoryError.duplicateName("bonds")) {
      try viewModel.save()
    }
  }

  @Test("Save rejects target allocation above 100")
  func saveRejectsTargetAllocationAbove100() {
    let tc = createTestContext(categoryName: "Equities")

    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: tc.context)
    viewModel.editedTargetAllocation = 150

    #expect(throws: CategoryError.invalidTargetAllocation) {
      try viewModel.save()
    }
  }

  @Test("Save rejects negative target allocation")
  func saveRejectsNegativeTargetAllocation() {
    let tc = createTestContext(categoryName: "Equities")

    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: tc.context)
    viewModel.editedTargetAllocation = -5

    #expect(throws: CategoryError.invalidTargetAllocation) {
      try viewModel.save()
    }
  }

  @Test("Save allows self-rename with different casing")
  func saveAllowsSelfRenameWithDifferentCasing() throws {
    let tc = createTestContext(categoryName: "Equities")

    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: tc.context)
    viewModel.editedName = "EQUITIES"

    try viewModel.save()
    #expect(tc.category.name == "EQUITIES")
  }

  @Test("Save rejects empty name")
  func saveRejectsEmptyName() throws {
    let tc = createTestContext(categoryName: "Equities")

    let viewModel = CategoryDetailViewModel(
      category: tc.category, modelContext: tc.context)
    viewModel.editedName = "   "

    #expect(throws: CategoryError.emptyName) {
      try viewModel.save()
    }
  }
}
