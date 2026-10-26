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
import Foundation
import SwiftUI
import Testing

@testable import AssetFlow

@Suite("ColumnMappingPreviewLayout Tests")
@MainActor
struct ColumnMappingPreviewLayoutTests {
  @Test("Preview takes its content width until the sheet reaches its cap")
  func intrinsicWidthAndHorizontalOverflow() throws {
    let short = previewHost(contentWidth: 180, contentHeight: 80)
    let medium = previewHost(contentWidth: 350, contentHeight: 80)
    let wide = previewHost(contentWidth: 800, contentHeight: 80)

    #expect(short.fittingSize.width < medium.fittingSize.width)
    #expect(medium.fittingSize.width < wide.fittingSize.width)
    #expect(wide.fittingSize.width == 500)
    let window = windowForHost(wide)
    window.displayIfNeeded()
    let scrollView = try #require(findScrollView(in: wide))
    #expect(scrollView.documentView?.frame.width ?? 0 > scrollView.contentSize.width)
  }

  @Test("Preview takes its content height until the sheet reaches its cap")
  func intrinsicHeightAndVerticalOverflow() throws {
    let short = previewHost(contentWidth: 180, contentHeight: 80)
    let tall = previewHost(contentWidth: 180, contentHeight: 800)

    #expect(short.fittingSize.height < tall.fittingSize.height)
    #expect(tall.fittingSize.height == 300)
    let window = windowForHost(tall)
    window.displayIfNeeded()
    let scrollView = try #require(findScrollView(in: tall))
    #expect(scrollView.documentView?.frame.height ?? 0 > scrollView.contentSize.height)
  }

  @Test("The mapping sheet grows with its table and stops at the parent window cap")
  func sheetRespondsToContentAndWindowSize() throws {
    let compact = sheetHost(
      columnWidths: [140, 140], rowCount: 1,
      parentSize: CGSize(width: 1200, height: 800))
    let wide = sheetHost(
      columnWidths: [500, 500], rowCount: 1,
      parentSize: CGSize(width: 1200, height: 800))
    let tall = sheetHost(
      columnWidths: [140, 140], rowCount: 200,
      parentSize: CGSize(width: 1200, height: 800))
    let narrowWindow = sheetHost(
      columnWidths: [500, 500], rowCount: 1,
      parentSize: CGSize(width: 700, height: 800))

    #expect(wide.fittingSize.width > compact.fittingSize.width)
    #expect(wide.fittingSize.width <= 1168)
    #expect(narrowWindow.fittingSize.width < wide.fittingSize.width)
    #expect(tall.fittingSize.height > compact.fittingSize.height)
    #expect(tall.fittingSize.height <= 640)
    let horizontalWindow = windowForHost(narrowWindow)
    let verticalWindow = windowForHost(tall)
    horizontalWindow.displayIfNeeded()
    verticalWindow.displayIfNeeded()
    let horizontalScrollView = try #require(findScrollView(in: narrowWindow))
    let verticalScrollView = try #require(findScrollView(in: tall))
    #expect(
      horizontalScrollView.documentView?.frame.width ?? 0 > horizontalScrollView.contentSize.width)
    #expect(
      verticalScrollView.documentView?.frame.height ?? 0 > verticalScrollView.contentSize.height)
  }

  @Test("Presented sheet follows narrow and wide CSV tables")
  func presentedSheetFollowsTableWidth() throws {
    let narrow = try presentedSheetWidth(columnWidths: [140, 140, 140])
    let wide = try presentedSheetWidth(columnWidths: [500, 500, 500])
    #expect(wide > 900)
    #expect(wide > narrow + 300)
    #expect(wide <= 1168)
  }

  @Test("Presented sheet opens at its final width")
  func presentedSheetWidthDoesNotJumpOnOpen() throws {
    let sizes = try sheetSizesWhileOpening(columnWidths: [500, 500, 500])
    #expect(abs(sizes.first.width - sizes.settled.width) <= 1)
    #expect(abs(sizes.parentFirst.width - sizes.parentSettled.width) <= 1)
  }

  @Test("A wide presented sheet still scrolls when its width is reduced")
  func presentedSheetStillScrollsAtReducedWidth() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(
      rootView: PresentedMappingSheet(columnWidths: [500, 500, 500], rowCount: 1))
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let sheet = try #require(window.sheets.first)
    let initialWidth = sheet.frame.width
    sheet.setContentSize(NSSize(width: 700, height: sheet.contentLayoutRect.height))
    sheet.displayIfNeeded()

    #expect(sheet.frame.width < initialWidth - 100)
    let contentView = try #require(sheet.contentView)
    let scrollView = try #require(findScrollView(in: contentView))
    #expect(scrollView.documentView?.frame.width ?? 0 > scrollView.contentSize.width)
  }

  @Test("Only a wide presented table needs horizontal scrolling")
  func presentedSheetScrollsOnlyForWideTable() throws {
    let narrow = try presentedSheetScrollWidths(columnWidths: [140, 140, 140])
    let wide = try presentedSheetScrollWidths(columnWidths: [500, 500, 500])

    #expect(narrow.document <= narrow.viewport + 1)
    #expect(wide.document > wide.viewport)
  }

  private func presentedSheetScrollWidths(columnWidths: [CGFloat]) throws -> (
    document: CGFloat, viewport: CGFloat
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(
      rootView: PresentedMappingSheet(columnWidths: columnWidths, rowCount: 1))
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let sheet = try #require(window.sheets.first)
    let contentView = try #require(sheet.contentView)
    let scrollView = try #require(findScrollView(in: contentView))
    return (scrollView.documentView?.frame.width ?? 0, scrollView.contentSize.width)
  }

  private func sheetSizesWhileOpening(columnWidths: [CGFloat]) throws -> (
    first: CGSize, settled: CGSize, parentFirst: CGSize, parentSettled: CGSize
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(
      rootView: PresentedMappingSheet(columnWidths: columnWidths, rowCount: 1))
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    let deadline = Date().addingTimeInterval(1)
    while window.sheets.isEmpty && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    let sheet = try #require(window.sheets.first)
    let first = sheet.frame.size
    let parentFirst = window.frame.size
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    return (first, sheet.frame.size, parentFirst, window.frame.size)
  }

  @Test("Presented sheet height follows CSV row count up to its cap")
  func presentedSheetFollowsRowCount() throws {
    let short = try presentedSheetSize(columnWidths: [140, 140, 140], rowCount: 1)
    let tall = try presentedSheetSize(columnWidths: [140, 140, 140], rowCount: 200)

    #expect(short.height < tall.height)
    #expect(tall.height <= 640)
  }

  @Test("Bulk Entry stripes every second data row with the system color")
  func alternatingDataRowBackgrounds() throws {
    let expected = try #require(NSColor.alternatingContentBackgroundColors.dropFirst().first)
    let background = { (index: Int, enabled: Bool) in
      ColumnMappingPreviewLayout.dataRowBackgroundColor(
        at: index, showsAlternatingRowBackgrounds: enabled)
    }

    #expect(background(0, true) == nil)
    #expect(background(1, true)?.isEqual(expected) == true)
    #expect(background(2, true) == nil)
    #expect(background(3, true)?.isEqual(expected) == true)
    #expect(background(1, false) == nil)
  }

  private func presentedSheetWidth(columnWidths: [CGFloat]) throws -> CGFloat {
    try presentedSheetSize(columnWidths: columnWidths, rowCount: 1).width
  }

  private func presentedSheetSize(columnWidths: [CGFloat], rowCount: Int) throws -> CGSize {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(
      rootView: PresentedMappingSheet(columnWidths: columnWidths, rowCount: rowCount))
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    return try #require(window.sheets.first).frame.size
  }

  private struct PresentedMappingSheet: View {
    let columnWidths: [CGFloat]
    let rowCount: Int
    @State private var isPresented = true

    var body: some View {
      Color.clear
        .sheet(isPresented: $isPresented) {
          ColumnMappingSheet(
            rawHeaders: columnWidths.indices.map { "Column \($0)" },
            schema: .assetWithoutPlatform,
            sampleRows: Array(
              repeating: columnWidths.indices.map { _ in "A" }, count: rowCount),
            preparedColumnWidths: columnWidths,
            initialMapping: [:],
            parentSize: CGSize(width: 1200, height: 800),
            onConfirm: { _ in },
            onCancel: {})
        }
    }
  }

  private func sheetHost(
    columnWidths: [CGFloat], rowCount: Int, parentSize: CGSize
  ) -> NSHostingView<some View> {
    let rows = Array(repeating: ["A", "1"], count: rowCount)
    let host = NSHostingView(
      rootView: ColumnMappingSheet(
        rawHeaders: ["Symbol", "Price"],
        schema: .assetWithoutPlatform,
        sampleRows: rows,
        preparedColumnWidths: columnWidths,
        initialMapping: [:],
        parentSize: parentSize,
        onConfirm: { _ in },
        onCancel: {}))
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    return host
  }

  private func previewHost(contentWidth: CGFloat, contentHeight: CGFloat) -> NSHostingView<
    some View
  > {
    let host = NSHostingView(
      rootView: ColumnMappingPreviewScrollView {
        Color.clear.frame(width: contentWidth, height: contentHeight)
      }
      .padding(16)
      .frame(maxWidth: 500, maxHeight: 300))
    host.frame.size = host.fittingSize
    host.layoutSubtreeIfNeeded()
    return host
  }

  private func findScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView { return scrollView }
    for child in view.subviews {
      if let scrollView = findScrollView(in: child) { return scrollView }
    }
    return nil
  }

  private func windowForHost<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: host.fittingSize),
      styleMask: [], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return window
  }

  @Test("The widest value anywhere in the CSV determines its column width")
  func columnWidthsIncludeLaterLongValues() throws {
    let widths = try ColumnMappingPreviewLayout.columnWidths(
      headers: ["Holding", "Currency"],
      rows: [["Short", "USD"], [String(repeating: "Wide value ", count: 12), "EUR"]])

    #expect(widths.count == 2)
    #expect(widths[0] > widths[1])
    #expect(widths[1] < 160)
  }

  @Test("Short CSV values have no fixed text-cell width floor")
  func shortValuesFollowTheirMeasuredTextWidth() throws {
    let widths = try ColumnMappingPreviewLayout.columnWidths(
      headers: ["A", "B"], rows: [["1", "2"]])

    #expect(widths.count == 2)
    #expect(widths.allSatisfy { $0 > 0 && $0 < 116 })
  }

  @Test("Natural picker widths expand only the columns that need them")
  func pickerWidthIsIncludedWithoutACommonFloor() {
    let widths = ColumnMappingPreviewLayout.fittedColumnWidths(
      textWidths: [116, 220, 116], pickerWidths: [0: 128, 1: 135, 2: 119])

    #expect(widths == [128, 220, 119])
    #expect(
      ColumnMappingPreviewLayout.fittedColumnWidths(
        textWidths: [116, 116], pickerWidths: [0: 128]
      ).isEmpty)
  }

  @Test("Existing prepared widths do not trigger a second sheet layout")
  func pickerMeasurementKeepsOnlyNewOverflow() {
    #expect(
      ColumnMappingPreviewLayout.pickerWidthsExceedingPrepared(
        preparedWidths: [140, 220], measuredWidths: [0: 130, 1: 200]
      ).isEmpty)
    #expect(
      ColumnMappingPreviewLayout.pickerWidthsExceedingPrepared(
        preparedWidths: [140, 220], measuredWidths: [0: 160, 1: 200]) == [0: 160])
  }

  @Test("Measured columns fit the one-line SwiftUI text")
  func measuredWidthsFitRenderedText() throws {
    let values = [
      String(repeating: "Wide W ", count: 20),
      String(repeating: "繁體中文資產", count: 16),
      String(repeating: "📈 portfolio ", count: 16),
    ]
    for value in values {
      let width = try ColumnMappingPreviewLayout.columnWidths(
        headers: ["Holding"], rows: [[value]])[0]
      let text = NSHostingView(
        rootView: Text(value)
          .font(.caption)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .padding(.horizontal, 8)
          .padding(.vertical, 2))

      #expect(width >= text.fittingSize.width)
    }
  }

  @Test("Column measurement runs off the main actor")
  func columnMeasurementRunsInBackground() async throws {
    let widths = try await Task.detached {
      try ColumnMappingPreviewLayout.columnWidths(
        headers: ["Holding"], rows: [[String(repeating: "Wide ", count: 20)]])
    }.value

    #expect(widths[0] > 160)
  }

  @Test("Embedded CSV line breaks remain visible on one preview line")
  func embeddedLineBreaksUseVisibleMarkers() {
    let text = ColumnMappingPreviewLayout.displayValue("First\r\nSecond\nThird")
    #expect(!text.contains("\r"))
    #expect(!text.contains("\n"))
    #expect(text.contains("First"))
    #expect(text.contains("Second"))
    #expect(text.contains("Third"))
  }

  @Test("Long CSV values stay on one line in the rendered preview row")
  func longValuesStayOnOneRenderedLine() throws {
    let longValue =
      "This CSV value is long enough to need a wider column in the mapping preview."
    let shortWidths = try ColumnMappingPreviewLayout.columnWidths(
      headers: ["Holding"], rows: [["Short"]])
    let longWidths = try ColumnMappingPreviewLayout.columnWidths(
      headers: ["Holding"], rows: [[longValue]])
    let short = NSHostingView(
      rootView: ColumnMappingPreviewDataRow(values: ["Short"], columnWidths: shortWidths))
    let long = NSHostingView(
      rootView: ColumnMappingPreviewDataRow(values: [longValue], columnWidths: longWidths))

    #expect(long.fittingSize.height == short.fittingSize.height)
    #expect(long.fittingSize.width > short.fittingSize.width)
  }

  @Test("Data rows retain the original caption height and vertical padding")
  func originalRowHeightIsPreserved() throws {
    let widths = try ColumnMappingPreviewLayout.columnWidths(
      headers: ["Holding"], rows: [["Short"]])
    let row = NSHostingView(
      rootView: ColumnMappingPreviewDataRow(values: ["Short"], columnWidths: widths))
    let originalCell = NSHostingView(
      rootView: Text("Short")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(minWidth: 100, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 2))

    #expect(row.fittingSize.height == originalCell.fittingSize.height)
  }
}
