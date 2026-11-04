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

import Charts
import SwiftData
import SwiftUI

/// Platform detail view for editing the platform name and viewing assets and value history.
///
/// Shows an editable name field, a table of assets on this platform with their
/// latest values, and a value history chart across all snapshots.
///
/// **Important:** The parent view must use the platform instance as view identity
/// to recreate the editor after selection or whole-store replacement,
/// because `@State` ViewModel initialization only runs on first view creation.
struct PlatformDetailView: View {
  @State private var viewModel: PlatformDetailViewModel
  @Query private var queryPlatforms: [Platform]
  @Query private var queryAssets: [Asset]
  @Query private var querySnapshots: [Snapshot]

  @State private var showSaveError = false
  @State private var saveErrorMessage = ""
  @State private var valueChartRange: ChartTimeRange = .all

  init(platform: Platform, modelContext: ModelContext) {
    _viewModel = State(
      wrappedValue: PlatformDetailViewModel(platform: platform, modelContext: modelContext))
  }

  var body: some View {
    Group {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadData() }
      } else {
        Form {
          platformDetailsSection
          assetsSection
          valueHistorySection
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(viewModel.platformName)
    .refreshOnStoreChanges { viewModel.requestRefresh() }
    .onAppear {
      viewModel.loadData()
    }
    .onChange(of: ModelQueryRevision(platforms: queryPlatforms)) {
      viewModel.reloadAfterStoreChange()
    }
    .onChange(of: queryAssets) {
      viewModel.reloadAfterStoreChange()
    }
    .onChange(of: querySnapshots) {
      viewModel.requestRefresh()
    }
    .alert("Save Error", isPresented: $showSaveError) {
      Button("OK") {}
    } message: {
      Text(saveErrorMessage)
    }
  }

  // MARK: - Platform Details Section

  private var platformDetailsSection: some View {
    Section {
      TextField("Name", text: $viewModel.editedName)
        .onSubmit { saveChanges() }
        .accessibilityIdentifier("Platform Name Field")
    } header: {
      Text("Platform Details")
    }
  }

  // MARK: - Assets Section

  private var assetsSection: some View {
    Section {
      if viewModel.assets.isEmpty {
        Text("No assets on this platform")
          .foregroundStyle(.secondary)
      } else {
        AssetTableView(rows: viewModel.assets, secondColumnTitle: "Category") { row in
          if let category = row.asset.category {
            Text(category.name)
          } else {
            Text("\u{2014}")
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Text("Assets on Platform")
    }
  }

  // MARK: - Value History Section

  private var filteredValueHistory: [PlatformValueHistoryEntry] {
    ChartDataService.filter(viewModel.valueHistory, range: valueChartRange)
  }

  private var valueHistorySection: some View {
    Section {
      ChartTimeRangeSelector(selection: $valueChartRange)

      let points = filteredValueHistory
      if viewModel.valueHistory.isEmpty {
        Text("No value history")
          .foregroundStyle(.secondary)
      } else if points.isEmpty {
        Text("No data for selected period")
          .foregroundStyle(.secondary)
      } else {
        SingleSeriesLineChart(
          data: points,
          dateKeyPath: \.date,
          valueOf: { $0.totalValue.doubleValue },
          color: .blue,
          height: ChartConstants.standardChartHeight,
          tooltipContent: { entry in
            ChartTooltipView {
              Text(entry.date.settingsFormatted())
                .font(.caption2)
              Text(entry.totalValue.formatted(currency: SettingsService.shared.mainCurrency))
                .font(.caption.bold())
            }
          }
        )
      }
    } header: {
      Text("Value History")
    }
    .conversionUnavailable(viewModel.conversionStatus.unavailableMessage)
  }

  // MARK: - Actions

  private func saveChanges() {
    do {
      try viewModel.save()
    } catch {
      saveErrorMessage = error.localizedDescription
      showSaveError = true
    }
  }
}

// MARK: - Previews

#Preview("Platform Detail") {
  NavigationStack {
    PlatformDetailView(
      platform: Platform(name: "Firstrade"),
      modelContext: PreviewContainer.container.mainContext
    )
  }
}
