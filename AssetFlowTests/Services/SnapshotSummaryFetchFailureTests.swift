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

@MainActor
struct SnapshotSummaryFetchFailureTests {
  private struct FetchFailure: Error {}

  private struct FailingModelFetcher: ModelFetching {
    func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] where T: PersistentModel {
      throw FetchFailure()
    }
  }

  @Test("snapshot fetch failures are propagated")
  func snapshotFetchFailureIsPropagated() {
    do {
      _ = try SnapshotSummaryService.fetchSnapshots(using: FailingModelFetcher())
      Issue.record("Expected the snapshot fetch to fail")
    } catch let error as PersistenceError {
      #expect(error.operation == "fetch snapshots")
      #expect(error.underlyingError is FetchFailure)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("dashboard exposes snapshot fetch failures instead of an empty state")
  func dashboardSnapshotLoadFailureProducesErrorState() {
    let container = TestDataManager.createInMemoryContainer()
    let viewModel = DashboardViewModel(
      modelContext: container.mainContext,
      fetcher: FailingModelFetcher())

    viewModel.loadData()

    let expectedMessage = String(
      localized: "Unable to load portfolio data. Please try again.",
      table: "Services")
    #expect(
      viewModel.loadState == .failed(expectedMessage))
    #expect(!viewModel.isEmpty)
  }

  @Test("snapshot creation does not insert after a read failure")
  func snapshotCreationDoesNotMutateAfterFetchFailure() throws {
    let container = TestDataManager.createInMemoryContainer()
    let viewModel = SnapshotListViewModel(
      modelContext: container.mainContext,
      fetcher: FailingModelFetcher())

    #expect(throws: PersistenceError.self) {
      try viewModel.createSnapshot(
        date: Date(timeIntervalSince1970: 1_735_689_600),
        copyFromLatest: false)
    }

    let snapshots = try container.mainContext.fetch(FetchDescriptor<Snapshot>())
    #expect(snapshots.isEmpty)
  }

  @Test("asset list exposes asset fetch failures instead of empty data")
  func assetListLoadFailureProducesErrorState() {
    let container = TestDataManager.createInMemoryContainer()
    let viewModel = AssetListViewModel(
      modelContext: container.mainContext,
      fetcher: FailingModelFetcher())

    viewModel.loadAssets()

    let expectedMessage = String(
      localized: "Unable to load portfolio data. Please try again.",
      table: "Services")
    #expect(
      viewModel.loadState == .failed(expectedMessage))
    #expect(viewModel.groups.isEmpty)
  }

  @Test("snapshot list does not trust an empty query result")
  func snapshotListQueryFailureProducesErrorState() {
    let container = TestDataManager.createInMemoryContainer()
    let viewModel = SnapshotListViewModel(
      modelContext: container.mainContext,
      fetcher: FailingModelFetcher())

    // The view model must perform its own throwing fetch rather than trusting
    // SwiftUI's query result.
    viewModel.loadRowData()

    let expectedMessage = String(
      localized: "Unable to load portfolio data. Please try again.",
      table: "Services")
    #expect(
      viewModel.loadState == .failed(expectedMessage))
  }
}
