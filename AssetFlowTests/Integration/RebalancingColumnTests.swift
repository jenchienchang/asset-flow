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

@Suite("RebalancingColumn Tests")
@MainActor
struct RebalancingColumnTests {
  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  @Test("Columns group current holdings, effective targets, actions, then configured goals")
  func columnOrder() throws {
    let source = try String(
      contentsOf: root.appending(path: "AssetFlow/Views/RebalancingView.swift"), encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"TableColumn\("([^"]+)"\)"#)
    let range = NSRange(source.startIndex..., in: source)
    let columns = regex.matches(in: source, range: range).compactMap {
      Range($0.range(at: 1), in: source).map { String(source[$0]) }
    }
    #expect(
      columns == [
        "Category", "Current balance", "Current %", "Effective target balance",
        "Effective target %", "Change", "Action", "Minimum",
      ])
    #expect(source.contains("row.effectivePercentage.map { $0.formattedPercentage() } ?? \"—\""))
    #expect(
      source.contains(
        "Effective targets are shares of the whole portfolio. Minimum-only categories retain any balance above their minimum."
      ))
  }

  @Test("Keep uses the neutral filled minus icon with its localized text")
  func keepIcon() throws {
    let source = try String(
      contentsOf: root.appending(path: "AssetFlow/Views/RebalancingView.swift"), encoding: .utf8)
    #expect(
      source.contains(
        #"Label("Protected", systemImage: "minus.circle.fill").foregroundStyle(.secondary)"#))
    #expect(!source.contains(#"Text("Protected").foregroundStyle(.secondary)"#))
    #expect(NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil) != nil)
  }

  @Test("New target headings have Traditional Chinese translations")
  func translations() throws {
    let data = try Data(
      contentsOf: root.appending(path: "AssetFlow/Resources/Localizable.xcstrings"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(json["strings"] as? [String: Any])
    for key in [
      "Effective target balance",
      "Effective target %",
      "(A) Portfolio total",
      "(B) Protected amount",
      "(C) Available for percentage targets",
      "(D) Targets fixed at minimums",
      "(E) Remaining allocation amount",
      "Protect uncategorized holdings and categories without percentage targets. Minimum-only categories retain the greater of their balance and minimum.",
      "Distribute the available amount using configured percentage weights.",
      "Fix targets that would fall below their minimums at those minimums, then redistribute the remainder proportionally. Repeat when necessary.",
      "Effective target % = effective target balance ÷ portfolio total × 100.",
      "Without a percentage target, retain the greater of the current balance and minimum.",
      "(A) Current balance",
      "(B) Minimum in display currency",
      "(C) Effective target balance",
      "(D) Portfolio total",
      "(A) Minimum in display currency",
      "(B) Portfolio total",
      "A 0% target assigns only the minimum balance, or zero when no minimum is set.",
      "(A) Configured target %",
      "(B) Effective target balance",
      "(C) Portfolio total",
      "The remaining allocation amount is shared proportionally after targets fixed at minimums have been accounted for.",
      "(B) Remaining allocation amount",
      "(C) Combined configured target % of remaining categories",
      "(D) Effective target balance",
      "(E) Portfolio total",
      "Effective target % is unavailable because the portfolio total is zero.",
      "Target calculation",
    ] {
      let entry = try #require(strings[key] as? [String: Any])
      let locales = try #require(entry["localizations"] as? [String: Any])
      let chinese = try #require(locales["zh-Hant"] as? [String: Any])
      let unit = try #require(chinese["stringUnit"] as? [String: String])
      #expect(unit["state"] == "translated")
      #expect(unit["value"]?.isEmpty == false)
    }
  }

  @Test("Minimum-only effective percentages use total holdings including protected balances")
  func effectiveShare() throws {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = Snapshot(date: Date())
    context.insert(snapshot)
    let reserve = AssetFlow.Category(name: "Reserve")
    reserve.minimumBalanceAmount = 50
    reserve.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    let donor = AssetFlow.Category(name: "Investments", targetAllocationPercentage: 100)
    let protected = AssetFlow.Category(name: "Protected")
    for category in [reserve, donor, protected] { context.insert(category) }
    for (category, amount): (AssetFlow.Category?, Decimal) in [
      (reserve, 40), (donor, 60), (protected, 100), (nil, 200),
    ] {
      let asset = Asset(name: UUID().uuidString)
      asset.category = category
      let value = SnapshotAssetValue(marketValue: amount)
      value.asset = asset
      value.snapshot = snapshot
      context.insert(asset)
      context.insert(value)
    }
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    #expect(vm.totalPortfolioValue == 400)
    #expect(
      vm.suggestions.first { $0.categoryID == reserve.id }?.effectivePercentage
        == Decimal(string: "12.5"))
    #expect(!vm.suggestions.contains { $0.categoryID == protected.id })
    reserve.minimumBalanceAmount = 500
    vm.loadRebalancing()
    #expect(vm.suggestions.isEmpty)
    _ = container.mainContext
  }
  @Test("Zero-total and unavailable plans never supply an effective share")
  func unavailableShares() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let category = AssetFlow.Category(name: "Reserve", targetAllocationPercentage: 100)
    context.insert(category)
    let vm = RebalancingViewModel(modelContext: context)
    vm.loadRebalancing()
    #expect(vm.suggestions.isEmpty)
    context.insert(Snapshot(date: Date()))
    vm.loadRebalancing()
    #expect(vm.goalAssessment.plan?.status == .feasible)
    #expect(vm.suggestions.count == 1)
    #expect(vm.suggestions.first?.effectivePercentage == nil)
    category.minimumBalanceAmount = 5
    category.minimumBalanceCurrency = SettingsService.shared.mainCurrency
    vm.loadRebalancing()
    #expect(vm.goalAssessment.plan?.status == .minimumsExceedPortfolio(5))
    #expect(vm.suggestions.isEmpty)
    category.minimumBalanceCurrency = SettingsService.shared.mainCurrency == "EUR" ? "USD" : "EUR"
    vm.loadRebalancing()
    #expect(!vm.goalAssessment.goalConversion.isComplete)
    #expect(vm.suggestions.isEmpty)
    _ = container.mainContext
  }

}

@Suite("RebalancingHelpLayout Tests")
@MainActor
struct RebalancingHelpLayoutTests {
  private func size(rows: [RebalancingHelpRow], notes: [String] = [], maximumWidth: CGFloat = 1600)
    -> NSSize
  {
    let content = RebalancingHelpContent(
      title: "Details", sections: [RebalancingHelpSection(rows: rows, notes: notes)])
    let hosting = NSHostingView(
      rootView: RebalancingHelpView(content: content, maximumWidth: maximumWidth).font(.callout))
    return hosting.fittingSize
  }

  @Test("Inline formulas widen rows instead of adding another line")
  func inlineFormula() {
    let plain = size(rows: [RebalancingHelpRow(label: "Effective target %", value: "46.67%")])
    let formula = size(rows: [
      RebalancingHelpRow(label: "Effective target %", value: "46.67%", formula: "(C) ÷ (D) × 100")
    ])
    #expect(formula.width > plain.width)
    #expect(abs(formula.height - plain.height) < 1)
    let result = size(rows: [
      RebalancingHelpRow(
        label: "Effective target %", value: "46.67%", formula: "(C) ÷ (D) × 100", isResult: true)
    ])
    #expect(abs(result.height - plain.height) < 1)
  }

  @Test("Explanatory paragraphs wrap without determining the natural table width")
  func paragraphWidth() {
    let rows = [RebalancingHelpRow(label: "(A) Current balance", value: "1,000,000.00")]
    let table = size(rows: rows)
    let withNotes = size(rows: rows, notes: [String(repeating: "Explanation text. ", count: 30)])
    #expect(abs(withNotes.width - table.width) < 1)
    #expect(withNotes.height > table.height)
    let proseOnly = size(
      rows: [], notes: [String(repeating: "Explanation text. ", count: 30)], maximumWidth: 260)
    #expect(proseOnly.width == 260)
    let lineHeight = NSHostingView(rootView: Text("Input").font(.callout)).fittingSize.height
    let row = RebalancingHelpRow(label: "Input", value: "1.00")
    let oneRow = size(rows: [row])
    let twoRows = size(rows: [row, row])
    #expect(abs(twoRows.height - oneRow.height - lineHeight - 4) < 1)
  }

  @Test("Screen constraints allow wrapping without clipping long labels or values")
  func constrainedWidth() {
    let row = RebalancingHelpRow(
      label: "(C) Combined configured target % of remaining categories", value: "90.00%",
      formula: "(A) × (B) ÷ (C)")
    let natural = size(rows: [row])
    let constrained = size(rows: [row], maximumWidth: 260)
    #expect(natural.width > 260)
    #expect(constrained.width <= 260)
    #expect(constrained.height > natural.height)
    let chinese = size(rows: [
      RebalancingHelpRow(label: "(C) 其餘類別設定的目標 % 合計", value: "90.00%", formula: "(A) × (B) ÷ (C)")
    ])
    #expect(chinese.width > 260)
    let largeValue = RebalancingHelpRow(label: "Balance", value: String(repeating: "9", count: 100))
    let largeNatural = size(rows: [largeValue])
    let largeConstrained = size(rows: [largeValue], maximumWidth: 260)
    #expect(largeConstrained.width <= 260)
    #expect(largeConstrained.height > largeNatural.height)
  }

  @Test("Tabular digits align across input and result rows")
  func numericWidths() {
    for value in ["111,111.11", "888,888.88", "USD 300.00", "≈ 466,666.67", "46.67%"] {
      let input = size(rows: [RebalancingHelpRow(label: "Balance", value: value)])
      let result = size(rows: [RebalancingHelpRow(label: "Balance", value: value, isResult: true)])
      #expect(abs(input.width - result.width) < 0.1)
    }
    let ones = size(rows: [RebalancingHelpRow(label: "Balance", value: "111,111.11")])
    let eights = size(rows: [RebalancingHelpRow(label: "Balance", value: "888,888.88")])
    #expect(abs(ones.width - eights.width) < 0.1)
    let number = size(rows: [RebalancingHelpRow(label: "Balance", value: "46.67")])
    let percentage = size(rows: [RebalancingHelpRow(label: "Balance", value: "46.67", suffix: "%")])
    let symbolWidth = NSHostingView(rootView: Text("%").font(.callout.bold())).fittingSize.width
    #expect(abs(percentage.width - number.width - symbolWidth - 2) < 1)
  }

  @Test("Rebalancing opts into natural sizing and uses consistent row labels and baselines")
  func layoutWiring() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let view = try String(
      contentsOf: root.appending(path: "AssetFlow/Views/RebalancingView.swift"), encoding: .utf8)
    #expect(view.components(separatedBy: "fitsContent: true").count - 1 == 3)
    let renderer = try String(
      contentsOf: root.appending(path: "AssetFlow/Views/Components/RebalancingHelpView.swift"),
      encoding: .utf8)
    #expect(renderer.contains("GridRow(alignment: .firstTextBaseline)"))
    #expect(renderer.contains(".font(.callout.bold())"))
    #expect(renderer.contains(".monospacedDigit()"))
    #expect(!renderer.contains("design: .monospaced"))
    #expect(!renderer.contains(".fontWeight(row.isResult"))
    #expect(renderer.contains(#"Text(verbatim: row.suffix ?? "")"#))
    #expect(!renderer.contains("row.isResult ? .primary : .secondary"))
    #expect(!renderer.contains("if row.isResult { Divider().gridCellColumns(2) }"))
  }
}
