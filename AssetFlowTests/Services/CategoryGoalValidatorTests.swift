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

@Suite("CategoryGoalValidator Tests")
@MainActor
struct CategoryGoalValidatorTests {
  @Test("All four goal combinations and explicit zeros are valid")
  func combinations() throws {
    for percentage: Decimal? in [nil, 0, 100] {
      try CategoryGoalValidator.validate(percentage: percentage, minimum: nil, currency: nil)
      try CategoryGoalValidator.validate(percentage: percentage, minimum: 0, currency: "USD")
      try CategoryGoalValidator.validate(percentage: percentage, minimum: 300000, currency: "TWD")
    }
  }

  @Test("Invalid ranges, nonfinite values and incomplete pairs are rejected")
  func invalid() {
    for percentage in [Decimal(-1), Decimal(101), Decimal.nan] {
      #expect(throws: CategoryGoalValidationError.percentage) {
        try CategoryGoalValidator.validate(percentage: percentage, minimum: nil, currency: nil)
      }
    }
    for minimum in [Decimal(-1), Decimal.nan] {
      #expect(throws: CategoryGoalValidationError.minimum) {
        try CategoryGoalValidator.validate(percentage: nil, minimum: minimum, currency: "USD")
      }
    }
    for (minimum, currency): (Decimal?, String?) in [(1, nil), (nil, "USD"), (1, ""), (1, "US$")] {
      #expect(throws: CategoryGoalValidationError.currency) {
        try CategoryGoalValidator.validate(percentage: nil, minimum: minimum, currency: currency)
      }
    }
    #expect(throws: CategoryGoalValidationError.currency) {
      try CategoryGoalValidator.validate(
        percentage: nil, minimum: 1, currency: "XYZ", supportedCurrencies: ["USD"])
    }
    // Restore accepts a syntactically valid code absent from the current currency list.
    #expect(throws: Never.self) {
      try CategoryGoalValidator.validate(percentage: nil, minimum: 1, currency: "XYZ")
    }
  }

  @Test("Form parsing consumes the entire number without binary floating point")
  func parsing() throws {
    #expect(try CategoryGoalValidator.parse(" ") == nil)
    #expect(
      try CategoryGoalValidator.parse("1,234.567890123456789", locale: Locale(identifier: "en_US"))
        == Decimal(string: "1234.567890123456789"))
    #expect(
      try CategoryGoalValidator.parse("1.234,50", locale: Locale(identifier: "de_DE"))
        == Decimal(string: "1234.50"))
    #expect(
      try CategoryGoalValidator.parse("300,000", locale: Locale(identifier: "zh_TW")) == 300000)
    for invalid in ["12garbage", "NaN", "1,23", "1.2.3", "1e999", "--3"] {
      #expect(throws: CategoryGoalValidationError.number) {
        try CategoryGoalValidator.parse(invalid, locale: Locale(identifier: "en_US"))
      }
    }
  }

  @Test("Currency default uses a single asset currency or the display currency")
  func currencyDefault() {
    #expect(
      CategoryGoalValidator.defaultCurrency(
        assetCurrencies: ["usd", "USD"], displayCurrency: "TWD") == "USD")
    #expect(
      CategoryGoalValidator.defaultCurrency(
        assetCurrencies: ["USD", "TWD"], displayCurrency: "TWD") == "TWD")
    #expect(
      CategoryGoalValidator.defaultCurrency(assetCurrencies: [], displayCurrency: "USD") == "USD")
    #expect(
      CategoryGoalValidator.defaultCurrency(assetCurrencies: [""], displayCurrency: "TWD") == "TWD")
  }
  @Test("Representable large powers and tiny values retain their exact meaning")
  func representableMagnitudes() throws {
    let large = "1" + String(repeating: "0", count: 100)
    #expect(
      try CategoryGoalValidator.parse(large, locale: Locale(identifier: "en_US"))
        == Decimal(sign: .plus, exponent: 100, significand: 1))
    #expect(throws: CategoryGoalValidationError.number) {
      try CategoryGoalValidator.parse(
        "0." + String(repeating: "0", count: 199) + "1", locale: Locale(identifier: "en_US"))
    }
    #expect(
      CategoryGoalPresentation.minimumStatus(
        .shortfall(Decimal(string: "0.00000000000000000001")!), currency: "USD"
      ).contains("0.00000000000000000001"))
  }

}
