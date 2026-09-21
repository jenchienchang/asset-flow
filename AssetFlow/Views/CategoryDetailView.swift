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

/// Category detail view for editing properties and viewing history.
///
/// Shows editable fields (name, target allocation), assets in the category,
/// value and allocation history charts, and a delete action with validation.
///
/// **Important:** The parent view must apply `.id(category.id)` to this view
/// to force view recreation when the selected category changes, because `@State`
/// ViewModel initialization only runs on first view creation.
struct CategoryDetailView: View {
  @State private var viewModel: CategoryDetailViewModel

  @State private var showDeleteConfirmation = false
  @State private var showSaveError = false
  @State private var saveErrorMessage = ""
  @State private var valueChartRange: ChartTimeRange = .all
  @State private var allocationChartRange: ChartTimeRange = .all

  let onDelete: () -> Void

  init(category: Category, modelContext: ModelContext, onDelete: @escaping () -> Void) {
    _viewModel = State(
      wrappedValue: CategoryDetailViewModel(category: category, modelContext: modelContext))
    self.onDelete = onDelete
  }

  var body: some View {
    Group {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadData() }
      } else {
        Form {
          categoryDetailsSection
          assetsSection
          valueHistorySection
          allocationHistorySection
          deleteSection
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(viewModel.category.name)
    .onAppear {
      viewModel.loadData()
    }
    .alert("Save Error", isPresented: $showSaveError) {
      Button("OK") {}
    } message: {
      Text(saveErrorMessage)
    }
    .confirmationDialog(
      "Delete Category",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        viewModel.deleteCategory()
        onDelete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Are you sure you want to delete \"\(viewModel.category.name)\"? This action cannot be undone."
      )
    }
  }

  // MARK: - Category Details Section

  private var categoryDetailsSection: some View {
    Section {
      TextField("Name", text: $viewModel.editedName)
        .onSubmit { saveChanges() }
        .accessibilityIdentifier("Category Name Field")

      HStack {
        TextField("Target Allocation (e.g. 40)", text: $viewModel.targetAllocationText)
          .onSubmit { saveChanges() }
        Text("%")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Category Details")
    }
  }

  // MARK: - Assets Section

  private var assetsSection: some View {
    Section {
      if viewModel.assets.isEmpty {
        Text("No assets in this category")
          .foregroundStyle(.secondary)
      } else {
        AssetTableView(rows: viewModel.assets, secondColumnTitle: "Platform") { row in
          Text(row.asset.platform.isEmpty ? "\u{2014}" : row.asset.platform)
            .foregroundStyle(row.asset.platform.isEmpty ? .secondary : .primary)
        }
      }
    } header: {
      Text("Assets in Category")
    }
  }

  // MARK: - Value History Section

  private var filteredValueHistory: [CategoryValueHistoryEntry] {
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

  // MARK: - Allocation History Section

  private var allocationHistorySection: some View {
    Section {
      CategoryAllocationLineChart(
        entries: viewModel.allocationHistory,
        timeRange: $allocationChartRange,
        targetAllocationPercentage: viewModel.category.targetAllocationPercentage
      )
    } header: {
      VStack(alignment: .leading, spacing: 2) {
        Text("Allocation History")
        Text("Based on current category assignments")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .conversionUnavailable(viewModel.conversionStatus.unavailableMessage)
  }

  // MARK: - Delete Section

  private var deleteSection: some View {
    Section {
      Button("Delete Category", role: .destructive) {
        showDeleteConfirmation = true
      }
      .disabled(!viewModel.canDelete)
      .accessibilityIdentifier("Delete Category Button")

      if let explanation = viewModel.deleteExplanation {
        Text(explanation)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Danger Zone")
    }
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

#Preview("Category Detail") {
  let container = PreviewContainer.container
  let category = Category(name: "Equities", targetAllocationPercentage: 60)
  container.mainContext.insert(category)
  return NavigationStack {
    CategoryDetailView(category: category, modelContext: container.mainContext) {}
  }
}
