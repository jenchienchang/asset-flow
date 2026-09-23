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

import SwiftData
import SwiftUI

/// Platform list view with selection binding, rename popover, and empty state.
///
/// Displays all platforms derived from asset data with their asset count
/// and total value. Supports selection for list-detail navigation and
/// renaming via context menu.
struct PlatformListView: View {
  @State private var viewModel: PlatformListViewModel
  @Binding var selectedPlatform: String?
  @Query private var assets: [Asset]
  @Query private var snapshots: [Snapshot]

  @State private var renamingPlatform: String?

  @State private var showError = false
  @State private var errorMessage = ""

  init(modelContext: ModelContext, selectedPlatform: Binding<String?>) {
    _viewModel = State(wrappedValue: PlatformListViewModel(modelContext: modelContext))
    _selectedPlatform = selectedPlatform
  }

  var body: some View {
    VStack(spacing: 0) {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadPlatforms() }
      } else {
        if let message = viewModel.conversionStatus.unavailableMessage {
          warningBanner(message)
        }

        if viewModel.platformRows.isEmpty {
          emptyState
        } else {
          platformList
        }
      }
    }
    .navigationTitle("Platforms")
    .onAppear {
      viewModel.loadPlatforms()
    }
    .onChange(of: queryRevision) {
      viewModel.loadPlatforms()
      if let selectedPlatform,
        !viewModel.platformRows.contains(where: { $0.name == selectedPlatform })
      {
        self.selectedPlatform = nil
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
  }

  private var queryRevision: ModelQueryRevision {
    ModelQueryRevision(snapshots: snapshots, assets: assets)
  }

  // MARK: - Platform List

  private func warningBanner(_ message: String) -> some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.yellow.opacity(0.15))
  }

  private var platformList: some View {
    List(selection: $selectedPlatform) {
      ForEach(viewModel.platformRows) { rowData in
        platformRow(rowData)
          .tag(rowData.name)
      }
      .onMove { source, destination in
        withAnimation(AnimationConstants.list) {
          viewModel.movePlatforms(from: source, to: destination)
        }
      }
    }
    .accessibilityIdentifier("Platform List")
  }

  private func platformRow(_ rowData: PlatformRowData) -> some View {
    HStack {
      Text(rowData.name)
        .font(.body)

      Spacer()

      HStack(spacing: 12) {
        if viewModel.conversionStatus.isComplete {
          Text(rowData.totalValue.formatted(currency: SettingsService.shared.mainCurrency))
            .font(.body)
            .monospacedDigit()
        } else {
          Text("—")
            .font(.body)
            .foregroundStyle(.secondary)
        }

        Text("\(rowData.assetCount)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, ChartConstants.badgePaddingH)
          .padding(.vertical, ChartConstants.badgePaddingV)
          .background(.quaternary)
          .clipShape(Capsule())
      }
    }
    .contextMenu {
      Button {
        renamingPlatform = rowData.name
      } label: {
        Label("Rename", systemImage: "pencil")
      }
      .accessibilityIdentifier("Rename Platform Button")
    }
    .popover(
      isPresented: Binding(
        get: { renamingPlatform == rowData.name },
        set: { if !$0 { renamingPlatform = nil } }
      ),
      arrowEdge: .trailing
    ) {
      RenamePlatformPopover(currentName: rowData.name) { newName in
        let trimmed = try viewModel.renamePlatform(from: rowData.name, to: newName)
        if selectedPlatform == rowData.name {
          selectedPlatform = trimmed
        }
        viewModel.loadPlatforms()
      } onError: { message in
        errorMessage = message
        showError = true
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Platforms", systemImage: "building.columns")
    } description: {
      Text(
        "No platforms yet. Platforms are created automatically when you import CSV data or create assets."
      )
    }
  }
}

// MARK: - Rename Platform Popover

private struct RenamePlatformPopover: View {
  let currentName: String
  let onRename: (String) throws -> Void
  let onError: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var newName: String

  init(
    currentName: String,
    onRename: @escaping (String) throws -> Void,
    onError: @escaping (String) -> Void
  ) {
    self.currentName = currentName
    self.onRename = onRename
    self.onError = onError
    _newName = State(wrappedValue: currentName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rename Platform")
        .font(.headline)

      TextField("Platform Name", text: $newName)
        .textFieldStyle(.roundedBorder)
        .onSubmit { renamePlatform() }
        .accessibilityIdentifier("Platform Name Field")

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.bordered)

        Spacer()

        Button("Rename") {
          renamePlatform()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        .buttonStyle(.borderedProminent)
      }
    }
    .frame(width: 280)
    .padding()
  }

  private func renamePlatform() {
    do {
      try onRename(newName)
      dismiss()
    } catch {
      dismiss()
      onError(error.localizedDescription)
    }
  }
}

// MARK: - Previews

#Preview("Platform List") {
  NavigationStack {
    PlatformListView(
      modelContext: PreviewContainer.container.mainContext,
      selectedPlatform: .constant(nil)
    )
  }
}
