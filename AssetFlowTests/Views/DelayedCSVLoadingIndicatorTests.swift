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

import Testing

@testable import AssetFlow

@Suite("Delayed CSV Loading Indicator Tests")
@MainActor
struct DelayedCSVLoadingIndicatorTests {
  @Test("A quick CSV load keeps delayed progress hidden")
  func quickLoadDoesNotFlash() async {
    let visibility = DelayedCSVLoadingVisibility()
    let delay = DelayGate()
    let loading = Task {
      await visibility.update(isLoading: true) {
        await delay.wait()
      }
    }

    await delay.waitUntilStarted()
    #expect(!visibility.isVisible)
    loading.cancel()
    await visibility.update(isLoading: false) {}
    delay.release()
    await loading.value
    #expect(!visibility.isVisible)
  }

  @Test("A longer CSV load reveals progress after the delay")
  func longLoadShowsProgress() async {
    let visibility = DelayedCSVLoadingVisibility()
    let delay = DelayGate()
    let loading = Task {
      await visibility.update(isLoading: true) {
        await delay.wait()
      }
    }

    await delay.waitUntilStarted()
    #expect(!visibility.isVisible)
    delay.release()
    await loading.value
    #expect(visibility.isVisible)
    await visibility.update(isLoading: false) {}
    #expect(!visibility.isVisible)
  }

  @MainActor
  private final class DelayGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
      await withCheckedContinuation { continuation in
        waiting = continuation
        started?.resume()
        started = nil
      }
    }

    func waitUntilStarted() async {
      if waiting != nil { return }
      await withCheckedContinuation { continuation in
        started = continuation
      }
    }

    func release() {
      waiting?.resume()
      waiting = nil
    }
  }
}
