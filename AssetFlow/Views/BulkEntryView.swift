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
  let onSave: (Snapshot) -> Void

  @Environment(\.modelContext) private var modelContext
  @State private var showZeroPendingConfirmation = false
  @State private var zeroPendingCount = 0
  @State private var csvImportTarget: CSVImportTarget?
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var showImportResult = false
  @State private var importResultTitle = ""
  @State private var importResultMessage = ""
  @State private var cachedCategoryNames: [String] = []

  init(viewModel: BulkEntryViewModel, onSave: @escaping (Snapshot) -> Void) {
    _viewModel = State(initialValue: viewModel)
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
        Divider()
        if case .failed(let message) = viewModel.loadState {
          DataLoadErrorView(message: message) { viewModel.retryLoad() }
        } else {
          BulkEntryContentArea(
            viewModel: viewModel,
            cachedCategoryNames: $cachedCategoryNames,
            csvImportTarget: $csvImportTarget)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        loadCachedCategoryNames()
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
          let accessing = url.startAccessingSecurityScopedResource()
          defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
          }

          do {
            let data = try Data(contentsOf: url)
            switch target {
            case .asset(let platform):
              viewModel.loadCSVForMapping(data: data, forPlatform: platform)
              if !viewModel.showColumnMappingSheet {
                showImportResultAlert(for: viewModel.lastImportFeedback)
                viewModel.lastImportFeedback = nil
              }

            case .cashFlow:
              viewModel.loadCashFlowCSVForMapping(data: data)
              if !viewModel.showCashFlowColumnMappingSheet {
                showImportResultAlert(for: viewModel.lastImportFeedback)
                viewModel.lastImportFeedback = nil
              }
            }
          } catch {
            viewModel.reportImportFailure(
              String(
                localized: "Could not open file. Please check the file is a valid CSV.",
                table: "Import"))
            showImportResultAlert(for: viewModel.lastImportFeedback)
            viewModel.lastImportFeedback = nil
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
            _ = viewModel.confirmColumnMapping(mapping)
            showImportResultAlert(for: viewModel.lastImportFeedback)
            viewModel.lastImportFeedback = nil
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
            _ = viewModel.confirmCashFlowColumnMapping(mapping)
            showImportResultAlert(for: viewModel.lastImportFeedback)
            viewModel.lastImportFeedback = nil
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
    }
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

  private func performSave() {
    do {
      let snapshot = try viewModel.saveSnapshot()
      onSave(snapshot)
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func loadCachedCategoryNames() {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    do {
      let categories = try fetchModels(
        descriptor,
        from: ModelContextFetcher(modelContext: modelContext),
        operation: "load bulk category names")
      cachedCategoryNames = categories.map(\.name)
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
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
