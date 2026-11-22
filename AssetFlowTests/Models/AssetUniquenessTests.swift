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
import Testing

@testable import AssetFlow

@Suite("Asset Uniqueness Constraints")
@MainActor
struct AssetUniquenessTests {

  @Test("Asset enforces unique (name, platform) constraint at database level — duplicate upserts")
  func assetEnforcesDatabaseUniqueness() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    // Create first asset
    let asset1 = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Interactive Brokers", in: context))
    context.insert(asset1)
    try context.save()

    // Attempt duplicate (same name AND platform)
    let asset2 = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Interactive Brokers", in: context))
    context.insert(asset2)
    try context.save()

    // With #Unique constraint, should only have 1 asset (upsert behavior)
    let descriptor = FetchDescriptor<AssetFlow.Asset>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 1)
  }

  @Test("Asset allows same name on different platforms")
  func assetAllowsSameNameDifferentPlatform() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    // Same asset name, different platforms - should be allowed
    let asset1 = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Interactive Brokers", in: context))
    let asset2 = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Schwab", in: context))

    context.insert(asset1)
    context.insert(asset2)
    try context.save()

    // Both should exist as separate records
    let descriptor = FetchDescriptor<AssetFlow.Asset>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 2)

    // Verify they have different persistent IDs
    #expect(asset1.persistentModelID != asset2.persistentModelID)
  }
}
