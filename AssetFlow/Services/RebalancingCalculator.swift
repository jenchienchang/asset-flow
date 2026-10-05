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

enum RebalancingActionType { case buy, sell, noAction }

struct CategoryGoalAllocation: Equatable {
  let id: UUID
  let name: String
  let currentValue: Decimal
  var percentage: Decimal?
  var minimum: Decimal?
}

enum RebalancingPlanStatus: Equatable {
  case feasible
  case noGoals
  case invalidData
  case invalidPercentageSum(Decimal)
  case minimumsExceedPortfolio(Decimal)
  case insufficientAvailableFunds(Decimal)
}

struct CategoryGoalTarget: Identifiable, Equatable {
  let allocation: CategoryGoalAllocation
  let targetValue: Decimal
  let minimumIsBinding: Bool
  var id: UUID { allocation.id }
  var difference: Decimal { targetValue - allocation.currentValue }
  var minimumShortfall: Decimal { max(0, (allocation.minimum ?? 0) - allocation.currentValue) }
}

struct RebalancingPlan: Equatable {
  var status: RebalancingPlanStatus
  var targets: [CategoryGoalTarget] = []
  var protectedValue: Decimal = 0
  var availableValue: Decimal = 0
  var totalMinimum: Decimal = 0
  var percentageSum: Decimal?
}

/// Closed-portfolio allocation with protected holdings and mandatory category minimums.
enum RebalancingCalculator {
  static func arithmeticTolerance(total: Decimal) -> Decimal {
    max(total, 1) * Decimal(sign: .plus, exponent: -28, significand: 1)
  }

  static func calculate(
    categories: [CategoryGoalAllocation], totalValue: Decimal, uncategorizedValue: Decimal = 0
  ) -> RebalancingPlan {
    do {
      return try allocate(
        categories: categories, total: totalValue, uncategorized: uncategorizedValue)
    } catch {
      return RebalancingPlan(status: .invalidData)
    }
  }
}

extension RebalancingCalculator {
  fileprivate enum ArithmeticError: Error { case invalid }

  fileprivate static func add(_ lhs: Decimal, _ rhs: Decimal, requireExact: Bool = false) throws
    -> Decimal
  {
    var lhs = lhs
    var rhs = rhs
    var result = Decimal()
    let status = NSDecimalAdd(&result, &lhs, &rhs, .plain)
    // Balance arithmetic may round at Decimal's finite precision limit. Percentage
    // sums require exact arithmetic; funding comparisons use a conservative error bound below.
    guard status == .noError || (!requireExact && status == .lossOfPrecision), result.isFinite
    else {
      throw ArithmeticError.invalid
    }
    return result
  }

  fileprivate static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
    try add(lhs, -rhs)
  }

  fileprivate static func portion(_ value: Decimal, weight: Decimal, sum: Decimal) throws -> Decimal
  {
    var weight = weight
    var sum = sum
    var ratio = Decimal()
    let division = NSDecimalDivide(&ratio, &weight, &sum, .plain)
    guard division == .noError || division == .lossOfPrecision else {
      throw ArithmeticError.invalid
    }
    var value = value
    var result = Decimal()
    let product = NSDecimalMultiply(&result, &value, &ratio, .plain)
    guard product == .noError || product == .lossOfPrecision, result.isFinite else {
      throw ArithmeticError.invalid
    }
    return result
  }

  fileprivate static func sum(_ values: [Decimal], requireExact: Bool = false) throws -> Decimal {
    try values.reduce(Decimal(0)) { try add($0, $1, requireExact: requireExact) }
  }

  /// Preserve strict funding decisions when nonnegative requirements need rounding.
  fileprivate static func requiredTotal(_ values: [Decimal], budget: Decimal) throws -> Decimal {
    let total = try sum(values)
    // The first pass has already rejected overflow, underflow and invalid results.
    // Failure of this exact pass therefore means precision loss only.
    if (try? sum(values, requireExact: true)) != nil { return total }

    // Decimal retains at least 38 significant decimal digits. Allow one conservative
    // relative unit (1e-37) per addition, using a scale of at least one. A funding
    // decision is safe only when the budget is outside this accumulated error bound.
    // Do not rely on NSDecimalAdd's rounding mode to bound operand normalization:
    // it may discard digits while aligning operands even for .up/.down.
    let errorBound =
      max(max(total, budget), 1)
      * Decimal(sign: .plus, exponent: -37, significand: 1) * Decimal(values.count)
    guard errorBound.isFinite, abs(try subtract(total, budget)) > errorBound else {
      throw ArithmeticError.invalid
    }
    return total
  }

  fileprivate static func allocate(
    categories input: [CategoryGoalAllocation], total: Decimal, uncategorized: Decimal
  ) throws -> RebalancingPlan {
    let categories = input.sorted { $0.id.uuidString < $1.id.uuidString }
    try validate(categories: categories, total: total, uncategorized: uncategorized)
    let minimum = try requiredTotal(categories.map { $0.minimum ?? 0 }, budget: total)
    let percentageCategories = categories.filter { $0.percentage != nil }
    let percentageSum = try sum(percentageCategories.map { $0.percentage ?? 0 }, requireExact: true)
    let protectedRequirements =
      [uncategorized]
      + categories.filter { $0.percentage == nil }.map { max($0.currentValue, $0.minimum ?? 0) }
    let protected = try requiredTotal(protectedRequirements, budget: total)
    let available = try subtract(total, protected)
    var plan = RebalancingPlan(
      status: .feasible, protectedValue: protected, availableValue: available,
      totalMinimum: minimum, percentageSum: percentageCategories.isEmpty ? nil : percentageSum)
    if minimum > total {
      plan.status = .minimumsExceedPortfolio(try subtract(minimum, total))
      return plan
    }
    let floors = percentageCategories.map { $0.minimum ?? 0 }
    // Compare original components so rounded subtotals cannot hide requirements.
    let required = try requiredTotal(protectedRequirements + floors, budget: total)
    if required > total {
      plan.status = .insufficientAvailableFunds(try subtract(required, total))
      return plan
    }
    if !percentageCategories.isEmpty && percentageSum != 100 {
      plan.status = .invalidPercentageSum(percentageSum)
      return plan
    }
    if categories.allSatisfy({ $0.percentage == nil && $0.minimum == nil }) {
      plan.status = .noGoals
      return plan
    }
    let allocation = try targetBalances(categories: categories, available: available)
    var targets = allocation.values
    let binding = allocation.binding
    try reconcile(
      targets: &targets, binding: binding, categories: categories, total: total,
      uncategorized: uncategorized)
    plan.targets = categories.map {
      CategoryGoalTarget(
        allocation: $0, targetValue: targets[$0.id] ?? $0.currentValue,
        minimumIsBinding: binding.contains($0.id))
    }.sorted {
      if abs($0.difference) != abs($1.difference) { return abs($0.difference) > abs($1.difference) }
      return $0.id.uuidString < $1.id.uuidString
    }
    guard plan.targets.allSatisfy({ $0.targetValue >= ($0.allocation.minimum ?? 0) }) else {
      throw ArithmeticError.invalid
    }
    return plan
  }
  fileprivate static func validate(
    categories: [CategoryGoalAllocation], total: Decimal, uncategorized: Decimal
  ) throws {
    guard total.isFinite, total >= 0, uncategorized.isFinite, uncategorized >= 0,
      Set(categories.map(\.id)).count == categories.count
    else { throw ArithmeticError.invalid }
    for category in categories {
      guard category.currentValue.isFinite, category.currentValue >= 0 else {
        throw ArithmeticError.invalid
      }
      try CategoryGoalValidator.validate(
        percentage: category.percentage, minimum: category.minimum,
        currency: category.minimum == nil ? nil : "USD")
    }
    // Conversion and regrouping can change the last Decimal digits. This tolerance
    // validates arithmetic consistency only; funding and minimum checks stay strict.
    let groupedTotal = try add(sum(categories.map(\.currentValue)), uncategorized)
    guard abs(try subtract(groupedTotal, total)) <= arithmeticTolerance(total: total) else {
      throw ArithmeticError.invalid
    }
  }

  fileprivate static func targetBalances(categories: [CategoryGoalAllocation], available: Decimal)
    throws -> (values: [UUID: Decimal], binding: Set<UUID>)
  {
    let percentageCategories = categories.filter { $0.percentage != nil }
    var targets: [UUID: Decimal] = [:]
    var binding: Set<UUID> = []
    for category in categories where category.percentage == nil || category.percentage == 0 {
      targets[category.id] =
        category.percentage == nil
        ? max(category.currentValue, category.minimum ?? 0) : (category.minimum ?? 0)
      if let minimum = category.minimum, targets[category.id] == minimum {
        binding.insert(category.id)
      }
    }
    var remaining = try subtract(
      available, sum(percentageCategories.filter { $0.percentage == 0 }.map { $0.minimum ?? 0 }))
    var flexible = percentageCategories.filter { ($0.percentage ?? 0) > 0 }
    while !flexible.isEmpty {
      let weights = try sum(flexible.map { $0.percentage ?? 0 }, requireExact: true)
      var proposed: [UUID: Decimal] = [:]
      for category in flexible {
        proposed[category.id] = try portion(
          remaining, weight: category.percentage ?? 0, sum: weights)
      }
      let below = flexible.filter { (proposed[$0.id] ?? 0) < ($0.minimum ?? 0) }
      if below.isEmpty {
        for category in flexible {
          targets[category.id] = proposed[category.id] ?? 0
          if category.minimum != nil && proposed[category.id] == category.minimum {
            binding.insert(category.id)
          }
        }
        break
      }
      for category in below {
        targets[category.id] = category.minimum ?? 0
        binding.insert(category.id)
        remaining = try subtract(remaining, category.minimum ?? 0)
      }
      let fixed = Set(below.map(\.id))
      flexible.removeAll { fixed.contains($0.id) }
    }
    return (targets, binding)
  }

  fileprivate static func reconcile(
    targets: inout [UUID: Decimal], binding: Set<UUID>, categories: [CategoryGoalAllocation],
    total: Decimal, uncategorized: Decimal
  ) throws {
    // Reconcile only arithmetic remainder, never a genuine funding deficit.
    let targetTotal = try add(
      uncategorized, sum(categories.map { targets[$0.id] ?? $0.currentValue }))
    let remainder = try subtract(total, targetTotal)
    if remainder != 0 {
      let tolerance = arithmeticTolerance(total: total)
      guard abs(remainder) <= tolerance,
        let recipient = categories.first(where: {
          ($0.percentage ?? 0) > 0 && !binding.contains($0.id)
            && (targets[$0.id] ?? 0) + remainder >= ($0.minimum ?? 0)
        })
      else { throw ArithmeticError.invalid }
      targets[recipient.id] = try add(targets[recipient.id] ?? 0, remainder)
    }
  }

}

/// A transfer between categories, before localized presentation.
struct RebalancingTransfer: Equatable {
  let sourceID: UUID
  let destinationID: UUID
  var amount: Decimal
}

struct RebalancingTransferPlan {
  var transfers: [RebalancingTransfer] = []
  var actionableIDs: Set<UUID> = []
  var residual: Decimal = 0
}

/// Funds mandatory minimums before optional percentage adjustments.
enum RebalancingTransferPlanner {
  static func calculate(targets: [CategoryGoalTarget], total: Decimal) -> RebalancingTransferPlan {
    let mandatoryDemand = targets.reduce(Decimal(0)) { $0 + $1.minimumShortfall }
    let largeDonorCapacity = targets.filter { $0.difference <= -1 }.reduce(Decimal(0)) {
      $0 - $1.difference
    }
    let includeSmallDonors = mandatoryDemand > largeDonorCapacity
    let actionable = targets.filter {
      abs($0.difference) >= 1 || ($0.difference > 0 && $0.minimumShortfall > 0)
        || ($0.difference < 0 && includeSmallDonors)
    }
    let donors = actionable.filter { $0.difference < 0 }
    let recipients = actionable.filter { $0.difference > 0 }
    var donorRemaining = donors.map { -$0.difference }
    var recipientRemaining = recipients.map(\.difference)
    var plan = RebalancingTransferPlan(actionableIDs: Set(actionable.map(\.id)))

    func transfer(from donor: Int, to recipient: Int, limit: Decimal) -> Decimal {
      let amount = min(limit, min(donorRemaining[donor], recipientRemaining[recipient]))
      guard amount > 0 else { return 0 }
      donorRemaining[donor] -= amount
      recipientRemaining[recipient] -= amount
      // Combine repeated pairs so each suggested move has one displayed amount.
      if let index = plan.transfers.firstIndex(where: {
        $0.sourceID == donors[donor].id && $0.destinationID == recipients[recipient].id
      }) {
        plan.transfers[index].amount += amount
      } else {
        plan.transfers.append(
          RebalancingTransfer(
            sourceID: donors[donor].id, destinationID: recipients[recipient].id, amount: amount))
      }
      return amount
    }

    // Complete every floor before any recipient receives its above-minimum share.
    for recipient in recipients.indices {
      var shortfall = recipients[recipient].minimumShortfall
      for donor in donors.indices where shortfall > 0 {
        shortfall -= transfer(from: donor, to: recipient, limit: shortfall)
      }
    }
    for donor in donors.indices {
      for recipient in recipients.indices {
        _ = transfer(from: donor, to: recipient, limit: recipientRemaining[recipient])
      }
    }
    let suppressed = targets.filter { !plan.actionableIDs.contains($0.id) }.reduce(Decimal(0)) {
      $0 + abs($1.difference)
    }
    let unmatched = donorRemaining.reduce(Decimal(0), +) + recipientRemaining.reduce(Decimal(0), +)
    // Keep real omitted adjustments; reconcile only Decimal transfer arithmetic noise.
    plan.residual =
      suppressed
      + (unmatched <= RebalancingCalculator.arithmeticTolerance(total: total) ? 0 : unmatched)
    return plan
  }
}
