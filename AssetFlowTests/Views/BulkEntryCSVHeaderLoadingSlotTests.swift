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
import SwiftData
import SwiftUI
import Testing

@testable import AssetFlow

@Suite("Bulk Entry CSV Loading Localization Tests")
@MainActor
struct BulkEntryCSVLoadingLocalizationTests {
  @Test("CSV loading status has a Traditional Chinese translation")
  func loadingStatusLocalizes() throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hant", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    #expect(String(localized: "Loading CSV…", bundle: bundle) == "正在載入 CSV…")
  }
}

@Suite("Bulk Entry CSV Header Loading Slot Tests", .serialized)
@MainActor
struct BulkEntryCSVHeaderLoadingSlotTests {
  @Test("Showing CSV progress keeps the header buttons in place")
  func loadingDoesNotMoveButtons() async throws {
    let probe = ButtonOriginProbe()
    let host = NSHostingView(rootView: HeaderHarness(isLoading: false, probe: probe))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    try? await Task.sleep(for: .milliseconds(50))
    window.displayIfNeeded()
    let buttonView = try #require(probe.view)
    let initialButtonX = buttonView.convert(.zero, to: nil).x
    let initialHeight = host.fittingSize.height
    let originalHeader = NSHostingView(
      rootView: HeaderHarness(isLoading: false, probe: ButtonOriginProbe(), useSlot: false))
    #expect(initialButtonX > 0)
    #expect(initialHeight == originalHeader.fittingSize.height)

    let before = try bitmapData(of: host)
    host.rootView = HeaderHarness(isLoading: true, probe: probe)
    #expect(try await waitForBitmapChange(from: before, in: host, window: window))

    let currentButtonView = try #require(probe.view)
    #expect(abs(currentButtonView.convert(.zero, to: nil).x - initialButtonX) <= 1)
    #expect(host.fittingSize.height == initialHeight)
  }

  @Test(
    "The delayed indicator paints inside wide and narrow header gaps",
    arguments: [CGFloat(460), CGFloat(700)])
  func loadingIndicatorIsVisible(width: CGFloat) async throws {
    let probe = ButtonOriginProbe()
    let host = NSHostingView(rootView: HeaderHarness(isLoading: false, probe: probe, width: width))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    try? await Task.sleep(for: .milliseconds(50))
    window.displayIfNeeded()
    let before = try bitmapData(of: host)

    host.rootView = HeaderHarness(isLoading: true, probe: probe, width: width)
    #expect(try await waitForBitmapChange(from: before, in: host, window: window))
  }

  @Test("A stale Bulk Entry draft still lets users cancel either CSV load")
  func staleDraftKeepsCancelClickable() async throws {
    try await verifyStaleDraftCancellation(for: .asset(platform: "Broker A"))
    try await verifyStaleDraftCancellation(for: .cashFlow)
  }

  private func verifyStaleDraftCancellation(for target: CSVImportTarget) async throws {
    let container = TestDataManager.createInMemoryContainer()
    let viewModel = BulkEntryViewModel(modelContext: container.mainContext, date: Date())
    try #require(viewModel.addPlatform(name: "Broker A") != nil)

    var tracker = BulkEntryCSVLoadingTracker()
    _ = tracker.begin(target)
    let probe = CancelProbe()
    let host = NSHostingView(
      rootView: ContentHarness(viewModel: viewModel, tracker: tracker, probe: probe))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    viewModel.markSourceDataStale()
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while probe.isEmpty && ContinuousClock.now < deadline {
      window.makeKeyAndOrderFront(nil)
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      for y in stride(from: 300, through: 60, by: -10) where probe.isEmpty {
        for x in stride(from: 300, through: 780, by: 10) where probe.isEmpty {
          click(NSPoint(x: CGFloat(x), y: CGFloat(y)), in: window)
        }
      }
      if probe.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
    }
    #expect(!probe.isEmpty)
    #expect(viewModel.rows.count == 1)
    #expect(viewModel.cashFlowRows.isEmpty)
    #expect(probe.importSelections == 0)
  }

  private func click(_ point: NSPoint, in window: NSWindow) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      guard
        let event = NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 1,
          clickCount: 1, pressure: 1)
      else { continue }
      window.sendEvent(event)
    }
  }

  private func bitmapData<Content: View>(of host: NSHostingView<Content>) throws -> Data {
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return try #require(bitmap.tiffRepresentation)
  }

  private func waitForBitmapChange<Content: View>(
    from before: Data,
    in host: NSHostingView<Content>,
    window: NSWindow
  ) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      window.makeKeyAndOrderFront(nil)
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      if try bitmapData(of: host) != before { return true }
      try await Task.sleep(for: .milliseconds(50))
    }
    return false
  }

  private final class ButtonOriginProbe {
    weak var view: NSView?
  }

  private final class CancelProbe {
    var count = 0
    var importSelections = 0
  }

  private struct ContentHarness: View {
    let viewModel: BulkEntryViewModel
    let tracker: BulkEntryCSVLoadingTracker
    let probe: CancelProbe
    @State private var cachedCategoryNames: [String] = []
    @State private var csvImportTarget: CSVImportTarget?

    var body: some View {
      BulkEntryContentArea(
        viewModel: viewModel,
        cachedCategoryNames: $cachedCategoryNames,
        csvImportTarget: $csvImportTarget,
        csvLoadingTracker: tracker,
        isSourceDataStale: viewModel.isSourceDataStale,
        onCancelCSVImport: { probe.count += 1 }
      )
      .frame(width: 800, height: 320)
      .onChange(of: csvImportTarget) { _, target in
        if target != nil { probe.importSelections += 1 }
      }
    }
  }

  private struct ButtonOriginMarker: NSViewRepresentable {
    let probe: ButtonOriginProbe

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      probe.view = view
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
  }

  private struct HeaderHarness: View {
    let isLoading: Bool
    let probe: ButtonOriginProbe
    var useSlot = true
    var width: CGFloat = 700

    var body: some View {
      HStack(spacing: 12) {
        Text("Broker A")
          .font(.title3)
        Text("1/2")
        if useSlot {
          BulkEntryCSVHeaderLoadingSlot(isLoading: isLoading, onCancel: {})
        } else {
          Spacer()
        }
        Button("Add Asset") {}
          .background(ButtonOriginMarker(probe: probe))
        Button("Import CSV") {}
      }
      .frame(width: width)
    }
  }
}
