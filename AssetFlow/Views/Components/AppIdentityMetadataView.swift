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

/// Shows the app icon beside its name and version metadata.
struct AppIdentityMetadataView: View {
  private let iconSize: CGFloat = 64

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if let appIcon = NSApplication.shared.applicationIconImage {
        Image(nsImage: appIcon)
          .resizable().scaledToFit()
          .frame(width: iconSize, height: iconSize)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(Constants.AppInfo.name)
          .font(.headline)
        AppVersionMetadataGrid()
      }
      .frame(height: iconSize, alignment: .leading)
    }
  }
}
