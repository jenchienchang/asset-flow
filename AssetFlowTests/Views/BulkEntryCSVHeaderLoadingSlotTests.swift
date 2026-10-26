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
  @Test(
    "Visible CSV status preserves header geometry at narrow and wide widths",
    arguments: [CGFloat(460), CGFloat(700)])
  func loadingDoesNotMoveButtons(width: CGFloat) throws {
    let hidden = try headerGeometry(width: width, showsStatus: false)
    let visible = try headerGeometry(width: width, showsStatus: true)
    #expect(abs(visible.buttonX - hidden.buttonX) <= 1)
    #expect(visible.height == hidden.height)
  }

  private func headerGeometry(width: CGFloat, showsStatus: Bool) throws
    -> (buttonX: CGFloat, height: CGFloat)
  {
    let probe = ButtonOriginProbe()
    let host = NSHostingView(
      rootView: HeaderHarness(showsStatus: showsStatus, probe: probe, width: width))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 100)
    let height = host.fittingSize.height
    host.layoutSubtreeIfNeeded()
    let buttonView = try #require(probe.view)
    #expect(buttonView.isDescendant(of: host))
    #expect(buttonView.bounds.width > 0)
    return (buttonView.convert(.zero, to: host).x, height)
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
    while !probe.cancelCallbackInvoked && ContinuousClock.now < deadline {
      window.makeKeyAndOrderFront(nil)
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      for y in stride(from: 300, through: 60, by: -10) where !probe.cancelCallbackInvoked {
        for x in stride(from: 300, through: 780, by: 10) where !probe.cancelCallbackInvoked {
          click(NSPoint(x: CGFloat(x), y: CGFloat(y)), in: window)
        }
      }
      if !probe.cancelCallbackInvoked { try await Task.sleep(for: .milliseconds(50)) }
    }
    #expect(probe.cancelCallbackInvoked)
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

  private final class ButtonOriginProbe {
    weak var view: NSView?
  }

  private final class CancelProbe {
    var cancelCallbackInvoked = false
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
        onCancelCSVImport: { probe.cancelCallbackInvoked = true }
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
    let showsStatus: Bool
    let probe: ButtonOriginProbe
    let width: CGFloat

    var body: some View {
      HStack(spacing: 12) {
        Text("Broker A")
          .font(.title3)
        Text("1/2")
        BulkEntryCSVHeaderStatusSlot {
          if showsStatus { BulkEntryCSVHeaderLoadingStatus(onCancel: {}) }
        }
        Button("Add Asset") {}
          .background(ButtonOriginMarker(probe: probe))
        Button("Import CSV") {}
      }
      .frame(width: width)
    }
  }
}
