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

/// Asset list view with grouping by platform or category.
///
/// Displays all assets grouped by the selected mode, with each row showing
/// the asset name, platform, category, and latest composite value.
struct AssetListView: View {
  @State private var viewModel: AssetListViewModel
  @Binding var selectedAsset: Asset?
  @Query private var assets: [Asset]
  @Environment(\.isAppLocked) private var isAppLocked

  @State private var showDeleteError = false
  @State private var deleteErrorMessage = ""

  init(modelContext: ModelContext, selectedAsset: Binding<Asset?>) {
    _viewModel = State(wrappedValue: AssetListViewModel(modelContext: modelContext))
    _selectedAsset = selectedAsset
  }

  var body: some View {
    Group {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadAssets() }
      } else if viewModel.groups.isEmpty {
        emptyState
      } else {
        assetList
      }
    }
    .navigationTitle("Assets")
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Picker("Grouping", selection: $viewModel.groupingMode) {
          Text("By Platform").tag(AssetGroupingMode.byPlatform)
          Text("By Category").tag(AssetGroupingMode.byCategory)
        }
        .pickerStyle(.segmented)
        .disabled(isAppLocked)
        .helpWhenUnlocked("Group assets by platform or category")
        .accessibilityIdentifier("Grouping Picker")
      }
      ToolbarItem(placement: .automatic) {
        Toggle(
          isOn: Binding(
            get: { SettingsService.shared.hideStaleAssets },
            set: { newValue in
              withAnimation(AnimationConstants.standard) {
                SettingsService.shared.hideStaleAssets = newValue
              }
            }
          )
        ) {
          ViewThatFits(in: .horizontal) {
            Label("Hide Stale Assets", systemImage: "eye.slash")
              .labelStyle(.titleAndIcon)
            Label("Hide Stale Assets", systemImage: "eye.slash")
              .labelStyle(.iconOnly)
          }
        }
        .toggleStyle(.button)
        .disabled(isAppLocked)
        .helpWhenUnlocked("Hide Stale Assets")
        .accessibilityIdentifier("Hide Stale Assets Toggle")
      }
    }
    .onAppear {
      viewModel.loadAssets()
    }
    .onChange(of: assets) {
      withAnimation(AnimationConstants.standard) {
        viewModel.loadAssets()
      }
    }
    .onChange(of: viewModel.groupingMode) {
      viewModel.loadAssets()
    }
    .alert("Cannot Delete Asset", isPresented: $showDeleteError) {
      Button("OK") {}
    } message: {
      Text(deleteErrorMessage)
    }
  }

  // MARK: - Asset List

  private var assetList: some View {
    List(selection: $selectedAsset) {
      ForEach(viewModel.groups, id: \.name) { group in
        Section(group.name) {
          ForEach(group.assets, id: \.asset.id) { rowData in
            assetRow(rowData)
              .tag(rowData.asset)
          }
        }
      }
    }
    .onDeleteCommand {
      deleteSelectedAsset()
    }
    .accessibilityIdentifier("Asset List")
  }

  private func deleteSelectedAsset() {
    guard let asset = selectedAsset else { return }
    deleteAsset(asset)
  }

  private func assetRow(_ rowData: AssetRowData) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(rowData.asset.name)
          .font(.body)

        HStack(spacing: 8) {
          if !rowData.asset.platform.isEmpty {
            Text(rowData.asset.platform)
          }
          if let categoryName = rowData.asset.category?.name {
            Text(categoryName)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      if let value = rowData.latestValue {
        let effectiveCurrency =
          rowData.asset.currency.isEmpty
          ? SettingsService.shared.mainCurrency : rowData.asset.currency
        HStack(spacing: 4) {
          if effectiveCurrency != SettingsService.shared.mainCurrency {
            Text(effectiveCurrency.uppercased())
              .font(.caption2)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
          Text(value.formatted(currency: effectiveCurrency))
            .font(.body)
            .monospacedDigit()
        }
      } else {
        Text("\u{2014}")
          .foregroundStyle(.secondary)
      }
    }
    .contextMenu {
      Button("Delete", role: .destructive) {
        deleteAsset(rowData.asset)
      }
      .disabled((rowData.asset.snapshotAssetValues?.count ?? 0) > 0)
    }
  }

  // MARK: - Empty State

  @ViewBuilder
  private var emptyState: some View {
    if viewModel.hasHiddenStaleAssets {
      ContentUnavailableView {
        Label("All Assets Are Stale", systemImage: "line.3.horizontal.decrease.circle")
      } description: {
        Text(
          "All assets are missing from the latest snapshot. Toggle “Hide Stale Assets” off to see them."
        )
      }
    } else {
      ContentUnavailableView {
        Label("No Assets", systemImage: "tray")
      } description: {
        Text("No assets yet. Assets are created automatically when you import CSV data.")
      }
    }
  }

  // MARK: - Actions

  private func deleteAsset(_ asset: Asset) {
    do {
      try viewModel.deleteAsset(asset)
      if selectedAsset?.id == asset.id {
        selectedAsset = nil
      }
      withAnimation(AnimationConstants.standard) {
        viewModel.loadAssets()
      }
    } catch {
      deleteErrorMessage = error.localizedDescription
      showDeleteError = true
    }
  }
}

// MARK: - Previews

#Preview("Asset List") {
  NavigationStack {
    AssetListView(
      modelContext: PreviewContainer.container.mainContext,
      selectedAsset: .constant(nil)
    )
  }
}
