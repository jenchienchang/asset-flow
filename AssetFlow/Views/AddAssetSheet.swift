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

// MARK: - Add Asset Sheet

struct AddAssetSheet: View {
  let viewModel: SnapshotDetailViewModel
  let onComplete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @FocusState private var focusedField: Field?
  enum Field { case asset, marketValue, newName, newMarketValue }

  @State private var mode: AddAssetMode = .selectExisting
  @State private var showError = false
  @State private var errorMessage = ""

  // Select Existing mode
  @State private var selectedAsset: Asset?
  @State private var marketValueText = ""

  // Create New mode
  @State private var newAssetName = ""
  @State private var newPlatform = ""
  @State private var newCategory: Category?
  @State private var newMarketValueText = ""
  @State private var newCurrency = SettingsService.shared.mainCurrency

  @Query(sort: \Asset.name) private var allAssets: [Asset]

  @State private var cachedPlatforms: [String] = []
  @State private var cachedCategories: [Category] = []

  enum AddAssetMode: String, CaseIterable {
    case selectExisting = "Select Existing"
    case createNew = "Create New"

    var localizedName: String {
      switch self {
      case .selectExisting:
        return String(localized: "Select Existing", table: "Snapshot")

      case .createNew:
        return String(localized: "Create New", table: "Snapshot")
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Mode", selection: $mode) {
          ForEach(AddAssetMode.allCases, id: \.self) { mode in
            Text(mode.localizedName).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        switch mode {
        case .selectExisting:
          selectExistingForm

        case .createNew:
          createNewForm
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Add Asset")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            addAsset()
          }
          .disabled(isAddDisabled)
        }
      }
    }
    .frame(minWidth: 400, minHeight: 300)
    .onAppear {
      do {
        cachedPlatforms = existingPlatforms()
        cachedCategories = try existingCategories()
      } catch {
        errorMessage = error.localizedDescription
        showError = true
      }
      focusedField = mode == .selectExisting ? .marketValue : .newName
    }
    .onChange(of: mode) {
      focusedField = mode == .selectExisting ? .marketValue : .newName
    }
    .alert("Error", isPresented: $showError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
  }

  private var selectExistingForm: some View {
    Group {
      Picker("Asset", selection: $selectedAsset) {
        Text("Select an asset").tag(nil as Asset?)
        ForEach(allAssets) { asset in
          Text(assetDisplayName(asset)).tag(asset as Asset?)
        }
      }

      if let asset = selectedAsset {
        LabeledContent("Platform") {
          Text(asset.platform.isEmpty ? "\u{2014}" : asset.platform)
            .foregroundStyle(asset.platform.isEmpty ? .secondary : .primary)
        }
        LabeledContent("Category") {
          Text(asset.category?.name ?? "\u{2014}")
            .foregroundStyle(asset.category == nil ? .secondary : .primary)
        }
        LabeledContent("Currency") {
          let currency =
            asset.currency.isEmpty
            ? SettingsService.shared.mainCurrency : asset.currency
          Text(currency.uppercased())
        }
      }

      TextField("Market Value", text: $marketValueText)
        .focused($focusedField, equals: .marketValue)
        .accessibilityIdentifier("Market Value Field")
    }
  }

  @ViewBuilder
  private var createNewForm: some View {
    TextField("Asset Name", text: $newAssetName)
      .focused($focusedField, equals: .newName)

    platformPicker

    categoryPicker

    Picker("Currency", selection: $newCurrency) {
      ForEach(CurrencyService.shared.currencies) { currency in
        Text(currency.displayName).tag(currency.code)
      }
    }

    TextField("Market Value", text: $newMarketValueText)
      .focused($focusedField, equals: .newMarketValue)
      .accessibilityIdentifier("New Market Value Field")
  }

  private var platformPicker: some View {
    PlatformPickerField(
      selectedPlatform: $newPlatform,
      cachedPlatforms: $cachedPlatforms
    )
  }

  private var categoryPicker: some View {
    CategoryPickerField(
      selectedCategory: $newCategory,
      cachedCategories: $cachedCategories,
      resolveCategory: { try viewModel.resolveCategory(name: $0) },
      onError: { message in
        errorMessage = message
        showError = true
      }
    )
  }

  private var isAddDisabled: Bool {
    switch mode {
    case .selectExisting:
      return selectedAsset == nil || Decimal.parse(marketValueText) == nil

    case .createNew:
      return newAssetName.trimmingCharacters(in: .whitespaces).isEmpty
        || Decimal.parse(newMarketValueText) == nil
    }
  }

  private func addAsset() {
    do {
      switch mode {
      case .selectExisting:
        guard let asset = selectedAsset,
          let value = Decimal.parse(marketValueText)
        else { return }
        try viewModel.addExistingAsset(asset, marketValue: value)

      case .createNew:
        guard let value = Decimal.parse(newMarketValueText) else { return }
        try viewModel.addNewAsset(
          name: newAssetName,
          platform: newPlatform,
          category: newCategory,
          marketValue: value,
          currency: newCurrency
        )
      }
      onComplete()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func assetDisplayName(_ asset: Asset) -> String {
    if asset.platform.isEmpty {
      return asset.name
    }
    return "\(asset.name) (\(asset.platform))"
  }

  private func existingPlatforms() -> [String] {
    let platforms = Set(allAssets.map(\.platform).filter { !$0.isEmpty })
    return platforms.sorted()
  }

  private func existingCategories() throws -> [Category] {
    let descriptor = FetchDescriptor<Category>(
      sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)])
    return try fetchModels(
      descriptor,
      from: ModelContextFetcher(modelContext: modelContext),
      operation: "load existing categories")
  }
}
