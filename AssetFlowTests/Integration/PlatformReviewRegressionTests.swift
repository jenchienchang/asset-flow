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

@Suite("PlatformReviewRegression Tests")
@MainActor
struct PlatformReviewRegressionTests {
  @Test(
    "Rename preserves displayed positions through both editors and a save",
    arguments: [false, true])
  func renamePreservesImplicitOrder(viaDetail: Bool) throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let settings = SettingsService.createForTesting()
    let beta = try context.findOrCreateAsset(name: "Bond", platform: "Beta")
    let alpha = try context.findOrCreateAsset(name: "Stock", platform: "Alpha")
    let hidden = try #require(try PlatformService.resolve(name: "Aardvark", in: context))
    let platform = try #require(alpha.platformRecord)
    let betaPlatform = try #require(beta.platformRecord)
    #expect(platform.displayOrder == betaPlatform.displayOrder)
    let list = PlatformListViewModel(modelContext: context, settingsService: settings)
    list.loadPlatforms()
    let originalIDs = list.platformRows.map(\.id)
    #expect(list.platformRows.map(\.name) == ["Alpha", "Beta"])

    if viaDetail {
      let editor = PlatformDetailViewModel(
        platform: platform, modelContext: context, settingsService: settings)
      editor.editedName = "Zeta"
      try editor.save()
    } else {
      try list.renamePlatform(id: platform.id, to: "Zeta")
    }
    list.loadPlatforms()
    #expect(list.platformRows.map(\.id) == originalIDs)
    #expect(list.platformRows.map(\.name) == ["Zeta", "Beta"])
    // Loading establishes visible positions before rename freezes the remaining hidden record.
    #expect(hidden.displayOrder > betaPlatform.displayOrder)
    #expect(platform.displayOrder < betaPlatform.displayOrder)

    try context.save()
    let reopenedContext = ModelContext(container)
    let reopenedList = PlatformListViewModel(
      modelContext: reopenedContext, settingsService: settings)
    reopenedList.loadPlatforms()
    #expect(reopenedList.platformRows.map(\.id) == originalIDs)
    #expect(reopenedList.platformRows.map(\.name) == ["Zeta", "Beta"])
  }

  @Test("Rejected rename leaves implicit ordering untouched")
  func rejectedRenamePreservesOrder() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let alpha = try #require(try PlatformService.resolve(name: "Alpha", in: context))
    let beta = try #require(try PlatformService.resolve(name: "Beta", in: context))
    let originalOrders = [alpha.displayOrder, beta.displayOrder]
    #expect(throws: PlatformError.duplicateName("Beta")) {
      try PlatformService.rename(alpha, to: "Beta", in: context, settings: .createForTesting())
    }
    #expect([alpha.displayOrder, beta.displayOrder] == originalOrders)
    #expect(alpha.name == "Alpha")
  }

  @Test(
    "Repeated CSV platform spellings exclude omitted assets from copy-forward",
    arguments: ["Broker   One", "  bRoKeR   ONE  "])
  func repeatedCSVDoesNotCopyStaleValues(platformLabel: String) async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let settings = SettingsService.createForTesting()
    let sourceDate = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 1))!
    let targetDate = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 2))!
    let firstImport = ImportViewModel(modelContext: context, settingsService: settings)
    firstImport.snapshotDate = sourceDate
    await firstImport.loadCSVData(
      Data(
        """
        Asset Name,Market Value,Platform,Currency
        Held,100,Broker   One,USD
        Omitted,500,Broker   One,USD
        Other Cash,25,Other,USD
        """.utf8))
    let source = try #require(firstImport.executeImport())
    #expect(source.assetValues?.count == 3)
    #expect(source.assetValues?.first { $0.asset?.name == "Held" }?.asset?.platform == "Broker One")

    let nextImport = ImportViewModel(modelContext: context, settingsService: settings)
    nextImport.snapshotDate = targetDate
    await nextImport.loadCSVData(
      Data(
        """
        Asset Name,Market Value,Platform,Currency
        Held,120,\(platformLabel),USD
        """.utf8))
    #expect(nextImport.copyForwardEnabled)
    #expect(nextImport.copyForwardPlatforms.map(\.platformName) == ["Other"])

    let target = try #require(nextImport.executeImport())
    let values = target.assetValues ?? []
    #expect(Set(values.compactMap { $0.asset?.name }) == ["Held", "Other Cash"])
    #expect(values.reduce(Decimal(0)) { $0 + $1.marketValue } == 145)
    #expect(!values.contains { $0.asset?.name == "Omitted" })
    #expect(source.assetValues?.first { $0.asset?.name == "Omitted" }?.marketValue == 500)
  }
}
