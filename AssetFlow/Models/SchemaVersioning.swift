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

enum CurrentSchema {
  static var schema: Schema { Schema(versionedSchema: SchemaV4.self) }
}

enum SchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] {
    [
      Category.self,
      Asset.self,
      Snapshot.self,
      SnapshotAssetValue.self,
      CashFlowOperation.self,
      ExchangeRate.self,
    ]
  }
}

enum SchemaV2: VersionedSchema {
  static let versionIdentifier = Schema.Version(2, 0, 0)
  static var models: [any PersistentModel.Type] {
    [
      Category.self, Asset.self, Snapshot.self, SnapshotAssetValue.self, CashFlowOperation.self,
      ExchangeRate.self,
    ]
  }
}

enum SchemaV3: VersionedSchema {
  static let versionIdentifier = Schema.Version(3, 0, 0)
  static var models: [any PersistentModel.Type] {
    [
      Category.self, Asset.self, Snapshot.self, SnapshotAssetValue.self,
      CashFlowOperation.self, ExchangeRate.self, Platform.self,
    ]
  }
}

enum SchemaV4: VersionedSchema {
  static let versionIdentifier = Schema.Version(4, 0, 0)
  static var models: [any PersistentModel.Type] {
    [
      Category.self, Asset.self, Snapshot.self, SnapshotAssetValue.self,
      CashFlowOperation.self, ExchangeRate.self, Platform.self,
    ]
  }
}

enum AssetFlowMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
  }

  static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
      .custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self,
        willMigrate: { context in
          let assets = try context.fetch(FetchDescriptor<SchemaV2.Asset>())
          var identities: Set<[String]> = []
          for asset in assets {
            guard
              identities.insert([
                asset.name.normalizedForIdentity, asset.platform.normalizedForIdentity,
              ]).inserted
            else { throw PlatformMigrationError.duplicateAssetIdentity }
          }
        },
        didMigrate: { context in
          let assets = try context.fetch(FetchDescriptor<SchemaV3.Asset>())
          var platforms: [String: SchemaV3.Platform] = [:]
          let orderedAssets = assets.sorted {
            $0.platform.collapsingWhitespace < $1.platform.collapsingWhitespace
          }
          for asset in orderedAssets {
            let key = asset.platform.normalizedForIdentity
            guard !key.isEmpty else {
              asset.identityKey = AssetIdentity.key(name: asset.name, platformID: nil)
              continue
            }
            let platform: SchemaV3.Platform
            if let existing = platforms[key] {
              platform = existing
            } else {
              platform = SchemaV3.Platform(name: asset.platform, displayOrder: Int.max)
              context.insert(platform)
              platforms[key] = platform
            }
            asset.platformRecord = platform
            asset.identityKey = AssetIdentity.key(name: asset.name, platformID: platform.id)
          }
          try context.save()
        }),
      .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
    ]
  }
}

private enum PlatformMigrationError: LocalizedError {
  case duplicateAssetIdentity
  var errorDescription: String? {
    String(
      localized:
        "Existing assets have conflicting normalized identities. The store was not migrated.",
      table: "Platform")
  }
}
