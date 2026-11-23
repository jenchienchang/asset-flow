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

struct AssetPortfolioSharePresentation {
  private static let englishPercent = Decimal.FormatStyle.Percent(
    locale: Locale(identifier: "en_US")
  )
  .scale(1)

  let percentage: Decimal

  var full: String { percentage.formattedPercentage() }

  var compact: String {
    percentage.formatted(
      Self.englishPercent.notation(.compactName).precision(.significantDigits(1...3)))
  }

  func scientific(significantDigits: ClosedRange<Int>) -> String {
    percentage.formatted(
      Self.englishPercent.notation(.scientific).precision(.significantDigits(significantDigits)))
  }
}

/// Asset list view with grouping by platform or category.
///
/// Displays all assets grouped by the selected mode, with each row showing
/// the asset name, platform, category, latest value, and portfolio share.
struct AssetListView: View {
  @State private var viewModel: AssetListViewModel
  @Binding var selectedAsset: Asset?
  @Query private var assets: [Asset]
  @Query private var snapshots: [Snapshot]
  @Environment(\.isAppLocked) private var isAppLocked

  @State private var showDeleteError = false
  @State private var deleteErrorMessage = ""
  @State private var idealPortfolioPercentageWidth: CGFloat = 0
  @State private var maximumPortfolioPercentageWidth: CGFloat = 0
  @ScaledMetric(relativeTo: .body) private var minimumAssetIdentityWidth: CGFloat = 64

  private var portfolioPercentageWidth: CGFloat {
    min(idealPortfolioPercentageWidth, maximumPortfolioPercentageWidth)
  }

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
    .refreshOnStoreChanges { viewModel.requestRefresh() }
    .onAppear {
      viewModel.loadAssets()
    }
    .onChange(of: queryRevision) {
      withAnimation(AnimationConstants.standard) {
        viewModel.requestRefresh()
      }
      selectedAsset = ModelSelectionResolver.resolve(selectedAsset, among: assets, id: \.id)
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

  private var queryRevision: ModelQueryRevision {
    ModelQueryRevision(snapshots: snapshots, assets: assets)
  }

  // MARK: - Asset List

  private var assetList: some View {
    List(selection: $selectedAsset) {
      ForEach(viewModel.groups) { group in
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
    .overlay(alignment: .topTrailing) {
      portfolioPercentageSizingGrid
    }
    .accessibilityIdentifier("Asset List")
  }

  private var portfolioPercentageSizingGrid: some View {
    let percentages = viewModel.groups.flatMap(\.assets).compactMap {
      $0.portfolioPercentage?.formattedPercentage()
    }

    // Size across groups and cap the column at the width of a regular signed percentage.
    return Grid(verticalSpacing: 0) {
      ForEach(Set(percentages).sorted(), id: \.self) { percentage in
        GridRow {
          portfolioPercentageText(percentage)
            .frame(height: 0)
        }
      }
    }
    .fixedSize()
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.width
    } action: { width in
      idealPortfolioPercentageWidth = width
    }
    .overlay {
      portfolioPercentageText((Decimal(-99_999) / 100).formattedPercentage())
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.width
        } action: { width in
          maximumPortfolioPercentageWidth = width
        }
    }
    .hidden()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
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
      .frame(minWidth: minimumAssetIdentityWidth, maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 8) {
        HStack(spacing: 4) {
          if let value = rowData.latestValue {
            let effectiveCurrency =
              rowData.asset.currency.isEmpty
              ? SettingsService.shared.mainCurrency : rowData.asset.currency
            let amount = value.formatted(currency: effectiveCurrency)
            if effectiveCurrency != SettingsService.shared.mainCurrency {
              Text(effectiveCurrency.uppercased())
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            }
            Text(amount)
              .font(.body)
              .monospacedDigit()
              .minimumScaleFactor(0.85)
              .helpWhenUnlocked(amount)
          } else {
            Text("\u{2014}")
              .foregroundStyle(.secondary)
          }
        }

        portfolioPercentageCell(rowData.portfolioPercentage)
      }
      .lineLimit(1)
      .layoutPriority(1)
    }
    .contextMenu {
      Button("Delete", role: .destructive) {
        deleteAsset(rowData.asset)
      }
      .disabled((rowData.asset.snapshotAssetValues?.count ?? 0) > 0)
    }
  }

  @ViewBuilder
  private func portfolioPercentageCell(_ share: Decimal?) -> some View {
    if portfolioPercentageWidth > 0 {
      if let share {
        let presentation = AssetPortfolioSharePresentation(percentage: share)
        let full = presentation.full
        let description = String(
          localized: "\(full) of portfolio",
          comment: "Assets list tooltip and VoiceOver label. The percentage is already formatted.")
        ViewThatFits(in: .horizontal) {
          portfolioPercentageText(full)
          portfolioPercentageText(presentation.compact)
          portfolioPercentageText(presentation.scientific(significantDigits: 1...3))
          portfolioPercentageText(presentation.scientific(significantDigits: 1...1))
          portfolioPercentageText("…")
        }
        .frame(width: portfolioPercentageWidth, alignment: .trailing)
        .helpWhenUnlocked(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: description))
      } else {
        Color.clear
          .frame(width: portfolioPercentageWidth, height: 0)
          .accessibilityHidden(true)
      }
    }
  }

  private func portfolioPercentageText(_ percentage: String) -> some View {
    Text(verbatim: percentage)
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
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
