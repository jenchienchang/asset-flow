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

@Suite("CategoryGoalMigration Tests")
@MainActor
struct CategoryGoalMigrationTests {
  @Test("V1 disk graph migrates and new goals survive reopening")
  func diskMigration() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "fixture.store")
    let id = UUID()
    try createLegacyStore(url: url, id: id)
    try verifyAndAddGoal(url: url, id: id)
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, migrationPlan: AssetFlowMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url)])
    let category = try #require(
      container.mainContext.fetch(FetchDescriptor<AssetFlow.Category>()).first)
    #expect(category.minimumBalanceAmount == Decimal(string: "300000.123456789")!)
    #expect(category.minimumBalanceCurrency == "TWD")
    #expect(category.id == id)
    #expect(category.assets?.first?.snapshotAssetValues?.first?.marketValue == 500000)
  }

  @Test("Migrated V1 multi-currency history remains rebalancable without minimum goals")
  func convertedHistoryMigration() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "converted.store")
    try createLegacyConvertedStore(url: url)
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, migrationPlan: AssetFlowMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let categories = try context.fetch(FetchDescriptor<AssetFlow.Category>())
    let snapshots = try context.fetch(FetchDescriptor<Snapshot>())
    #expect(categories.count == 6)
    #expect(snapshots.count == 3)
    #expect(
      categories.allSatisfy { $0.minimumBalanceAmount == nil && $0.minimumBalanceCurrency == nil })
    for snapshot in snapshots {
      #expect(snapshot.assetValues?.count == 30)
      let assessment = CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: categories, displayCurrency: "TWD")
      #expect(assessment.assetConversion == .applied)
      let plan = try #require(assessment.plan)
      #expect(plan.status == .feasible)
      let total = try #require(assessment.totalValue)
      #expect(
        abs(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } - total)
          <= RebalancingCalculator.arithmeticTolerance(total: total))
    }
  }

  private func createLegacyConvertedStore(url: URL) throws {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let weights: [Decimal] = [35, 20, 15, 15, 10, 5]
    let categories = weights.enumerated().map { index, weight in
      let category = SchemaV1.Category(
        name: "Category \(index)", targetAllocationPercentage: weight)
      category.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
      context.insert(category)
      return category
    }
    let currencies = ["USD", "EUR", "USDT", "TWD"]
    let assets = (0..<30).map { index in
      let asset = SchemaV1.Asset(name: "Asset \(index)")
      asset.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 100 + index))!
      asset.currency = currencies[index % currencies.count]
      asset.category = categories[(index * 7 + 1) % categories.count]
      context.insert(asset)
      return asset
    }
    let rates = [
      "usd": Decimal(string: "0.031234568")!, "eur": Decimal(string: "4.821943")!,
      "usdt": Decimal(string: "0.02874319")!, "twd": Decimal(1),
    ]
    for seed in 1...3 {
      let snapshot = SchemaV1.Snapshot(
        date: Date(timeIntervalSince1970: Double(1_700_000_000 + seed * 86400)))
      context.insert(snapshot)
      let rate = SchemaV1.ExchangeRate(
        baseCurrency: "twd", ratesJSON: try JSONEncoder().encode(rates), fetchDate: snapshot.date)
      rate.snapshot = snapshot
      context.insert(rate)
      for (index, asset) in assets.enumerated() {
        let value = SchemaV1.SnapshotAssetValue(
          marketValue: Decimal((seed * 7919 + index * 1543) % 100000 + 1) / 100)
        value.asset = asset
        value.snapshot = snapshot
        context.insert(value)
      }
    }
    try context.save()
  }

  private func createLegacyStore(url: URL, id: UUID) throws {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let container = try ModelContainer(
      for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let category = SchemaV1.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.id = id
    category.displayOrder = 7
    let asset = SchemaV1.Asset(name: "Account", platform: "Bank")
    asset.currency = "TWD"
    asset.category = category
    let snapshot = SchemaV1.Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    let value = SchemaV1.SnapshotAssetValue(marketValue: 500000)
    value.asset = asset
    value.snapshot = snapshot
    let flow = SchemaV1.CashFlowOperation(cashFlowDescription: "Deposit", amount: 20)
    flow.currency = "USD"
    flow.snapshot = snapshot
    let rate = SchemaV1.ExchangeRate(
      baseCurrency: "twd", ratesJSON: try JSONEncoder().encode(["usd": Decimal(string: "0.03")!]),
      fetchDate: snapshot.date)
    rate.snapshot = snapshot
    for model: any PersistentModel in [category, asset, snapshot, value, flow, rate] {
      context.insert(model)
    }
    try context.save()
  }

  private func verifyAndAddGoal(url: URL, id: UUID) throws {
    let schema = CurrentSchema.schema
    let container = try ModelContainer(
      for: schema, migrationPlan: AssetFlowMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url)])
    let context = container.mainContext
    let category = try #require(context.fetch(FetchDescriptor<AssetFlow.Category>()).first)
    #expect(category.id == id)
    #expect(category.displayOrder == 7)
    #expect(category.targetAllocationPercentage == 100)
    #expect(category.minimumBalanceAmount == nil)
    #expect(category.minimumBalanceCurrency == nil)
    let snapshot = try #require(context.fetch(FetchDescriptor<Snapshot>()).first)
    #expect(snapshot.cashFlowOperations?.first?.currency == "USD")
    #expect(snapshot.exchangeRate?.baseCurrency == "twd")
    #expect(snapshot.assetValues?.first?.asset?.category?.id == id)
    category.minimumBalanceAmount = Decimal(string: "300000.123456789")!
    category.minimumBalanceCurrency = "TWD"
    try context.save()
  }
}
