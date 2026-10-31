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

@Suite("CategoryListViewModel Tests")
@MainActor
struct CategoryListViewModelTests {

  // MARK: - Test Helpers

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
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
    let asset = Asset(name: name, platform: platform)
    asset.category = category
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  // MARK: - Listing

  @Test("Lists categories sorted alphabetically by name")
  func listsCategoriesSortedAlphabetically() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let crypto = Category(name: "Crypto")
    let bonds = Category(name: "Bonds")
    let equities = Category(name: "Equities")
    context.insert(crypto)
    context.insert(bonds)
    context.insert(equities)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 3)
    #expect(viewModel.categoryRows[0].category.name == "Bonds")
    #expect(viewModel.categoryRows[1].category.name == "Crypto")
    #expect(viewModel.categoryRows[2].category.name == "Equities")
  }

  @Test("Computes target allocation percentage")
  func computesTargetAllocationPercentage() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: 40)
    context.insert(equities)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 1)
    #expect(viewModel.categoryRows[0].targetAllocation == 40)
  }

  @Test("Categories without target allocation show nil")
  func categoriesWithoutTargetAllocationShowNil() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 1)
    #expect(viewModel.categoryRows[0].targetAllocation == nil)
  }

  @Test("Computes current allocation from latest snapshot direct values")
  func computesCurrentAllocationFromLatestSnapshotDirectValues() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    context.insert(equities)
    context.insert(bonds)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    // Equities: 7000 out of 10000 = 70%
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 7000, snapshot: snapshot, context: context)
    // Bonds: 3000 out of 10000 = 30%
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: bonds,
      marketValue: 3000, snapshot: snapshot, context: context)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    // Sorted alphabetically: Bonds, Equities
    #expect(viewModel.categoryRows.count == 2)
    #expect(viewModel.categoryRows[0].category.name == "Bonds")
    #expect(viewModel.categoryRows[0].currentAllocation == 30)
    #expect(viewModel.categoryRows[1].category.name == "Equities")
    #expect(viewModel.categoryRows[1].currentAllocation == 70)
  }

  @Test("Computes current value from latest snapshot direct values")
  func computesCurrentValueFromLatestSnapshotDirectValues() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let snapshot = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snapshot)

    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 5000, snapshot: snapshot, context: context)
    createAssetWithValue(
      name: "MSFT", platform: "Firstrade", category: equities,
      marketValue: 3000, snapshot: snapshot, context: context)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 1)
    #expect(viewModel.categoryRows[0].currentValue == 8000)
  }

  @Test("Computes asset count per category")
  func computesAssetCountPerCategory() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let asset1 = Asset(name: "AAPL", platform: "Firstrade")
    asset1.category = equities
    let asset2 = Asset(name: "MSFT", platform: "Firstrade")
    asset2.category = equities
    let asset3 = Asset(name: "GOOG", platform: "Firstrade")
    asset3.category = equities
    context.insert(asset1)
    context.insert(asset2)
    context.insert(asset3)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 1)
    #expect(viewModel.categoryRows[0].assetCount == 3)
  }

  // MARK: - Create

  @Test("Create category with unique name succeeds")
  func createCategoryWithUniqueNameSucceeds() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = CategoryListViewModel(modelContext: context)
    let category = try viewModel.createCategory(name: "Equities", targetAllocation: nil)

    #expect(category.name == "Equities")

    let descriptor = FetchDescriptor<AssetFlow.Category>()
    let all = try context.fetch(descriptor)
    #expect(all.count == 1)
  }

  @Test("Create category rejects duplicate name (case-insensitive)")
  func createCategoryRejectsDuplicateNameCaseInsensitive() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let existing = Category(name: "Equities")
    context.insert(existing)

    let viewModel = CategoryListViewModel(modelContext: context)

    #expect(throws: CategoryError.self) {
      try viewModel.createCategory(name: "equities", targetAllocation: nil)
    }
  }

  @Test("Create category rejects empty name")
  func createCategoryRejectsEmptyName() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = CategoryListViewModel(modelContext: context)

    #expect(throws: CategoryError.emptyName) {
      try viewModel.createCategory(name: "   ", targetAllocation: nil)
    }
  }

  @Test("Create category validates target allocation range 0-100")
  func createCategoryValidatesTargetAllocationRange() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = CategoryListViewModel(modelContext: context)

    #expect(throws: CategoryError.invalidTargetAllocation) {
      try viewModel.createCategory(name: "Equities", targetAllocation: 150)
    }

    #expect(throws: CategoryError.invalidTargetAllocation) {
      try viewModel.createCategory(name: "Equities", targetAllocation: -5)
    }
  }

  // MARK: - Delete

  @Test("Delete category succeeds when no assets")
  func deleteCategorySucceedsWhenNoAssets() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let category = Category(name: "Empty")
    context.insert(category)

    let viewModel = CategoryListViewModel(modelContext: context)
    try viewModel.deleteCategory(category)

    let descriptor = FetchDescriptor<AssetFlow.Category>()
    let remaining = try context.fetch(descriptor)
    #expect(remaining.isEmpty)
  }

  @Test("Delete category blocked when assets assigned")
  func deleteCategoryBlockedWhenAssetsAssigned() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let asset = Asset(name: "AAPL", platform: "Firstrade")
    asset.category = equities
    context.insert(asset)

    let viewModel = CategoryListViewModel(modelContext: context)

    #expect(throws: CategoryError.cannotDelete(assetCount: 1)) {
      try viewModel.deleteCategory(equities)
    }
  }

  // MARK: - Edit

  @Test("Edit category name with uniqueness check")
  func editCategoryNameWithUniquenessCheck() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    context.insert(equities)
    context.insert(bonds)

    let viewModel = CategoryListViewModel(modelContext: context)

    // Rename to existing name should throw
    #expect(throws: CategoryError.duplicateName("Bonds")) {
      try viewModel.editCategory(equities, newName: "Bonds", newTargetAllocation: nil)
    }
  }

  @Test("Edit target allocation updates category")
  func editTargetAllocationUpdatesCategory() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: 50)
    context.insert(equities)

    let viewModel = CategoryListViewModel(modelContext: context)
    try viewModel.editCategory(equities, newName: "Equities", newTargetAllocation: 70)

    #expect(equities.targetAllocationPercentage == 70)
  }

  @Test("Edit category rejects empty name")
  func editCategoryRejectsEmptyName() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    context.insert(equities)

    let viewModel = CategoryListViewModel(modelContext: context)

    #expect(throws: CategoryError.emptyName) {
      try viewModel.editCategory(equities, newName: "  ", newTargetAllocation: nil)
    }
  }

  // MARK: - Target Allocation Warning

  @Test("Target allocation sum warning when not 100%")
  func targetAllocationSumWarningWhenNot100() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: 60)
    let bonds = Category(name: "Bonds", targetAllocationPercentage: 30)
    context.insert(equities)
    context.insert(bonds)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.goalAssessment.plan == nil)
    #expect(
      viewModel.targetAllocationSumWarning
        == CategoryGoalPresentation.diagnostic(
          RebalancingPlan(status: .invalidPercentageSum(90)), currency: "USD"))
  }

  @Test("No warning when sum is 100%")
  func noWarningWhenSumIs100() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: 60)
    let bonds = Category(name: "Bonds", targetAllocationPercentage: 40)
    context.insert(equities)
    context.insert(bonds)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.targetAllocationSumWarning == nil)
  }

  // MARK: - Empty State

  @Test("Empty state when no categories")
  func emptyStateWhenNoCategories() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.isEmpty)
  }

  // MARK: - Nil Allocation

  @Test("Current allocation is nil when no snapshots exist")
  func currentAllocationIsNilWhenNoSnapshotsExist() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: 60)
    let bonds = Category(name: "Bonds", targetAllocationPercentage: 40)
    context.insert(equities)
    context.insert(bonds)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 2)
    #expect(viewModel.categoryRows[0].currentAllocation == nil)
    #expect(viewModel.categoryRows[1].currentAllocation == nil)
  }

  // MARK: - Display Order

  @Test("New categories receive sequential displayOrder values")
  func newCategoriesReceiveSequentialDisplayOrder() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let viewModel = CategoryListViewModel(modelContext: context)
    let cat1 = try viewModel.createCategory(name: "Alpha", targetAllocation: nil)
    let cat2 = try viewModel.createCategory(name: "Beta", targetAllocation: nil)
    let cat3 = try viewModel.createCategory(name: "Gamma", targetAllocation: nil)

    #expect(cat1.displayOrder == 0)
    #expect(cat2.displayOrder == 1)
    #expect(cat3.displayOrder == 2)
  }

  @Test("Categories sorted by displayOrder")
  func categoriesSortedByDisplayOrder() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let gamma = Category(name: "Gamma")
    gamma.displayOrder = 0
    let alpha = Category(name: "Alpha")
    alpha.displayOrder = 1
    let beta = Category(name: "Beta")
    beta.displayOrder = 2
    context.insert(gamma)
    context.insert(alpha)
    context.insert(beta)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 3)
    #expect(viewModel.categoryRows[0].category.name == "Gamma")
    #expect(viewModel.categoryRows[1].category.name == "Alpha")
    #expect(viewModel.categoryRows[2].category.name == "Beta")
  }

  @Test("Delete category compacts displayOrder")
  func deleteCategoryCompactsDisplayOrder() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let a = Category(name: "A")
    a.displayOrder = 0
    let b = Category(name: "B")
    b.displayOrder = 1
    let c = Category(name: "C")
    c.displayOrder = 2
    context.insert(a)
    context.insert(b)
    context.insert(c)

    let viewModel = CategoryListViewModel(modelContext: context)
    try viewModel.deleteCategory(b)
    viewModel.loadCategories()

    #expect(viewModel.categoryRows.count == 2)
    #expect(a.displayOrder == 0)
    #expect(c.displayOrder == 1)
  }

  @Test("Migration normalizes all-zero displayOrder alphabetically")
  func migrationNormalizesAllZeroDisplayOrder() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let gamma = Category(name: "Gamma")
    let alpha = Category(name: "Alpha")
    let beta = Category(name: "Beta")
    context.insert(gamma)
    context.insert(alpha)
    context.insert(beta)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    #expect(alpha.displayOrder == 0)
    #expect(beta.displayOrder == 1)
    #expect(gamma.displayOrder == 2)
  }

  @Test("moveCategories updates displayOrder correctly")
  func moveCategoriesUpdatesDisplayOrder() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let a = Category(name: "A")
    a.displayOrder = 0
    let b = Category(name: "B")
    b.displayOrder = 1
    let c = Category(name: "C")
    c.displayOrder = 2
    context.insert(a)
    context.insert(b)
    context.insert(c)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    // Move C (index 2) to position 0
    viewModel.moveCategories(from: IndexSet(integer: 2), to: 0)

    #expect(viewModel.categoryRows[0].category.name == "C")
    #expect(viewModel.categoryRows[1].category.name == "A")
    #expect(viewModel.categoryRows[2].category.name == "B")
    #expect(c.displayOrder == 0)
    #expect(a.displayOrder == 1)
    #expect(b.displayOrder == 2)
  }

  @Test("moveCategories moves item downward correctly")
  func moveCategoriesMovesItemDownward() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let a = Category(name: "A")
    a.displayOrder = 0
    let b = Category(name: "B")
    b.displayOrder = 1
    let c = Category(name: "C")
    c.displayOrder = 2
    context.insert(a)
    context.insert(b)
    context.insert(c)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    // Move A (index 0) to after C (destination 3 in SwiftUI onMove semantics)
    viewModel.moveCategories(from: IndexSet(integer: 0), to: 3)

    #expect(viewModel.categoryRows[0].category.name == "B")
    #expect(viewModel.categoryRows[1].category.name == "C")
    #expect(viewModel.categoryRows[2].category.name == "A")
    #expect(b.displayOrder == 0)
    #expect(c.displayOrder == 1)
    #expect(a.displayOrder == 2)
  }

  // MARK: - Direct Values Only (No Carry Forward)

  @Test("Current allocation uses only stored values from latest snapshot")
  func currentAllocationUsesDirectValuesOnly() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities")
    let bonds = Category(name: "Bonds")
    context.insert(equities)
    context.insert(bonds)

    // Snapshot 1: Equities on Firstrade, Bonds on Vanguard
    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 5000, snapshot: snap1, context: context)
    createAssetWithValue(
      name: "Treasury", platform: "Vanguard", category: bonds,
      marketValue: 5000, snapshot: snap1, context: context)

    // Snapshot 2: Only Firstrade updated — Vanguard NOT carried forward
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    createAssetWithValue(
      name: "AAPL", platform: "Firstrade", category: equities,
      marketValue: 7000, snapshot: snap2, context: context)

    let viewModel = CategoryListViewModel(modelContext: context)
    viewModel.loadCategories()

    // Latest snapshot only has AAPL=7000 (direct), no carry-forward
    // Bonds: 0 (not in latest snapshot), Equities: 7000/7000 = 100%
    let equitiesRow = viewModel.categoryRows.first { $0.category.name == "Equities" }

    #expect(equitiesRow != nil)
    #expect(equitiesRow!.currentValue == 7000)
    #expect(equitiesRow!.currentAllocation == 100)
  }
}
