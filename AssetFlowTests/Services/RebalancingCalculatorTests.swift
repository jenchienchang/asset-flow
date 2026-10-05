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

@Suite("RebalancingCalculator Tests")
@MainActor
struct RebalancingCalculatorTests {
  private func row(
    _ number: Int, _ value: Decimal, _ percentage: Decimal? = nil, _ minimum: Decimal? = nil
  ) -> CategoryGoalAllocation {
    CategoryGoalAllocation(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
      name: "Category \(number)", currentValue: value, percentage: percentage, minimum: minimum)
  }

  @Test("Minimum takes priority and preserves proportions of flexible weights")
  func example() throws {
    let rows = [row(1, 200000, 10, 300000), row(2, 600000, 60), row(3, 200000, 30)]
    let plan = RebalancingCalculator.calculate(categories: rows, totalValue: 1_000_000)
    #expect(plan.status == .feasible)
    let reserve = try #require(plan.targets.first { $0.id == rows[0].id })
    #expect(reserve.targetValue == 300000)
    #expect(reserve.minimumIsBinding)
    let equity = try #require(plan.targets.first { $0.id == rows[1].id })
    #expect(abs(equity.targetValue - Decimal(1_400_000) / 3) < Decimal(string: "0.000000000001")!)
    #expect(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } == 1_000_000)
  }

  @Test("Protected holdings and minimum-only surplus are unchanged")
  func protected() {
    let rows = [row(1, 200, nil, 100), row(2, 100), row(3, 500, 100)]
    let plan = RebalancingCalculator.calculate(
      categories: rows, totalValue: 1000, uncategorizedValue: 200)
    #expect(plan.status == .feasible)
    #expect(plan.protectedValue == 500)
    #expect(plan.availableValue == 500)
    #expect(plan.targets.first { $0.id == rows[0].id }?.targetValue == 200)
    #expect(plan.targets.first { $0.id == rows[0].id }?.minimumIsBinding == false)
  }

  @Test("Minimum-only top-up is funded from percentage allocation")
  func minimumOnly() {
    let plan = RebalancingCalculator.calculate(
      categories: [row(1, 200, nil, 300), row(2, 800, 100)], totalValue: 1000)
    #expect(plan.status == .feasible)
    #expect(plan.targets.map(\.targetValue).sorted() == [300, 700])
    let blocked = RebalancingCalculator.calculate(
      categories: [row(1, 200, nil, 300), row(2, 800)], totalValue: 1000)
    #expect(blocked.status == .insufficientAvailableFunds(100))
    #expect(blocked.targets.isEmpty)
  }

  @Test("Global shortfall and protected-funds shortfall are distinct")
  func infeasible() {
    let global = RebalancingCalculator.calculate(
      categories: [row(1, 200, 50, 300), row(2, 200, 50, 200)], totalValue: 400)
    #expect(global.status == .minimumsExceedPortfolio(100))
    #expect(global.totalMinimum == 500)
    #expect(global.targets.isEmpty)
    let protected = RebalancingCalculator.calculate(
      categories: [row(1, 200), row(2, 300, 100, 400)], totalValue: 500)
    #expect(protected.status == .insufficientAvailableFunds(100))
    #expect(protected.targets.isEmpty)
  }

  @Test("Multiple iterations, zero weight, and exact feasibility boundary")
  func binding() {
    let plan = RebalancingCalculator.calculate(
      categories: [row(1, 10, 10, 50), row(2, 20, 20, 20), row(3, 70, 70)], totalValue: 100)
    #expect(plan.status == .feasible)
    #expect(plan.targets.map(\.targetValue).sorted() == [20, 30, 50])
    let zero = RebalancingCalculator.calculate(
      categories: [row(1, 50, 0, 40), row(2, 50, 100, 60)], totalValue: 100)
    #expect(zero.status == .feasible)
    #expect(zero.targets.map(\.targetValue).sorted() == [40, 60])
  }

  @Test("Incomplete percentage plans and invalid inputs have no targets")
  func invalid() {
    for percentage in [Decimal(0), 30, 99, 101] {
      let plan = RebalancingCalculator.calculate(
        categories: [row(1, 100, percentage)], totalValue: 100)
      #expect(plan.status == (percentage > 100 ? .invalidData : .invalidPercentageSum(percentage)))
      #expect(plan.targets.isEmpty)
    }
    for rows in [
      [row(1, -1, 100)], [row(1, 100, 100, .nan)], [row(1, 50, 50), row(1, 50, 50)],
      [row(1, 99, 100)],
    ] {
      #expect(
        RebalancingCalculator.calculate(categories: rows, totalValue: 100).status == .invalidData)
    }
  }

  @Test("Zero portfolio still reports positive minimums; no goals is distinct")
  func zero() {
    #expect(
      RebalancingCalculator.calculate(categories: [row(1, 0, 100, 10)], totalValue: 0).status
        == .minimumsExceedPortfolio(10))
    #expect(
      RebalancingCalculator.calculate(categories: [row(1, 0, 100)], totalValue: 0).status
        == .feasible)
    #expect(
      RebalancingCalculator.calculate(categories: [], totalValue: 100, uncategorizedValue: 100)
        .status == .noGoals)
    #expect(
      RebalancingCalculator.calculate(categories: [row(1, 100, nil, 0)], totalValue: 100).status
        == .feasible)
  }

  @Test("Generated plans conserve funds, respect floors and are permutation independent")
  func invariants() {
    for amount in 1...50 {
      let rows = [
        row(1, Decimal(amount), 10, Decimal(amount * 2)), row(2, Decimal(amount * 4), 40),
        row(3, Decimal(amount * 5), 50),
      ]
      let total = Decimal(amount * 10)
      let plan = RebalancingCalculator.calculate(categories: rows, totalValue: total)
      let reversed = RebalancingCalculator.calculate(categories: rows.reversed(), totalValue: total)
      #expect(plan.status == .feasible)
      #expect(plan == reversed)
      #expect(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } == total)
      #expect(plan.targets.allSatisfy { $0.targetValue >= ($0.allocation.minimum ?? 0) })
    }
  }
  @Test("Unconstrained baseline, tiny minimums, and checked overflow")
  func precisionBoundaries() {
    let baseline = RebalancingCalculator.calculate(
      categories: [row(1, 70, 50), row(2, 30, 50)], totalValue: 100)
    #expect(baseline.status == .feasible)
    #expect(baseline.targets.first { $0.id == row(1, 0).id }?.difference == -20)
    let tiny = Decimal(string: "0.00000000000000000001")!
    let insufficient = RebalancingCalculator.calculate(
      categories: [row(1, 0, 100, tiny)], totalValue: 0)
    #expect(insufficient.status == .minimumsExceedPortfolio(tiny))
    let huge = Decimal(sign: .plus, exponent: 127, significand: 9)
    #expect(
      RebalancingCalculator.calculate(
        categories: [row(1, huge, 50), row(2, huge, 50)], totalValue: huge
      ).status == .invalidData)
    #expect(
      RebalancingCalculator.calculate(categories: [row(1, 100, 100, 101)], totalValue: 100).targets
        .isEmpty)
  }

  // Synthetic converted balances reproduce the precision pattern of legacy multi-currency portfolios.
  private func convertedRows() -> [CategoryGoalAllocation] {
    let balances = [
      "895.4924410885819264143105797808062018", "43785.7167286731593293223462653601175",
      "733.6529826130254961537289013992907008", "49716.27880704306037806737453431813079",
      "1060.7984745672024741893464937266989675", "54008.34661403292402067419681573849034",
    ]
    let weights: [Decimal] = [35, 20, 15, 15, 10, 5]
    return balances.enumerated().map {
      row($0.offset + 1, Decimal(string: $0.element)!, weights[$0.offset])
    }
  }

  @Test("Converted balances tolerate addition precision loss even when totals match")
  func convertedAdditionPrecision() {
    let rows = convertedRows()
    let total = rows.reduce(Decimal(0)) { $0 + $1.currentValue }
    let plan = RebalancingCalculator.calculate(categories: rows, totalValue: total)
    #expect(plan.status == .feasible)
    #expect(plan == RebalancingCalculator.calculate(categories: rows.reversed(), totalValue: total))
    #expect(
      abs(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } - total)
        <= RebalancingCalculator.arithmeticTolerance(total: total))
  }

  @Test("Independently converted total tolerates a negligible regrouping difference")
  func convertedRegroupingPrecision() {
    let rows = convertedRows()
    let total = Decimal(string: "150200.286048017953624821303590323534497")!
    let plan = RebalancingCalculator.calculate(categories: rows, totalValue: total)
    #expect(plan.status == .feasible)
    #expect(plan.targets.count == rows.count)
    #expect(plan.targets.allSatisfy { $0.targetValue >= 0 })
    #expect(
      abs(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } - total)
        <= RebalancingCalculator.arithmeticTolerance(total: total))
  }

  @Test("Consistency tolerance accepts either sign but rejects material mismatches")
  func consistencyTolerance() {
    let rows = [row(1, 50, 50), row(2, 50, 50)]
    let tiny = Decimal(string: "0.000000000000000000000000001")!
    let material = Decimal(string: "0.000000000000000000000001")!
    for sign in [Decimal(-1), 1] {
      #expect(
        RebalancingCalculator.calculate(categories: rows, totalValue: 100 + sign * tiny).status
          == .feasible)
      let invalid = RebalancingCalculator.calculate(
        categories: rows, totalValue: 100 + sign * material)
      #expect(invalid.status == .invalidData)
      #expect(invalid.targets.isEmpty)
    }
  }

  @Test("Arithmetic tolerance never excuses a real minimum funding deficit")
  func strictMinimumBoundary() {
    let tiny = Decimal(string: "0.000000000000000000000000001")!
    let global = RebalancingCalculator.calculate(
      categories: [row(1, 1, 100, 1 + tiny)], totalValue: 1)
    #expect(global.status == .minimumsExceedPortfolio(tiny))
    let protected = RebalancingCalculator.calculate(
      categories: [row(1, 1), row(2, 0, 100, tiny)], totalValue: 1)
    #expect(protected.status == .insufficientAvailableFunds(tiny))
    #expect(global.targets.isEmpty && protected.targets.isEmpty)
    let bound = RebalancingCalculator.calculate(
      categories: [row(1, 1, 50, 1), row(2, 1, 50, 1)], totalValue: 2)
    #expect(bound.status == .feasible)
    #expect(bound.targets.allSatisfy { $0.targetValue == 1 && $0.minimumIsBinding })
  }

  @Test("Converted balances preserve protected holdings and binding minimums")
  func convertedFinancialConstraints() {
    var rows = convertedRows()
    rows[0].percentage = nil
    rows[0].minimum = 100
    rows[1].percentage = 55
    rows[1].minimum = 100000
    let total = rows.reduce(Decimal(0)) { $0 + $1.currentValue }
    let plan = RebalancingCalculator.calculate(categories: rows, totalValue: total)
    #expect(plan.status == .feasible)
    #expect(plan.targets.first { $0.id == rows[0].id }?.targetValue == rows[0].currentValue)
    #expect(plan.targets.first { $0.id == rows[1].id }?.targetValue == 100000)
    #expect(plan.targets.first { $0.id == rows[1].id }?.minimumIsBinding == true)
    #expect(plan.targets.allSatisfy { $0.targetValue >= ($0.allocation.minimum ?? 0) })
    #expect(
      abs(plan.targets.reduce(Decimal(0)) { $0 + $1.targetValue } - total)
        <= RebalancingCalculator.arithmeticTolerance(total: total))
  }

  @Test("Percentage validation never rounds away an excess above 100 percent")
  func exactPercentageSum() {
    let tiny = Decimal(sign: .plus, exponent: -37, significand: 1)
    let plan = RebalancingCalculator.calculate(
      categories: [row(1, 100, 100), row(2, 0, tiny)], totalValue: 100)
    #expect(plan.status == .invalidData)
    #expect(plan.targets.isEmpty)
  }

  @Test("Precision loss cannot erase a mandatory funding requirement")
  func exactFundingRequirements() {
    let tiny = Decimal(sign: .plus, exponent: -37, significand: 1)
    let global = RebalancingCalculator.calculate(
      categories: [row(1, 100, 50, 100), row(2, 0, 50, tiny)], totalValue: 100)
    let protected = RebalancingCalculator.calculate(
      categories: [row(1, 100), row(2, 0, 100, tiny)], totalValue: 100)
    // Preserve the conservative existing outcome when the exact required sum cannot
    // be represented: unavailable, rather than claiming an unfunded plan is feasible.
    #expect(global.status == .invalidData)
    #expect(protected.status == .invalidData)
    #expect(global.targets.isEmpty && protected.targets.isEmpty)
    // Rounded requirement sums remain usable when the funding answer is unambiguous.
    let funded = RebalancingCalculator.calculate(
      categories: [row(1, 200, 50, 100), row(2, 0, 50, tiny)], totalValue: 200)
    #expect(funded.status == .feasible)
    #expect(funded.targets.allSatisfy { $0.targetValue >= ($0.allocation.minimum ?? 0) })
    let unfunded = RebalancingCalculator.calculate(
      categories: [row(1, 99, 50, 100), row(2, 0, 50, tiny)], totalValue: 99)
    #expect(unfunded.status == .minimumsExceedPortfolio(1))
    #expect(unfunded.targets.isEmpty)
  }

  @Test("Invalid numbers, overflow and underflow remain unavailable")
  func arithmeticErrors() {
    let tiny = Decimal(sign: .plus, exponent: -127, significand: 1)
    let underflow = RebalancingCalculator.calculate(
      categories: [row(1, tiny, 1), row(2, 0, 99)], totalValue: tiny)
    #expect(underflow.status == .invalidData)
    #expect(underflow.targets.isEmpty)
    for total in [Decimal.nan, -1] {
      #expect(
        RebalancingCalculator.calculate(categories: [row(1, 1, 100)], totalValue: total).status
          == .invalidData)
    }
    #expect(
      RebalancingCalculator.calculate(
        categories: [row(1, 1, 100)], totalValue: 1, uncategorizedValue: .nan
      ).status == .invalidData)
  }

}
