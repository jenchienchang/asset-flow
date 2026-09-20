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
/// **Important:** The parent view must apply `.id(platform)` to this view
/// to force view recreation when the selected platform changes (e.g., after rename),
/// because `@State` ViewModel initialization only runs on first view creation.
struct PlatformDetailView: View {
  @State private var viewModel: PlatformDetailViewModel

  @State private var showSaveError = false
  @State private var saveErrorMessage = ""
  @State private var valueChartRange: ChartTimeRange = .all

  let onRename: (String) -> Void

  init(platformName: String, modelContext: ModelContext, onRename: @escaping (String) -> Void) {
    _viewModel = State(
      wrappedValue: PlatformDetailViewModel(platformName: platformName, modelContext: modelContext))
    self.onRename = onRename
  }

  var body: some View {
    Form {
      platformDetailsSection
      assetsSection
      valueHistorySection
    }
    .formStyle(.grouped)
    .navigationTitle(viewModel.platformName)
    .onAppear {
      viewModel.loadData()
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
    let oldName = viewModel.platformName
    do {
      try viewModel.save()
      if viewModel.platformName != oldName {
        onRename(viewModel.platformName)
      }
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
      platformName: "Firstrade",
      modelContext: PreviewContainer.container.mainContext
    ) { _ in }
  }
}
