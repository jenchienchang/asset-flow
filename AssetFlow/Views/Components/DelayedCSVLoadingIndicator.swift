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
  @State private var isVisible = false

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
      if isLoading && isVisible {
        content
      }
    }
    .task(id: isLoading) {
      guard isLoading else {
        isVisible = false
        return
      }
      isVisible = false
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      isVisible = true
    }
  }
}
