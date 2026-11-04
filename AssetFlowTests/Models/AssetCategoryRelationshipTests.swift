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

@Suite("Asset Category Relationship Delete Rules")
@MainActor
struct AssetCategoryRelationshipTests {

  @Test("Deleting a category nullifies asset.category references")
  func deletingCategoryNullifiesAssetReferences() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    // Create category and asset
    let equities = Category(name: "Equities", targetAllocationPercentage: Decimal(60))
    let apple = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Interactive Brokers", in: context))
    apple.category = equities

    context.insert(equities)
    context.insert(apple)
    try context.save()

    // Verify relationship established
    #expect(apple.category?.name == "Equities")

    // Delete the category
    context.delete(equities)
    try context.save()

    // Verify: Asset still exists, but category is nil (nullify behavior)
    #expect(apple.category == nil)

    // Verify asset wasn't cascade-deleted
    let assets = try context.fetch(FetchDescriptor<AssetFlow.Asset>())
    #expect(assets.count == 1)
    #expect(assets.first?.name == "AAPL")
  }

  @Test("Deleting an asset does not delete the category")
  func deletingAssetDoesNotDeleteCategory() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let equities = Category(name: "Equities", targetAllocationPercentage: Decimal(60))
    let apple = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "Interactive Brokers", in: context))
    apple.category = equities

    context.insert(equities)
    context.insert(apple)
    try context.save()

    // Delete the asset
    context.delete(apple)
    try context.save()

    // Verify: Category still exists (not cascade-deleted)
    let categories = try context.fetch(FetchDescriptor<AssetFlow.Category>())
    #expect(categories.count == 1)
    #expect(categories.first?.name == "Equities")
  }
}
