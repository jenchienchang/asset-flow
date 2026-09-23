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
import SwiftUI
import UniformTypeIdentifiers

/// Full-screen view for bulk snapshot entry with a platform-grouped table.
///
/// Displays all assets from the most recent snapshot, grouped by platform,
/// allowing the user to enter new values for each asset. Supports per-platform
/// CSV import, inline asset creation, and keyboard navigation between rows.
struct BulkEntryView: View {
  @State private var viewModel: BulkEntryViewModel
  let onReload: () -> Void
  let onSave: (Snapshot) -> Void

  @State private var showZeroPendingConfirmation = false
  @State private var zeroPendingCount = 0
  @State private var csvImportTarget: CSVImportTarget?
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var showImportResult = false
  @State private var importResultTitle = ""
  @State private var importResultMessage = ""
  @State private var csvImportTask: Task<Void, Never>?
  @State private var cachedCategoryNames: [String] = []
  @Query private var querySnapshots: [Snapshot]
  @Query private var queryAssets: [Asset]
  @Query private var queryCategories: [Category]
  @Query private var querySnapshotAssetValues: [SnapshotAssetValue]

  init(
    viewModel: BulkEntryViewModel,
    onReload: @escaping () -> Void,
    onSave: @escaping (Snapshot) -> Void
  ) {
    _viewModel = State(initialValue: viewModel)
    self.onReload = onReload
    self.onSave = onSave
  }

  /// Derived binding that maps `csvImportTarget` to the Bool that
  /// `.fileImporter(isPresented:)` expects.  The setter is a no-op:
  /// `csvImportTarget` is cleared inside the `onCompletion` callback
  /// (which always fires — both on selection and cancel) so the target
  /// context is still available when the callback reads it.
  private var showCSVFileImporter: Binding<Bool> {
    Binding(
      get: { csvImportTarget != nil },
      set: { _ in }
    )
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        BulkEntryToolbar(
          viewModel: viewModel,
          onSave: { handleSave() })
        if viewModel.isSourceDataStale {
          staleSourceDataBanner
        }
        Divider()
        if viewModel.isCSVImporting {
          HStack {
            ProgressView()
            Text("Loading CSV…")
            Spacer()
            Button("Cancel") {
              csvImportTask?.cancel()
            }
          }
          .padding(.horizontal)
          .padding(.vertical, 8)
        }
        if case .failed(let message) = viewModel.loadState {
          DataLoadErrorView(message: message) { viewModel.retryLoad() }
        } else {
          BulkEntryContentArea(
            viewModel: viewModel,
            cachedCategoryNames: $cachedCategoryNames,
            csvImportTarget: $csvImportTarget
          )
          .disabled(viewModel.isSourceDataStale)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        cachedCategoryNames = sortedCategoryNames(from: queryCategories)
      }
      .onChange(of: queryRevision) {
        cachedCategoryNames = sortedCategoryNames(from: queryCategories)
        viewModel.markSourceDataStale()
      }
      .fileImporter(
        isPresented: showCSVFileImporter,
        allowedContentTypes: [.commaSeparatedText, .plainText]
      ) { result in
        let target = csvImportTarget
        csvImportTarget = nil
        guard let target else { return }

        switch result {
        case .failure(let error):
          guard !isUserCancellation(error) else { return }
          viewModel.reportImportFailure(
            String(
              localized: "Could not open file. Please check the file is a valid CSV.",
              table: "Import"))
          showImportResultAlert(for: viewModel.lastImportFeedback)
          viewModel.lastImportFeedback = nil

        case .success(let url):
          startCSVImportTask { @MainActor in
            switch target {
            case .asset(let platform):
              await viewModel.loadCSVFileForMapping(from: url, forPlatform: platform)
              if !viewModel.showColumnMappingSheet {
                showImportResultAlert(for: viewModel.lastImportFeedback)
                viewModel.lastImportFeedback = nil
              }

            case .cashFlow:
              await viewModel.loadCashFlowCSVFileForMapping(from: url)
              if !viewModel.showCashFlowColumnMappingSheet {
                showImportResultAlert(for: viewModel.lastImportFeedback)
                viewModel.lastImportFeedback = nil
              }
            }
          }
        }
      }
      .sheet(isPresented: $viewModel.showColumnMappingSheet) {
        ColumnMappingSheet(
          rawHeaders: viewModel.pendingRawHeaders,
          schema: .assetWithoutPlatform,
          sampleRows: viewModel.pendingSampleRows,
          initialMapping: viewModel.pendingPartialMapping,
          parentSize: geometry.size,
          onConfirm: { mapping in
            startCSVImportTask { @MainActor in
              _ = await viewModel.confirmColumnMapping(mapping)
              showImportResultAlert(for: viewModel.lastImportFeedback)
              viewModel.lastImportFeedback = nil
            }
          },
          onCancel: {
            viewModel.showColumnMappingSheet = false
          }
        )
      }
      .sheet(isPresented: $viewModel.showCashFlowColumnMappingSheet) {
        ColumnMappingSheet(
          rawHeaders: viewModel.pendingCashFlowRawHeaders,
          schema: .cashFlow,
          sampleRows: viewModel.pendingCashFlowSampleRows,
          initialMapping: viewModel.pendingCashFlowPartialMapping,
          parentSize: geometry.size,
          onConfirm: { mapping in
            startCSVImportTask { @MainActor in
              _ = await viewModel.confirmCashFlowColumnMapping(mapping)
              showImportResultAlert(for: viewModel.lastImportFeedback)
              viewModel.lastImportFeedback = nil
            }
          },
          onCancel: {
            viewModel.showCashFlowColumnMappingSheet = false
          }
        )
      }
      .alert(
        String(
          localized:
            "\(zeroPendingCount) assets will be saved with a value of 0. Continue?",
          table: "Snapshot"),
        isPresented: $showZeroPendingConfirmation
      ) {
        Button("Continue") { performSave() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "You can update these values later in the snapshot detail view.",
            table: "Snapshot"))
      }
      .alert(
        String(localized: "Unable to Save Snapshot", table: "Snapshot"),
        isPresented: $showError
      ) {
        Button("OK") {}
      } message: {
        Text(errorMessage)
      }
      .alert(importResultTitle, isPresented: $showImportResult) {
        Button("OK") {}
      } message: {
        Text(importResultMessage)
      }
      .onDisappear {
        csvImportTask?.cancel()
      }
    }
  }

  private var staleSourceDataBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(
        String(
          localized: "Source data changed. Your draft can no longer be saved.",
          table: "Snapshot")
      )
      .font(.callout)
      Spacer()
      Button(
        String(localized: "Discard Draft and Reload", table: "Snapshot"),
        action: onReload
      )
      .buttonStyle(.bordered)
      .accessibilityIdentifier("Reload Bulk Entry Button")
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.yellow.opacity(0.15))
    .accessibilityIdentifier("Bulk Entry Stale Data Banner")
  }

  // MARK: - Save

  private func handleSave() {
    let pending = viewModel.toolbarStats.pendingCount
    if pending > 0 {
      zeroPendingCount = pending
      showZeroPendingConfirmation = true
    } else {
      performSave()
    }
  }

  private func startCSVImportTask(
    _ operation: @escaping @MainActor () async -> Void
  ) {
    csvImportTask?.cancel()
    csvImportTask = Task { @MainActor in
      await operation()
    }
  }

  private func performSave() {
    do {
      let snapshot = try viewModel.saveSnapshot()
      onSave(snapshot)
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func sortedCategoryNames(from categories: [Category]) -> [String] {
    categories.sorted {
      if $0.displayOrder != $1.displayOrder {
        return $0.displayOrder < $1.displayOrder
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    .map(\.name)
  }

  private var queryRevision: ModelQueryRevision {
    ModelQueryRevision(
      snapshots: querySnapshots,
      assets: queryAssets,
      categories: queryCategories,
      snapshotAssetValues: querySnapshotAssetValues)
  }

  private func showImportResultAlert(for feedback: CSVImportFeedback?) {
    guard let feedback else { return }
    importResultTitle = feedback.title
    importResultMessage = feedback.message
    showImportResult = true
  }

  private func isUserCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
  }

}
