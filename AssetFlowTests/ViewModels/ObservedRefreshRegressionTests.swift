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
import Observation
import SwiftData
import Testing

@testable import AssetFlow

@Suite("ObservedRefreshRegression Tests")
@MainActor
struct ObservedRefreshRegressionTests {
  private final class CountingFetcher: ModelFetching {
    let context: ModelContext
    var calls = 0
    init(_ context: ModelContext) { self.context = context }
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
      calls += 1
      if calls > 100 { throw ProbeStopped() }
      return try context.fetch(descriptor)
    }
  }
  private struct ProbeStopped: Error {}
  @MainActor private final class ChangeFlag { var changed = false }
  private func settle() async {
    for _ in 0..<100 { await Task.yield() }
  }

  @Test("Repeated category loads settle and later minimum changes still refresh")
  func categoryReloads() async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 0
    category.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    let snapshot = Snapshot(date: Date())
    context.insert(category)
    context.insert(snapshot)
    let fetcher = CountingFetcher(context)
    let vm = CategoryListViewModel(modelContext: context, fetcher: fetcher)
    vm.loadCategories()
    vm.loadCategories()
    await settle()
    #expect(fetcher.calls < 20)
    let settled = fetcher.calls
    await settle()
    #expect(fetcher.calls == settled)
    category.minimumBalanceAmount = 100
    category.minimumBalanceAmount = 200
    await settle()
    #expect(vm.goalAssessment.plan?.status == .minimumsExceedPortfolio(200))
    #expect(fetcher.calls < 30)
    _ = container.mainContext
  }

  @Test("Saving minimums settles and external refresh preserves the draft")
  func saveAndDraft() async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    category.minimumBalanceAmount = 0
    category.minimumBalanceCurrency = "USD"
    context.insert(category)
    context.insert(Snapshot(date: Date()))
    let fetcher = CountingFetcher(context)
    let vm = CategoryDetailViewModel(category: category, modelContext: context, fetcher: fetcher)
    vm.loadData()
    vm.minimumBalanceText = "100"
    try vm.save()
    await settle()
    #expect(fetcher.calls < 20)
    vm.editedName = "Unsaved name"
    category.minimumBalanceAmount = 200
    await settle()
    #expect(vm.goalAssessment.minimums[category.id] == 200)
    #expect(vm.editedName == "Unsaved name")
    #expect(vm.hasUnsavedChanges)
    #expect(fetcher.calls < 30)
    _ = container.mainContext
  }

  @Test("All aggregate loaders settle after repeated explicit refreshes")
  func allLoaders() async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    let asset = Asset(name: "Cash", platform: "Bank")
    asset.category = category
    let snapshot = Snapshot(date: Date())
    let value = SnapshotAssetValue(marketValue: 100)
    value.asset = asset
    value.snapshot = snapshot
    for model: any PersistentModel in [category, asset, snapshot, value] { context.insert(model) }
    let fetcher = CountingFetcher(context)
    let dashboard = DashboardViewModel(modelContext: context, fetcher: fetcher)
    let platformList = PlatformListViewModel(modelContext: context, fetcher: fetcher)
    let platformDetail = PlatformDetailViewModel(
      platformName: "Bank", modelContext: context, fetcher: fetcher)
    let rebalancing = RebalancingViewModel(modelContext: context, fetcher: fetcher)
    let assetList = AssetListViewModel(modelContext: context, fetcher: fetcher)
    let assetDetail = AssetDetailViewModel(asset: asset, modelContext: context, fetcher: fetcher)
    let snapshotList = SnapshotListViewModel(modelContext: context, fetcher: fetcher)
    let snapshotDetail = SnapshotDetailViewModel(
      snapshot: snapshot, modelContext: context, fetcher: fetcher)
    let loads: [() -> Void] = [
      dashboard.loadData, platformList.loadPlatforms, platformDetail.loadData,
      rebalancing.loadRebalancing, assetList.loadAssets, assetDetail.loadValueHistory,
      snapshotList.loadRowData, snapshotDetail.loadData,
    ]
    for load in loads {
      fetcher.calls = 0
      load()
      load()
      await settle()
      #expect(fetcher.calls < 20)
    }
    fetcher.calls = 0
    value.marketValue = 250
    await settle()
    #expect(dashboard.totalPortfolioValue == 250)
    #expect(platformList.platformRows.first?.totalValue == 250)
    #expect(platformDetail.totalValue == 250)
    #expect(rebalancing.totalPortfolioValue == 250)
    #expect(assetDetail.valueHistory.first?.marketValue == 250)
    #expect(assetList.groups.flatMap(\.assets).first?.latestValue == 250)
    #expect(snapshotList.rowDataMap[snapshot.id]?.totalValue == 250)
    #expect(snapshotDetail.totalValue == 250)
    #expect(fetcher.calls < 50)

    // A query notification covers a new snapshot outside the tracked dependency set.
    fetcher.calls = 0
    let newSnapshot = Snapshot(date: snapshot.date.addingTimeInterval(86400))
    context.insert(newSnapshot)
    let newValue = SnapshotAssetValue(marketValue: 400)
    newValue.asset = asset
    newValue.snapshot = newSnapshot
    context.insert(newValue)
    let requests: [() -> Void] = [
      dashboard.requestRefresh, platformList.requestRefresh,
      platformDetail.requestRefresh, rebalancing.requestRefresh, assetList.requestRefresh,
      assetDetail.requestRefresh, snapshotList.requestRefresh, snapshotDetail.requestRefresh,
    ]
    for request in requests {
      request()
      request()
    }
    await settle()
    #expect(dashboard.totalPortfolioValue == 400)
    #expect(platformList.platformRows.first?.totalValue == 400)
    #expect(platformDetail.totalValue == 400)
    #expect(rebalancing.totalPortfolioValue == 400)
    #expect(assetList.groups.flatMap(\.assets).first?.latestValue == 400)
    #expect(assetDetail.valueHistory.last?.marketValue == 400)
    #expect(snapshotList.rowDataMap[newSnapshot.id]?.totalValue == 400)
    #expect(snapshotDetail.totalValue == 250)  // remains bound to its original snapshot
    #expect(fetcher.calls < 50)
    fetcher.calls = 0
    context.delete(newSnapshot)
    for request in requests { request() }
    await settle()
    #expect(dashboard.totalPortfolioValue == 250)
    #expect(rebalancing.totalPortfolioValue == 250)
    #expect(snapshotList.rowDataMap[newSnapshot.id] == nil)
    #expect(fetcher.calls < 50)
    _ = container.mainContext
  }
  @Test("Dashboard cache readers are invalidated when a refresh publishes new caches")
  func cacheReaders() async {
    let container = TestDataManager.createInMemoryContainer()
    let vm = DashboardViewModel(modelContext: container.mainContext)
    vm.loadData()
    let flag = ChangeFlag()
    withObservationTracking {
      _ = vm.growthRate(for: .oneMonth)
    } onChange: {
      Task { @MainActor in flag.changed = true }
    }
    vm.loadData()
    await settle()
    #expect(flag.changed)
    _ = container.mainContext
  }

  @Test("Clean category editors adopt externally updated saved fields")
  func cleanEditor() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    context.insert(category)
    let vm = CategoryDetailViewModel(category: category, modelContext: context)
    vm.loadData()
    category.name = "Updated reserve"
    category.targetAllocationPercentage = 0
    category.minimumBalanceAmount = 20
    category.minimumBalanceCurrency = "USD"
    await settle()
    #expect(vm.editedName == "Updated reserve")
    #expect(vm.editedTargetAllocation == 0)
    #expect(vm.minimumEnabled)
    #expect(vm.minimumBalanceText == "20")
    #expect(vm.editedMinimumCurrency == "USD")
    #expect(!vm.hasUnsavedChanges)
    _ = container.mainContext
  }

}
