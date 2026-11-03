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

/// Error types for platform operations.
enum PlatformError: LocalizedError, Equatable {
  case notFound
  case hasAssets
  case emptyName
  case duplicateName(String)

  var errorDescription: String? {
    switch self {
    case .notFound:
      return String(localized: "This platform no longer exists.", table: "Platform")

    case .hasAssets:
      return String(
        localized: "Move or delete the platform's assets before deleting it.", table: "Platform")

    case .emptyName:
      return String(
        localized: "Platform name cannot be empty.",
        table: "Platform")

    case .duplicateName(let name):
      return String(
        localized: "A platform named '\(name)' already exists.",
        table: "Platform")
    }
  }
}
