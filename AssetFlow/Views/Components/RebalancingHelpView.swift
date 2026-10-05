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
import SwiftUI

/// Tables set the natural width; explanatory text wraps within that width.
struct RebalancingHelpView: View {
  let content: RebalancingHelpContent
  // Leave room for popup padding and the system's screen-edge margins.
  var maximumWidth: CGFloat = (NSScreen.main?.visibleFrame.width ?? 1024) - 64

  var body: some View {
    RebalancingHelpLayout(
      maximumWidth: maximumWidth, hasTable: content.sections.contains { !$0.rows.isEmpty }
    ) {
      Text(verbatim: content.title).font(.headline)
        .layoutValue(key: HelpWidthSource.self, value: true)
      ForEach(content.sections.indices, id: \.self) { index in
        section(content.sections[index])
      }
    }
  }

  @ViewBuilder
  private func section(_ section: RebalancingHelpSection) -> some View {
    if let title = section.title {
      Text(verbatim: title).font(.subheadline.weight(.semibold))
        .layoutValue(key: HelpWidthSource.self, value: true)
        .layoutValue(key: HelpBlockSpacing.self, value: 10)
    }
    if !section.rows.isEmpty {
      let hasSuffix = section.rows.contains { $0.suffix != nil }
      Grid(alignment: .leading, horizontalSpacing: hasSuffix ? 2 : 12, verticalSpacing: 4) {
        ForEach(section.rows.indices, id: \.self) { index in
          let row = section.rows[index]
          GridRow(alignment: .firstTextBaseline) {
            rowLabel(row)
              .foregroundStyle(.secondary)
              .padding(.trailing, hasSuffix ? 10 : 0)
              .fixedSize(horizontal: false, vertical: true)
              .anchorPreference(key: HelpResultRows.self, value: .bounds) {
                row.isResult ? [$0] : []
              }
            Text(verbatim: row.value)
              .font(.callout.bold())
              .monospacedDigit()
              .multilineTextAlignment(.trailing)
              .gridColumnAlignment(.trailing)
              .accessibilityLabel(Text(verbatim: row.value + (row.suffix ?? "")))
              .fixedSize(horizontal: false, vertical: true)
            if hasSuffix {
              Text(verbatim: row.suffix ?? "")
                .font(.callout.bold())
                .gridColumnAlignment(.leading)
                .accessibilityHidden(true)
            }
          }
        }
      }
      .overlayPreferenceValue(HelpResultRows.self) { anchors in
        GeometryReader { geometry in
          ForEach(anchors.indices, id: \.self) { index in
            Divider()
              .frame(width: geometry.size.width)
              .position(x: geometry.size.width / 2, y: geometry[anchors[index]].minY - 2)
          }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .layoutValue(key: HelpWidthSource.self, value: true)
      .layoutValue(key: HelpBlockSpacing.self, value: section.title == nil ? 10 : 4)
    }
    ForEach(section.bullets.indices, id: \.self) { index in
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•").accessibilityHidden(true)
        Text(verbatim: section.bullets[index]).fixedSize(horizontal: false, vertical: true)
      }
      .layoutValue(
        key: HelpBlockSpacing.self,
        value: index == 0 && section.title == nil && section.rows.isEmpty ? 10 : 4)
    }
    ForEach(section.notes.indices, id: \.self) { index in
      Text(verbatim: section.notes[index]).fixedSize(horizontal: false, vertical: true)
        .layoutValue(
          key: HelpBlockSpacing.self,
          value: index == 0 && section.title == nil && section.rows.isEmpty
            && section.bullets.isEmpty ? 10 : 4)
    }
  }

  private func rowLabel(_ row: RebalancingHelpRow) -> Text {
    let label = Text(verbatim: row.label)
    guard let formula = row.formula else { return label }
    // Both strings are already presentation text, rather than localization keys.
    return label + Text(verbatim: " · " + formula).font(.caption)
  }
}

nonisolated private struct HelpResultRows: PreferenceKey {
  static var defaultValue: [Anchor<CGRect>] { [] }

  static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
    value.append(contentsOf: nextValue())
  }
}

nonisolated private struct HelpWidthSource: LayoutValueKey {
  static let defaultValue = false
}

nonisolated private struct HelpBlockSpacing: LayoutValueKey {
  static let defaultValue: CGFloat = 4
}

/// Measure title/table blocks first so a long paragraph cannot widen the popup.
private struct RebalancingHelpLayout: Layout {
  let maximumWidth: CGFloat
  let hasTable: Bool

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let naturalWidth =
      subviews.filter { $0[HelpWidthSource.self] }
      .map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    let preferredWidth = hasTable ? naturalWidth : max(naturalWidth, 360)
    let width = max(1, min(preferredWidth, maximumWidth, proposal.width ?? .infinity))
    var height: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
      guard size.height > 0 else { continue }
      if height > 0 { height += subview[HelpBlockSpacing.self] }
      height += size.height
    }
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let childProposal = ProposedViewSize(width: bounds.width, height: nil)
    var offset: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(childProposal)
      guard size.height > 0 else { continue }
      if offset > 0 { offset += subview[HelpBlockSpacing.self] }
      subview.place(
        at: CGPoint(x: bounds.minX, y: bounds.minY + offset), anchor: .topLeading,
        proposal: childProposal)
      offset += size.height
    }
  }
}
