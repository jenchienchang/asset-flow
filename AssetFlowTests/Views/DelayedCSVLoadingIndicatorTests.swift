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
import Testing

@testable import AssetFlow

@Suite("Delayed CSV Loading Indicator Tests")
@MainActor
struct DelayedCSVLoadingIndicatorTests {
  @Test("A quick CSV load never inserts a loading row")
  func quickLoadDoesNotFlash() async {
    let host = NSHostingView(rootView: indicator(isLoading: true))
    let window = windowForHost(host)
    defer { window.close() }

    #expect(host.fittingSize.height == 0)
    try? await Task.sleep(for: .milliseconds(50))
    host.rootView = indicator(isLoading: false)
    try? await Task.sleep(for: .milliseconds(300))
    #expect(host.fittingSize.height == 0)
  }

  @Test("A longer CSV load shows progress after the delay")
  func longLoadShowsProgress() async {
    let host = NSHostingView(rootView: indicator(isLoading: false))
    let window = windowForHost(host)
    defer { window.close() }

    #expect(host.fittingSize.height == 0)
    host.rootView = indicator(isLoading: true)
    #expect(await waitForHeight(30, in: host))
    host.rootView = indicator(isLoading: false)
    #expect(await waitForHeight(0, in: host))
  }

  private func waitForHeight<Content: View>(
    _ expectedHeight: CGFloat,
    in host: NSHostingView<Content>
  ) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while ContinuousClock.now < deadline {
      host.layoutSubtreeIfNeeded()
      if host.fittingSize.height == expectedHeight { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return false
  }

  private func indicator(isLoading: Bool) -> some View {
    DelayedCSVLoadingIndicator(isLoading: isLoading, delay: .milliseconds(200)) {
      Color.clear.frame(width: 100, height: 30)
    }
  }

  private func windowForHost<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    return window
  }
}
