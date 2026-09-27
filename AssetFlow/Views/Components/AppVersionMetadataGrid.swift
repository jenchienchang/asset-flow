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

import SwiftUI

/// Displays the app's version metadata as compact, selectable aligned rows.
struct AppVersionMetadataGrid: View {
  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
      GridRow {
        Text("Version")
          .foregroundStyle(.secondary)
        Text(Constants.AppInfo.version)
          .monospaced()
      }
      GridRow {
        Text("Build")
          .foregroundStyle(.secondary)
        Text(Constants.AppInfo.buildNumber)
          .monospaced()
      }
      GridRow {
        Text("Commit")
          .foregroundStyle(.secondary)
        Text(Constants.AppInfo.commit)
          .monospaced()
      }
    }
    .font(.caption)
    .textSelection(.enabled)
  }
}
