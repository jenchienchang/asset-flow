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

import SwiftUI

// MARK: - Asset Entry Row View

struct BulkEntryRowView: View, Equatable {
  var viewModel: BulkEntryViewModel
  let row: BulkEntryRow
  @Binding var cachedCategoryNames: [String]
  var focusedRowID: FocusState<UUID?>.Binding
  var nameFieldFocusedRowID: FocusState<UUID?>.Binding

  static func == (lhs: BulkEntryRowView, rhs: BulkEntryRowView) -> Bool {
    lhs.row == rhs.row && lhs.cachedCategoryNames == rhs.cachedCategoryNames
  }

  @State private var localValueText: String = ""
  @State private var localAssetName: String = ""
  @State private var isHoveringPreviousValue = false

  var body: some View {
    let isExcluded = !row.isIncluded
    let parsedValue = Decimal.parse(localValueText)
    let localIsUpdated =
      row.isIncluded && parsedValue != nil && parsedValue != Decimal(0)
      && !row.hasMissingCurrency
    let localValidationError = !localValueText.isEmpty && parsedValue == nil
    let localZeroValueError = row.isIncluded && parsedValue == Decimal(0)

    let cellStyle = BulkEntryRowCellStyle()

    GridRow {
      Toggle("", isOn: includeBinding)
        .labelsHidden()
        .accessibilityLabel("Include \(row.assetName)")
        .helpWhenUnlocked("Include or exclude this asset from the snapshot")
        .modifier(cellStyle)
        .publishesBulkEntryDataRowMetadata(rowID: row.id, isTinted: localIsUpdated)

      // `.frame(maxWidth: .infinity)` makes this the flex column.
      // `TextField`'s natural width is independent of its text, so
      // typing does not reflow the column.
      HStack(spacing: 6) {
        if row.isNewRow {
          TextField("Asset name", text: $localAssetName)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .disabled(isExcluded)
            .focused(nameFieldFocusedRowID, equals: row.id)
            .onSubmit { commitAssetName() }
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(
                  row.isNewRow && localAssetName.trimmingCharacters(in: .whitespaces).isEmpty
                    ? .red : .clear,
                  lineWidth: 1.5)
            )
        } else {
          Text(row.assetName)
            .strikethrough(isExcluded)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        sourceBadge
      }
      .modifier(cellStyle)

      // `Grid` widens this column to fit the longest category name across
      // all rows in the section, instead of clipping to a fixed width.
      Group {
        if row.isNewAsset {
          BulkEntryCategoryPicker(
            categoryName: categoryNameBinding,
            cachedNames: $cachedCategoryNames
          )
        } else {
          Text(row.asset?.category?.name ?? "\u{2014}")
            .font(.callout)
            .foregroundStyle(row.asset?.category != nil ? .primary : .secondary)
        }
      }
      .modifier(cellStyle)

      Group {
        if row.isNewAsset {
          BulkEntryCurrencyPicker(selection: currencyBinding)
            .accessibilityLabel("Currency for \(row.assetName)")
            .disabled(isExcluded)
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(row.isIncluded && row.hasMissingCurrency ? .red : .clear, lineWidth: 1.5)
            )
            .helpWhenUnlocked(
              row.hasMissingCurrency ? "Select a currency before saving." : nil)
        } else {
          Text(row.currency.uppercased())
            .font(.callout)
        }
      }
      .modifier(cellStyle)

      // `.fixedSize()` reports each cell's natural text width; `Grid`
      // widens the column to the widest cell, so trailing edges align
      // across the header and every row.
      HStack(spacing: 4) {
        Text(row.previousValue?.formattedFullPrecision(currency: row.currency) ?? "\u{2014}")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .fixedSize()

        if row.previousValue != nil && row.isIncluded {
          Button {
            viewModel.fillWithPreviousValue(row.id)
            localValueText = "\(row.previousValue!)"
          } label: {
            Image(systemName: "arrow.right.circle.fill")
              .foregroundStyle(.secondary)
              .imageScale(.small)
          }
          .buttonStyle(.plain)
          .helpWhenUnlocked("Fill with previous value")
          .opacity(isHoveringPreviousValue ? 1 : 0)
        } else {
          // Placeholder to maintain consistent spacing
          Color.clear
            .frame(width: 14, height: 14)
        }
      }
      .contentShape(Rectangle())
      .onHoverWhenUnlocked { isHoveringPreviousValue = $0 }
      .modifier(cellStyle)

      // Fixed 160pt width — letting this `TextField` flex with content
      // would reflow the entire column on every keystroke.
      TextField("Enter value\u{2026}", text: $localValueText)
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .frame(width: 160)
        .multilineTextAlignment(.trailing)
        .focused(focusedRowID, equals: row.id)
        .onSubmit {
          commitValue()
          viewModel.advanceFocus(from: row.id)
        }
        .disabled(isExcluded)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(
              (localValidationError || localZeroValueError) ? .red : .clear,
              lineWidth: 1.5)
        )
        .helpWhenUnlocked(
          localZeroValueError
            ? LocalizedStringKey(
              "Value cannot be 0. Exclude the asset instead if it is no longer held.")
            : nil
        )
        .modifier(cellStyle)

      Group {
        if row.isNewRow {
          Button {
            viewModel.removeManualRow(rowID: row.id)
          } label: {
            Image(systemName: "trash")
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
          .helpWhenUnlocked("Remove this manually added asset")
        } else {
          Color.clear
            .frame(width: 1, height: 1)
        }
      }
      .frame(width: 28)
      .modifier(cellStyle)
    }
    .opacity(isExcluded ? 0.5 : 1.0)
    .accessibilityLabel(
      "\(row.assetName), \(row.platform), \(row.isUpdated ? "updated" : row.isPending ? "pending" : "excluded")"
    )
    .onAppear {
      localValueText = row.newValueText
      localAssetName = row.assetName
    }
    .onDisappear {
      commitValue()
      commitAssetName()
    }
    .onChange(of: row.newValueText) { _, newValue in
      localValueText = newValue
    }
    .onChange(of: row.assetName) { _, newValue in
      localAssetName = newValue
    }
    .onChange(of: localValueText) { _, newValue in
      viewModel.setPendingValue(row.id, to: newValue)
    }
    .onChange(of: localAssetName) { _, newValue in
      viewModel.setPendingName(row.id, to: newValue)
    }
  }

  // MARK: - Source Badge

  @ViewBuilder
  private var sourceBadge: some View {
    if row.source == .csv {
      Text("CSV")
        .font(.caption2)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.blue.opacity(0.15), in: Capsule())
        .foregroundStyle(.blue)
    } else if row.source == .manualNew {
      Text("NEW")
        .font(.caption2)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(.green.opacity(0.15), in: Capsule())
        .foregroundStyle(.green)
    }
  }

  // MARK: - Local State Commits

  private func commitValue() {
    viewModel.updateRowValue(row.id, to: localValueText)
  }

  private func commitAssetName() {
    guard row.isNewRow else { return }
    viewModel.updateRowAssetName(row.id, to: localAssetName)
  }

  // MARK: - Bindings

  private var includeBinding: Binding<Bool> {
    Binding(
      get: { row.isIncluded },
      set: { _ in viewModel.toggleInclude(rowID: row.id) }
    )
  }

  private var currencyBinding: Binding<String> {
    Binding(
      get: { row.currency },
      set: { newValue in viewModel.updateRowCurrency(row.id, to: newValue) }
    )
  }

  private var categoryNameBinding: Binding<String> {
    Binding(
      get: { row.categoryName ?? "" },
      set: { newValue in
        viewModel.updateRowCategoryName(row.id, to: newValue.isEmpty ? nil : newValue)
      }
    )
  }
}

// MARK: - Row Cell Style

/// Per-cell padding/sizing for asset / cash-flow data rows. The
/// updated-row tint is rendered behind the Grid via
/// `BulkEntryDataRowsKey` rather than at the `GridRow` level (which
/// would forward per cell and leave gaps).
struct BulkEntryRowCellStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxHeight: .infinity)
  }
}

// MARK: - Category Name Picker

/// A lightweight picker for selecting or creating a category by name.
///
/// Unlike `CategoryPickerField`, this does not create `Category` objects
/// in the database. It stores category names as strings, deferring
/// database creation to snapshot save time.
struct BulkEntryCategoryPicker: View {
  @Binding var categoryName: String
  @Binding var cachedNames: [String]

  @State private var showNewField = false
  @State private var newName = ""

  var body: some View {
    if showNewField {
      HStack(spacing: 2) {
        TextField("Category", text: $newName)
          .textFieldStyle(.roundedBorder)
          .font(.callout)
          .onSubmit { commitNew() }
        Button {
          commitNew()
        } label: {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
        Button {
          showNewField = false
          newName = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    } else {
      Picker("", selection: pickerBinding) {
        Text("None").tag("")
        ForEach(cachedNames, id: \.self) { name in
          Text(name).tag(name)
        }
        Divider()
        Text("New Category\u{2026}").tag("__new__")
      }
      .labelsHidden()
      .font(.callout)
    }
  }

  private var pickerBinding: Binding<String> {
    Binding(
      get: { categoryName },
      set: { newValue in
        if newValue == "__new__" {
          showNewField = true
          newName = ""
        } else {
          categoryName = newValue
        }
      }
    )
  }

  private func commitNew() {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    // Case-insensitive match against existing names
    if let match = cachedNames.first(where: { $0.lowercased() == trimmed.lowercased() }) {
      categoryName = match
    } else {
      categoryName = trimmed
      cachedNames.append(trimmed)
      cachedNames.sort()
    }

    showNewField = false
    newName = ""
  }
}

// MARK: - Currency Picker

/// An extracted currency picker that avoids rebuilding 340+ items on every parent re-render.
///
/// By isolating the `ForEach(CurrencyService.shared.currencies)` in its own `View` struct,
/// SwiftUI can skip re-diffing the picker content when only the parent's other state changes
/// (e.g., typing in a description field). The `@Binding` only triggers re-render when the
/// selected currency actually changes.
struct BulkEntryCurrencyPicker: View {
  @Binding var selection: String

  var body: some View {
    Picker("", selection: $selection) {
      Text("Select Currency").tag("")
      ForEach(CurrencyService.shared.currencies) { currency in
        Text(currency.code).tag(currency.code)
      }
    }
    .labelsHidden()
  }
}
