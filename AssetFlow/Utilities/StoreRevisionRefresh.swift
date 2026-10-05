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

private struct StoreRevisionKey: EnvironmentKey {
  static let defaultValue: ModelQueryRevision? = nil
}

extension EnvironmentValues {
  var storeRevision: ModelQueryRevision? {
    get { self[StoreRevisionKey.self] }
    set { self[StoreRevisionKey.self] = newValue }
  }
}

/// The app shell's queries cover membership, date ordering and store replacement,
/// including records outside a screen's last observed dependency set.
private struct StoreRevisionRefresh: ViewModifier {
  @Environment(\.storeRevision) private var revision
  let refresh: () -> Void

  func body(content: Content) -> some View {
    content.onChange(of: revision) { refresh() }
  }
}

extension View {
  func refreshOnStoreChanges(_ refresh: @escaping () -> Void) -> some View {
    modifier(StoreRevisionRefresh(refresh: refresh))
  }
}
