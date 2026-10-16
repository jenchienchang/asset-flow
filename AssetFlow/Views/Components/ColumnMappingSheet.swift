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

import AppKit
import SwiftUI

/// Sizing for the scrollable mapping table.
enum ColumnMappingPreviewLayout {
  nonisolated static let cellHorizontalPadding: CGFloat = 8
  nonisolated static let cellVerticalPadding: CGFloat = 2
  nonisolated static let headerVerticalPadding: CGFloat = 4
  nonisolated static let textMeasurementClearance: CGFloat = 8
  static let dataRowHeight: CGFloat = 24
  static let pickerRowHeight: CGFloat = 36
  static let dividerHeight: CGFloat = 1

  nonisolated static func displayValue(_ value: String) -> String {
    guard value.rangeOfCharacter(from: .newlines) != nil else { return value }

    var displayed = String()
    displayed.reserveCapacity(value.utf8.count)
    var previousWasCarriageReturn = false
    for scalar in value.unicodeScalars {
      if scalar.value == 13 {
        displayed.append(" ↵ ")
        previousWasCarriageReturn = true
      } else if scalar.value == 10 && previousWasCarriageReturn {
        previousWasCarriageReturn = false
      } else if CharacterSet.newlines.contains(scalar) {
        displayed.append(" ↵ ")
        previousWasCarriageReturn = false
      } else {
        displayed.unicodeScalars.append(scalar)
        previousWasCarriageReturn = false
      }
    }
    return displayed
  }

  nonisolated static func columnWidths(
    headers: [String],
    rows: [[String]]
  ) throws -> [CGFloat] {
    let captionFont = NSFont.preferredFont(forTextStyle: .caption1)
    let headerFont = NSFont.systemFont(ofSize: captionFont.pointSize, weight: .semibold)
    let captionAttributes: [NSAttributedString.Key: Any] = [.font: captionFont]
    let headerAttributes: [NSAttributedString.Key: Any] = [.font: headerFont]
    let cellInsets = 2 * cellHorizontalPadding + textMeasurementClearance

    var widths = headers.map { header in
      ceil((displayValue(header) as NSString).size(withAttributes: headerAttributes).width)
        + cellInsets
    }

    for (rowIndex, row) in rows.enumerated() {
      if rowIndex.isMultiple(of: 256) {
        try Task.checkCancellation()
      }
      for columnIndex in 0..<min(row.count, widths.count) {
        let text = displayValue(row[columnIndex])
        let textWidth = ceil((text as NSString).size(withAttributes: captionAttributes).width)
        widths[columnIndex] = max(widths[columnIndex], textWidth + cellInsets)
      }
    }
    return widths
  }

  static func fittedColumnWidths(
    textWidths: [CGFloat], pickerWidths: [Int: CGFloat]
  ) -> [CGFloat] {
    guard !textWidths.isEmpty,
      textWidths.indices.allSatisfy({ pickerWidths[$0] != nil })
    else { return [] }
    return textWidths.enumerated().map { index, textWidth in
      max(textWidth, pickerWidths[index] ?? textWidth)
    }
  }

  static func pickerWidthsExceedingPrepared(
    preparedWidths: [CGFloat], measuredWidths: [Int: CGFloat]
  ) -> [Int: CGFloat] {
    measuredWidths.filter { index, width in
      preparedWidths.indices.contains(index) && width > preparedWidths[index]
    }
  }

  /// Finishes text and picker sizing within the existing CSV loading task.
  @MainActor
  static func prepareColumnWidths(
    headers: [String],
    rows: [[String]],
    schema: CSVColumnSchema,
    initialMapping: [CanonicalColumn: Int]
  ) async throws -> [CGFloat] {
    let measurement = Task.detached(priority: .userInitiated) {
      try columnWidths(headers: headers, rows: rows)
    }
    let textWidths = try await withTaskCancellationHandler {
      try await measurement.value
    } onCancel: {
      measurement.cancel()
    }
    try Task.checkCancellation()

    var assignments = [CanonicalColumn?](repeating: nil, count: headers.count)
    for (column, index) in initialMapping where assignments.indices.contains(index) {
      assignments[index] = column
    }
    var pickerWidths: [Int: CGFloat] = [:]
    var measuredSelections: [CanonicalColumn?: CGFloat] = [:]
    for index in headers.indices {
      if index.isMultiple(of: 256) {
        try Task.checkCancellation()
      }
      let selection = assignments[index]
      if let measured = measuredSelections[selection] {
        pickerWidths[index] = measured
      } else {
        let cell = ColumnMappingPickerCell(
          schema: schema,
          selection: .constant(selection),
          isDuplicate: false)
        let measured = NSHostingView(rootView: cell).fittingSize.width
        measuredSelections[selection] = measured
        pickerWidths[index] = measured
      }
    }
    return fittedColumnWidths(textWidths: textWidths, pickerWidths: pickerWidths)
  }

  static func maxSheetWidth(parentWidth: CGFloat) -> CGFloat {
    max(1, parentWidth - 32)
  }
}

struct ColumnMappingPreviewDataRow: View {
  let values: [String]
  let columnWidths: [CGFloat]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(columnWidths.indices, id: \.self) { columnIndex in
        let value = columnIndex < values.count ? values[columnIndex] : ""
        Text(ColumnMappingPreviewLayout.displayValue(value))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .helpWhenUnlocked(value)
          .fixedSize(horizontal: true, vertical: false)
          .padding(.horizontal, ColumnMappingPreviewLayout.cellHorizontalPadding)
          .padding(.vertical, ColumnMappingPreviewLayout.cellVerticalPadding)
          .frame(
            width: columnWidths[columnIndex],
            alignment: .leading)
      }
    }
  }
}

struct ColumnMappingPreviewScrollView<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      content
    }
  }
}

private struct ColumnMappingPickerCell: View {
  let schema: CSVColumnSchema
  @Binding var selection: CanonicalColumn?
  let isDuplicate: Bool

  var body: some View {
    Picker("", selection: $selection) {
      Text(String(localized: "— Skip —", table: "Import"))
        .tag(CanonicalColumn?.none)

      ForEach(schema.allColumns) { column in
        Text(column.rawValue)
          .tag(CanonicalColumn?.some(column))
      }
    }
    .labelsHidden()
    .padding(.horizontal, 4)
    .padding(.vertical, 4)
    .overlay(
      isDuplicate
        ? RoundedRectangle(cornerRadius: 4).stroke(.red, lineWidth: 1.5)
        : nil
    )
  }
}

/// Sheet for mapping arbitrary CSV column headers to canonical AssetFlow columns.
///
/// Presents a full CSV table preview with a dropdown above each column,
/// allowing users to assign each CSV column to a canonical field or skip it.
/// Auto-detected mappings are pre-selected.
struct ColumnMappingSheet: View {
  let rawHeaders: [String]
  let schema: CSVColumnSchema
  let sampleRows: [[String]]
  let preparedColumnWidths: [CGFloat]
  let initialMapping: [CanonicalColumn: Int]
  let parentSize: CGSize
  let onConfirm: (CSVColumnMapping) -> Void
  let onCancel: () -> Void

  @State private var columnAssignments: [CanonicalColumn?]
  @State private var pickerCellWidths: [Int: CGFloat] = [:]

  init(
    rawHeaders: [String],
    schema: CSVColumnSchema,
    sampleRows: [[String]],
    preparedColumnWidths: [CGFloat],
    initialMapping: [CanonicalColumn: Int],
    parentSize: CGSize,
    onConfirm: @escaping (CSVColumnMapping) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.rawHeaders = rawHeaders
    self.schema = schema
    self.sampleRows = sampleRows
    self.preparedColumnWidths = preparedColumnWidths
    self.initialMapping = initialMapping
    self.parentSize = parentSize
    self.onConfirm = onConfirm
    self.onCancel = onCancel

    // Build initial assignments array from the partial mapping (inverse: index → column)
    var assignments = [CanonicalColumn?](repeating: nil, count: rawHeaders.count)
    for (column, index) in initialMapping where index < rawHeaders.count {
      assignments[index] = column
    }
    _columnAssignments = State(initialValue: assignments)
  }

  // MARK: - Computed

  private var mappedRequiredCount: Int {
    let mapped = Set(columnAssignments.compactMap { $0 })
    return schema.requiredColumns.filter { mapped.contains($0) }.count
  }

  private var allRequiredMapped: Bool {
    mappedRequiredCount == schema.requiredColumns.count
  }

  private var hasDuplicateAssignments: Bool {
    let assigned = columnAssignments.compactMap { $0 }
    return assigned.count != Set(assigned).count
  }

  private var duplicateColumns: Set<CanonicalColumn> {
    let assigned = columnAssignments.compactMap { $0 }
    var seen = Set<CanonicalColumn>()
    var duplicates = Set<CanonicalColumn>()
    for col in assigned where !seen.insert(col).inserted {
      duplicates.insert(col)
    }
    return duplicates
  }

  private var isConfirmDisabled: Bool {
    !allRequiredMapped || hasDuplicateAssignments
  }

  private var columnWidths: [CGFloat] {
    preparedColumnWidths.enumerated().map { index, width in
      max(width, pickerCellWidths[index] ?? width)
    }
  }

  private var maxSheetWidth: CGFloat {
    ColumnMappingPreviewLayout.maxSheetWidth(parentWidth: parentSize.width)
  }

  private var maxSheetHeight: CGFloat {
    max(1, parentSize.height * Self.maxParentHeightRatio)
  }

  // MARK: - Body

  var body: some View {
    sheetContent(table: csvTable)
      .frame(
        maxWidth: maxSheetWidth,
        maxHeight: maxSheetHeight,
        alignment: .topLeading
      )
      .background(pickerCellMeasurement)
      .onPreferenceChange(PickerCellWidthsPreferenceKey.self) { widths in
        let expanded = ColumnMappingPreviewLayout.pickerWidthsExceedingPrepared(
          preparedWidths: preparedColumnWidths, measuredWidths: widths)
        if pickerCellWidths != expanded {
          pickerCellWidths = expanded
        }
      }
      .fixedSize(horizontal: true, vertical: true)
  }

  private func sheetContent(table: some View) -> some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text(String(localized: "Map CSV Columns", table: "Import"))
          .font(.headline)

        Divider()

        Text(
          String(
            localized:
              "Use the dropdowns above each column to assign it to the corresponding field.",
            table: "Import")
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        table
        statusBar
      }
      .padding()

      Divider()

      HStack {
        Spacer()
        Button(String(localized: "Cancel", table: "Import")) {
          onCancel()
        }
        Button(String(localized: "Confirm", table: "Import")) {
          confirmMapping()
        }
        .buttonStyle(.borderedProminent)
        .disabled(isConfirmDisabled)
      }
      .padding()
    }
  }

  private var pickerCellMeasurement: some View {
    let dupes = duplicateColumns
    return HStack(spacing: 0) {
      ForEach(rawHeaders.indices, id: \.self) { index in
        pickerCell(at: index, duplicates: dupes)
          .fixedSize(horizontal: true, vertical: true)
          .background(
            GeometryReader { proxy in
              Color.clear.preference(
                key: PickerCellWidthsPreferenceKey.self,
                value: [index: proxy.size.width])
            })
      }
    }
    .hidden()
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  // MARK: - CSV Table

  private var csvTable: some View {
    ColumnMappingPreviewScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        Section {
          dataRows
        } header: {
          tableHeader
        }
      }
    }
  }

  @ViewBuilder
  private var dataRows: some View {
    if sampleRows.isEmpty {
      Text(String(localized: "No data rows in this CSV.", table: "Import"))
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
        .frame(height: ColumnMappingPreviewLayout.dataRowHeight, alignment: .leading)
    } else {
      ForEach(sampleRows.indices, id: \.self) { rowIndex in
        ColumnMappingPreviewDataRow(
          values: sampleRows[rowIndex],
          columnWidths: columnWidths)
      }
    }
  }

  private var tableHeader: some View {
    VStack(alignment: .leading, spacing: 0) {
      pickerRow

      Divider()
        .frame(height: ColumnMappingPreviewLayout.dividerHeight)

      headerRow

      Divider()
        .frame(height: ColumnMappingPreviewLayout.dividerHeight)
    }
    .background(.background)
  }

  private var pickerRow: some View {
    let dupes = duplicateColumns
    return HStack(spacing: 0) {
      ForEach(rawHeaders.indices, id: \.self) { index in
        pickerCell(at: index, duplicates: dupes)
          .frame(width: columnWidths[index], alignment: .leading)
      }
    }
    .frame(height: ColumnMappingPreviewLayout.pickerRowHeight)
  }

  private var headerRow: some View {
    HStack(spacing: 0) {
      ForEach(rawHeaders.indices, id: \.self) { index in
        Text(ColumnMappingPreviewLayout.displayValue(rawHeaders[index]))
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .helpWhenUnlocked(rawHeaders[index])
          .fixedSize(horizontal: true, vertical: false)
          .padding(.horizontal, ColumnMappingPreviewLayout.cellHorizontalPadding)
          .padding(.vertical, ColumnMappingPreviewLayout.headerVerticalPadding)
          .frame(
            width: columnWidths[index],
            alignment: .leading)
      }
    }
  }

  // MARK: - Picker Cell

  private func pickerCell(at index: Int, duplicates: Set<CanonicalColumn>) -> some View {
    let isDuplicate =
      columnAssignments[index].map { duplicates.contains($0) } ?? false
    return ColumnMappingPickerCell(
      schema: schema,
      selection: $columnAssignments[index],
      isDuplicate: isDuplicate)
  }

  // MARK: - Status Bar

  private var statusBar: some View {
    VStack(alignment: .leading, spacing: 4) {
      if hasDuplicateAssignments {
        Label {
          Text(
            String(
              localized: "Two or more columns are mapped to the same field.",
              table: "Import")
          )
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
        .font(.callout)
      }

      Label {
        Text(
          String(
            localized:
              "\(mappedRequiredCount) of \(schema.requiredColumns.count) required columns mapped.",
            table: "Import")
        )
      } icon: {
        Image(
          systemName: allRequiredMapped
            ? "checkmark.circle.fill"
            : "info.circle.fill"
        )
        .foregroundStyle(allRequiredMapped ? .green : .secondary)
      }
      .font(.callout)
    }
  }

  // MARK: - Actions

  private func confirmMapping() {
    var columnMap: [CanonicalColumn: Int] = [:]
    for (index, assignment) in columnAssignments.enumerated() {
      if let column = assignment {
        columnMap[column] = index
      }
    }
    let mapping = CSVColumnMapping(
      schema: schema, columnMap: columnMap, rawHeaders: rawHeaders)
    onConfirm(mapping)
  }
}

extension ColumnMappingSheet {
  private static let maxParentHeightRatio: CGFloat = 0.8
}

private struct PickerCellWidthsPreferenceKey: PreferenceKey {
  static let defaultValue: [Int: CGFloat] = [:]

  static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: max)
  }
}
