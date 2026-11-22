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

@Suite("Asset Model Tests")
@MainActor
struct AssetModelTests {

  // MARK: - Creation and Properties

  @Test("Asset initializes with name and empty platform by default")
  func testInitializesWithNameAndEmptyPlatform() {
    let asset = Asset(name: "AAPL")
    #expect(asset.name == "AAPL")
    #expect(asset.platform == "")
    #expect(asset.category == nil)
  }

  @Test("Asset initializes with name and platform")
  func testInitializesWithNameAndPlatform() {
    let asset = Asset(name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: nil))
    #expect(asset.name == "AAPL")
    #expect(asset.platform == "Firstrade")
  }

  @Test("Asset persists in SwiftData context")
  func testPersistsInContext() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(
      name: "BTC", platform: TestDataManager.platform(named: "Binance", in: context))
    context.insert(asset)

    let descriptor = FetchDescriptor<Asset>()
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "BTC")
    #expect(fetched.first?.platform == "Binance")
  }

  // MARK: - Normalized Identity

  @Test("normalizedName trims whitespace")
  func testNormalizedNameTrimsWhitespace() {
    let asset = Asset(name: "  AAPL  ")
    #expect(asset.normalizedName == "aapl")
  }

  @Test("normalizedName collapses multiple spaces")
  func testNormalizedNameCollapsesSpaces() {
    let asset = Asset(name: "My   Stock   Name")
    #expect(asset.normalizedName == "my stock name")
  }

  @Test("normalizedName lowercases")
  func testNormalizedNameLowercases() {
    let asset = Asset(name: "AAPL")
    #expect(asset.normalizedName == "aapl")
  }

  @Test("normalizedPlatform trims and lowercases")
  func testNormalizedPlatformTrimsAndLowercases() {
    let asset = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "  Firstrade  ", in: nil))
    #expect(asset.normalizedPlatform == "firstrade")
  }

  @Test("normalizedPlatform collapses multiple spaces")
  func testNormalizedPlatformCollapsesSpaces() {
    let asset = Asset(
      name: "AAPL", platform: TestDataManager.platform(named: "My   Broker   App", in: nil))
    #expect(asset.normalizedPlatform == "my broker app")
  }

  @Test("normalizedIdentity combines name and platform")
  func testNormalizedIdentityCombinesNameAndPlatform() {
    let asset = Asset(name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: nil))
    #expect(asset.normalizedIdentity == "aapl|firstrade")
  }

  @Test("normalizedIdentity matches case-insensitively")
  func testNormalizedIdentityMatchesCaseInsensitively() {
    let a = Asset(name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: nil))
    let b = Asset(name: "aapl", platform: TestDataManager.platform(named: "firstrade", in: nil))
    #expect(a.normalizedIdentity == b.normalizedIdentity)
  }

  @Test("normalizedIdentity distinguishes different platforms")
  func testNormalizedIdentityDistinguishesPlatforms() {
    let a = Asset(name: "AAPL", platform: TestDataManager.platform(named: "Firstrade", in: nil))
    let b = Asset(name: "AAPL", platform: TestDataManager.platform(named: "Schwab", in: nil))
    #expect(a.normalizedIdentity != b.normalizedIdentity)
  }

  @Test("normalizedIdentity with empty platform")
  func testNormalizedIdentityWithEmptyPlatform() {
    let asset = Asset(name: "Gold")
    #expect(asset.normalizedIdentity == "gold|")
  }

  // MARK: - Category Relationship

  @Test("Asset can be assigned to a category")
  func testAssetCanBeAssignedToCategory() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let category = Category(name: "Stocks")
    let asset = Asset(name: "AAPL")
    context.insert(category)
    context.insert(asset)
    asset.category = category

    #expect(asset.category?.name == "Stocks")
    #expect(category.assets?.contains(where: { $0.name == "AAPL" }) == true)
  }

  @Test("Asset category can be set to nil")
  func testAssetCategoryCanBeSetToNil() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let category = Category(name: "Stocks")
    let asset = Asset(name: "AAPL")
    context.insert(category)
    context.insert(asset)
    asset.category = category
    asset.category = nil

    #expect(asset.category == nil)
  }

  // MARK: - Snapshot Asset Values Relationship

  @Test("Asset snapshotAssetValues starts empty")
  func testSnapshotAssetValuesStartsEmpty() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let asset = Asset(name: "AAPL")
    context.insert(asset)

    #expect(asset.snapshotAssetValues?.isEmpty ?? true)
  }
}
