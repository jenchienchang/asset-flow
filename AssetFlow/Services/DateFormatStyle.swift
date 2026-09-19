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

/// User-selectable date display format.
///
/// Maps to `Date.FormatStyle.DateStyle` for rendering. Uses stable `String` raw
/// values for UserDefaults persistence.
enum DateFormatStyle: String, CaseIterable, Sendable {
  case numeric
  case abbreviated
  case long
  case complete

  /// The corresponding `Date.FormatStyle.DateStyle`.
  var dateStyle: Date.FormatStyle.DateStyle {
    switch self {
    case .numeric: .numeric
    case .abbreviated: .abbreviated
    case .long: .long
    case .complete: .complete
    }
  }

  /// Localized display name for pickers.
  var localizedName: String {
    switch self {
    case .numeric:
      String(localized: "Numeric", table: "Settings")

    case .abbreviated:
      String(localized: "Abbreviated", table: "Settings")

    case .long:
      String(localized: "Long", table: "Settings")

    case .complete:
      String(localized: "Complete", table: "Settings")
    }
  }

  /// Preview string showing a date in this format.
  func preview(for date: Date) -> String {
    date.formatted(date: dateStyle, time: .omitted)
  }
}
