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

@Suite("Bulk Entry CSV Loading Tracker Tests")
@MainActor
struct BulkEntryCSVLoadingTrackerTests {
  @Test("An asset import activates only its platform header")
  func assetImportTargetsOnePlatform() {
    var tracker = BulkEntryCSVLoadingTracker()
    let operationID = tracker.begin(.asset(platform: "Broker A"))

    #expect(tracker.isActive(for: .asset(platform: "Broker A")))
    #expect(!tracker.isActive(for: .asset(platform: "Broker B")))
    #expect(!tracker.isActive(for: .cashFlow))

    tracker.finish(operationID)
    #expect(tracker.activeTarget == nil)
  }

  @Test("A cash flow import activates only the cash flow header")
  func cashFlowImportTargetsCashFlowHeader() {
    var tracker = BulkEntryCSVLoadingTracker()
    let operationID = tracker.begin(.cashFlow)

    #expect(tracker.isActive(for: .cashFlow))
    #expect(!tracker.isActive(for: .asset(platform: "Broker A")))

    tracker.finish(operationID)
    #expect(!tracker.isActive(for: .cashFlow))
  }

  @Test("A cancelled task cannot hide a newer import's indicator")
  func oldCompletionDoesNotClearNewTarget() {
    var tracker = BulkEntryCSVLoadingTracker()
    let oldID = tracker.begin(.asset(platform: "Broker A"))
    let newID = tracker.begin(.cashFlow)

    tracker.finish(oldID)
    #expect(tracker.isActive(for: .cashFlow))

    tracker.finish(newID)
    #expect(tracker.activeTarget == nil)
  }
}
