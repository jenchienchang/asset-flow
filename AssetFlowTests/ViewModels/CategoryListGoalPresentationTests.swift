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

@Suite("CategoryListGoalPresentation Tests")
@MainActor
struct CategoryListGoalPresentationTests {
  private struct Fixture {
    let container: ModelContainer
    let categories: [AssetFlow.Category]
    let snapshot: Snapshot
    let vm: CategoryListViewModel
  }
  private func fixture(_ entries: [(Decimal, Decimal?, Decimal?)]) -> Fixture {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let settings = SettingsService.createForTesting()
    settings.mainCurrency = "USD"
    let snapshot = Snapshot(date: Date())
    context.insert(snapshot)
    let categories = entries.enumerated().map { index, entry in
      let category = AssetFlow.Category(
        name: "Category \(index)", targetAllocationPercentage: entry.1)
      category.displayOrder = index
      category.minimumBalanceAmount = entry.2
      category.minimumBalanceCurrency = entry.2 == nil ? nil : "USD"
      let asset = Asset(name: "Asset \(index)")
      asset.category = category
      let value = SnapshotAssetValue(marketValue: entry.0)
      value.asset = asset
      value.snapshot = snapshot
      for model: any PersistentModel in [category, asset, value] { context.insert(model) }
      return category
    }
    let vm = CategoryListViewModel(modelContext: context, settingsService: settings)
    vm.loadCategories()
    return Fixture(container: container, categories: categories, snapshot: snapshot, vm: vm)
  }

  @Test("Minimum-only categories show effective share and warn on every positive shortfall")
  func minimumOnly() throws {
    let tc = fixture([(1, nil, Decimal(string: "1.01")!), (9, 100, nil)])
    let row = try #require(tc.vm.categoryRows.first)
    #expect(row.effectiveTargetAllocation == Decimal(string: "10.1"))
    #expect(row.hasMinimumShortfall)
    #expect(row.hasWarning)
    #expect(!row.hasAllocationDeviation)
    #expect(row.warningMessage.hasPrefix("• "))
    #expect(row.warningMessage.contains("USD"))
    _ = tc.container.mainContext
  }

  @Test("Minimum-only surplus is protected and no-goal categories have no effective target")
  func protectedSurplus() {
    let tc = fixture([(40, nil, 20), (10, nil, nil), (50, 100, nil)])
    #expect(tc.vm.categoryRows[0].effectiveTargetAllocation == 40)
    #expect(!tc.vm.categoryRows[0].hasWarning)
    #expect(tc.vm.categoryRows[1].effectiveTargetAllocation == nil)
    #expect(!tc.vm.categoryRows[1].hasWarning)
    _ = tc.container.mainContext
  }

  @Test("Zero and infeasible portfolios retain minimum warnings without effective shares")
  func unavailableShares() {
    for value: Decimal in [0, 10] {
      let tc = fixture([(value, 100, 20)])
      #expect(tc.vm.categoryRows[0].effectiveTargetAllocation == nil)
      #expect(tc.vm.categoryRows[0].hasMinimumShortfall)
      #expect(!tc.vm.categoryRows[0].hasAllocationDeviation)
      if value == 0 { #expect(tc.vm.categoryRows[0].currentAllocation == nil) }
      _ = tc.container.mainContext
    }
  }

  @Test("The five percentage point boundary is strict and combined warnings explain both reasons")
  func thresholdAndCombined() throws {
    let tc = fixture([(20, 10, 30), (60, 60, nil), (20, 30, nil)])
    var row = try #require(tc.vm.categoryRows.first)
    #expect(row.effectiveTargetAllocation == 30)
    #expect(row.hasMinimumShortfall && row.hasAllocationDeviation)
    #expect(row.warningMessage.components(separatedBy: "\n").count == 2)
    row.minimumStatus = .met
    row.effectiveTargetAllocation = 25
    #expect(!row.hasWarning)
    row.effectiveTargetAllocation = Decimal(string: "25.0001")
    #expect(row.hasAllocationDeviation)
    let targets = try #require(tc.vm.goalAssessment.plan?.targets)
    for row in tc.vm.categoryRows {
      let target = try #require(targets.first { $0.id == row.id })
      #expect(row.currentValue == tc.vm.goalAssessment.values[row.id])
      #expect(row.effectiveTargetAllocation == target.targetValue / 100 * 100)
    }
    _ = tc.container.mainContext
  }

  @Test("Missing minimum conversion does not fabricate a shortfall or effective share")
  func missingRates() {
    let tc = fixture([(10, 100, 20)])
    tc.categories[0].minimumBalanceCurrency = "TWD"
    tc.vm.loadCategories()
    #expect(tc.vm.categoryRows[0].minimumStatus == .unavailable)
    #expect(tc.vm.categoryRows[0].effectiveTargetAllocation == nil)
    #expect(!tc.vm.categoryRows[0].hasWarning)
    _ = tc.container.mainContext
  }
}
