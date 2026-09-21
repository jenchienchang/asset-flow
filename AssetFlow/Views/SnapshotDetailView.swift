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

/// Snapshot detail view with full CRUD for asset values and cash flow operations.
///
/// Shows a summary section, asset breakdown,
/// category allocation, cash flow operations, and a danger zone for snapshot deletion.
///
/// **Important:** The parent view must apply `.id(snapshot.id)` to this view
/// to force view recreation when the selected snapshot changes.
struct SnapshotDetailView: View {
  @State private var viewModel: SnapshotDetailViewModel

  @State private var showAddAssetSheet = false
  @State private var showAddCashFlowSheet = false
  @State private var showDeleteConfirmation = false

  @State private var editingAssetValue: SnapshotAssetValue?
  @State private var editingCashFlow: CashFlowOperation?

  @State private var showError = false
  @State private var errorMessage = ""

  let onDelete: () -> Void

  init(snapshot: Snapshot, modelContext: ModelContext, onDelete: @escaping () -> Void) {
    _viewModel = State(
      wrappedValue: SnapshotDetailViewModel(snapshot: snapshot, modelContext: modelContext))
    self.onDelete = onDelete
  }

  var body: some View {
    Form {
      summarySection
      assetBreakdownSection
      categoryAllocationSection
      if !viewModel.usedCurrencyCodes.isEmpty {
        exchangeRateSection
      }
      cashFlowSection
      dangerZoneSection
    }
    .formStyle(.grouped)
    .navigationTitle(
      viewModel.snapshot.date.settingsFormatted()
    )
    .onAppear {
      viewModel.loadData()
    }
    .task(id: SettingsService.shared.mainCurrency) {
      await viewModel.fetchExchangeRatesIfNeeded()
    }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
    .sheet(isPresented: $showAddAssetSheet) {
      AddAssetSheet(viewModel: viewModel) {
        viewModel.loadData()
      }
    }
    .sheet(isPresented: $showAddCashFlowSheet) {
      AddCashFlowSheet(viewModel: viewModel) {
        viewModel.loadData()
      }
    }
    .confirmationDialog(
      "Delete Snapshot",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        viewModel.deleteSnapshot()
        onDelete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      let data = viewModel.deleteConfirmationData()
      let dateStr = data.date.settingsFormatted()
      let assetCount = data.assetCount
      let cfCount = data.cashFlowCount
      Text(
        "Delete snapshot from \(dateStr)? This will remove all \(assetCount) asset values and \(cfCount) cash flow operations. This action cannot be undone."
      )
    }
  }

  // MARK: - Summary Section

  private var summarySection: some View {
    Section {
      if viewModel.totalConversionStatus.isComplete {
        LabeledContent("Total Value") {
          Text(viewModel.totalValue.formatted(currency: SettingsService.shared.mainCurrency))
            .monospacedDigit()
        }
      } else {
        nativeCurrencyTotalsView(
          title: "Portfolio Values",
          totals: viewModel.nativeCurrencyTotals
        )
      }

      if viewModel.cashFlowConversionStatus.isComplete {
        LabeledContent("Net Cash Flow") {
          HStack(spacing: 4) {
            Text(viewModel.netCashFlow.formatted(currency: SettingsService.shared.mainCurrency))
              .monospacedDigit()
            Text("(\(viewModel.cashFlowOperations.count) operations)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      } else if !viewModel.nativeCashFlowTotals.isEmpty {
        nativeCurrencyTotalsView(
          title: "Cash Flow Totals",
          totals: viewModel.nativeCashFlowTotals
        )
      }

      if let message = viewModel.conversionStatus.unavailableMessage {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if viewModel.isFetchingRates {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Fetching exchange rates...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      }

      if let error = viewModel.ratesFetchError {
        HStack {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.yellow)
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Retry") {
            Task { await viewModel.fetchExchangeRatesIfNeeded() }
          }
          .font(.caption)
        }
        .transition(.opacity)
      }
    } header: {
      Text("Summary")
    }
    .animation(AnimationConstants.standard, value: viewModel.isFetchingRates)
    .animation(AnimationConstants.standard, value: viewModel.ratesFetchError)
  }

  private func nativeCurrencyTotalsView(
    title: LocalizedStringKey,
    totals: [(code: String, value: Decimal)]
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(totals, id: \.code) { total in
        LabeledContent(total.code.uppercased()) {
          Text(total.value.formatted(currency: total.code))
            .monospacedDigit()
        }
      }
    }
  }

  // MARK: - Asset Breakdown Section

  private var assetBreakdownSection: some View {
    Section {
      if viewModel.sortedAssetValues.isEmpty {
        Text("No assets in this snapshot")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.sortedAssetValues, id: \.id) { sav in
          if let asset = sav.asset {
            assetRow(sav, asset: asset)
          }
        }
      }
    } header: {
      HStack {
        Text("Assets")
        Spacer()
        Button {
          showAddAssetSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.plain)
        .helpWhenUnlocked("Add an asset to this snapshot")
      }
    }
  }

  @ViewBuilder
  private func assetRow(_ sav: SnapshotAssetValue, asset: Asset) -> some View {
    let displayCurrency = SettingsService.shared.mainCurrency
    let assetCurrency = asset.currency.isEmpty ? displayCurrency : asset.currency
    let isDifferentCurrency = assetCurrency != displayCurrency

    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(asset.name)
          .font(.body)
        HStack(spacing: 8) {
          if !asset.platform.isEmpty { Text(asset.platform) }
          if let categoryName = asset.category?.name { Text(categoryName) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      if sav.marketValue == 0 {
        HoverWarningIcon(
          message: String(
            localized:
              """
              This asset has a value of 0. \
              If the value hasn't been updated yet, \
              please enter the current value. \
              If the asset is no longer held, \
              remove it from the snapshot to \
              dismiss this warning.
              """,
            table: "Snapshot"))
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 1) {
        HStack(spacing: 4) {
          if isDifferentCurrency {
            Text(assetCurrency.uppercased())
              .font(.caption2)
              .padding(.horizontal, 4)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
          Text(sav.marketValue.formatted(currency: assetCurrency))
            .font(.body)
            .monospacedDigit()
        }
        if isDifferentCurrency, let exchangeRate = viewModel.exchangeRate {
          let converted = CurrencyConversionService.convert(
            value: sav.marketValue, from: assetCurrency, to: displayCurrency,
            using: exchangeRate, forSnapshotDate: viewModel.snapshot.date)
          if let converted, converted != sav.marketValue {
            Text("\u{2248} \(converted.formatted(currency: displayCurrency))")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      Button("Edit Value") {
        editingAssetValue = sav
      }
      Button("Remove from Snapshot", role: .destructive) {
        viewModel.removeAsset(sav)
        viewModel.loadData()
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
        do {
          try viewModel.editAssetValue(sav, newValue: newValue)
          viewModel.loadData()
        } catch {
          errorMessage = error.localizedDescription
          showError = true
        }
      }
    }
  }

  // MARK: - Category Allocation Section

  private var categoryAllocationSection: some View {
    Section {
      if viewModel.categoryAllocations.isEmpty {
        Text("No category data")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.categoryAllocations, id: \.categoryName) { allocation in
          HStack {
            Text(allocation.categoryName)
              .font(.body)
            Spacer()
            Text(allocation.value.formatted(currency: SettingsService.shared.mainCurrency))
              .font(.body)
              .monospacedDigit()
            Text(allocation.percentage.formattedPercentage())
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(width: 60, alignment: .trailing)
          }
        }
      }
    } header: {
      Text("Category Allocation")
    }
    .conversionUnavailable(viewModel.totalConversionStatus.unavailableMessage)
  }

  // MARK: - Exchange Rate Section

  private var exchangeRateSection: some View {
    Section {
      let baseCurrency = SettingsService.shared.mainCurrency

      ForEach(viewModel.usedCurrencyCodes, id: \.self) { code in
        LabeledContent(code.uppercased()) {
          if let entry = viewModel.usedCurrencyRates.first(where: { $0.code == code }) {
            let rate = entry.rate.description
            Text("1 \(code.uppercased()) = \(rate) \(baseCurrency.uppercased())")
              .monospacedDigit()
          } else {
            Text("Unavailable")
              .foregroundStyle(.orange)
          }
        }
      }

      if let fetchDate = viewModel.exchangeRate?.fetchDate {
        LabeledContent("Rate Date", value: fetchDate.settingsFormatted())
      }
    } header: {
      HStack {
        Text("Exchange Rates")
        if viewModel.isFetchingRates {
          ProgressView()
            .controlSize(.mini)
        }
      }
    }
  }

  // MARK: - Cash Flow Section

  private var cashFlowSection: some View {
    Section {
      let operations = viewModel.sortedCashFlowOperations
      if operations.isEmpty {
        Text("No cash flow operations")
          .foregroundStyle(.secondary)
      } else {
        ForEach(operations) { operation in
          let direction = operation.amount < 0 ? "outflow" : "inflow"
          let currency =
            operation.currency.isEmpty
            ? SettingsService.shared.mainCurrency : operation.currency
          let formatted = operation.amount.formatted(currency: currency)
          HStack {
            Text(operation.cashFlowDescription)
              .font(.body)
            Spacer()
            HStack(spacing: 4) {
              if currency.lowercased() != SettingsService.shared.mainCurrency.lowercased() {
                Text(currency.uppercased())
                  .font(.caption2)
                  .padding(.horizontal, 4)
                  .padding(.vertical, 1)
                  .background(.quaternary, in: Capsule())
              }
              Text(formatted)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(operation.amount < 0 ? .red : .primary)
            }
          }
          .accessibilityLabel("\(operation.cashFlowDescription), \(direction), \(formatted)")
          .contextMenu {
            Button("Edit") {
              editingCashFlow = operation
            }
            Button("Remove", role: .destructive) {
              viewModel.removeCashFlow(operation)
            }
          }
          .popover(
            isPresented: Binding(
              get: { editingCashFlow?.id == operation.id },
              set: { if !$0 { editingCashFlow = nil } }
            ),
            arrowEdge: .trailing
          ) {
            EditCashFlowPopover(
              currentDescription: operation.cashFlowDescription,
              currentAmount: operation.amount
            ) { newDescription, newAmount in
              do {
                try viewModel.editCashFlow(
                  operation, newDescription: newDescription, newAmount: newAmount)
              } catch {
                errorMessage = error.localizedDescription
                showError = true
              }
            }
          }
        }

        if viewModel.cashFlowConversionStatus.isComplete {
          LabeledContent("Net Cash Flow") {
            Text(viewModel.netCashFlow.formatted(currency: SettingsService.shared.mainCurrency))
              .monospacedDigit()
              .fontWeight(.semibold)
          }
        }
      }
    } header: {
      HStack {
        Text("Cash Flow Operations")
        Spacer()
        Button {
          showAddCashFlowSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.plain)
        .helpWhenUnlocked("Add a cash flow operation")
      }
    }
  }

  // MARK: - Danger Zone Section

  private var dangerZoneSection: some View {
    Section {
      Button("Delete Snapshot", role: .destructive) {
        showDeleteConfirmation = true
      }
      .accessibilityIdentifier("Delete Snapshot Button")
    } header: {
      Text("Danger Zone")
    }
  }

}

/// Preserves a metric or chart's layout while clearly obscuring unavailable
/// currency-dependent data.
struct CurrencyConversionUnavailableOverlay: ViewModifier {
  let message: String

  func body(content: Content) -> some View {
    content
      .blur(radius: 4)
      .overlay {
        RoundedRectangle(cornerRadius: ChartConstants.cardCornerRadius)
          .fill(.regularMaterial.opacity(0.94))
          .overlay {
            VStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              Text(message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal)
            }
            .padding()
          }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(message)
  }
}

extension View {
  @ViewBuilder
  func conversionUnavailable(_ message: String?) -> some View {
    if let message {
      modifier(CurrencyConversionUnavailableOverlay(message: message))
    } else {
      self
    }
  }
}

// MARK: - Previews

#Preview("Snapshot Detail") {
  let container = PreviewContainer.container
  let snapshot = Snapshot(date: Date())
  container.mainContext.insert(snapshot)
  return NavigationStack {
    SnapshotDetailView(snapshot: snapshot, modelContext: container.mainContext) {}
  }
}
