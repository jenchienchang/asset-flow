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

/// Owns canonical platform resolution and validated mutations.
@MainActor
enum PlatformService {
  static func resolve(
    name: String, in context: ModelContext, fetcher: (any ModelFetching)? = nil
  ) throws -> Platform? {
    let key = name.normalizedForIdentity
    guard !key.isEmpty else { return nil }
    var descriptor = FetchDescriptor<Platform>(predicate: #Predicate { $0.normalizedName == key })
    descriptor.fetchLimit = 1
    let platforms = try fetchModels(
      descriptor, from: fetcher ?? ModelContextFetcher(modelContext: context),
      operation: "resolve platform")
    var lookup = PlatformResolutionLookup(platforms: platforms)
    return lookup.resolve(name: name, in: context)
  }

  /// Establishes positions for newly visible platforms, retaining hidden established positions.
  /// Routine model edits rely on the owning context's autosave.
  static func reconcileDisplayOrder(_ platforms: [Platform]) {
    let additions = orderedForDisplay(
      platforms.filter { $0.displayOrder == Int.max && !($0.assets ?? []).isEmpty })
    guard !additions.isEmpty else { return }

    let established = orderedForDisplay(platforms.filter { $0.displayOrder != Int.max })
    let nextOrder: Int
    if let last = established.last, last.displayOrder >= Int.max - additions.count {
      // Reserve Int.max for unresolved positions. Compact only when appending would exhaust them.
      for (index, platform) in established.enumerated() where platform.displayOrder != index {
        platform.displayOrder = index
      }
      nextOrder = established.count
    } else {
      nextOrder = (established.last?.displayOrder ?? -1) + 1
    }
    for (index, platform) in additions.enumerated() {
      platform.displayOrder = nextOrder + index
    }
  }

  static func orderedForDisplay(_ platforms: [Platform]) -> [Platform] {
    platforms.sorted {
      $0.displayOrder == $1.displayOrder
        ? $0.normalizedName < $1.normalizedName : $0.displayOrder < $1.displayOrder
    }
  }

  static func rename(
    _ platform: Platform, to name: String, in context: ModelContext,
    settings: SettingsService
  ) throws {
    let trimmed = name.collapsingWhitespace
    guard !trimmed.isEmpty else { throw PlatformError.emptyName }
    let platforms = try context.fetch(FetchDescriptor<Platform>())
    guard
      !platforms.contains(where: {
        $0.id != platform.id && $0.normalizedName == trimmed.normalizedForIdentity
      })
    else { throw PlatformError.duplicateName(trimmed) }
    // Freeze the current order before changing a name that may break an ordering tie.
    // Include hidden platforms so reusing them retains their relative position.
    for (index, item) in orderedForDisplay(platforms).enumerated() {
      item.displayOrder = index
    }
    let followsDefault = settings.defaultPlatform.normalizedForIdentity == platform.normalizedName
    platform.rename(to: trimmed)
    if followsDefault { settings.defaultPlatform = trimmed }
  }

  static func delete(_ platform: Platform, in context: ModelContext) throws {
    guard (platform.assets ?? []).isEmpty else { throw PlatformError.hasAssets }
    context.delete(platform)
  }

  /// Moves the old name-based preference into model storage once, after migration succeeds.
  static func migrateLegacyOrder(in context: ModelContext, settings: SettingsService) throws {
    guard let names = settings.legacyPlatformOrder else { return }
    let platforms = try context.fetch(FetchDescriptor<Platform>())
    let order = Dictionary(
      names.enumerated().map { ($1.normalizedForIdentity, $0) }, uniquingKeysWith: min)
    let sorted = platforms.sorted {
      let left = order[$0.normalizedName] ?? Int.max
      let right = order[$1.normalizedName] ?? Int.max
      return left == right ? $0.normalizedName < $1.normalizedName : left < right
    }
    for (index, platform) in sorted.enumerated() { platform.displayOrder = index }
    try context.save()
    settings.clearLegacyPlatformOrder()
  }
}
