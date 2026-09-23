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

// MARK: - Toolbar

/// Toolbar extracted as its own observation boundary.
///
/// Reading `viewModel.toolbarStats` inside this struct means only changes
/// to the stored stats (not every `rows` mutation) invalidate this subtree.
struct BulkEntryToolbar: View {
  var viewModel: BulkEntryViewModel
  let onSave: () -> Void

  @State private var showAddPlatformPopover = false
  @State private var newPlatformName = ""
  @State private var addPlatformError = ""

  var body: some View {
    let stats = viewModel.toolbarStats
    HStack(spacing: 16) {
      Text("New Snapshot — \(viewModel.snapshotDate.settingsFormatted())")
        .font(.headline)

      Spacer()

      BulkEntryProgressStats(
        updatedCount: stats.updatedCount,
        pendingCount: stats.pendingCount,
        excludedCount: stats.excludedCount
      )

      BulkEntryValidationWarnings(
        zeroValueCount: stats.zeroValueCount,
        hasInvalidNewRows: stats.hasInvalidNewRows,
        hasEmptyCashFlowDescriptions: stats.hasEmptyCashFlowDescriptions,
        hasEmptyCashFlowAmounts: stats.hasEmptyCashFlowAmounts,
        hasCashFlowValidationErrors: stats.hasCashFlowValidationErrors
      )

      Button {
        newPlatformName = ""
        addPlatformError = ""
        showAddPlatformPopover = true
      } label: {
        Label("Add Platform", systemImage: "plus.rectangle.on.folder")
      }
      .disabled(viewModel.isSourceDataStale)
      .helpWhenUnlocked("Add a new platform with an empty asset")
      .popover(isPresented: $showAddPlatformPopover, arrowEdge: .bottom) {
        addPlatformPopover
      }

      Button("Save Snapshot") {
        onSave()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!stats.canSave || viewModel.isSourceDataStale)
      .helpWhenUnlocked("Save the snapshot with entered values")
      .accessibilityIdentifier("Save Snapshot Button")
    }
    .padding(.horizontal)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial)
  }

  private var addPlatformPopover: some View {
    VStack(spacing: 12) {
      Text("New Platform")
        .font(.headline)
      TextField("Platform name", text: $newPlatformName)
        .textFieldStyle(.roundedBorder)
        .onSubmit { commitNewPlatform() }
      if !addPlatformError.isEmpty {
        Text(addPlatformError)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Button("Cancel") { showAddPlatformPopover = false }
          .buttonStyle(.bordered)
        Button("Add") { commitNewPlatform() }
          .buttonStyle(.borderedProminent)
          .disabled(newPlatformName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
    .frame(width: 260)
  }

  private func commitNewPlatform() {
    let trimmed = newPlatformName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      addPlatformError = String(
        localized: "Platform name cannot be empty.", table: "Snapshot")
      return
    }
    if let rowID = viewModel.addPlatform(name: trimmed) {
      showAddPlatformPopover = false
      viewModel.pendingFocusRowID = rowID
    } else {
      addPlatformError = String(
        localized: "A platform with this name already exists.", table: "Snapshot")
    }
  }
}

// MARK: - Progress Stats View

struct BulkEntryProgressStats: View {
  let updatedCount: Int
  let pendingCount: Int
  let excludedCount: Int

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 4) {
        Circle()
          .fill(.green)
          .frame(width: 8, height: 8)
        Text("\(updatedCount) updated")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 4) {
        Circle()
          .fill(.orange)
          .frame(width: 8, height: 8)
        Text("\(pendingCount) pending")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 4) {
        Circle()
          .fill(.gray)
          .frame(width: 8, height: 8)
        Text("\(excludedCount) excluded")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Validation Warnings View

struct BulkEntryValidationWarnings: View {
  let zeroValueCount: Int
  let hasInvalidNewRows: Bool
  let hasEmptyCashFlowDescriptions: Bool
  let hasEmptyCashFlowAmounts: Bool
  let hasCashFlowValidationErrors: Bool

  @State private var isHovering = false
  @Environment(\.isAppLocked) private var isLocked

  private var warnings: [String] {
    var result: [String] = []
    if zeroValueCount > 0 {
      result.append(
        String(
          localized:
            "\(zeroValueCount) assets have a value of 0. Exclude them or enter a non-zero value.",
          table: "Snapshot"))
    }
    if hasInvalidNewRows {
      result.append(
        String(
          localized: "Some new assets are missing a name.",
          table: "Snapshot"))
    }
    if hasEmptyCashFlowDescriptions {
      result.append(
        String(
          localized: "Some cash flows are missing a description.",
          table: "Snapshot"))
    }
    if hasEmptyCashFlowAmounts {
      result.append(
        String(
          localized: "Some cash flows are missing an amount.",
          table: "Snapshot"))
    }
    if hasCashFlowValidationErrors {
      result.append(
        String(
          localized: "Some cash flows have invalid amounts.",
          table: "Snapshot"))
    }
    return result
  }

  var body: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .foregroundStyle(.red)
      .imageScale(.large)
      .opacity(warnings.isEmpty ? 0 : 1)
      .onHoverWhenUnlocked { hovering in
        isHovering = hovering
      }
      .popover(
        isPresented: Binding(
          get: { !isLocked && isHovering && !warnings.isEmpty },
          set: { if !$0 { isHovering = false } }
        ),
        arrowEdge: .bottom
      ) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(warnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.red)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(idealWidth: 300, alignment: .leading)
        .padding()
      }
  }
}

// MARK: - Header Background Sizing

/// Height of the header `GridRow` (asset or cash-flow), captured via
/// `GeometryReader` so the parent `Grid` can render a single continuous
/// `.fill.quaternary` strip behind the header.
///
/// This is necessary because `.background()` applied to a `GridRow` is
/// forwarded to each cell individually rather than spanning the row, so
/// any column where the data row is wider than the header label leaves
/// a gap in a per-cell tint. Capturing the row's height and rendering
/// the strip as a `.background(alignment: .top)` on the parent `Grid`
/// guarantees a contiguous bar across the full Grid width.
struct BulkEntryHeaderHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

extension View {
  /// Publishes this view's measured height via `BulkEntryHeaderHeightKey`,
  /// for the parent `Grid` to consume when sizing the header tint strip.
  fileprivate func publishesBulkEntryHeaderHeight() -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: BulkEntryHeaderHeightKey.self,
          value: proxy.size.height)
      }
    )
  }
}

// MARK: - Data Row Backgrounds

/// Per-row metadata (height + tint state) published by data rows; same
/// rationale as `BulkEntryHeaderHeightKey`.
struct BulkEntryDataRowMetadata: Equatable {
  let height: CGFloat
  let isTinted: Bool
}

struct BulkEntryDataRowsKey: PreferenceKey {
  static let defaultValue: [UUID: BulkEntryDataRowMetadata] = [:]
  static func reduce(
    value: inout [UUID: BulkEntryDataRowMetadata],
    nextValue: () -> [UUID: BulkEntryDataRowMetadata]
  ) {
    value.merge(nextValue()) { _, new in new }
  }
}

extension View {
  /// Publishes this view's measured height and tint state via
  /// `BulkEntryDataRowsKey`, for the parent `Grid` to consume when
  /// sizing the row tint strips. Attach to a single cell, not the
  /// `GridRow`: `.background()` on a `GridRow` forwards per cell and
  /// would publish the same value 7 times per row.
  func publishesBulkEntryDataRowMetadata(
    rowID: UUID,
    isTinted: Bool
  ) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: BulkEntryDataRowsKey.self,
          value: [
            rowID: BulkEntryDataRowMetadata(
              height: proxy.size.height,
              isTinted: isTinted)
          ]
        )
      }
    )
  }

  /// Renders the section's header tint strip and (optionally) per-row
  /// tint strips behind the Grid, sized via the heights published by
  /// `BulkEntryHeaderHeightKey` and `BulkEntryDataRowsKey`. Pass an
  /// empty `rowIDs` for sections without per-row tints (cash flow).
  fileprivate func bulkEntrySectionBackgrounds(
    rowIDs: [UUID] = []
  ) -> some View {
    modifier(BulkEntrySectionBackgroundsModifier(rowIDs: rowIDs))
  }
}

private struct BulkEntrySectionBackgroundsModifier: ViewModifier {
  let rowIDs: [UUID]
  @State private var headerHeight: CGFloat = 0
  @State private var rowMetadata: [UUID: BulkEntryDataRowMetadata] = [:]

  func body(content: Content) -> some View {
    content
      .background(alignment: .top) {
        VStack(spacing: 0) {
          Rectangle()
            .fill(.fill.quaternary)
            .frame(height: headerHeight)
          ForEach(rowIDs, id: \.self) { id in
            let metadata = rowMetadata[id]
            Rectangle()
              .fill(
                metadata?.isTinted == true
                  ? Color.green.opacity(0.06) : Color.clear
              )
              .frame(height: metadata?.height ?? 0)
            // 1pt spacer matches the Divider() between rows in the Grid
            Color.clear.frame(height: 1)
          }
        }
      }
      .onPreferenceChange(BulkEntryHeaderHeightKey.self) { headerHeight = $0 }
      .onPreferenceChange(BulkEntryDataRowsKey.self) { rowMetadata = $0 }
  }
}

// MARK: - Column Headers View

/// Asset table column headers — emitted as a `GridRow` so the parent `Grid`
/// can size every column to the widest cell across the header and all
/// data rows simultaneously, eliminating header/row alignment drift.
///
/// Per-column-alignment is set here on the header cells; data rows
/// inherit the same alignment from the column.
struct BulkEntryColumnHeaders: View {
  var body: some View {
    GridRow {
      Text("Include")
        .gridColumnAlignment(.center)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Asset Name")
        .gridColumnAlignment(.leading)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Category")
        .gridColumnAlignment(.leading)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Currency")
        .gridColumnAlignment(.leading)
        .modifier(BulkEntryHeaderCellStyle())
      // Reserve space for the trailing fill-button so the "Previous Value"
      // header label right-aligns with the previous-value text in rows.
      HStack(spacing: 4) {
        Text("Previous Value")
        Color.clear.frame(width: 14, height: 14)
      }
      .gridColumnAlignment(.trailing)
      .modifier(BulkEntryHeaderCellStyle())
      Text("New Value")
        .gridColumnAlignment(.trailing)
        .modifier(BulkEntryHeaderCellStyle())
      Color.clear
        .frame(width: 28, height: 1)
        .modifier(BulkEntryHeaderCellStyle())
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .publishesBulkEntryHeaderHeight()
  }
}

/// Per-cell padding for asset-table column headers. The header tint is
/// rendered at the parent `Grid` level via `BulkEntryHeaderHeightKey`, not
/// here, so this modifier only handles spacing/sizing.
struct BulkEntryHeaderCellStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .frame(maxHeight: .infinity)
  }
}

// MARK: - Content Area

/// Owns the `viewModel.rows.isEmpty` observation so that `BulkEntryView.body`
/// does not depend on `rows`, preventing cascading re-evaluations of unrelated
/// children (toolbar, cash flow section) on every asset row commit.
struct BulkEntryContentArea: View {
  var viewModel: BulkEntryViewModel
  @Binding var cachedCategoryNames: [String]
  var csvImportTarget: Binding<CSVImportTarget?>

  @State private var showEmptyStatePopover = false
  @State private var emptyStatePlatformName = ""
  @State private var emptyStatePlatformError = ""

  var body: some View {
    if viewModel.rows.isEmpty {
      ContentUnavailableView {
        Label("No Assets", systemImage: "tray")
      } description: {
        Text(
          "Add a platform to start building your snapshot, or import assets from a CSV file."
        )
      } actions: {
        Button("Add Platform") {
          emptyStatePlatformName = ""
          emptyStatePlatformError = ""
          showEmptyStatePopover = true
        }
        .buttonStyle(.borderedProminent)
        .popover(isPresented: $showEmptyStatePopover, arrowEdge: .bottom) {
          emptyStateAddPlatformPopover
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
          BulkEntryAssetSection(
            viewModel: viewModel,
            cachedCategoryNames: $cachedCategoryNames,
            csvImportTarget: csvImportTarget)
          BulkEntryCashFlowSection(
            viewModel: viewModel,
            csvImportTarget: csvImportTarget)
        }
        .padding()
      }
    }
  }

  private var emptyStateAddPlatformPopover: some View {
    VStack(spacing: 12) {
      Text("New Platform")
        .font(.headline)
      TextField("Platform name", text: $emptyStatePlatformName)
        .textFieldStyle(.roundedBorder)
        .onSubmit { commitEmptyStatePlatform() }
      if !emptyStatePlatformError.isEmpty {
        Text(emptyStatePlatformError)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Button("Cancel") { showEmptyStatePopover = false }
          .buttonStyle(.bordered)
        Button("Add") { commitEmptyStatePlatform() }
          .buttonStyle(.borderedProminent)
          .disabled(emptyStatePlatformName.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
    .frame(width: 260)
  }

  private func commitEmptyStatePlatform() {
    let trimmed = emptyStatePlatformName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      emptyStatePlatformError = String(
        localized: "Platform name cannot be empty.", table: "Snapshot")
      return
    }
    if let rowID = viewModel.addPlatform(name: trimmed) {
      showEmptyStatePopover = false
      viewModel.pendingFocusRowID = rowID
    } else {
      emptyStatePlatformError = String(
        localized: "A platform with this name already exists.", table: "Snapshot")
    }
  }
}

// MARK: - Asset Section

/// The entire asset section extracted as its own observation boundary.
///
/// By placing `viewModel.platformGroups` access inside this struct, mutations
/// to `rows` only invalidate this subtree — not the parent `BulkEntryView.body`.
/// This mirrors the `BulkEntryCashFlowSection` pattern for cash flow rows.
struct BulkEntryAssetSection: View {
  var viewModel: BulkEntryViewModel
  @Binding var cachedCategoryNames: [String]
  var csvImportTarget: Binding<CSVImportTarget?>
  @FocusState private var focusedRowID: UUID?
  @FocusState private var nameFieldFocusedRowID: UUID?

  var body: some View {
    ForEach(viewModel.platformGroups, id: \.platform) { group in
      BulkEntryPlatformSection(
        viewModel: viewModel,
        platform: group.platform,
        rows: group.rows,
        cachedCategoryNames: $cachedCategoryNames,
        focusedRowID: $focusedRowID,
        nameFieldFocusedRowID: $nameFieldFocusedRowID,
        csvImportTarget: csvImportTarget
      )
      .equatable()
    }
    .onChange(of: focusedRowID) { oldValue, _ in
      if let oldID = oldValue {
        viewModel.flushRowCommit(for: oldID)
      }
    }
    .onChange(of: nameFieldFocusedRowID) { oldValue, _ in
      if let oldID = oldValue {
        viewModel.flushRowCommit(for: oldID)
      }
    }
    .onChange(of: viewModel.pendingFocusRowID) { _, rowID in
      guard let rowID else { return }
      let isNewRow = viewModel.rows.first(where: { $0.id == rowID })?.isNewRow ?? false
      if isNewRow {
        nameFieldFocusedRowID = rowID
      } else {
        focusedRowID = rowID
      }
      viewModel.pendingFocusRowID = nil
    }
  }
}

/// A single platform's header + rows, extracted as an Equatable observation boundary.
///
/// When only one platform's rows change, SwiftUI compares `platform` and `rows`
/// via `Equatable` and skips body re-evaluation for all unchanged platforms.
struct BulkEntryPlatformSection: View, Equatable {
  var viewModel: BulkEntryViewModel
  let platform: String
  let rows: [BulkEntryRow]
  @Binding var cachedCategoryNames: [String]
  var focusedRowID: FocusState<UUID?>.Binding
  var nameFieldFocusedRowID: FocusState<UUID?>.Binding
  var csvImportTarget: Binding<CSVImportTarget?>

  static func == (lhs: BulkEntryPlatformSection, rhs: BulkEntryPlatformSection) -> Bool {
    lhs.platform == rhs.platform && lhs.rows == rhs.rows
      && lhs.cachedCategoryNames == rhs.cachedCategoryNames
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      platformHeader
      // One `Grid` per platform section. Column widths auto-size to the
      // widest cell across the header and every row in this section, so
      // the "Previous Value" and "Category" columns finally have a single
      // shared width that respects content (the long-standing alignment
      // drift between the header and rows is eliminated). Cells use
      // `horizontalSpacing: 0` and per-cell horizontal padding.
      //
      // The header tint and per-row "updated" tints are rendered as a
      // single `.background(alignment: .top)` strip stack on this `Grid`,
      // sized via the heights published by `BulkEntryHeaderHeightKey` and
      // `BulkEntryDataRowsKey`. `Grid` has no native row-background API
      // and `.background()` on `GridRow` is forwarded per cell (which
      // leaves gaps where a cell is narrower than its column) — this is
      // the SwiftUI-idiomatic alternative.
      //
      // NOTE: `.equatable()` cannot be applied to `BulkEntryRowView` here:
      // `EquatableView` is opaque to `Grid`'s row introspection, so the
      // `GridRow` returned from the row's `body` would not be recognized
      // and each cell would render as its own implicit row. The row view
      // is left un-`.equatable()`-wrapped; the section-level
      // `BulkEntryPlatformSection: Equatable` boundary still keeps cross-
      // platform mutations isolated.
      Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
        BulkEntryColumnHeaders()
        ForEach(rows) { row in
          BulkEntryRowView(
            viewModel: viewModel,
            row: row,
            cachedCategoryNames: $cachedCategoryNames,
            focusedRowID: focusedRowID,
            nameFieldFocusedRowID: nameFieldFocusedRowID
          )
          Divider()
        }
      }
      .bulkEntrySectionBackgrounds(rowIDs: rows.map(\.id))
    }
    .padding(.bottom, 16)
  }

  private var platformHeader: some View {
    HStack(spacing: 12) {
      Text(platform.isEmpty ? "No Platform" : platform)
        .font(.title3)
        .fontWeight(.bold)

      Text("\(rows.count)")
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())

      let (groupUpdated, groupTotal) = rows.reduce(into: (0, 0)) { acc, row in
        if row.isIncluded {
          acc.1 += 1
          if row.isUpdated { acc.0 += 1 }
        }
      }
      Text("\(groupUpdated)/\(groupTotal)")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      Button {
        let rowID = viewModel.addManualRow(forPlatform: platform)
        nameFieldFocusedRowID.wrappedValue = rowID
      } label: {
        Label("Add Asset", systemImage: "plus")
          .font(.callout)
      }
      .helpWhenUnlocked("Add a new asset to this platform")

      Button {
        csvImportTarget.wrappedValue = .asset(platform: platform)
      } label: {
        Label("Import CSV", systemImage: "doc.text")
          .font(.callout)
      }
      .helpWhenUnlocked("Import a CSV file to fill values for this platform")
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
  }
}

// MARK: - Cash Flow Section

/// The entire cash flow section extracted as its own observation boundary.
///
/// By placing all `viewModel.cashFlowRows` accesses (header count badge,
/// row list, etc.) inside this struct, mutations to cash flow rows only
/// invalidate this subtree — not the parent `BulkEntryView.body` which
/// also reads asset-related properties like `platformGroups`.
struct BulkEntryCashFlowSection: View {
  var viewModel: BulkEntryViewModel
  @Binding var csvImportTarget: CSVImportTarget?
  @FocusState private var focusedAmountRowID: UUID?
  @FocusState private var focusedDescriptionRowID: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.top, 24)

      BulkEntryCashFlowList(
        viewModel: viewModel,
        focusedAmountRowID: $focusedAmountRowID,
        focusedDescriptionRowID: $focusedDescriptionRowID
      )
    }
    .padding(.bottom, 16)
    .onChange(of: focusedAmountRowID) { oldValue, _ in
      if let oldID = oldValue {
        viewModel.flushCashFlowCommit(for: oldID)
      }
    }
    .onChange(of: focusedDescriptionRowID) { oldValue, _ in
      if let oldID = oldValue {
        viewModel.flushCashFlowCommit(for: oldID)
      }
    }
    .onChange(of: viewModel.pendingCashFlowFocusRowID) { _, rowID in
      guard let rowID else { return }
      let isNewRow =
        viewModel.cashFlowRows.first(where: { $0.id == rowID })?.source == .manualNew
      if isNewRow {
        focusedDescriptionRowID = rowID
      } else {
        focusedAmountRowID = rowID
      }
      viewModel.pendingCashFlowFocusRowID = nil
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("Cash Flow Operations")
        .font(.title3)
        .fontWeight(.bold)

      if !viewModel.cashFlowRows.isEmpty {
        Text("\(viewModel.cashFlowCount)")
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }

      Spacer()

      Button {
        viewModel.addManualCashFlowRow()
      } label: {
        Label("Add Cash Flow", systemImage: "plus")
          .font(.callout)
      }
      .helpWhenUnlocked("Add a new cash flow operation")

      Button {
        csvImportTarget = .cashFlow
      } label: {
        Label("Import CSV", systemImage: "doc.text")
          .font(.callout)
      }
      .helpWhenUnlocked("Import cash flows from a CSV file")
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
  }
}

// MARK: - Cash Flow Row List

/// Isolates the cash flow `ForEach` into its own observation boundary.
///
/// When this struct's `body` accesses `viewModel.cashFlowRows`, only this
/// subtree is invalidated on mutations — the parent `BulkEntryView.body`
/// is NOT re-evaluated.
struct BulkEntryCashFlowList: View {
  var viewModel: BulkEntryViewModel
  var focusedAmountRowID: FocusState<UUID?>.Binding
  var focusedDescriptionRowID: FocusState<UUID?>.Binding

  var body: some View {
    if !viewModel.cashFlowRows.isEmpty {
      // See `BulkEntryPlatformSection.body` for why `.equatable()` is
      // not applied to the row view inside a `Grid`.
      Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
        BulkEntryCashFlowColumnHeaders()
        ForEach(viewModel.cashFlowRows) { row in
          BulkEntryCashFlowRowView(
            viewModel: viewModel,
            row: row,
            focusedAmountRowID: focusedAmountRowID,
            focusedDescriptionRowID: focusedDescriptionRowID
          )
          Divider()
        }
      }
      .bulkEntrySectionBackgrounds()
      BulkEntryCashFlowNetSummary(viewModel: viewModel)
    }
  }
}

// MARK: - Cash Flow Net Summary

struct BulkEntryCashFlowNetSummary: View {
  var viewModel: BulkEntryViewModel

  var body: some View {
    let totals = viewModel.includedCashFlowNetByCurrency
    if !totals.isEmpty {
      HStack(alignment: .firstTextBaseline) {
        Text("Net Cash Flow")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          ForEach(totals, id: \.currency) { entry in
            Text(entry.total.formatted(currency: entry.currency))
              .monospacedDigit()
              .fontWeight(.semibold)
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 8)
    }
  }
}

// MARK: - Cash Flow Column Headers View

/// Cash-flow table column headers — emitted as a `GridRow` so the parent
/// `Grid` can size each column to the widest cell across header and rows.
struct BulkEntryCashFlowColumnHeaders: View {
  var body: some View {
    GridRow {
      Text("Include")
        .gridColumnAlignment(.center)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Description")
        .gridColumnAlignment(.leading)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Amount")
        .gridColumnAlignment(.trailing)
        .modifier(BulkEntryHeaderCellStyle())
      Text("Currency")
        .gridColumnAlignment(.leading)
        .modifier(BulkEntryHeaderCellStyle())
      Color.clear
        .frame(width: 28, height: 1)
        .modifier(BulkEntryHeaderCellStyle())
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .publishesBulkEntryHeaderHeight()
  }
}
