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

struct AboutView: View {
  private let privacyText: LocalizedStringKey =
    "All data is stored locally. Exchange rates are fetched from cdn.jsdelivr.net. No personal data is collected or transmitted."

  var body: some View {
    AboutWindowContentLayout(spacing: 16) {
      VStack(spacing: 16) {
        AppIdentityMetadataView()
          .fixedSize(horizontal: true, vertical: false)

        VStack(spacing: 6) {
          Text(Constants.AppInfo.copyright)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

          Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
              Text("Developer")
                .foregroundStyle(.secondary)
              Text(Constants.AppInfo.developerName)
            }
            GridRow {
              Text("License")
                .foregroundStyle(.secondary)
              Text(Constants.AppInfo.license)
            }
          }
          .font(.caption)
          .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
      }
      .fixedSize(horizontal: true, vertical: true)

      Rectangle()
        .fill(.separator)
        .frame(height: 1)

      Text(privacyText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 16) {
        Link("User Guide", destination: Constants.AppInfo.documentationURL)
        Link("View Source Code on GitHub", destination: Constants.AppInfo.repositoryURL)
      }
      .font(.caption)
      .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 20)
  }
}

/// Uses the widest fixed content group to size the window and wrap the privacy text.
private struct AboutWindowContentLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    guard subviews.count == 4 else { return .zero }

    let creditsSize = subviews[0].sizeThatFits(.unspecified)
    let linksSize = subviews[3].sizeThatFits(.unspecified)
    let contentWidth = max(creditsSize.width, linksSize.width)
    let privacySize = subviews[2].sizeThatFits(
      ProposedViewSize(width: contentWidth, height: nil)
    )
    let contentHeight =
      creditsSize.height + linksSize.height + privacySize.height + (spacing * 3) + 1
    return CGSize(
      width: contentWidth,
      height: contentHeight
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    guard subviews.count == 4 else { return }

    let creditsSize = subviews[0].sizeThatFits(.unspecified)
    let linksSize = subviews[3].sizeThatFits(.unspecified)
    let contentWidth = max(creditsSize.width, linksSize.width)
    let privacySize = subviews[2].sizeThatFits(
      ProposedViewSize(width: contentWidth, height: nil)
    )
    let contentX = bounds.minX + (bounds.width - contentWidth) / 2
    let creditsX = contentX + (contentWidth - creditsSize.width) / 2
    let dividerY = bounds.minY + creditsSize.height + spacing
    let privacyY = dividerY + 1 + spacing
    let linksY = privacyY + privacySize.height + spacing

    subviews[0].place(
      at: CGPoint(x: creditsX, y: bounds.minY),
      proposal: ProposedViewSize(width: creditsSize.width, height: creditsSize.height)
    )
    subviews[1].place(
      at: CGPoint(x: contentX, y: dividerY),
      proposal: ProposedViewSize(width: contentWidth, height: 1)
    )
    subviews[2].place(
      at: CGPoint(x: contentX, y: privacyY),
      proposal: ProposedViewSize(width: contentWidth, height: privacySize.height)
    )
    subviews[3].place(
      at: CGPoint(x: contentX + (contentWidth - linksSize.width) / 2, y: linksY),
      proposal: ProposedViewSize(width: linksSize.width, height: linksSize.height)
    )
  }
}
