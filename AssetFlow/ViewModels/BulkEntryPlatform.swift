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

/// Identity for saved platforms, unassigned assets, and not-yet-persisted names.
enum BulkEntryPlatform: Equatable, Identifiable {
  enum ID: Hashable {
    case persisted(UUID)
    case draft(UUID)
    case unassigned
  }

  case persisted(Platform)
  case draft(UUID, String)
  case unassigned

  static func draft(name: String) -> Self {
    name.normalizedForIdentity.isEmpty ? .unassigned : .draft(UUID(), name.collapsingWhitespace)
  }

  var id: ID {
    switch self {
    case .persisted(let platform): .persisted(platform.id)
    case .draft(let id, _): .draft(id)
    case .unassigned: .unassigned
    }
  }

  var platformID: UUID? {
    if case .persisted(let platform) = self { platform.id } else { nil }
  }

  var name: String {
    switch self {
    case .persisted(let platform): platform.name
    case .draft(_, let name): name
    case .unassigned: ""
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct BulkEntryPlatformGroup: Identifiable {
  let scope: BulkEntryPlatform
  let rows: [BulkEntryRow]
  var id: BulkEntryPlatform.ID { scope.id }
  /// Display projection; never a grouping or matching key.
  var platform: String { scope.name }
}

/// Resolves draft names against current records without mutating SwiftData.
struct BulkEntryPlatformLookup {
  private let platformsByID: [UUID: Platform]
  private let platformsByName: [String: Platform]
  private var draftsByName: [String: BulkEntryPlatform] = [:]

  init(platforms: [Platform]) {
    platformsByID = Dictionary(uniqueKeysWithValues: platforms.map { ($0.id, $0) })
    platformsByName = Dictionary(
      platforms.map { ($0.normalizedName, $0) }, uniquingKeysWith: { first, _ in first })
  }

  mutating func resolve(_ scope: BulkEntryPlatform) throws -> BulkEntryPlatform {
    switch scope {
    case .persisted(let record):
      guard let current = platformsByID[record.id] else { throw BulkEntryError.sourceDataChanged }
      return .persisted(current)

    case .unassigned:
      return .unassigned

    case .draft(_, let name):
      let key = name.normalizedForIdentity
      if let existing = platformsByName[key] { return .persisted(existing) }
      if let draft = draftsByName[key] { return draft }
      draftsByName[key] = scope
      return scope
    }
  }
}
