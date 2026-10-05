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

@Suite("CategoryGoalAssessment Tests")
@MainActor
struct CategoryGoalAssessmentTests {
  @Test("Missing goal-only currency does not hide valid asset values")
  func missingGoalRate() throws {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 300000
    category.minimumBalanceCurrency = "TWD"
    let snapshot = Snapshot(date: Date())
    let asset = Asset(name: "USD account")
    asset.currency = "USD"
    asset.category = category
    let value = SnapshotAssetValue(marketValue: 10000)
    value.asset = asset
    value.snapshot = snapshot
    for model: any PersistentModel in [category, snapshot, asset, value] {
      container.mainContext.insert(model)
    }
    let unavailable = CategoryGoalAssessmentService.assess(
      snapshot: snapshot, categories: [category], displayCurrency: "USD")
    #expect(unavailable.totalValue == 10000)
    #expect(unavailable.assetConversion.isComplete)
    #expect(unavailable.goalConversion == .missingRates(["twd"]))
    #expect(unavailable.statuses[category.id] == .unavailable)
    #expect(unavailable.plan == nil)
    #expect(
      CategoryGoalAssessmentService.requiredCurrencies(
        categories: [category], displayCurrency: "USD") == ["twd"])
    let rate = ExchangeRate(
      baseCurrency: "usd", ratesJSON: try JSONEncoder().encode(["twd": Decimal(30)]),
      fetchDate: snapshot.date)
    rate.snapshot = snapshot
    container.mainContext.insert(rate)
    let complete = CategoryGoalAssessmentService.assess(
      snapshot: snapshot, categories: [category], displayCurrency: "USD")
    #expect(complete.minimums[category.id] == 10000)
    #expect(complete.statuses[category.id] == .met)
    #expect(complete.plan?.status == .feasible)
    category.minimumBalanceAmount = 300003
    let short = CategoryGoalAssessmentService.assess(
      snapshot: snapshot, categories: [category], displayCurrency: "USD")
    #expect(short.statuses[category.id] == .shortfall(Decimal(string: "0.1")!))
    #expect(short.plan?.status == .minimumsExceedPortfolio(Decimal(string: "0.1")!))
  }

  @Test("No snapshot, zero value, and ID-based categories are distinct")
  func noSnapshotAndZero() {
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Uncategorized", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 10
    category.minimumBalanceCurrency = "USD"
    container.mainContext.insert(category)
    let absent = CategoryGoalAssessmentService.assess(
      snapshot: nil, categories: [category], displayCurrency: "USD")
    #expect(absent.totalValue == nil)
    #expect(absent.statuses[category.id] == .noSnapshot)
    let snapshot = Snapshot(date: Date())
    container.mainContext.insert(snapshot)
    let zero = CategoryGoalAssessmentService.assess(
      snapshot: snapshot, categories: [category], displayCurrency: "USD")
    #expect(zero.totalValue == 0)
    #expect(zero.statuses[category.id] == .shortfall(10))
    #expect(zero.plan?.status == .minimumsExceedPortfolio(10))
  }
  @Test("Synthetic multi-currency snapshots calculate consistently across relationship ordering")
  func convertedSnapshots() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let weights: [Decimal] = [35, 20, 15, 15, 10, 5]
    let categories = weights.enumerated().map { index, weight in
      let category = AssetFlow.Category(
        name: "Category \(index)", targetAllocationPercentage: weight)
      category.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
      context.insert(category)
      return category
    }
    let currencies = ["USD", "EUR", "USDT", "TWD"]
    let rates = [
      "usd": Decimal(string: "0.031234568")!, "eur": Decimal(string: "4.821943")!,
      "usdt": Decimal(string: "0.02874319")!, "twd": Decimal(1),
    ]
    for seed in 1...3 {
      let snapshot = Snapshot(
        date: Date(timeIntervalSince1970: Double(1_700_000_000 + seed * 86400)))
      context.insert(snapshot)
      let rate = ExchangeRate(
        baseCurrency: "twd", ratesJSON: try JSONEncoder().encode(rates), fetchDate: snapshot.date)
      rate.snapshot = snapshot
      context.insert(rate)
      var values: [SnapshotAssetValue] = []
      for index in 0..<30 {
        let asset = Asset(name: "Asset \(seed)-\(index)")
        asset.id = UUID(
          uuidString: String(format: "00000000-0000-0000-0000-%012d", seed * 100 + index))!
        asset.currency = currencies[index % currencies.count]
        asset.category = categories[(index * 7 + seed) % categories.count]
        let value = SnapshotAssetValue(
          marketValue: Decimal((seed * 7919 + index * 1543) % 100000 + 1) / 100)
        value.asset = asset
        value.snapshot = snapshot
        context.insert(asset)
        context.insert(value)
        values.append(value)
      }
      snapshot.assetValues = values
      let forward = CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: categories, displayCurrency: "TWD")
      #expect(forward.assetConversion == .applied)
      #expect(forward.plan?.status == .feasible)
      snapshot.assetValues = values.reversed()
      let reverse = CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: categories.reversed(), displayCurrency: "TWD")
      #expect(reverse.totalValue == forward.totalValue)
      #expect(reverse.values == forward.values)
      #expect(reverse.plan == forward.plan)
      #expect(
        categories.allSatisfy { $0.minimumBalanceAmount == nil && $0.minimumBalanceCurrency == nil }
      )
    }
  }

}
