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

struct RebalancingHelpRow: Equatable {
  let label: String
  var value: String
  var currency: String?
  var numberValue: String?
  var formula: String?
  var isResult = false
  var suffix: String?
}

struct RebalancingHelpSection: Equatable {
  var title: String?
  var rows: [RebalancingHelpRow] = []
  var bullets: [String] = []
  var notes: [String] = []
}

struct RebalancingHelpContent: Equatable {
  let title: String
  var sections: [RebalancingHelpSection] = []
}

struct RebalancingCategoryHelpInput {
  var name: String
  var current: Decimal?
  var percentage: Decimal?
  var minimum: Decimal?
  var minimumCurrency: String?
  var convertedMinimum: Decimal?
  var status: MinimumBalanceStatus = .notSet
  var target: Decimal?
  var difference: Decimal?
  var share: Decimal?
  var minimumIsBinding = false
}

@MainActor
enum RebalancingHelpPresentation {
  /// Display precision follows the asset formatter; arithmetic inputs stay untouched.
  static func monetaryValue(
    _ value: Decimal, currency: String, locale: Locale = .current,
    showPositiveSign: Bool = false, includeCurrency: Bool = true
  ) -> String {
    let code = currency.uppercased()
    let unit = Decimal.currencyDisplayUnit(currency: code, locale: locale)
    if value != 0 && abs(value) < unit {
      let threshold = unit.formattedCurrencyNumber(currency: code, locale: locale)
      if showPositiveSign || value < 0 {
        let amount = includeCurrency ? "\(code) \(threshold)" : threshold
        return value > 0
          ? String(localized: "Increase <\(amount)", table: "Rebalancing", locale: locale)
          : String(localized: "Decrease <\(amount)", table: "Rebalancing", locale: locale)
      }
      return includeCurrency ? "\(code) <\(threshold)" : "<\(threshold)"
    }
    let prefix = showPositiveSign && value > 0 ? "+" : ""
    let number = prefix + value.formattedCurrencyNumber(currency: code, locale: locale)
    return includeCurrency ? "\(code) \(number)" : number
  }

  static func unavailableReason(assessment: CategoryGoalAssessment, currency: String) -> String? {
    assessment.assetConversion.unavailableMessage ?? assessment.goalConversion.unavailableMessage
      ?? CategoryGoalPresentation.diagnostic(
        assessment.plan, currency: currency, formatAmount: { monetaryValue($0, currency: currency) }
      )
  }

  static func calculation(assessment: CategoryGoalAssessment, currency: String)
    -> RebalancingHelpContent
  {
    var content = RebalancingHelpContent(title: String(localized: "Calculation details"))
    guard let plan = assessment.plan, plan.status == .feasible else {
      let reason =
        unavailableReason(assessment: assessment, currency: currency)
        ?? String(localized: "Add a snapshot to calculate rebalancing from your category goals.")
      content.sections = [RebalancingHelpSection(notes: [reason])]
      return content
    }
    let totalIsRounded = assessment.totalValue.map { moneyIsRounded($0, currency) } ?? false
    var rows = [
      row(String(localized: "(A) Portfolio total"), assessment.totalValue, currency),
      row(String(localized: "(B) Protected amount"), plan.protectedValue, currency),
      row(
        String(localized: "(C) Available for percentage targets"), plan.availableValue, currency,
        formula: "(A) − (B)", isResult: true,
        approximate: totalIsRounded
          || moneyIsRounded(plan.protectedValue, currency)
          || moneyIsRounded(plan.availableValue, currency)),
    ]
    let allocation = allocationBasis(plan)
    if allocation.fixed > 0 {
      rows.append(
        row(String(localized: "(D) Targets fixed at minimums"), allocation.fixed, currency))
      rows.append(
        row(
          String(localized: "(E) Remaining allocation amount"), allocation.remaining, currency,
          formula: "(C) − (D)", isResult: true,
          approximate: moneyIsRounded(plan.availableValue, currency)
            || moneyIsRounded(allocation.fixed, currency)
            || moneyIsRounded(allocation.remaining, currency)))
    }
    content.sections = [
      RebalancingHelpSection(title: String(localized: "Allocation basis"), rows: rows),
      RebalancingHelpSection(
        title: String(localized: "How allocation works"),
        bullets: [
          String(
            localized:
              "Protect uncategorized holdings and categories without percentage targets. Minimum-only categories retain the greater of their balance and minimum."
          ),
          String(localized: "Distribute the available amount using configured percentage weights."),
          String(
            localized:
              "Fix targets that would fall below their minimums at those minimums, then redistribute the remainder proportionally. Repeat when necessary."
          ),
          String(
            localized: "Effective target % = effective target balance ÷ portfolio total × 100."),
        ]),
    ]
    return compactCurrencies(content)
  }

  static func category(
    _ input: RebalancingCategoryHelpInput, diagnostic: String?, currency: String,
    assessment: CategoryGoalAssessment? = nil
  ) -> RebalancingHelpContent {
    if let diagnostic {
      return RebalancingHelpContent(
        title: input.name, sections: [RebalancingHelpSection(notes: [diagnostic])])
    }
    if input.percentage == nil && input.minimum == nil {
      return RebalancingHelpContent(
        title: input.name,
        sections: [
          RebalancingHelpSection(notes: [
            String(localized: "No percentage target is set; the current balance is retained.")
          ])
        ])
    }
    guard let assessment, let plan = assessment.plan, plan.status == .feasible,
      let total = assessment.totalValue, let target = input.target
    else {
      let reason =
        assessment.flatMap { unavailableReason(assessment: $0, currency: currency) }
        ?? String(localized: "Add a snapshot to calculate rebalancing from your category goals.")
      return RebalancingHelpContent(
        title: input.name, sections: [RebalancingHelpSection(notes: [reason])])
    }
    var rows: [RebalancingHelpRow] = []
    var notes: [String] = []
    let targetLetter: String
    let totalLetter: String
    var approximateInputs = false
    if input.percentage == nil, let current = input.current, let minimum = input.convertedMinimum {
      notes.append(
        String(
          localized:
            "Without a percentage target, retain the greater of the current balance and minimum."))
      approximateInputs = moneyIsRounded(current, currency) || moneyIsRounded(minimum, currency)
      rows = [
        row(String(localized: "(A) Current balance"), current, currency),
        row(String(localized: "(B) Minimum in display currency"), minimum, currency),
        row(
          String(localized: "(C) Effective target balance"), target, currency,
          formula: "max((A), (B))",
          isResult: true, approximate: approximateInputs || moneyIsRounded(target, currency)),
        row(String(localized: "(D) Portfolio total"), total, currency),
      ]
      targetLetter = "C"
      totalLetter = "D"
    } else if input.minimumIsBinding, let minimum = input.convertedMinimum {
      notes.append(String(localized: "The minimum determines the effective target."))
      approximateInputs = moneyIsRounded(minimum, currency)
      rows = [
        row(String(localized: "(A) Minimum in display currency"), minimum, currency),
        row(
          String(localized: "Effective target balance"), target, currency, formula: "(A)",
          isResult: true,
          approximate: approximateInputs || moneyIsRounded(target, currency)),
        row(String(localized: "(B) Portfolio total"), total, currency),
      ]
      targetLetter = "A"
      totalLetter = "B"
    } else if input.percentage == 0 {
      notes.append(
        String(
          localized: "A 0% target assigns only the minimum balance, or zero when no minimum is set."
        ))
      rows = [
        percentageRow(String(localized: "(A) Configured target %"), 0),
        row(
          String(localized: "(B) Effective target balance"), target, currency, isResult: true,
          approximate: moneyIsRounded(target, currency)),
        row(String(localized: "(C) Portfolio total"), total, currency),
      ]
      targetLetter = "B"
      totalLetter = "C"
    } else if let percentage = input.percentage {
      let allocation = allocationBasis(plan)
      guard allocation.weight > 0 else {
        return RebalancingHelpContent(
          title: input.name,
          sections: [
            RebalancingHelpSection(notes: [
              String(
                localized:
                  "Rebalancing is unavailable because the portfolio data or goal configuration is invalid.",
                table: "Rebalancing")
            ])
          ])
      }
      notes.append(
        String(
          localized:
            "The remaining allocation amount is shared proportionally after targets fixed at minimums have been accounted for."
        ))
      approximateInputs =
        moneyIsRounded(allocation.remaining, currency) || isRounded(percentage, digits: 2)
        || isRounded(allocation.weight, digits: 2)
      rows = [
        percentageRow(String(localized: "(A) Configured target %"), percentage),
        row(String(localized: "(B) Remaining allocation amount"), allocation.remaining, currency),
        percentageRow(
          String(localized: "(C) Combined configured target % of remaining categories"),
          allocation.weight),
        row(
          String(localized: "(D) Effective target balance"), target, currency,
          formula: "(B) × (A) ÷ (C)",
          isResult: true, approximate: approximateInputs || moneyIsRounded(target, currency)),
        row(String(localized: "(E) Portfolio total"), total, currency),
      ]
      targetLetter = "D"
      totalLetter = "E"
    } else {
      return RebalancingHelpContent(title: input.name)
    }
    let share = total > 0 ? target / total * 100 : nil
    let approximateShare =
      share.map {
        isRounded($0, digits: 2) || moneyIsRounded(target, currency)
          || moneyIsRounded(total, currency) || approximateInputs
      } ?? false
    rows.append(
      percentageRow(
        String(localized: "Effective target %"), share, approximate: approximateShare,
        formula: total > 0 ? "(\(targetLetter)) ÷ (\(totalLetter)) × 100" : nil, isResult: true))
    if total == 0 {
      notes.append(
        String(localized: "Effective target % is unavailable because the portfolio total is zero."))
    }
    return compactCurrencies(
      RebalancingHelpContent(
        title: input.name,
        sections: [
          RebalancingHelpSection(notes: notes),
          RebalancingHelpSection(title: String(localized: "Target calculation"), rows: rows),
        ]))
  }

  static func percentageRow(
    _ label: String, _ value: Decimal?, approximate: Bool = false,
    formula: String? = nil, isResult: Bool = false, locale: Locale = .current
  ) -> RebalancingHelpRow {
    guard let value else {
      return RebalancingHelpRow(label: label, value: "—", formula: formula, isResult: isResult)
    }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .percent
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let symbol = formatter.percentSymbol ?? "%"
    // Let Foundation format the number, omitting its unit without parsing values.
    formatter.percentSymbol = ""
    let number =
      formatter.string(from: NSDecimalNumber(decimal: value / 100))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(value)"
    return RebalancingHelpRow(
      label: label, value: (approximate ? "≈ " : "") + number,
      formula: formula, isResult: isResult, suffix: symbol)
  }

  /// Use the final plan, including constraints discovered in later allocation passes.
  /// Exact minimum ties can be removed from the proportional group without changing its ratio.
  private static func allocationBasis(_ plan: RebalancingPlan) -> (
    fixed: Decimal, remaining: Decimal, weight: Decimal
  ) {
    let percentageTargets = plan.targets.filter { $0.allocation.percentage != nil }.sorted {
      $0.id.uuidString < $1.id.uuidString
    }
    let fixed = percentageTargets.filter { $0.minimumIsBinding || $0.allocation.percentage == 0 }
      .reduce(Decimal(0)) { $0 + $1.targetValue }
    let weight = percentageTargets.filter {
      !$0.minimumIsBinding && ($0.allocation.percentage ?? 0) > 0
    }
    .reduce(Decimal(0)) { $0 + ($1.allocation.percentage ?? 0) }
    return (fixed, plan.availableValue - fixed, weight)
  }

  private static func isRounded(_ value: Decimal, digits: Int) -> Bool {
    var value = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, digits, .bankers)
    return rounded != value
  }

  private static func moneyIsRounded(_ value: Decimal, _ currency: String) -> Bool {
    isRounded(
      value, digits: max(0, -Decimal.currencyDisplayUnit(currency: currency.uppercased()).exponent))
  }

  static func minimum(
    _ input: RebalancingCategoryHelpInput, currency: String, snapshotDate: Date?,
    unavailableReason: String?
  ) -> RebalancingHelpContent {
    var rows = [
      row(String(localized: "Required minimum"), input.minimum, input.minimumCurrency ?? currency)
    ]
    if let originalCurrency = input.minimumCurrency,
      originalCurrency.caseInsensitiveCompare(currency) != .orderedSame
    {
      rows.append(
        row(String(localized: "Minimum in display currency"), input.convertedMinimum, currency))
    }
    rows.append(row(String(localized: "Current balance"), input.current, currency))
    let shortfall: Decimal?
    switch input.status {
    case .shortfall(let amount): shortfall = amount
    case .met: shortfall = 0
    default: shortfall = nil
    }
    rows.append(row(String(localized: "Shortfall"), shortfall, currency))
    var notes: [String] = []
    if input.status == .unavailable || input.status == .noSnapshot {
      notes.append(
        unavailableReason
          ?? CategoryGoalPresentation.minimumStatus(input.status, currency: currency))
    }
    if let snapshotDate {
      notes.append(
        String(localized: "Assessed using snapshot: \(snapshotDate.settingsFormatted())."))
    }
    return compactCurrencies(
      RebalancingHelpContent(
        title: String(localized: "Minimum balance"),
        sections: [
          RebalancingHelpSection(rows: rows), RebalancingHelpSection(notes: notes),
        ].filter { !$0.rows.isEmpty || !$0.notes.isEmpty }))
  }

  /// Decide using intended monetary currencies, even when a value is unavailable.
  /// Percentage and explanatory rows never participate in this per-table decision.
  private static func compactCurrencies(_ input: RebalancingHelpContent) -> RebalancingHelpContent {
    var content = input
    content.sections = content.sections.map { original in
      let currencies = Set(original.rows.compactMap(\.currency))
      guard currencies.count == 1, let currency = currencies.first else { return original }
      var section = original
      let title = section.title ?? String(localized: "Assessment")
      section.title = String(localized: "\(title) (\(currency))")
      section.rows = section.rows.map { row in
        guard row.currency != nil else { return row }
        var compact = row
        compact.value = row.numberValue ?? "—"
        return compact
      }
      return section
    }
    return content
  }

  private static func row(
    _ label: String, _ amount: Decimal?, _ currency: String, showPositiveSign: Bool = false,
    formula: String? = nil,
    isResult: Bool = false, approximate: Bool = false
  ) -> RebalancingHelpRow {
    let usesBound =
      amount.map {
        $0 != 0 && abs($0) < Decimal.currencyDisplayUnit(currency: currency.uppercased())
      } ?? false
    let prefix = approximate && !usesBound ? "≈ " : ""
    return RebalancingHelpRow(
      label: label,
      value: amount.map {
        prefix + monetaryValue($0, currency: currency, showPositiveSign: showPositiveSign)
      } ?? "—",
      currency: currency.uppercased(),
      numberValue: amount.map {
        prefix
          + monetaryValue(
            $0, currency: currency, showPositiveSign: showPositiveSign, includeCurrency: false)
      } ?? "—",
      formula: formula, isResult: isResult)
  }
}
