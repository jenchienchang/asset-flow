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

@Suite("Bulk Entry CSV Header Loading Slot Tests")
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

  @Test(
    "CSV status stays enabled when a stale draft disables header editing actions",
    arguments: [false, true])
  func headerStatusRemainsEnabled(isSourceDataStale: Bool) {
    let statusProbe = EnabledProbe()
    let addProbe = EnabledProbe()
    let importProbe = EnabledProbe()
    let host = NSHostingView(
      rootView: HStack {
        BulkEntryCSVHeaderControls(isSourceDataStale: isSourceDataStale) {
          BulkEntryCSVHeaderLoadingSlot(isLoading: false, onCancel: {})
            .background(EnabledMarker(probe: statusProbe))
        } actions: {
          Button("Add Asset") {}
            .background(EnabledMarker(probe: addProbe))
          Button("Import CSV") {}
            .background(EnabledMarker(probe: importProbe))
        }
      })
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 100)
    _ = host.fittingSize
    host.layoutSubtreeIfNeeded()

    #expect(statusProbe.isEnabled == true)
    #expect(addProbe.isEnabled == !isSourceDataStale)
    #expect(importProbe.isEnabled == !isSourceDataStale)
  }

  private final class ButtonOriginProbe {
    weak var view: NSView?
  }

  private final class EnabledProbe {
    var isEnabled: Bool?
  }

  private struct EnabledMarker: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let probe: EnabledProbe

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
      probe.isEnabled = isEnabled
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
        BulkEntryCSVHeaderControls(isSourceDataStale: false) {
          BulkEntryCSVHeaderStatusSlot {
            if showsStatus { BulkEntryCSVHeaderLoadingStatus(onCancel: {}) }
          }
        } actions: {
          Button("Add Asset") {}
            .background(ButtonOriginMarker(probe: probe))
          Button("Import CSV") {}
        }
      }
      .frame(width: width)
    }
  }
}

@Suite("Bulk Entry CSV File Import Presentation Tests")
@MainActor
struct BulkEntryCSVFileImportPresentationTests {
  @Test("Canceling the file picker allows asset and cash flow requests to reopen it")
  func cancelAllowsReopening() {
    var presentation = BulkEntryCSVFileImportPresentation()

    presentation.request(.asset(platform: "Broker A"))
    #expect(presentation.isPresented)
    #expect(presentation.target == .asset(platform: "Broker A"))

    presentation.isPresented = false  // SwiftUI dismisses before the cancellation callback.
    presentation.cancel()
    #expect(!presentation.isPresented)
    #expect(presentation.target == nil)

    presentation.request(.asset(platform: "Broker A"))
    #expect(presentation.isPresented)
    #expect(presentation.target == .asset(platform: "Broker A"))

    presentation.isPresented = false
    presentation.cancel()
    presentation.request(.cashFlow)
    #expect(presentation.isPresented)
    #expect(presentation.target == .cashFlow)
  }

  @Test("Successful selection retains the target until the completion callback")
  func completionAfterDismissalRetainsTarget() {
    var presentation = BulkEntryCSVFileImportPresentation()
    presentation.request(.cashFlow)

    presentation.isPresented = false  // SwiftUI dismisses before onCompletion.
    #expect(presentation.complete() == .cashFlow)
    #expect(!presentation.isPresented)
    #expect(presentation.target == nil)

    presentation.request(.asset(platform: "Broker B"))
    #expect(presentation.isPresented)
    #expect(presentation.complete() == .asset(platform: "Broker B"))
  }
}
