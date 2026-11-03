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

@Suite("PlatformService Tests")
@MainActor
struct PlatformServiceTests {
  @Test("Resolution reuses canonical identity, including hidden empty platforms")
  func canonicalResolution() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let first = try PlatformService.resolve(name: " Broker   One ", in: context)
    let second = try PlatformService.resolve(name: "broker ONE", in: context)
    #expect(first === second)
    #expect(first?.name == "Broker One")
    #expect(try PlatformService.resolve(name: " \n ", in: context) == nil)
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 1)
  }

  @Test("Referenced platforms cannot be deleted, and empty platforms stay hidden")
  func lifecycle() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let platform = try #require(try PlatformService.resolve(name: "Broker", in: context))
    let asset = Asset(name: "Fund", platform: platform)
    context.insert(asset)
    try context.save()
    #expect(throws: PlatformError.hasAssets) { try PlatformService.delete(platform, in: context) }
    #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
    asset.updateIdentity(name: asset.name, platform: nil)
    let list = PlatformListViewModel(modelContext: context, settingsService: .createForTesting())
    list.loadPlatforms()
    #expect(list.platformRows.isEmpty)
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 1)
    #expect(try PlatformService.resolve(name: "BROKER", in: context)?.id == platform.id)
    try PlatformService.delete(platform, in: context)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<Platform>()) == 0)
  }

  @Test("Duplicate and blank renames leave models and preferences unchanged")
  func invalidRenameIsAtomic() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let first = try #require(try PlatformService.resolve(name: "Broker One", in: context))
    _ = try PlatformService.resolve(name: "Broker Two", in: context)
    let settings = SettingsService.createForTesting()
    settings.defaultPlatform = "Broker One"
    #expect(throws: PlatformError.duplicateName("BROKER TWO")) {
      try PlatformService.rename(first, to: " BROKER   TWO ", in: context, settings: settings)
    }
    #expect(throws: PlatformError.emptyName) {
      try PlatformService.rename(first, to: " ", in: context, settings: settings)
    }
    #expect(first.name == "Broker One")
    #expect(first.normalizedName == "broker one")
    #expect(settings.defaultPlatform == "Broker One")
  }

  @Test("Legacy name ordering migrates once and does not override later model ordering")
  func legacyOrderMigration() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let domain = "platform-migration-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(
      ["beta", " BETA ", "Alpha", "Gone"], forKey: Constants.UserDefaultsKeys.platformOrder)
    let settings = SettingsService.createForTesting(userDefaults: defaults)
    let alpha = try #require(try PlatformService.resolve(name: "Alpha", in: context))
    let beta = try #require(try PlatformService.resolve(name: "Beta", in: context))
    try PlatformService.migrateLegacyOrder(in: context, settings: settings)
    #expect(beta.displayOrder == 0)
    #expect(alpha.displayOrder == 1)
    #expect(settings.legacyPlatformOrder == nil)
    alpha.displayOrder = 0
    beta.displayOrder = 1
    try PlatformService.migrateLegacyOrder(in: context, settings: settings)
    #expect(alpha.displayOrder == 0)
  }

  @Test("Reordering visible platforms retains an empty platform's position when reused")
  func hiddenOrderIsRetained() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let platforms = try ["Alpha", "Beta", "Gamma"].map {
      try #require(try PlatformService.resolve(name: $0, in: context))
    }
    let assets = platforms.enumerated().map { index, platform in
      platform.displayOrder = index
      let asset = Asset(name: "Fund \(index)", platform: platform)
      context.insert(asset)
      return asset
    }
    assets[1].updateIdentity(name: assets[1].name, platform: nil)
    let list = PlatformListViewModel(modelContext: context, settingsService: .createForTesting())
    list.loadPlatforms()
    list.movePlatforms(from: IndexSet(integer: 0), to: 2)
    assets[1].updateIdentity(name: assets[1].name, platform: platforms[1])
    list.loadPlatforms()
    #expect(list.platformRows.map(\.name) == ["Gamma", "Beta", "Alpha"])
  }

  @Test("Assets without a platform retain database uniqueness")
  func nilPlatformUniqueness() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    context.insert(Asset(name: "Cash"))
    try context.save()
    context.insert(Asset(name: "Cash"))
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 1)
  }

  @Test("An open settings editor follows a renamed default platform")
  func settingsFollowsRename() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let platform = try #require(try PlatformService.resolve(name: "Broker", in: context))
    let settings = SettingsService.createForTesting()
    settings.defaultPlatform = "Broker"
    let editor = SettingsViewModel(
      settingsService: settings,
      authenticationService: AuthenticationService.createForTesting())
    try PlatformService.rename(platform, to: "Renamed", in: context, settings: settings)
    #expect(editor.defaultPlatformString == "Renamed")
  }

  @Test("Asset reassignment updates uniqueness and platform renames retain asset identity")
  func assetIdentityAfterReassignment() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let first = try context.findOrCreateAsset(name: "Fund", platform: "Alpha")
    let oldID = first.id
    let beta = try #require(try PlatformService.resolve(name: "Beta", in: context))
    first.updateIdentity(name: "Fund", platform: beta)
    let newAlphaAsset = try context.findOrCreateAsset(name: "Fund", platform: "Alpha")
    let matched = try context.findOrCreateAsset(name: " FUND ", platform: "beta")
    #expect(matched === first)
    #expect(newAlphaAsset.id != oldID)
    let key = first.identityKey
    try PlatformService.rename(beta, to: "Gamma", in: context, settings: .createForTesting())
    #expect(first.identityKey == key)
    #expect(try context.findOrCreateAsset(name: "Fund", platform: "Gamma") === first)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 2)
    #expect(first.id == oldID)
  }

  @Test("Existing platform selections follow identity while new-name drafts retain their text")
  func selectedInputsFollowRename() async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let asset = try context.findOrCreateAsset(name: "Fund", platform: "Broker")
    asset.currency = "USD"
    let platform = try #require(asset.platformRecord)
    let settings = SettingsService.createForTesting()
    let assetEditor = AssetDetailViewModel(asset: asset, modelContext: context)
    _ = try assetEditor.existingPlatforms()
    let importer = ImportViewModel(modelContext: context, settingsService: settings)
    importer.selectedPlatform = "Broker"
    await importer.loadCSVData(Data("Asset Name,Market Value,Currency\nFund,100,USD".utf8))
    try PlatformService.rename(platform, to: "Renamed", in: context, settings: settings)
    importer.refreshAfterStoreChange()
    _ = try assetEditor.existingPlatforms()
    #expect(importer.selectedPlatform == "Renamed")
    #expect(importer.assetPreviewRows.first?.csvRow.platform == "Renamed")
    #expect(assetEditor.editedPlatform == "Renamed")
    importer.selectedPlatform = "Future Broker"
    assetEditor.editedPlatform = "Future Broker"
    try PlatformService.rename(platform, to: "Again", in: context, settings: settings)
    importer.refreshAfterStoreChange()
    _ = try assetEditor.existingPlatforms()
    #expect(importer.selectedPlatform == "Future Broker")
    #expect(assetEditor.editedPlatform == "Future Broker")
  }

  @Test("An external rename updates a clean platform editor and preserves an edited draft")
  func editorRefresh() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let platform = try #require(try PlatformService.resolve(name: "Broker", in: context))
    let settings = SettingsService.createForTesting()
    let editor = PlatformDetailViewModel(
      platform: TestDataManager.platform(named: "Broker", in: context)!, modelContext: context,
      settingsService: settings)
    editor.loadData()
    try PlatformService.rename(platform, to: "Renamed", in: context, settings: settings)
    editor.loadData()
    #expect(editor.platformName == "Renamed")
    #expect(editor.editedName == "Renamed")
    editor.editedName = "My Draft"
    try PlatformService.rename(platform, to: "External", in: context, settings: settings)
    editor.reloadAfterStoreChange()
    #expect(editor.platformName == "External")
    #expect(editor.editedName == "My Draft")
  }
}
