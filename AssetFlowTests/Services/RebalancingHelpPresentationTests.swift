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

@Suite("RebalancingHelpPresentation Tests")
@MainActor
struct RebalancingHelpPresentationTests {
  private func fixture(_ categories: [CategoryGoalAllocation], uncategorized: Decimal = 0)
    -> CategoryGoalAssessment
  {
    let total = categories.reduce(uncategorized) { $0 + $1.currentValue }
    return CategoryGoalAssessment(
      totalValue: total,
      plan: RebalancingCalculator.calculate(
        categories: categories, totalValue: total, uncategorizedValue: uncategorized))
  }

  private func categoryContent(
    _ category: CategoryGoalAllocation, assessment: CategoryGoalAssessment
  ) -> RebalancingHelpContent {
    let target = assessment.plan?.targets.first { $0.id == category.id }
    let input = RebalancingCategoryHelpInput(
      name: category.name, current: category.currentValue, percentage: category.percentage,
      minimum: category.minimum, minimumCurrency: category.minimum == nil ? nil : "USD",
      convertedMinimum: category.minimum,
      target: target?.targetValue, minimumIsBinding: target?.minimumIsBinding ?? false)
    return RebalancingHelpPresentation.category(
      input, diagnostic: nil, currency: "USD", assessment: assessment)
  }

  @Test(
    "Calculation reconciles portfolio, protected funds and allocation without overlapping minimum totals"
  )
  func calculation() {
    let protected = CategoryGoalAllocation(id: UUID(), name: "Protected", currentValue: 20)
    let flexible = CategoryGoalAllocation(
      id: UUID(), name: "Flexible", currentValue: 80, percentage: 100)
    let assessment = fixture([protected, flexible])
    let content = RebalancingHelpPresentation.calculation(assessment: assessment, currency: "USD")
    #expect(content.sections.first?.rows.map(\.value) == ["100.00", "20.00", "80.00"])
    #expect(content.sections.first?.rows.last?.formula == "(A) − (B)")
    #expect(content.sections.last?.bullets.count == 4)
    #expect(!content.sections.flatMap(\.rows).contains { $0.label.contains("Total minimum") })
    let blocked = RebalancingHelpPresentation.calculation(
      assessment: CategoryGoalAssessment(
        plan: RebalancingPlan(status: .minimumsExceedPortfolio(10))), currency: "USD")
    #expect(blocked.sections.flatMap(\.rows).isEmpty)
    #expect(!blocked.sections.flatMap(\.notes).isEmpty)
  }

  @Test("Category calculations use lettered inputs and actual remaining percentage weights")
  func category() throws {
    let reserve = CategoryGoalAllocation(
      id: UUID(), name: "Reserve", currentValue: 200000, percentage: 10, minimum: 300000)
    let equities = CategoryGoalAllocation(
      id: UUID(), name: "Equities", currentValue: 600000, percentage: 60)
    let bonds = CategoryGoalAllocation(
      id: UUID(), name: "Bonds", currentValue: 200000, percentage: 30)
    let assessment = fixture([reserve, equities, bonds])
    let content = categoryContent(equities, assessment: assessment)
    #expect(content.title == "Equities")
    let rows = content.sections.flatMap(\.rows)
    #expect(
      rows.map(\.value) == [
        "60.00", "700,000.00", "90.00", "≈ 466,666.67", "1,000,000.00", "≈ 46.67",
      ])
    #expect(rows.map(\.suffix) == ["%", nil, "%", nil, nil, "%"])
    try #require(rows.count == 6)
    #expect(rows[3].formula == "(B) × (A) ÷ (C)")
    #expect(rows[5].formula == "(D) ÷ (E) × 100")
    #expect(rows[3].isResult && rows[5].isResult)
    #expect(!content.sections.flatMap(\.notes).joined().contains("Reserve"))
    let minimumRows = categoryContent(reserve, assessment: assessment).sections.flatMap(\.rows)
    #expect(minimumRows.map(\.value) == ["300,000.00", "300,000.00", "1,000,000.00", "30.00"])
    try #require(minimumRows.count == 4)
    #expect(minimumRows[1].formula == "(A)")
    #expect(minimumRows.last?.formula == "(A) ÷ (B) × 100")
    let basis = RebalancingHelpPresentation.calculation(assessment: assessment, currency: "USD")
      .sections.first?.rows
    #expect(
      basis?.map(\.value) == ["1,000,000.00", "0.00", "1,000,000.00", "300,000.00", "700,000.00"])
    #expect(basis?.last?.formula == "(C) − (D)")
  }

  @Test("Minimum-only calculations compare balances; protected categories omit irrelevant results")
  func protectedAndMinimumOnly() throws {
    for current in [Decimal(20), Decimal(80)] {
      let reserve = CategoryGoalAllocation(
        id: UUID(), name: "Reserve", currentValue: current, minimum: 50)
      let donor = CategoryGoalAllocation(
        id: UUID(), name: "Donor", currentValue: 100, percentage: 100)
      let assessment = fixture([reserve, donor], uncategorized: 100)
      let rows = categoryContent(reserve, assessment: assessment).sections.flatMap(\.rows)
      try #require(rows.count == 5)
      #expect(rows[2].formula == "max((A), (B))")
      #expect(rows[2].value == (current < 50 ? "50.00" : "80.00"))
      #expect(rows.last?.formula == "(C) ÷ (D) × 100")
    }
    let protected = CategoryGoalAllocation(id: UUID(), name: "Protected", currentValue: 50)
    let content = categoryContent(protected, assessment: fixture([protected]))
    #expect(content.sections.flatMap(\.rows).isEmpty)
    #expect(!content.sections.flatMap(\.notes).isEmpty)
  }

  @Test("Zero percentages, zero totals and unavailable calculations have honest explanations")
  func specialCases() {
    for minimum in [Decimal?.none, Decimal(20)] {
      let zero = CategoryGoalAllocation(
        id: UUID(), name: "Zero", currentValue: 30, percentage: 0, minimum: minimum)
      let donor = CategoryGoalAllocation(
        id: UUID(), name: "Donor", currentValue: 70, percentage: 100)
      let rows = categoryContent(zero, assessment: fixture([zero, donor])).sections.flatMap(\.rows)
      #expect(rows.contains { $0.isResult && $0.value == (minimum == nil ? "0.00" : "20.00") })
      #expect(!rows.contains { $0.formula == "(B) × (A) ÷ (C)" })
    }
    let empty = CategoryGoalAllocation(id: UUID(), name: "Empty", currentValue: 0, percentage: 100)
    let content = categoryContent(empty, assessment: fixture([empty]))
    #expect(content.sections.flatMap(\.rows).last?.value == "—")
    #expect(content.sections.flatMap(\.rows).last?.formula == nil)
    #expect(content.sections.flatMap(\.rows).last?.suffix == nil)
    #expect(!content.sections.flatMap(\.notes).isEmpty)
    let unavailable = RebalancingHelpPresentation.category(
      RebalancingCategoryHelpInput(name: "Blocked", percentage: 100),
      diagnostic: "Missing snapshot rate", currency: "USD")
    #expect(unavailable.sections.flatMap(\.rows).isEmpty)
    #expect(unavailable.sections.flatMap(\.notes) == ["Missing snapshot rate"])
  }

  @Test("Repeated minimum constraints and protected holdings use final allocation inputs")
  func repeatedConstraints() throws {
    let first = CategoryGoalAllocation(
      id: UUID(), name: "First", currentValue: 0, percentage: 10, minimum: 40)
    let second = CategoryGoalAllocation(
      id: UUID(), name: "Second", currentValue: 0, percentage: 30, minimum: 25)
    let third = CategoryGoalAllocation(id: UUID(), name: "Third", currentValue: 100, percentage: 60)
    let protected = CategoryGoalAllocation(id: UUID(), name: "Protected", currentValue: 50)
    let assessment = fixture([first, second, third, protected], uncategorized: 50)
    #expect(assessment.plan?.status == .feasible)
    let rows = categoryContent(third, assessment: assessment).sections.flatMap(\.rows)
    #expect(rows.map(\.value) == ["60.00", "35.00", "60.00", "35.00", "200.00", "17.50"])
    // Equality with the minimum is also a valid minimum-determined explanation.
    let equal = CategoryGoalAllocation(
      id: UUID(), name: "Equal", currentValue: 100, percentage: 100, minimum: 100)
    let equalRows = categoryContent(equal, assessment: fixture([equal])).sections.flatMap(\.rows)
    try #require(equalRows.count == 4)
    #expect(equalRows[1].formula == "(A)")
  }

  @Test("Unavailable assessments show only the reason and never fabricate a calculation")
  func blockedAssessments() {
    let input = RebalancingCategoryHelpInput(
      name: "Reserve", current: 20, percentage: 100, minimum: 50, minimumCurrency: "TWD")
    let assessments = [
      CategoryGoalAssessment(),
      CategoryGoalAssessment(totalValue: 20, goalConversion: .missingRates(["twd"])),
      CategoryGoalAssessment(
        totalValue: 20, plan: RebalancingPlan(status: .minimumsExceedPortfolio(30))),
      CategoryGoalAssessment(
        totalValue: 20, plan: RebalancingPlan(status: .insufficientAvailableFunds(30))),
      CategoryGoalAssessment(
        totalValue: 20, plan: RebalancingPlan(status: .invalidPercentageSum(50))),
    ]
    for assessment in assessments {
      let content = RebalancingHelpPresentation.category(
        input, diagnostic: nil, currency: "USD", assessment: assessment)
      #expect(content.sections.flatMap(\.rows).isEmpty)
      #expect(content.sections.flatMap(\.notes).count == 1)
    }
  }

  @Test("Rounded formula inputs mark results approximate without changing Decimal targets")
  func roundedFormulaInputs() throws {
    let reserve = CategoryGoalAllocation(
      id: UUID(), name: "Reserve", currentValue: Decimal(string: "0.123456")!,
      minimum: Decimal(string: "0.1")!)
    let assessment = fixture([reserve])
    let original = try #require(assessment.plan?.targets.first?.targetValue)
    let rows = categoryContent(reserve, assessment: assessment).sections.flatMap(\.rows)
    try #require(rows.count == 5)
    #expect(rows[0].value == "0.12")
    #expect(rows[2].value == "≈ 0.12")
    #expect(rows.last?.value == "≈ 100.00")
    #expect(assessment.plan?.targets.first?.targetValue == original)
  }

  @Test("Tiny target results use a bound instead of combining approximation and inequality")
  func tinyTargetResults() throws {
    let tiny = CategoryGoalAllocation(
      id: UUID(), name: "Tiny", currentValue: Decimal(string: "0.000001")!,
      minimum: Decimal(string: "0.0000001")!)
    let rows = categoryContent(tiny, assessment: fixture([tiny])).sections.flatMap(\.rows)
    try #require(rows.count == 5)
    #expect(rows[2].value == "<0.01")
  }

  @Test("Percentage symbols are separate metadata while numeric formatting remains localized")
  func percentageSuffix() {
    for identifier in ["en_US", "zh_TW", "de_DE", "fr_FR"] {
      let locale = Locale(identifier: identifier)
      let formatter = NumberFormatter()
      formatter.locale = locale
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 2
      formatter.maximumFractionDigits = 2
      let value = Decimal(string: "46.66666667")!
      let symbolFormatter = NumberFormatter()
      symbolFormatter.locale = locale
      symbolFormatter.numberStyle = .percent
      let row = RebalancingHelpPresentation.percentageRow(
        "Share", value, approximate: true, locale: locale)
      #expect(row.value == "≈ " + formatter.string(from: NSDecimalNumber(decimal: value))!)
      #expect(row.suffix == symbolFormatter.percentSymbol)
      let zero = RebalancingHelpPresentation.percentageRow("Zero", 0, locale: locale)
      #expect(zero.suffix == symbolFormatter.percentSymbol)
      #expect(!zero.value.contains("%"))
      let unavailable = RebalancingHelpPresentation.percentageRow(
        "Unavailable", nil, locale: locale)
      #expect(unavailable.value == "—" && unavailable.suffix == nil)
    }
  }

  @Test(
    "Minimum assessment distinguishes original denomination, conversion, missing values and zero")
  func minimum() {
    let input = RebalancingCategoryHelpInput(
      name: "Reserve", current: 50, minimum: 3000, minimumCurrency: "TWD", convertedMinimum: 100,
      status: .shortfall(50))
    let content = RebalancingHelpPresentation.minimum(
      input, currency: "USD", snapshotDate: Date(timeIntervalSince1970: 1_700_000_000),
      unavailableReason: nil)
    #expect(
      content.sections.flatMap(\.rows).map(\.value) == [
        "TWD 3,000.00", "USD 100.00", "USD 50.00", "USD 50.00",
      ])
    #expect(!content.sections.flatMap(\.notes).isEmpty)
    var unavailable = input
    unavailable.current = nil
    unavailable.convertedMinimum = nil
    unavailable.status = .unavailable
    let missing = RebalancingHelpPresentation.minimum(
      unavailable, currency: "USD", snapshotDate: nil, unavailableReason: "Missing snapshot rate")
    #expect(missing.sections.flatMap(\.rows).map(\.value) == ["TWD 3,000.00", "—", "—", "—"])
    #expect(missing.sections.flatMap(\.notes).contains("Missing snapshot rate"))
    var met = input
    met.current = 100
    met.status = .met
    let complete = RebalancingHelpPresentation.minimum(
      met, currency: "USD", snapshotDate: nil, unavailableReason: nil)
    #expect(complete.sections.flatMap(\.rows).last?.value == "USD 0.00")
  }
  @Test(
    "Currency compaction is per table, ignoring percentages and preserving unavailable currencies")
  func currencyCompaction() throws {
    let input = RebalancingCategoryHelpInput(
      name: "Reserve", current: Decimal(string: "1000.123456789")!, percentage: 10, minimum: 3000,
      minimumCurrency: "TWD", convertedMinimum: 100, status: .shortfall(50), target: 1050,
      difference: -50, share: 30)
    let mixed = RebalancingHelpPresentation.minimum(
      input, currency: "USD", snapshotDate: nil, unavailableReason: nil)
    #expect(mixed.sections.first?.title == nil)
    #expect(
      mixed.sections.first?.rows.map(\.value) == [
        "TWD 3,000.00", "USD 100.00", "USD 1,000.12", "USD 50.00",
      ])
    var missing = input
    missing.current = nil
    missing.minimum = nil
    missing.convertedMinimum = nil
    missing.status = .unavailable
    let unavailable = RebalancingHelpPresentation.minimum(
      missing, currency: "USD", snapshotDate: nil, unavailableReason: "Missing rate")
    #expect(unavailable.sections.first?.title == nil)
    #expect(unavailable.sections.first?.rows.allSatisfy { $0.value == "—" } == true)
    missing.minimumCurrency = "usd"
    let single = RebalancingHelpPresentation.minimum(
      missing, currency: "USD", snapshotDate: nil, unavailableReason: "Missing rate")
    #expect(single.sections.first?.title?.contains("USD") == true)
    #expect(single.sections.first?.rows.allSatisfy { $0.value == "—" } == true)

  }

  private func expectedNumber(_ value: Decimal, currency: String, locale: Locale) -> String {
    let assetFormatter = NumberFormatter()
    assetFormatter.locale = locale
    assetFormatter.numberStyle = .currency
    assetFormatter.currencyCode = currency
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = assetFormatter.minimumFractionDigits
    formatter.maximumFractionDigits = assetFormatter.maximumFractionDigits
    return formatter.string(from: NSDecimalNumber(decimal: value))!
  }

  @Test("Popup amounts use asset formatting precision in every locale and denomination")
  func assetDisplayPrecision() {
    let value = Decimal(string: "1234.56789123456789123456789")!
    for code in ["USD", "TWD", "JPY", "KWD", "BTC", "XYZ"] {
      for identifier in ["en_US", "zh_TW", "de_DE"] {
        let locale = Locale(identifier: identifier)
        let number = expectedNumber(value, currency: code, locale: locale)
        #expect(
          RebalancingHelpPresentation.monetaryValue(
            value, currency: code, locale: locale, includeCurrency: false) == number)
        #expect(
          RebalancingHelpPresentation.monetaryValue(value, currency: code, locale: locale)
            == "\(code) \(number)")
      }
    }
  }

  @Test("Signed changes and actual zero use rounded asset display values")
  func displaySignsAndZero() {
    let locale = Locale(identifier: "en_US")
    for value in [
      Decimal(0), Decimal(string: "50.126")!, Decimal(string: "-50.126")!,
      Decimal(string: "50.125")!, Decimal(string: "-50.125")!,
    ] {
      let number = expectedNumber(value, currency: "USD", locale: locale)
      let signed = (value > 0 ? "+" : "") + number
      #expect(
        RebalancingHelpPresentation.monetaryValue(
          value, currency: "USD", locale: locale, showPositiveSign: true, includeCurrency: false)
          == signed)
    }
  }

  @Test("Tiny nonzero amounts have bounds and changes retain their direction")
  func tinyBounds() {
    let locale = Locale(identifier: "en_US")
    let tiny = Decimal(string: "0.00000000000000000000000000000001")!
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        tiny, currency: "USD", locale: locale, includeCurrency: false) == "<0.01")
    #expect(
      RebalancingHelpPresentation.monetaryValue(tiny, currency: "USD", locale: locale)
        == "USD <0.01")
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        tiny, currency: "USD", locale: locale, showPositiveSign: true, includeCurrency: false)
        == String(format: String(localized: "Increase <%@", table: "Rebalancing"), "0.01"))
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        -tiny, currency: "USD", locale: locale, showPositiveSign: true, includeCurrency: false)
        == String(format: String(localized: "Decrease <%@", table: "Rebalancing"), "0.01"))
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        -tiny, currency: "USD", locale: locale, showPositiveSign: true)
        == String(format: String(localized: "Decrease <%@", table: "Rebalancing"), "USD 0.01"))
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        Decimal(string: "0.009")!, currency: "USD", locale: locale, includeCurrency: false)
        == "<0.01")
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        Decimal(string: "0.01")!, currency: "USD", locale: locale, includeCurrency: false) == "0.01"
    )
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        Decimal(string: "0.1")!, currency: "JPY", locale: locale, includeCurrency: false) == "<1")
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        Decimal(string: "0.0001")!, currency: "KWD", locale: locale, includeCurrency: false)
        == "<0.001")
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        tiny, currency: "USD", locale: Locale(identifier: "de_DE"), includeCurrency: false)
        == "<0,01")
    #expect(
      RebalancingHelpPresentation.monetaryValue(
        Decimal(string: "0.1")!, currency: "jpy", locale: locale, includeCurrency: false) == "<1")
  }

  @Test("Popup tables, shortfall explanations and blocked diagnostics share display precision")
  func computedPopupAmounts() throws {
    let third = Decimal(1) / 3
    let plan = RebalancingPlan(
      status: .feasible, protectedValue: third, availableValue: third, totalMinimum: third)
    let calculation = RebalancingHelpPresentation.calculation(
      assessment: CategoryGoalAssessment(totalValue: third * 2, plan: plan), currency: "USD")
    #expect(calculation.sections.first?.rows.map(\.value) == ["0.67", "0.33", "≈ 0.33"])
    let input = RebalancingCategoryHelpInput(
      name: "Reserve", current: 1, minimum: 2, minimumCurrency: "USD", status: .shortfall(third),
      target: 2, difference: third)
    for status in [
      RebalancingPlanStatus.minimumsExceedPortfolio(third), .insufficientAvailableFunds(third),
    ] {
      let blocked = RebalancingHelpPresentation.calculation(
        assessment: CategoryGoalAssessment(plan: RebalancingPlan(status: status)), currency: "USD")
      #expect(blocked.sections.flatMap(\.notes).first?.contains("USD 0.33") == true)
      #expect(blocked.sections.flatMap(\.notes).first?.contains("33333333") == false)
      // The presentation injection must not change exact diagnostics elsewhere.
      #expect(
        CategoryGoalPresentation.diagnostic(RebalancingPlan(status: status), currency: "USD")?
          .contains("33333333") == true)
    }
    let tiny = Decimal(string: "0.00000001")!
    var short = input
    short.status = .shortfall(tiny)
    let minimum = RebalancingHelpPresentation.minimum(
      short, currency: "USD", snapshotDate: nil, unavailableReason: nil)
    #expect(minimum.sections.first?.rows.last?.value == "<0.01")
    #expect(short.status == .shortfall(tiny))
    #expect(short.current == 1 && short.minimum == 2)
  }

}
