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
import SwiftData

// MARK: - Decimal Extensions
extension Decimal {
  var doubleValue: Double {
    NSDecimalNumber(decimal: self).doubleValue
  }

  @MainActor private static var currencyFormatters: [String: NumberFormatter] = [:]

  func formatted(currency: String = "USD", locale: Locale = .current) -> String {
    let key = "\(currency)-\(locale.identifier)"
    let formatter: NumberFormatter
    if let cached = Self.currencyFormatters[key] {
      formatter = cached
    } else {
      let f = NumberFormatter()
      f.numberStyle = .currency
      f.currencyCode = currency
      f.locale = locale
      Self.currencyFormatters[key] = f
      formatter = f
    }
    return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "\(self)"
  }

  @MainActor private static var fullPrecisionFormatters: [String: NumberFormatter] = [:]

  /// Formats a currency value preserving full decimal precision.
  ///
  /// Unlike `formatted(currency:)` which uses the currency's default fraction digits (typically 2),
  /// this method preserves all significant digits. Useful for displaying crypto values, fractional
  /// shares, or any high-precision monetary values.
  ///
  /// Examples:
  ///   - Input: Decimal(1234.56789) → Output: "$1,234.56789" (vs "$1,234.57" from formatted())
  ///   - Input: Decimal(0.00012345) → Output: "$0.00012345" (vs "$0.00" from formatted())
  ///
  /// - Parameters:
  ///   - currency: The currency code (e.g., "USD", "EUR")
  ///   - locale: The locale for formatting (defaults to `.current`)
  /// - Returns: Formatted currency string with full precision
  func formattedFullPrecision(currency: String = "USD", locale: Locale = .current) -> String {
    let key = "full-\(currency)-\(locale.identifier)"
    let formatter: NumberFormatter
    if let cached = Self.fullPrecisionFormatters[key] {
      formatter = cached
    } else {
      let f = NumberFormatter()
      f.numberStyle = .currency
      f.currencyCode = currency
      f.locale = locale
      f.usesSignificantDigits = true
      f.minimumSignificantDigits = 1
      f.maximumSignificantDigits = 15
      Self.fullPrecisionFormatters[key] = f
      formatter = f
    }
    return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "\(self)"
  }

  @MainActor private static var percentageFormatters: [Int: NumberFormatter] = [:]

  /// Formats a percentage value for display.
  ///
  /// **IMPORTANT:** Expects percentage-scale input (0-100 range).
  /// For decimal ratios (0.0-1.0) from CalculationService,
  /// multiply by 100 first: `(ratio * 100).formattedPercentage()`
  ///
  /// Examples:
  ///   - Input: Decimal(45.67) → Output: "45.67%"
  ///   - Input: Decimal(0.4567) * 100 → Output: "45.67%"
  ///
  /// - Parameter decimals: Number of decimal places (default: 2)
  /// - Returns: Formatted percentage string
  func formattedPercentage(decimals: Int = 2) -> String {
    let formatter: NumberFormatter
    if let cached = Self.percentageFormatters[decimals] {
      formatter = cached
    } else {
      let f = NumberFormatter()
      f.numberStyle = .percent
      f.minimumFractionDigits = decimals
      f.maximumFractionDigits = decimals
      Self.percentageFormatters[decimals] = f
      formatter = f
    }
    return formatter.string(from: NSDecimalNumber(decimal: self / 100)) ?? "\(self)%"
  }

  // MARK: - Parsing

  @MainActor private static var parseFormatters: [String: NumberFormatter] = [:]

  /// Parses a user-entered numeric string, handling locale-specific separators and currency symbols.
  ///
  /// Supports:
  /// - Thousands grouping separators (e.g., "1,000" in US, "1.000" in Germany)
  /// - Decimal separators (e.g., "1.50" in US, "1,50" in Germany)
  /// - Currency symbols ($, €, £, ¥, ₩, ₹)
  /// - Leading/trailing whitespace
  ///
  /// - Parameters:
  ///   - string: The user-entered numeric string
  ///   - locale: The locale to use for parsing (defaults to `.current`)
  /// - Returns: The parsed Decimal, or nil if parsing fails
  @MainActor
  static func parse(_ string: String, locale: Locale = .current) -> Decimal? {
    // Strip whitespace and currency symbols in one pass
    let cleaned = String(
      string.trimmingCharacters(in: .whitespacesAndNewlines)
        .filter { !Constants.Parsing.currencySymbols.contains($0) }
    )

    guard !cleaned.isEmpty else { return nil }

    // Use cached NumberFormatter for locale-aware parsing
    let key = locale.identifier
    let formatter: NumberFormatter
    if let cached = parseFormatters[key] {
      formatter = cached
    } else {
      let f = NumberFormatter()
      f.numberStyle = .decimal
      f.locale = locale
      parseFormatters[key] = f
      formatter = f
    }

    guard let number = formatter.number(from: cleaned) else { return nil }
    return number.decimalValue
  }
}

// MARK: - ModelContext Extensions
extension ModelContext {
  /// Finds an existing asset by normalized (name, platform) or creates a new one.
  func findOrCreateAsset(name: String, platform: String) -> Asset {
    let normalizedName = name.normalizedForIdentity
    let normalizedPlatform = platform.normalizedForIdentity

    let descriptor = FetchDescriptor<Asset>()
    let allAssets = (try? fetch(descriptor)) ?? []

    if let existing = allAssets.first(where: {
      $0.normalizedName == normalizedName && $0.normalizedPlatform == normalizedPlatform
    }) {
      return existing
    }

    let newAsset = Asset(name: name, platform: platform)
    insert(newAsset)
    return newAsset
  }

  /// Resolves a category by name, reusing an existing one (case-insensitive) or creating a new one.
  func resolveCategory(name: String) -> Category? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    let normalizedInput = trimmed.lowercased()

    let descriptor = FetchDescriptor<Category>()
    let allCategories = (try? fetch(descriptor)) ?? []

    if let existing = allCategories.first(where: { $0.name.lowercased() == normalizedInput }) {
      return existing
    }

    let newCategory = Category(name: trimmed)
    let maxOrder = allCategories.map(\.displayOrder).max() ?? -1
    newCategory.displayOrder = maxOrder + 1
    insert(newCategory)
    return newCategory
  }
}

// MARK: - String Extensions
extension String {
  /// Trims leading/trailing whitespace and collapses internal whitespace runs to a single space.
  /// Preserves original casing — suitable for display normalization.
  nonisolated var collapsingWhitespace: String {
    let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
    var result = ""
    result.reserveCapacity(trimmed.count)
    var previousWasWhitespace = false
    for char in trimmed {
      if char.isWhitespace {
        if !previousWasWhitespace {
          result.append(" ")
          previousWasWhitespace = true
        }
      } else {
        result.append(char)
        previousWasWhitespace = false
      }
    }
    return result
  }

  /// Normalizes a string for identity comparison (SPEC 6.1):
  /// trims whitespace, collapses internal runs of whitespace, lowercases.
  nonisolated var normalizedForIdentity: String {
    collapsingWhitespace.lowercased()
  }
}

// MARK: - Date Extensions
extension Date {
  @MainActor private static var dateStyleFormatters: [DateFormatter.Style: DateFormatter] = [:]

  func formatted(style: DateFormatter.Style = .medium) -> String {
    let formatter: DateFormatter
    if let cached = Self.dateStyleFormatters[style] {
      formatter = cached
    } else {
      let f = DateFormatter()
      f.dateStyle = style
      f.timeStyle = .none
      Self.dateStyleFormatters[style] = f
      formatter = f
    }
    return formatter.string(from: self)
  }

  @MainActor private static var dateTimeFormatters: [String: DateFormatter] = [:]

  func formattedWithTime(
    dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .short
  ) -> String {
    let key = "\(dateStyle.rawValue)-\(timeStyle.rawValue)"
    let formatter: DateFormatter
    if let cached = Self.dateTimeFormatters[key] {
      formatter = cached
    } else {
      let f = DateFormatter()
      f.dateStyle = dateStyle
      f.timeStyle = timeStyle
      Self.dateTimeFormatters[key] = f
      formatter = f
    }
    return formatter.string(from: self)
  }

  /// Formats the date using the system's short date format (date only, no time).
  var formattedDate: String {
    formatted(style: .short)
  }

  /// Formats the date using the shared settings service's date format preference.
  @MainActor
  func settingsFormatted() -> String {
    self.formatted(date: SettingsService.shared.dateFormat.dateStyle, time: .omitted)
  }

  /// Formats the date using the given settings service's date format preference.
  @MainActor
  func settingsFormatted(using service: SettingsService) -> String {
    self.formatted(date: service.dateFormat.dateStyle, time: .omitted)
  }

  var startOfDay: Date {
    Calendar.current.startOfDay(for: self)
  }

  var endOfDay: Date {
    var components = DateComponents()
    components.day = 1
    components.second = -1
    return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
  }
}
