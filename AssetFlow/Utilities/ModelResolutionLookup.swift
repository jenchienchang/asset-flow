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

enum ModelSelectionResolver {
  static func resolve<Model, ID: Equatable>(
    _ selected: Model?,
    among models: [Model],
    id: KeyPath<Model, ID>
  ) -> Model? {
    guard let selected else { return nil }
    let selectedID = selected[keyPath: id]
    return models.first { $0[keyPath: id] == selectedID }
  }
}

private struct AssetResolutionKey: Hashable {
  let name: String
  let platform: String

  init(name: String, platform: String) {
    self.name = name.normalizedForIdentity
    self.platform = platform.normalizedForIdentity
  }

  init(asset: Asset) {
    self.init(name: asset.name, platform: asset.platform)
  }
}

struct AssetResolutionLookup {
  private var assetsByIdentity: [AssetResolutionKey: Asset] = [:]

  init(assets: [Asset]) {
    for asset in assets {
      let key = AssetResolutionKey(asset: asset)
      if assetsByIdentity[key] == nil {
        assetsByIdentity[key] = asset
      }
    }
  }

  func asset(named name: String, platform: String) -> Asset? {
    assetsByIdentity[AssetResolutionKey(name: name, platform: platform)]
  }

  mutating func resolve(name: String, platform: String, in modelContext: ModelContext) -> Asset {
    let key = AssetResolutionKey(name: name, platform: platform)
    if let existing = assetsByIdentity[key] {
      return existing
    }

    let newAsset = Asset(name: name, platform: platform)
    modelContext.insert(newAsset)
    assetsByIdentity[key] = newAsset
    return newAsset
  }
}

struct CategoryResolutionLookup {
  private var categoriesByName: [String: Category] = [:]
  private var nextDisplayOrder: Int

  init(categories: [Category]) {
    var maxDisplayOrder = -1
    for category in categories {
      maxDisplayOrder = max(maxDisplayOrder, category.displayOrder)
      if let key = Self.key(for: category.name), categoriesByName[key] == nil {
        categoriesByName[key] = category
      }
    }
    nextDisplayOrder = maxDisplayOrder + 1
  }

  func category(named name: String) -> Category? {
    guard let key = Self.key(for: name) else { return nil }
    return categoriesByName[key]
  }

  mutating func resolve(name: String, in modelContext: ModelContext) -> Category? {
    guard let key = Self.key(for: name) else { return nil }
    if let existing = categoriesByName[key] {
      return existing
    }

    let newCategory = Category(name: name.trimmingCharacters(in: .whitespaces))
    newCategory.displayOrder = nextDisplayOrder
    nextDisplayOrder += 1
    modelContext.insert(newCategory)
    categoriesByName[key] = newCategory
    return newCategory
  }

  private static func key(for name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    return trimmed.lowercased()
  }
}

struct SnapshotAssetValueLookup {
  private var valuesByIdentity: [AssetResolutionKey: SnapshotAssetValue] = [:]
  private var valuesByAssetID: [UUID: SnapshotAssetValue] = [:]

  init(values: [SnapshotAssetValue]) {
    for value in values {
      register(value)
    }
  }

  func value(forAssetNamed name: String, platform: String) -> SnapshotAssetValue? {
    valuesByIdentity[AssetResolutionKey(name: name, platform: platform)]
  }

  func value(for asset: Asset) -> SnapshotAssetValue? {
    valuesByAssetID[asset.id]
  }

  mutating func register(_ value: SnapshotAssetValue) {
    guard let asset = value.asset else { return }

    let identityKey = AssetResolutionKey(asset: asset)
    if valuesByIdentity[identityKey] == nil {
      valuesByIdentity[identityKey] = value
    }
    if valuesByAssetID[asset.id] == nil {
      valuesByAssetID[asset.id] = value
    }
  }
}

struct CashFlowDescriptionLookup {
  private var descriptions: Set<String> = []

  init(operations: [CashFlowOperation]) {
    descriptions = Set(operations.map { Self.key(for: $0.cashFlowDescription) })
  }

  func contains(_ description: String) -> Bool {
    descriptions.contains(Self.key(for: description))
  }

  private static func key(for description: String) -> String {
    description.trimmingCharacters(in: .whitespaces).lowercased()
  }
}
