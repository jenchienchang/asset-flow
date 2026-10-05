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

@Suite("RebalancingTransferPlanner Tests")
@MainActor
struct RebalancingTransferPlannerTests {
  private func target(_ current: String, _ goal: String, minimum: String? = nil)
    -> CategoryGoalTarget
  {
    CategoryGoalTarget(
      allocation: CategoryGoalAllocation(
        id: UUID(), name: "Category", currentValue: Decimal(string: current)!, percentage: 25,
        minimum: minimum.map { Decimal(string: $0)! }), targetValue: Decimal(string: goal)!,
      minimumIsBinding: minimum == goal)
  }

  @Test("Reviewer's portfolio funds the minimum before the larger buy")
  func reportedPortfolio() {
    let ids = (0..<4).map { _ in UUID() }
    let balances = ["40", "20.5", "39.5", "0"]
    let percentages = ["30", "20", "49.8", "0.2"]
    let goals = ids.indices.map {
      CategoryGoalAllocation(
        id: ids[$0], name: "Category", currentValue: Decimal(string: balances[$0])!,
        percentage: Decimal(string: percentages[$0])!,
        minimum: $0 == 3 ? Decimal(string: "0.2")! : nil)
    }
    let allocation = RebalancingCalculator.calculate(categories: goals, totalValue: 100)
    #expect(allocation.status == .feasible)
    let plan = RebalancingTransferPlanner.calculate(targets: allocation.targets, total: 100)
    #expect(
      plan.transfers == [
        RebalancingTransfer(
          sourceID: ids[0], destinationID: ids[3], amount: Decimal(string: "0.2")!),
        RebalancingTransfer(
          sourceID: ids[0], destinationID: ids[2], amount: Decimal(string: "9.8")!),
      ])
    #expect(!plan.actionableIDs.contains(ids[1]))
    #expect(plan.residual == 1)
    verify(plan, targets: allocation.targets)
  }

  @Test("All minimums precede above-minimum increases, regardless of target ordering")
  func multipleMinimums() {
    let donor = target("12", "2")
    let first = target("0", "10", minimum: "0.4")
    let second = target("0", "0.4", minimum: "0.4")
    let smallDonor = target("0.4", "0")
    for targets in [[donor, first, second, smallDonor], [second, first, smallDonor, donor]] {
      let plan = RebalancingTransferPlanner.calculate(
        targets: targets, total: Decimal(string: "12.4")!)
      #expect(
        plan.transfers.contains {
          $0.destinationID == second.id && $0.amount == Decimal(string: "0.4")!
        })
      #expect(!plan.actionableIDs.contains(smallDonor.id))
      #expect(plan.residual == Decimal(string: "0.8")!)
      verify(plan, targets: targets)
    }
  }

  @Test("Small donors participate when mandatory shortfalls exceed large donor capacity")
  func supportingDonors() {
    let donor = target("2", "1")
    let small = target("0.8", "0")
    let recipient = target("0", "1.8", minimum: "1.8")
    let targets = [recipient, donor, small]
    let plan = RebalancingTransferPlanner.calculate(
      targets: targets, total: Decimal(string: "2.8")!)
    #expect(plan.actionableIDs == Set(targets.map(\.id)))
    #expect(plan.transfers.reduce(Decimal(0)) { $0 + $1.amount } == Decimal(string: "1.8")!)
    #expect(plan.residual == 0)
    verify(plan, targets: targets)
  }

  @Test("Mandatory demand excludes a recipient's optional target increase")
  func actualShortfallOnly() {
    let large = target("2", "1")
    let small = target("0.5", "0")
    let recipient = target("0", "1.5", minimum: "0.2")
    let targets = [recipient, large, small]
    let plan = RebalancingTransferPlanner.calculate(
      targets: targets, total: Decimal(string: "2.5")!)
    #expect(!plan.actionableIDs.contains(small.id))
    #expect(plan.transfers.reduce(Decimal(0)) { $0 + $1.amount } == 1)
    #expect(plan.residual == 1)
    verify(plan, targets: targets)
  }

  @Test("Optional subunit adjustments remain suppressed; zero differences produce no moves")
  func optionalAndZero() {
    let targets = [target("1", "0.5"), target("0", "0.5"), target("2", "2")]
    let plan = RebalancingTransferPlanner.calculate(targets: targets, total: 3)
    #expect(plan.transfers.isEmpty)
    #expect(plan.actionableIDs.isEmpty)
    #expect(plan.residual == 1)
    let empty = RebalancingTransferPlanner.calculate(targets: [], total: 0)
    #expect(empty.transfers.isEmpty)
    #expect(empty.residual == 0)
  }

  @Test("Fully matched ordinary adjustments preserve donor and recipient capacities")
  func ordinaryTransfers() {
    let targets = [target("5", "2"), target("3", "1"), target("0", "4"), target("0", "1")]
    let plan = RebalancingTransferPlanner.calculate(targets: targets, total: 8)
    #expect(plan.residual == 0)
    #expect(plan.transfers.reduce(Decimal(0)) { $0 + $1.amount } == 5)
    verify(plan, targets: targets)
  }

  private func verify(_ plan: RebalancingTransferPlan, targets: [CategoryGoalTarget]) {
    for move in plan.transfers {
      #expect(move.amount > 0)
      #expect(move.sourceID != move.destinationID)
    }
    for target in targets {
      let received = plan.transfers.filter { $0.destinationID == target.id }.reduce(Decimal(0)) {
        $0 + $1.amount
      }
      let sent = plan.transfers.filter { $0.sourceID == target.id }.reduce(Decimal(0)) {
        $0 + $1.amount
      }
      #expect(received <= max(0, target.difference))
      #expect(sent <= max(0, -target.difference))
      #expect(target.allocation.currentValue + received - sent >= (target.allocation.minimum ?? 0))
    }
  }
}
