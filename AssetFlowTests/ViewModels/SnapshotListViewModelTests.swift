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

@Suite("SnapshotListViewModel Tests")
@MainActor
struct SnapshotListViewModelTests {

  // MARK: - Test Helpers

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar.current.date(from: components)!
  }

  private func createViewModel(context: ModelContext) -> SnapshotListViewModel {
    SnapshotListViewModel(modelContext: context)
  }

  private func createAssetWithValue(
    name: String,
    platform: String,
    marketValue: Decimal,
    snapshot: Snapshot,
    context: ModelContext
  ) -> (Asset, SnapshotAssetValue) {
    let asset = Asset(name: name, platform: platform)
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: marketValue)
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)
    return (asset, sav)
  }

  // MARK: - Creation: Date Validation

  @Test("createSnapshot rejects future dates")
  func createSnapshotRejectsFutureDates() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

    #expect(throws: SnapshotError.self) {
      try viewModel.createSnapshot(date: tomorrow, copyFromLatest: false)
    }
  }

  @Test("createSnapshot rejects date that already has a snapshot")
  func createSnapshotRejectsDuplicateDate() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let date = makeDate(year: 2025, month: 6, day: 15)
    let existing = Snapshot(date: date)
    context.insert(existing)

    #expect(throws: SnapshotError.self) {
      try viewModel.createSnapshot(date: date, copyFromLatest: false)
    }
  }

  @Test("createSnapshot succeeds with valid past date")
  func createSnapshotSucceedsWithPastDate() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let date = makeDate(year: 2025, month: 1, day: 15)
    let snapshot = try viewModel.createSnapshot(date: date, copyFromLatest: false)

    #expect(snapshot.date == Calendar.current.startOfDay(for: date))
  }

  @Test("createSnapshot succeeds with today's date")
  func createSnapshotSucceedsWithToday() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let today = Calendar.current.startOfDay(for: Date())
    let snapshot = try viewModel.createSnapshot(date: today, copyFromLatest: false)

    #expect(snapshot.date == today)
  }

  // MARK: - Creation: Start Empty

  @Test("createSnapshot with start empty creates snapshot with no asset values")
  func createSnapshotStartEmptyHasNoAssets() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let date = makeDate(year: 2025, month: 3, day: 1)
    let snapshot = try viewModel.createSnapshot(date: date, copyFromLatest: false)

    #expect(snapshot.assetValues?.isEmpty ?? true)
  }

  @Test("createSnapshot normalizes date to start of day")
  func createSnapshotNormalizesDate() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    var components = DateComponents()
    components.year = 2025
    components.month = 3
    components.day = 1
    components.hour = 14
    components.minute = 30
    let dateWithTime = Calendar.current.date(from: components)!

    let snapshot = try viewModel.createSnapshot(date: dateWithTime, copyFromLatest: false)

    let expected = Calendar.current.startOfDay(for: dateWithTime)
    #expect(snapshot.date == expected)
  }

  // MARK: - Creation: Copy from Latest

  @Test("canCopyFromLatest returns false when no prior snapshots exist")
  func canCopyFromLatestFalseWhenNoPriorSnapshots() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let date = makeDate(year: 2025, month: 3, day: 1)
    let result = try viewModel.canCopyFromLatest(for: date)
    #expect(result == false)
  }

  @Test("canCopyFromLatest returns false when selected date is before all snapshots")
  func canCopyFromLatestFalseWhenDateBeforeAll() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap)

    let selectedDate = makeDate(year: 2025, month: 1, day: 15)
    let result = try viewModel.canCopyFromLatest(for: selectedDate)
    #expect(result == false)
  }

  @Test("canCopyFromLatest returns true when prior snapshots exist")
  func canCopyFromLatestTrueWhenPriorExists() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)

    let selectedDate = makeDate(year: 2025, month: 3, day: 1)
    let result = try viewModel.canCopyFromLatest(for: selectedDate)
    #expect(result == true)
  }

  @Test("copyFromLatest copies all direct asset values from most recent prior snapshot")
  func copyFromLatestCopiesDirectValues() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    // Create a prior snapshot with assets
    let priorDate = makeDate(year: 2025, month: 1, day: 1)
    let priorSnap = Snapshot(date: priorDate)
    context.insert(priorSnap)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: priorSnap, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: priorSnap, context: context)

    // Create new snapshot copying from latest
    let newDate = makeDate(year: 2025, month: 2, day: 1)
    let newSnap = try viewModel.createSnapshot(date: newDate, copyFromLatest: true)

    let newValues = newSnap.assetValues ?? []
    #expect(newValues.count == 2)

    let totalValue = newValues.reduce(Decimal(0)) { $0 + $1.marketValue }
    #expect(totalValue == Decimal(65000))
  }

  @Test(
    "copyFromLatest selects most recent snapshot BEFORE selected date, ignoring later snapshots")
  func copyFromLatestSelectsCorrectPriorSnapshot() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    // Snapshot Jan 1: AAPL at 10000
    let snap1 = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap1)
    let (apple, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 10000,
      snapshot: snap1, context: context)

    // Snapshot Feb 1: AAPL at 15000
    let snap2 = Snapshot(date: makeDate(year: 2025, month: 2, day: 1))
    context.insert(snap2)
    let sav2 = SnapshotAssetValue(marketValue: 15000)
    sav2.snapshot = snap2
    sav2.asset = apple
    context.insert(sav2)

    // Snapshot Mar 1: AAPL at 20000
    let snap3 = Snapshot(date: makeDate(year: 2025, month: 3, day: 1))
    context.insert(snap3)
    let sav3 = SnapshotAssetValue(marketValue: 20000)
    sav3.snapshot = snap3
    sav3.asset = apple
    context.insert(sav3)

    // Create snapshot for Feb 15 -- should copy from Feb 1 (15000), not Jan 1 or Mar 1
    let selectedDate = makeDate(year: 2025, month: 2, day: 15)
    let newSnap = try viewModel.createSnapshot(date: selectedDate, copyFromLatest: true)

    let newValues = newSnap.assetValues ?? []
    #expect(newValues.count == 1)
    #expect(newValues.first?.marketValue == Decimal(15000))
  }

  // MARK: - Deletion

  @Test("deleteSnapshot removes snapshot from context")
  func deleteSnapshotRemovesFromContext() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)

    viewModel.deleteSnapshot(snap)

    let descriptor = FetchDescriptor<Snapshot>()
    let remaining = try context.fetch(descriptor)
    #expect(remaining.isEmpty)
  }

  @Test("deleteSnapshot cascades to asset values")
  func deleteSnapshotCascadesToAssetValues() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)

    viewModel.deleteSnapshot(snap)

    let savDescriptor = FetchDescriptor<SnapshotAssetValue>()
    let remainingSAVs = try context.fetch(savDescriptor)
    #expect(remainingSAVs.isEmpty)
  }

  @Test("deleteSnapshot cascades to cash flow operations")
  func deleteSnapshotCascadesToCashFlows() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let cf = CashFlowOperation(cashFlowDescription: "Salary", amount: 5000)
    cf.snapshot = snap
    context.insert(cf)

    viewModel.deleteSnapshot(snap)

    let cfDescriptor = FetchDescriptor<CashFlowOperation>()
    let remainingCFs = try context.fetch(cfDescriptor)
    #expect(remainingCFs.isEmpty)
  }

  @Test("deleteSnapshot preserves asset records")
  func deleteSnapshotPreservesAssetRecords() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)

    viewModel.deleteSnapshot(snap)

    let assetDescriptor = FetchDescriptor<Asset>()
    let remainingAssets = try context.fetch(assetDescriptor)
    #expect(remainingAssets.count == 1)
    #expect(remainingAssets.first?.name == "AAPL")
  }

  @Test("confirmationData returns correct counts")
  func confirmationDataReturnsCorrectCounts() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 15))
    context.insert(snap)

    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: snap, context: context)

    let cf1 = CashFlowOperation(cashFlowDescription: "Salary", amount: 5000)
    cf1.snapshot = snap
    context.insert(cf1)
    let cf2 = CashFlowOperation(cashFlowDescription: "Rent", amount: -2000)
    cf2.snapshot = snap
    context.insert(cf2)

    let data = viewModel.confirmationData(for: snap)
    #expect(data.assetCount == 2)
    #expect(data.cashFlowCount == 2)
  }

  // MARK: - Snapshot Row Data

  @Test("snapshotRowData lists platforms from direct asset values")
  func snapshotRowDataListsPlatforms() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)
    let (_, _) = createAssetWithValue(
      name: "BTC", platform: "Binance", marketValue: 50000,
      snapshot: snap, context: context)

    let rowData = viewModel.snapshotRowData(for: snap)

    #expect(rowData.platforms.sorted() == ["Binance", "Firstrade"])
    #expect(rowData.totalValue == Decimal(65000))
    #expect(rowData.assetCount == 2)
  }

  @Test("snapshotRowData with direct values shows correct totals")
  func snapshotRowDataWithDirectValues() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 1, day: 1))
    context.insert(snap)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 15000,
      snapshot: snap, context: context)

    let rowData = viewModel.snapshotRowData(for: snap)

    #expect(rowData.platforms == ["Firstrade"])
    #expect(rowData.totalValue == Decimal(15000))
    #expect(rowData.assetCount == 1)
  }

  // MARK: - Row Data Map

  @Test("loadAllSnapshotRowData returns empty map when no snapshots exist")
  func loadAllSnapshotRowDataEmptyContext() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let rowDataMap = try viewModel.loadAllSnapshotRowData()

    #expect(rowDataMap.isEmpty)
  }

  @Test("loadAllSnapshotRowData keys results by snapshot UUID")
  func loadAllSnapshotRowDataKeyedByUUID() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snap = Snapshot(date: makeDate(year: 2025, month: 6, day: 1))
    context.insert(snap)
    let (_, _) = createAssetWithValue(
      name: "AAPL", platform: "Firstrade", marketValue: 5000,
      snapshot: snap, context: context)

    let rowDataMap = try viewModel.loadAllSnapshotRowData()

    #expect(rowDataMap.count == 1)
    #expect(rowDataMap[snap.id] != nil)
    #expect(rowDataMap[snap.id]?.totalValue == Decimal(5000))
  }

  // MARK: - Zero-Value Assets

  @Test("rowData.hasZeroValueAssets is true when snapshot has zero-value asset")
  func hasZeroValueAssetsTrue() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snapshot = Snapshot(date: makeDate(year: 2026, month: 3, day: 1))
    context.insert(snapshot)
    let asset = Asset(name: "Test", platform: "P1")
    asset.currency = "USD"
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: Decimal(0))
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)

    let rowData = viewModel.snapshotRowData(for: snapshot)
    #expect(rowData.hasZeroValueAssets == true)
  }

  @Test("rowData.hasZeroValueAssets is false when all assets have non-zero values")
  func hasZeroValueAssetsFalse() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let viewModel = createViewModel(context: context)

    let snapshot = Snapshot(date: makeDate(year: 2026, month: 3, day: 1))
    context.insert(snapshot)
    let asset = Asset(name: "Test", platform: "P1")
    asset.currency = "USD"
    context.insert(asset)
    let sav = SnapshotAssetValue(marketValue: Decimal(500))
    sav.snapshot = snapshot
    sav.asset = asset
    context.insert(sav)

    let rowData = viewModel.snapshotRowData(for: snapshot)
    #expect(rowData.hasZeroValueAssets == false)
  }
}
