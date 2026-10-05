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

import Foundation
import Observation

/// Tracks source reads, then publishes derived state outside observation tracking.
/// Explicit refreshes supersede queued callbacks without losing subsequent changes.
@MainActor
final class ObservedRefresh {
  private(set) var isComputing = false
  private var generation: UInt64 = 0
  private var pending: Task<Void, Never>?
  private var publications: [() -> Void] = []

  func perform(_ compute: () -> Void, reload: @escaping @MainActor () -> Void) {
    pending?.cancel()
    pending = nil
    generation &+= 1
    let current = generation
    publications = []
    isComputing = true
    withObservationTracking {
      compute()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, self.generation == current else { return }
        self.request(reload: reload)
      }
    }
    isComputing = false
    let updates = publications
    publications = []
    for update in updates { update() }
  }

  func request(reload: @escaping @MainActor () -> Void) {
    guard pending == nil else { return }
    let current = generation
    pending = Task { @MainActor [weak self] in
      guard let self, !Task.isCancelled, self.generation == current else { return }
      self.pending = nil
      reload()
    }
  }

  /// Values passed to this closure must be calculated before calling publish.
  func publish(_ update: @escaping () -> Void) {
    publications.append(update)
  }
}
