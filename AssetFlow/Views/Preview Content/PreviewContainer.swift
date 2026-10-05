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

/// A container for providing a `ModelContainer` for SwiftUI previews.
class PreviewContainer {
  /// A shared, in-memory `ModelContainer` for SwiftUI previews.
  static let container: ModelContainer = {
    do {
      let schema = CurrentSchema.schema
      let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      return container
    } catch {
      fatalError("Failed to create in-memory model container for previews: \(error)")
    }
  }()
}
