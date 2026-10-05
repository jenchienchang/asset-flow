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

import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import AssetFlow

@Suite("CategoryGoalPreview Tests", .serialized)
@MainActor
struct CategoryGoalPreviewTests {
  @Test("Goal screens render with sample data in wide, narrow and localized layouts")
  func renderSamples() async throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let reserve = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 10)
    reserve.minimumBalanceAmount = 300000
    reserve.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    let equity = AssetFlow.Category(name: "Equities", targetAllocationPercentage: 60)
    let bonds = AssetFlow.Category(name: "Bonds", targetAllocationPercentage: 30)
    let snapshot = Snapshot(date: Date())
    for model: any PersistentModel in [reserve, equity, bonds, snapshot] { context.insert(model) }
    for (category, amount) in [
      (reserve, Decimal(200000)), (equity, Decimal(600000)), (bonds, Decimal(200000)),
    ] {
      let asset = Asset(name: category.name + " account", platform: "Sample Bank")
      asset.category = category
      let value = SnapshotAssetValue(marketValue: amount)
      value.asset = asset
      value.snapshot = snapshot
      context.insert(asset)
      context.insert(value)
    }
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "assetflow-goal-previews")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for language in ["en", "zh-Hant"] {
      let root = RebalancingView(modelContext: context).modelContainer(container).environment(
        \.locale, Locale(identifier: language))
      try await render(
        root, width: 1100, height: 720, to: directory.appending(path: "rebalancing-\(language).png")
      )
      let detail = CategoryDetailView(category: reserve, modelContext: context, onDelete: {})
        .modelContainer(container).environment(\.locale, Locale(identifier: language))
      try await render(
        detail, width: 620, height: 900, to: directory.appending(path: "category-\(language).png"))
      try await render(
        detail, width: 380, height: 900,
        to: directory.appending(path: "category-narrow-\(language).png"))
      try await render(
        root, width: 900, height: 720,
        to: directory.appending(path: "rebalancing-narrow-\(language).png"))
      let list = CategoryListView(modelContext: context, selectedCategory: .constant(nil))
        .modelContainer(container).environment(\.locale, Locale(identifier: language))
      try await render(
        list, width: 380, height: 600,
        to: directory.appending(path: "category-list-\(language).png"))

      let assessment = CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: [reserve, equity, bonds],
        displayCurrency: SettingsService.shared.mainCurrency)
      let input = RebalancingCategoryHelpInput(
        name: "Reserve", current: 200000, percentage: 10, minimum: 300000,
        minimumCurrency: SettingsService.shared.mainCurrency, convertedMinimum: 300000,
        status: .shortfall(100000),
        target: 300000, difference: 100000, share: 30, minimumIsBinding: true)
      let helpSamples: [(String, RebalancingHelpContent)] = [
        (
          "calculation-help",
          RebalancingHelpPresentation.calculation(
            assessment: assessment, currency: SettingsService.shared.mainCurrency)
        ),
        (
          "category-help",
          RebalancingHelpPresentation.category(
            input, diagnostic: nil, currency: SettingsService.shared.mainCurrency,
            assessment: assessment)
        ),
        (
          "minimum-help",
          RebalancingHelpPresentation.minimum(
            input, currency: SettingsService.shared.mainCurrency, snapshotDate: snapshot.date,
            unavailableReason: nil)
        ),
      ]
      for (name, content) in helpSamples {
        let help = RebalancingHelpView(content: content).font(.callout).padding(16)
          .fixedSize(horizontal: true, vertical: true).environment(
            \.locale, Locale(identifier: language))
        let helpSize = NSHostingView(rootView: help).fittingSize
        #expect(helpSize.width > 0 && helpSize.height > 0)
        try await render(
          help, width: ceil(helpSize.width), height: ceil(helpSize.height),
          to: directory.appending(path: "\(name)-\(language).png"))
        let constrained = RebalancingHelpView(content: content, maximumWidth: 288).font(.callout)
          .padding(16)
          .fixedSize(horizontal: true, vertical: true).environment(
            \.locale, Locale(identifier: language))
        let constrainedSize = NSHostingView(rootView: constrained).fittingSize
        #expect(constrainedSize.width <= 320)
        try await render(
          constrained, width: ceil(constrainedSize.width), height: ceil(constrainedSize.height),
          to: directory.appending(path: "\(name)-narrow-\(language).png"))
      }

    }
    reserve.minimumBalanceAmount = 1_100_000
    try await render(
      RebalancingView(modelContext: context).modelContainer(container), width: 900, height: 720,
      to: directory.appending(path: "infeasible.png"))
  }

  private func render<V: View>(_ root: V, width: CGFloat, height: CGFloat, to url: URL) async throws
  {
    let hosting = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(
      contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    defer { window.contentView = nil }
    hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(250))
    hosting.layoutSubtreeIfNeeded()
    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    #expect(png.count > 1000)
    try png.write(to: url)
  }
}
