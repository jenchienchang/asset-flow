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
import Testing

@testable import AssetFlow

@Suite("CategoryGoalLocalization Tests")
@MainActor
struct CategoryGoalLocalizationTests {
  @Test("Snapshot assessment uses natural Traditional Chinese wording")
  func snapshotAssessmentWording() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appending(path: "AssetFlow/Resources/Localizable.xcstrings")
    let json = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let strings = try #require(json["strings"] as? [String: Any])
    let entry = try #require(strings["Assessed using snapshot: %@."] as? [String: Any])
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let chinese = try #require(localizations["zh-Hant"] as? [String: Any])
    let unit = try #require(chinese["stringUnit"] as? [String: String])
    #expect(unit["value"] == "評估依據：%@ 的快照資料。")
  }

  @Test("Compiled Chinese diagnostic interpolates the sum and displays one literal percent sign")
  func compiledPercentageDiagnostic() throws {
    let path = try #require(Bundle.main.path(forResource: "zh-Hant", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let text = try #require(
      CategoryGoalPresentation.diagnostic(
        RebalancingPlan(status: .invalidPercentageSum(90)), currency: "USD", bundle: bundle))
    #expect(text == "目標比例合計為 \(Decimal(90).formattedPercentage())。請將合計設為 100%，以計算再平衡。")
    #expect(!text.contains("100%%"))
  }

  @Test("Goal UI and diagnostics have Traditional Chinese translations with matching placeholders")
  func catalogs() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let keys: [String: [String]] = [
      "Category": [
        "Current allocation differs from the effective target by more than 5 percentage points.",
        "Minimum balance met", "Minimum balance unavailable", "Minimum balance shortfall: %@",
        "Choose a currency for the minimum balance.",
      ],
      "Rebalancing": [
        "Increase <%@", "Decrease <%@", "Small adjustment: %@",
        "Percentage targets sum to %@. Set their total to 100%% to calculate rebalancing.",
      ],
      "Localizable": [
        "Current: %@", "Effective target: %@",
        "Categories marked with ⚠ have a minimum balance shortfall or differ from their effective target by more than 5 percentage points.",
        "Effective targets are shares of the whole portfolio. Minimum-only categories retain any balance above their minimum.",
        "Minimum balance", "Minimum balance amount", "Minimum balance currency", "Effective target",
        "Save Changes", "Revert", "Category Settings", "Calculation details", "Allocation basis",
        "Assessment", "%@ (%@)", "Configured goals", "How allocation works",
        "Minimum balance status", "Required minimum", "Minimum in display currency", "Shortfall",
        "Explanation", "Current balance is %@ below the minimum.", "Assessed using snapshot: %@.",
        "Details for %@", "Category calculation details", "Pool target %", "Effective balance",
        "Unsaved changes are not included in this assessment.",
        "Add a snapshot to calculate rebalancing from your category goals.",
      ],
    ]
    for (table, required) in keys {
      let url = root.appending(path: "AssetFlow/Resources/\(table).xcstrings")
      let json = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      let strings = try #require(json["strings"] as? [String: Any])
      for key in required {
        let entry = try #require(strings[key] as? [String: Any])
        if table == "Rebalancing" {
          #expect(entry["extractionState"] as? String != "stale")
        }
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let chinese = try #require(localizations["zh-Hant"] as? [String: Any])
        let unit = try #require(chinese["stringUnit"] as? [String: String])
        let value = try #require(unit["value"])
        #expect(!value.isEmpty)
        #expect(unit["state"] == "translated")
        #expect(
          value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
      }
    }
  }
}
