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
import SwiftData

@testable import AssetFlow

@MainActor
class TestDataManager {
  /// Creates a new, empty, in-memory `ModelContainer` for testing.
  ///
  /// Each call to this function returns a brand new container, ensuring that
  /// tests do not interfere with each other.
  ///
  /// - Returns: A new `ModelContainer` configured for in-memory storage.
  static func createInMemoryContainer() -> ModelContainer {
    let schema = CurrentSchema.schema
    // Use a unique name per container to ensure true isolation.
    // Without a unique name, ModelConfiguration(isStoredInMemoryOnly: true) may
    // share the same backing store across calls, causing test interference.
    let configuration = ModelConfiguration(
      UUID().uuidString,
      schema: schema,
      isStoredInMemoryOnly: true
    )

    do {
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return container
    } catch {
      fatalError("Failed to create in-memory model container: \(error)")
    }
  }
}
