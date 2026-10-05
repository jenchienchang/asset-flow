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
import Testing

@testable import AssetFlow

@Suite("ObservedRefresh Tests")
@MainActor
struct ObservedRefreshTests {
  @Observable final class Source { var value = 0 }
  private func settle() async { for _ in 0..<100 { await Task.yield() } }

  @Test("Requests coalesce while retaining the latest source value")
  func coalescing() async {
    let source = Source()
    let refresh = ObservedRefresh()
    var loads = 0
    var displayed = -1
    let reload: @MainActor () -> Void = {
      loads += 1
      refresh.perform {
        let value = source.value
        refresh.publish { displayed = value }
      } reload: {
      }
    }
    refresh.request(reload: reload)
    source.value = 1
    refresh.request(reload: reload)
    source.value = 2
    refresh.request(reload: reload)
    await settle()
    #expect(loads == 1)
    #expect(displayed == 2)
  }

  @Test("An explicit refresh supersedes queued work without suppressing later source changes")
  func generations() async {
    let source = Source()
    let refresh = ObservedRefresh()
    var loads = 0
    func load() {
      loads += 1
      refresh.perform {
        let value = source.value
        refresh.publish { _ = value }
      } reload: {
        load()
      }
    }
    load()
    refresh.request { load() }
    source.value = 1
    load()
    await settle()
    #expect(loads == 2)
    source.value = 2
    source.value = 3
    await settle()
    #expect(loads == 3)
  }

  @Test("Derived output reads during publication never become source dependencies")
  func publication() async {
    let source = Source()
    let output = Source()
    let refresh = ObservedRefresh()
    var loads = 0
    func load() {
      loads += 1
      refresh.perform {
        let value = source.value
        refresh.publish { output.value = value + output.value }
      } reload: {
        load()
      }
    }
    load()
    output.value = 10
    await settle()
    #expect(loads == 1)
    source.value = 2
    await settle()
    #expect(loads == 2)
    #expect(output.value == 12)
  }

  @Test("A source mutation during publication triggers a follow-up refresh")
  func duringPublication() async {
    let source = Source()
    let refresh = ObservedRefresh()
    var displayed = -1
    var loads = 0
    func load() {
      loads += 1
      refresh.perform {
        let value = source.value
        refresh.publish {
          displayed = value
          if value == 0 { source.value = 1 }
        }
      } reload: {
        load()
      }
    }
    load()
    await settle()
    #expect(loads == 2)
    #expect(displayed == 1)
  }
}
