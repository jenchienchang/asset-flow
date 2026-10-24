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

struct DelayedCSVLoadingIndicator<Content: View>: View {
  let isLoading: Bool
  let delay: Duration
  let content: Content
  @State private var visibility = DelayedCSVLoadingVisibility()

  init(
    isLoading: Bool,
    delay: Duration = .milliseconds(200),
    @ViewBuilder content: () -> Content
  ) {
    self.isLoading = isLoading
    self.delay = delay
    self.content = content()
  }

  var body: some View {
    Group {
      if isLoading && visibility.isVisible {
        content
      }
    }
    .task(id: isLoading) {
      await visibility.update(isLoading: isLoading) {
        try await Task.sleep(for: delay)
      }
    }
  }
}

@MainActor
@Observable
final class DelayedCSVLoadingVisibility {
  private(set) var isVisible = false
  @ObservationIgnored private var generation = 0

  func update(
    isLoading: Bool,
    afterDelay: @MainActor () async throws -> Void
  ) async {
    generation &+= 1
    let currentGeneration = generation
    isVisible = false
    guard isLoading else { return }

    do {
      try await afterDelay()
    } catch {
      return
    }
    guard !Task.isCancelled, generation == currentGeneration else { return }
    isVisible = true
  }
}
