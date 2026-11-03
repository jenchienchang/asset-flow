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

/// An existing selection follows its model; a new-name draft remains editable text.
enum PlatformSelection {
  case none
  case existing(Platform)
  case newName(String)

  init(name: String, platforms: [Platform]) {
    let key = name.normalizedForIdentity
    if key.isEmpty {
      self = .none
    } else if let platform = platforms.first(where: { $0.normalizedName == key }) {
      self = .existing(platform)
    } else {
      self = .newName(name)
    }
  }

  var name: String {
    switch self {
    case .none: ""
    case .existing(let platform): platform.name
    case .newName(let name): name
    }
  }

  func refreshed(with platforms: [Platform]) -> PlatformSelection {
    switch self {
    case .none: .none

    case .existing(let platform):
      platforms.first(where: { $0.id == platform.id }).map(Self.existing) ?? .none

    case .newName(let name):
      Self(name: name, platforms: platforms)
    }
  }
}

/// Picker actions cannot collide with an arbitrary platform name.
enum PlatformPickerOption: Hashable {
  case none
  case name(String)
  case create
}
