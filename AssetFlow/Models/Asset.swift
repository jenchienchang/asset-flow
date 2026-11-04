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
final class Asset {
  #Unique<Asset>([\.identityKey])

  var id: UUID
  private(set) var identityKey: String = ""
  private(set) var name: String
  @Relationship(deleteRule: .nullify)
  private(set) var platformRecord: Platform?

  /// Display/interchange projection; identity and membership use platformRecord.
  var platform: String { platformRecord?.name ?? "" }
  var currency: String

  @Relationship(deleteRule: .nullify)
  var category: Category?

  @Relationship(deleteRule: .deny, inverse: \SnapshotAssetValue.asset)
  var snapshotAssetValues: [SnapshotAssetValue]?

  init(
    name: String,
    platform: Platform? = nil
  ) {
    self.id = UUID()
    self.name = name
    self.platformRecord = platform
    self.identityKey = AssetIdentity.key(name: name, platformID: platform?.id)
    self.currency = ""
    self.category = nil
    self.snapshotAssetValues = []
  }

  /// Keep the uniqueness key synchronized with both mutable identity components.
  func updateIdentity(name: String, platform: Platform?) {
    self.name = name
    self.platformRecord = platform
    self.identityKey = AssetIdentity.key(name: name, platformID: platform?.id)
  }

  /// Normalized identity for case-insensitive matching.
  ///
  /// Applies the SPEC Section 6.1 normalization:
  /// 1. Trim leading and trailing whitespace
  /// 2. Collapse multiple consecutive spaces to a single space
  /// 3. Lowercased for case-insensitive comparison
  var normalizedName: String {
    name.normalizedForIdentity
  }

  /// Normalized platform for case-insensitive matching.
  var normalizedPlatform: String {
    platform.normalizedForIdentity
  }

  /// Combined normalized identity tuple for matching.
  var normalizedIdentity: String {
    "\(normalizedName)|\(normalizedPlatform)"
  }
}

/// A fixed UUID scope or an explicit nil scope makes arbitrary asset names unambiguous.
enum AssetIdentity {
  nonisolated static func key(name: String, platformID: UUID?) -> String {
    "\(platformID?.uuidString ?? "none"):\(name.normalizedForIdentity)"
  }
}
