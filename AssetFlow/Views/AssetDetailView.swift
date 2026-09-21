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

/// Asset detail view for editing properties and viewing value history.
///
/// Shows editable fields (name, platform, category), a value history table
/// with a sparkline chart, and a delete action with validation.
///
/// **Important:** The parent view must apply `.id(asset.id)` to this view
/// to force view recreation when the selected asset changes, because `@State`
/// ViewModel initialization only runs on first view creation.
struct AssetDetailView: View {
  @State private var viewModel: AssetDetailViewModel

  @State private var showDeleteConfirmation = false
  @State private var showSaveError = false
  @State private var saveErrorMessage = ""
  @State private var valueChartRange: ChartTimeRange = .all
  @State private var editingAssetValue: SnapshotAssetValue?
  @State private var showConvertedChart = false

  @State private var cachedPlatforms: [String] = []
  @State private var cachedCategories: [Category] = []

  let onDelete: () -> Void

  init(asset: Asset, modelContext: ModelContext, onDelete: @escaping () -> Void) {
    _viewModel = State(
      wrappedValue: AssetDetailViewModel(asset: asset, modelContext: modelContext))
    self.onDelete = onDelete
  }

  var body: some View {
    Form {
      editableFieldsSection
      valueHistorySection
      deleteSection
    }
    .formStyle(.grouped)
    .navigationTitle(viewModel.asset.name)
    .onAppear {
      viewModel.loadValueHistory()
      do {
        cachedPlatforms = try viewModel.existingPlatforms()
        cachedCategories = try viewModel.existingCategories()
      } catch {
        saveErrorMessage = error.localizedDescription
        showSaveError = true
      }
    }
    .onChange(of: viewModel.isDifferentCurrency) { _, newValue in
      if !newValue { showConvertedChart = false }
    }
    .alert("Save Error", isPresented: $showSaveError) {
      Button("OK") {}
    } message: {
      Text(saveErrorMessage)
    }
    .confirmationDialog(
      "Delete Asset",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        viewModel.deleteAsset()
        onDelete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Are you sure you want to delete \"\(viewModel.asset.name)\"? This action cannot be undone."
      )
    }
  }

  // MARK: - Editable Fields Section

  private var editableFieldsSection: some View {
    Section {
      TextField("Name", text: $viewModel.editedName)
        .onSubmit { saveChanges() }
        .accessibilityIdentifier("Asset Name Field")

      platformPicker

      categoryPicker

      currencyPicker
    } header: {
      Text("Asset Details")
    }
  }

  // MARK: - Platform Picker

  private var platformPicker: some View {
    PlatformPickerField(
      selectedPlatform: $viewModel.editedPlatform,
      cachedPlatforms: $cachedPlatforms,
      onCommit: { saveChanges() }
    )
    .accessibilityIdentifier("Platform Picker")
  }

  // MARK: - Category Picker

  private var categoryPicker: some View {
    CategoryPickerField(
      selectedCategory: $viewModel.editedCategory,
      cachedCategories: $cachedCategories,
      resolveCategory: { try viewModel.resolveCategory(name: $0) },
      onCommit: { saveChanges() },
      onError: { message in
        saveErrorMessage = message
        showSaveError = true
      }
    )
    .accessibilityIdentifier("Category Picker")
  }

  // MARK: - Currency Picker

  private var currencyPicker: some View {
    Picker("Currency", selection: currencyBinding) {
      ForEach(CurrencyService.shared.currencies) { currency in
        Text(currency.displayName).tag(currency.code)
      }
    }
    .accessibilityIdentifier("Currency Picker")
  }

  private var currencyBinding: Binding<String> {
    Binding(
      get: { viewModel.editedCurrency },
      set: { newValue in
        viewModel.editedCurrency = newValue
        saveChanges()
      }
    )
  }

  // MARK: - Value History Section

  private var filteredValueHistory: [AssetValueHistoryEntry] {
    ChartDataService.filter(viewModel.valueHistory, range: valueChartRange)
  }

  private var valueHistorySection: some View {
    Section {
      if viewModel.valueHistory.isEmpty {
        Text("No recorded values")
          .foregroundStyle(.secondary)
      } else {
        HStack {
          ChartTimeRangeSelector(selection: $valueChartRange)
          Spacer()
          convertedChartToggle
            .opacity(viewModel.isDifferentCurrency ? 1 : 0)
            .allowsHitTesting(viewModel.isDifferentCurrency)
        }

        let points = filteredValueHistory
        if points.isEmpty {
          Text("No data for selected period")
            .foregroundStyle(.secondary)
        } else if showConvertedChart && viewModel.isDifferentCurrency {
          let displayCurrency = SettingsService.shared.mainCurrency
          SingleSeriesLineChart(
            data: points,
            dateKeyPath: \.date,
            valueOf: { ($0.convertedMarketValue ?? $0.marketValue).doubleValue },
            color: .green,
            height: ChartConstants.standardChartHeight,
            tooltipContent: { entry in
              ChartTooltipView {
                Text(entry.date.settingsFormatted())
                  .font(.caption2)
                Text(
                  (entry.convertedMarketValue ?? entry.marketValue)
                    .formatted(currency: displayCurrency)
                )
                .font(.caption.bold())
              }
            }
          )
        } else {
          let effectiveCurrency =
            viewModel.asset.currency.isEmpty
            ? SettingsService.shared.mainCurrency : viewModel.asset.currency
          SingleSeriesLineChart(
            data: points,
            dateKeyPath: \.date,
            valueOf: { $0.marketValue.doubleValue },
            color: .blue,
            height: ChartConstants.standardChartHeight,
            tooltipContent: { entry in
              ChartTooltipView {
                Text(entry.date.settingsFormatted())
                  .font(.caption2)
                Text(entry.marketValue.formatted(currency: effectiveCurrency))
                  .font(.caption.bold())
              }
            }
          )
        }

        valueHistoryTable
      }
    } header: {
      Text("Value History")
    }
  }

  // MARK: - Converted Value Chart

  private var convertedChartToggle: some View {
    Button {
      withAnimation(AnimationConstants.chart) { showConvertedChart.toggle() }
    } label: {
      Text(SettingsService.shared.mainCurrency.uppercased())
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          showConvertedChart
            ? AnyShapeStyle(.tint.opacity(0.15))
            : AnyShapeStyle(.clear)
        )
        .foregroundStyle(showConvertedChart ? .primary : .secondary)
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(
              showConvertedChart
                ? AnyShapeStyle(.tint.opacity(0.3))
                : AnyShapeStyle(.clear),
              lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
    .helpWhenUnlocked("Show values converted to \(SettingsService.shared.mainCurrency)")
    .accessibilityLabel("Show values converted to \(SettingsService.shared.mainCurrency)")
    .accessibilityAddTraits(showConvertedChart ? .isSelected : [])
  }

  // MARK: - Value History Table

  private func marketValueCell(
    for entry: AssetValueHistoryEntry, currency: String
  ) -> some View {
    let sav = entry.snapshotAssetValue
    return Text(entry.marketValue.formatted(currency: currency))
      .monospacedDigit()
      .frame(maxWidth: .infinity, alignment: .trailing)
      .contentShape(Rectangle())
      .onTapGesture(count: 2) {
        editingAssetValue = sav
      }
      .contextMenu {
        Button("Edit Value") {
          editingAssetValue = sav
        }
      }
      .popover(
        isPresented: Binding(
          get: { editingAssetValue?.id == sav.id },
          set: { if !$0 { editingAssetValue = nil } }
        ),
        arrowEdge: .trailing
      ) {
        EditValuePopover(currentValue: sav.marketValue) { newValue in
          viewModel.editAssetValue(sav, newValue: newValue)
        }
      }
  }

  private var valueHistoryTable: some View {
    let effectiveCurrency =
      viewModel.asset.currency.isEmpty
      ? SettingsService.shared.mainCurrency : viewModel.asset.currency
    let displayCurrency = SettingsService.shared.mainCurrency
    let showConverted = viewModel.isDifferentCurrency
    let tableHeight = CGFloat(viewModel.valueHistory.count) * 28 + 32

    return Group {
      if showConverted {
        Table(viewModel.valueHistory) {
          TableColumn("Date") { entry in
            Text(entry.date.settingsFormatted())
          }
          TableColumn("Market Value") { entry in
            marketValueCell(for: entry, currency: effectiveCurrency)
          }
          .alignment(.trailing)
          TableColumn("Converted Value") { entry in
            if let converted = entry.convertedMarketValue {
              Text(converted.formatted(currency: displayCurrency))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
              Text("—")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
          }
          .alignment(.trailing)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .scrollDisabled(true)
        .frame(height: tableHeight)
        .padding(-1)
        .clipped()
      } else {
        Table(viewModel.valueHistory) {
          TableColumn("Date") { entry in
            Text(entry.date.settingsFormatted())
          }
          TableColumn("Market Value") { entry in
            marketValueCell(for: entry, currency: effectiveCurrency)
          }
          .alignment(.trailing)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .scrollDisabled(true)
        .frame(height: tableHeight)
        .padding(-1)
        .clipped()
      }
    }
  }

  // MARK: - Delete Section

  private var deleteSection: some View {
    Section {
      Button("Delete Asset", role: .destructive) {
        showDeleteConfirmation = true
      }
      .disabled(!viewModel.canDelete)
      .accessibilityIdentifier("Delete Asset Button")

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
      cachedPlatforms = try viewModel.existingPlatforms()
      cachedCategories = try viewModel.existingCategories()
    } catch {
      saveErrorMessage = error.localizedDescription
      showSaveError = true
    }
  }
}

// MARK: - Previews

#Preview("Asset Detail") {
  let container = PreviewContainer.container
  let asset = Asset(name: "AAPL", platform: "Firstrade")
  container.mainContext.insert(asset)
  return NavigationStack {
    AssetDetailView(asset: asset, modelContext: container.mainContext) {}
  }
}
