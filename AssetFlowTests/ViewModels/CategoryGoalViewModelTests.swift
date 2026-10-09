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

@Suite("CategoryGoalViewModel Tests")
@MainActor
struct CategoryGoalViewModelTests {
  @Test("Creation saves combined goals; invalid pairs never insert a category")
  func creation() throws {
    let container = TestDataManager.createInMemoryContainer()
    let vm = CategoryListViewModel(modelContext: container.mainContext)
    let category = try vm.createCategory(
      name: "Reserve", targetAllocation: 100, minimumBalance: 300000, minimumCurrency: "twd")
    #expect(category.minimumBalanceAmount == 300000)
    #expect(category.minimumBalanceCurrency == "TWD")
    #expect(throws: (any Error).self) {
      try vm.createCategory(name: "Invalid", targetAllocation: nil, minimumBalance: 10)
    }
    #expect(try container.mainContext.fetch(FetchDescriptor<AssetFlow.Category>()).count == 1)
  }

  @Test("Editing validates all form fields atomically and never saves stale numeric input")
  func editing() throws {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    container.mainContext.insert(category)
    let vm = CategoryDetailViewModel(category: category, modelContext: container.mainContext)
    vm.editedName = "Renamed"
    vm.targetAllocationText = "12garbage"
    #expect(throws: (any Error).self) { try vm.save() }
    #expect(category.name == "Reserve")
    #expect(category.targetAllocationPercentage == 100)
    vm.targetAllocationText = "100"
    vm.minimumEnabled = true
    vm.minimumBalanceText = "300000"
    vm.editedMinimumCurrency = "TWD"
    try vm.save()
    #expect(category.minimumBalanceAmount == 300000)
    #expect(category.minimumBalanceCurrency == "TWD")
    vm.minimumEnabled = false
    try vm.save()
    #expect(category.minimumBalanceAmount == nil)
    #expect(category.minimumBalanceCurrency == nil)
  }

  @Test("Category percentages include uncategorized balances")
  func denominator() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    let snapshot = Snapshot(date: Date())
    context.insert(category)
    context.insert(snapshot)
    for categorized in [true, false] {
      let asset = Asset(name: categorized ? "Reserve account" : "Other account")
      if categorized { asset.category = category }
      let value = SnapshotAssetValue(marketValue: 100)
      value.asset = asset
      value.snapshot = snapshot
      context.insert(asset)
      context.insert(value)
    }
    let vm = CategoryListViewModel(modelContext: context)
    vm.loadCategories()
    #expect(vm.categoryRows.first?.currentAllocation == 50)
  }

  @Test("Rebalancing removes stale suggestions when a minimum becomes infeasible")
  func stalePlan() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 50
    category.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    let snapshot = Snapshot(date: Date())
    let asset = Asset(name: "Account")
    asset.category = category
    let value = SnapshotAssetValue(marketValue: 100)
    value.asset = asset
    value.snapshot = snapshot
    for model: any PersistentModel in [category, snapshot, asset, value] { context.insert(model) }
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    #expect(vm.goalAssessment.plan?.status == .feasible)
    category.minimumBalanceAmount = 200
    vm.loadRebalancing()
    #expect(vm.goalAssessment.plan?.status == .minimumsExceedPortfolio(100))
    #expect(vm.suggestions.isEmpty)
    #expect(vm.summaryTexts.isEmpty)
    #expect(!vm.isEmpty)
  }
  @Test("Subunit mandatory top-up has a funded donor transfer")
  func smallMandatoryTransfer() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let reserve = AssetFlow.Category(name: "Reserve")
    reserve.minimumBalanceAmount = Decimal(string: "1.25")!
    reserve.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    let donor = AssetFlow.Category(name: "Investments", targetAllocationPercentage: 100)
    let snapshot = Snapshot(date: Date())
    for model: any PersistentModel in [reserve, donor, snapshot] { context.insert(model) }
    for (category, amount) in [(reserve, Decimal(1)), (donor, Decimal(9))] {
      let asset = Asset(name: category.name)
      asset.category = category
      let value = SnapshotAssetValue(marketValue: amount)
      value.asset = asset
      value.snapshot = snapshot
      context.insert(asset)
      context.insert(value)
    }
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    #expect(vm.suggestions.first { $0.categoryID == reserve.id }?.actionType == .buy)
    #expect(vm.suggestions.first { $0.categoryID == donor.id }?.actionType == .sell)
    #expect(vm.summaryTexts.count == 1)
    #expect(vm.smallAdjustmentResidual == 0)
    let oldID = vm.suggestions.first { $0.categoryID == reserve.id }?.id
    reserve.name = "New reserve name"
    vm.loadRebalancing()
    #expect(vm.suggestions.first { $0.categoryID == reserve.id }?.id == oldID)
  }

  @Test("Suggested Moves uses minimum-first transfers for the reported portfolio")
  func minimumFirstSummary() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = Snapshot(date: Date())
    context.insert(snapshot)
    let entries: [(String, String, String, String?)] = [
      ("Donor", "40", "30", nil), ("Small donor", "20.5", "20", nil),
      ("Larger buy", "39.5", "49.8", nil), ("Minimum", "0", "0.2", "0.2"),
    ]
    for (name, balance, percentage, minimum) in entries {
      let category = AssetFlow.Category(
        name: name, targetAllocationPercentage: Decimal(string: percentage)!)
      category.minimumBalanceAmount = minimum.map { Decimal(string: $0)! }
      category.minimumBalanceCurrency = minimum == nil ? nil : SettingsService.shared.mainCurrency
      let asset = Asset(name: name)
      asset.category = category
      let value = SnapshotAssetValue(marketValue: Decimal(string: balance)!)
      value.asset = asset
      value.snapshot = snapshot
      for model: any PersistentModel in [category, asset, value] { context.insert(model) }
    }
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    let currency = SettingsService.shared.mainCurrency
    let mandatory = CategoryGoalPresentation.amount(Decimal(string: "0.2")!, currency: currency)
    let optional = Decimal(string: "9.8")!.formatted(currency: currency)
    #expect(
      vm.summaryTexts == [
        String(
          localized: "Move \(mandatory) from \("Donor") to \("Minimum")", table: "Rebalancing"),
        String(
          localized: "Move \(optional) from \("Donor") to \("Larger buy")", table: "Rebalancing"),
      ])
    #expect(vm.smallAdjustmentResidual == 1)
    #expect(vm.suggestions.first { $0.categoryName == "Small donor" }?.actionType == .noAction)
  }

  @Test("Historical minimum conversion has gaps without hiding category values")
  func historyGaps() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "USD"
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 300000
    category.minimumBalanceCurrency = "TWD"
    context.insert(category)
    for day in 0..<3 {
      let snapshot = Snapshot(
        date: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(day * 86400)))
      context.insert(snapshot)
      if day != 1 {
        let rate = ExchangeRate(
          baseCurrency: "usd", ratesJSON: try JSONEncoder().encode(["twd": Decimal(30)]),
          fetchDate: snapshot.date)
        rate.snapshot = snapshot
        context.insert(rate)
      }
    }
    let vm = CategoryDetailViewModel(
      category: category, modelContext: context, settingsService: settings)
    vm.loadData()
    #expect(vm.valueHistory.count == 3)
    #expect(vm.minimumHistory.count == 2)
    #expect(vm.minimumHistory.map(\.segment) == [0, 1])
    #expect(vm.minimumHistory.allSatisfy { $0.amount == 10000 })
    #expect(vm.conversionStatus.isComplete)
  }

  @Test("A fully funded recurring allocation has no spurious residual")
  func noArithmeticResidual() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = Snapshot(date: Date())
    context.insert(snapshot)
    for (name, value, weight, minimum): (String, Decimal, Decimal, Decimal?) in [
      ("Reserve", 200000, 10, 300000), ("Equities", 600000, 60, nil), ("Bonds", 200000, 30, nil),
    ] {
      let category = AssetFlow.Category(name: name, targetAllocationPercentage: weight)
      category.minimumBalanceAmount = minimum
      category.minimumBalanceCurrency = minimum == nil ? nil : SettingsService.shared.mainCurrency
      let asset = Asset(name: name)
      asset.category = category
      let amount = SnapshotAssetValue(marketValue: value)
      amount.asset = asset
      amount.snapshot = snapshot
      for model: any PersistentModel in [category, asset, amount] { context.insert(model) }
    }
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    #expect(vm.smallAdjustmentResidual == 0)
  }

  @Test("Dirty fields remain drafts until save, and Revert restores every field")
  func draftsAndRevert() throws {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 50
    category.minimumBalanceCurrency = "USD"
    container.mainContext.insert(category)
    let vm = CategoryDetailViewModel(category: category, modelContext: container.mainContext)
    #expect(!vm.hasUnsavedChanges)
    vm.editedName = "New name"
    vm.targetAllocationText = "invalid"
    vm.minimumEnabled = false
    vm.minimumBalanceText = "80"
    vm.editedMinimumCurrency = "TWD"
    #expect(vm.hasUnsavedChanges)
    #expect(category.name == "Reserve")
    #expect(throws: (any Error).self) { try vm.save() }
    #expect(vm.hasUnsavedChanges)
    vm.revertChanges()
    #expect(vm.editedName == "Reserve")
    #expect(vm.editedTargetAllocation == 100)
    #expect(vm.minimumEnabled)
    #expect(vm.minimumBalanceText == "50")
    #expect(vm.editedMinimumCurrency == "USD")
    #expect(!vm.hasUnsavedChanges)
    vm.minimumBalanceText = "80"
    try vm.save()
    #expect(category.minimumBalanceAmount == 80)
    #expect(!vm.hasUnsavedChanges)
  }

  @Test(
    "Snapshot-sheet cancellation preserves protection after either Save or Discard",
    arguments: [true, false])
  func snapshotSheetCancellation(save: Bool) throws {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    container.mainContext.insert(category)
    let vm = CategoryDetailViewModel(category: category, modelContext: container.mainContext)
    let session = CategoryEditingSession()
    session.editor = vm
    var sheetPresented = false
    vm.editedName = "First draft"
    session.requestNavigation { sheetPresented = true }
    if save { try session.saveAndNavigate() } else { session.discardAndNavigate() }
    #expect(sheetPresented)
    session.updateVisibleCategory(category)
    #expect(session.editor === vm)
    sheetPresented = false
    vm.editedName = "Second draft"
    var left = false
    session.requestNavigation { left = true }
    #expect(session.needsConfirmation)
    #expect(!left)
    session.cancelNavigation()
    #expect(vm.editedName == "Second draft")
    #expect(session.editor === vm)
  }

  @Test("Editor is released when navigation actually replaces the visible category")
  func actualEditorReplacement() {
    let container = TestDataManager.createInMemoryContainer()
    let first = AssetFlow.Category(name: "First")
    let second = AssetFlow.Category(name: "Second")
    container.mainContext.insert(first)
    container.mainContext.insert(second)
    let vm = CategoryDetailViewModel(category: first, modelContext: container.mainContext)
    let session = CategoryEditingSession()
    session.editor = vm
    session.updateVisibleCategory(first)
    #expect(session.editor === vm)
    session.updateVisibleCategory(second)
    #expect(session.editor == nil)
    session.editor = vm
    session.updateVisibleCategory(nil)
    #expect(session.editor == nil)
  }

  @Test("ContentView retains editor registration while opening the snapshot sheet")
  func snapshotSheetWiring() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
      contentsOf: root.appending(path: "AssetFlow/Views/ContentView.swift"), encoding: .utf8)
    let start = try #require(source.range(of: "private var sidebarBinding:"))
    let end = try #require(
      source.range(of: "// MARK: - Detail Pane", range: start.upperBound..<source.endIndex))
    let sidebar = String(source[start.lowerBound..<end.lowerBound])
    // Source contracts should survive formatter changes to indentation and line wrapping.
    let normalizedSource = source.filter { !$0.isWhitespace }
    let normalizedSidebar = sidebar.filter { !$0.isWhitespace }
    #expect(!normalizedSidebar.contains("categoryEditingSession.editor=nil"))
    #expect(normalizedSource.contains(".onChange(of:selectedSection)"))
    #expect(normalizedSource.contains(".onChange(of:selectedCategory.map(ObjectIdentifier.init))"))
    #expect(
      normalizedSource.contains(
        "categoryEditingSession.updateVisibleCategory(selectedSection==.categories?selectedCategory:nil)"
      ))
  }

  @Test("Navigation waits for Save or Discard; Cancel and invalid saves retain the draft")
  func guardedNavigation() throws {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    container.mainContext.insert(category)
    let vm = CategoryDetailViewModel(category: category, modelContext: container.mainContext)
    let session = CategoryEditingSession()
    session.editor = vm
    var navigated = false
    vm.editedName = "New name"
    session.requestNavigation { navigated = true }
    #expect(!navigated)
    #expect(session.needsConfirmation)
    session.cancelNavigation()
    #expect(!session.needsConfirmation)
    #expect(vm.editedName == "New name")
    session.requestNavigation { navigated = true }
    vm.targetAllocationText = "invalid"
    #expect(throws: (any Error).self) { try session.saveAndNavigate() }
    #expect(!navigated)
    #expect(session.needsConfirmation)
    #expect(category.name == "Reserve")
    vm.targetAllocationText = "100"
    try session.saveAndNavigate()
    #expect(navigated)
    #expect(category.name == "New name")
    #expect(!session.needsConfirmation)
    navigated = false
    vm.editedName = "Discard me"
    session.requestNavigation { navigated = true }
    session.discardAndNavigate()
    #expect(navigated)
    #expect(vm.editedName == "New name")
    #expect(!vm.hasUnsavedChanges)
  }

}
