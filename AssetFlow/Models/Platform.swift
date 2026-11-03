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

@Model
final class Platform {
  #Unique<Platform>([\.normalizedName])
  private(set) var id: UUID
  private(set) var name: String
  private(set) var normalizedName: String
  var displayOrder: Int

  @Relationship(deleteRule: .deny, inverse: \Asset.platformRecord)
  private(set) var assets: [Asset]?

  init(id: UUID = UUID(), name: String, displayOrder: Int = 0) {
    self.id = id
    self.name = name.collapsingWhitespace
    normalizedName = name.normalizedForIdentity
    self.displayOrder = displayOrder
    assets = []
  }

  func rename(to name: String) {
    self.name = name.collapsingWhitespace
    normalizedName = name.normalizedForIdentity
  }
}
