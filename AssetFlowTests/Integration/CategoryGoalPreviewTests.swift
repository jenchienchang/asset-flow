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
import SwiftUI
import Testing

@testable import AssetFlow

@Suite("Category Goal Help Layout Tests")
@MainActor
struct CategoryGoalPreviewTests {
  @Test("Localized rebalancing help respects its constrained width")
  func helpLayoutsFit() throws {
    var localizedLabels: [String] = []
    for language in ["en", "zh-Hant"] {
      let locale = Locale(identifier: language)
      let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
      let bundle = try #require(Bundle(path: path))
      let label = String(
        localized: "(C) Combined configured target % of remaining categories", bundle: bundle)
      localizedLabels.append(label)
      let content = RebalancingHelpContent(
        title: String(localized: "Calculation details", bundle: bundle),
        sections: [
          RebalancingHelpSection(rows: [
            RebalancingHelpRow(label: label, value: "90.00%", formula: "(A) × (B) ÷ (C)")
          ])
        ])
      let help = RebalancingHelpView(content: content, maximumWidth: 288).font(.callout)
        .padding(16)
        .fixedSize(horizontal: true, vertical: true)
        .environment(\.locale, locale)
      let constrainedSize = NSHostingView(rootView: help).fittingSize
      #expect(constrainedSize.width > 0 && constrainedSize.width <= 320)
      #expect(constrainedSize.height > 0)
    }
    #expect(localizedLabels[0] != localizedLabels[1])
  }
}
