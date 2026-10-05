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

struct RebalancingRowData: Identifiable {
  let categoryID: UUID
  var id: String { categoryID.uuidString }
  let categoryName: String
  let currentValue: Decimal
  let currentPercentage: Decimal
  let targetPercentage: Decimal?
  let difference: Decimal
  let actionText: String
  let actionType: RebalancingActionType
  let targetValue: Decimal
  let effectivePercentage: Decimal?
  let minimumIsBinding: Bool
}

struct NoTargetRowData: Identifiable {
  let categoryID: UUID
  var id: String { categoryID.uuidString }
  let categoryName: String
  let currentValue: Decimal
  let currentPercentage: Decimal
}

struct UncategorizedRowData {
  let currentValue: Decimal
  let currentPercentage: Decimal
}

@Observable
@MainActor
final class RebalancingViewModel {
  @ObservationIgnored private let refresh = ObservedRefresh()

  private let fetcher: any ModelFetching
  var goalAssessment = CategoryGoalAssessment()
  var suggestions: [RebalancingRowData] = []
  var noTargetRows: [NoTargetRowData] = []
  var uncategorizedRow: UncategorizedRowData?
  var summaryTexts: [String] = []
  var totalPortfolioValue: Decimal = 0
  var conversionStatus: CurrencyConversionStatus = .notNeeded
  var loadState: DataLoadState = .idle
  var categories: [Category] = []
  var snapshotDate: Date?
  var smallAdjustmentResidual: Decimal = 0

  var isEmpty: Bool {
    if case .failed = loadState { return false }
    return snapshotDate == nil && conversionStatus.isComplete
  }

  init(modelContext: ModelContext, fetcher: (any ModelFetching)? = nil) {
    self.fetcher = fetcher ?? ModelContextFetcher(modelContext: modelContext)
  }

  /// Coalesces source-observation and query notifications before refreshing.
  func requestRefresh() {
    refresh.request { [weak self] in self?.loadRebalancing() }
  }

  func loadRebalancing() {
    refresh.perform {
      performLoad()
    } reload: { [weak self] in
      self?.loadRebalancing()
    }
  }

  private func performLoad() {
    var state: DataLoadState = .loaded
    var loadedCategories: [Category] = []
    var suggestions: [RebalancingRowData] = []
    var noTargetRows: [NoTargetRowData] = []
    var summaryTexts: [String] = []
    var uncategorizedRow: UncategorizedRowData?
    var snapshotDate: Date?
    var totalPortfolioValue: Decimal = 0
    var smallAdjustmentResidual: Decimal = 0
    var goalAssessment: CategoryGoalAssessment = CategoryGoalAssessment()
    var conversionStatus: CurrencyConversionStatus = .notNeeded
    defer {
      let result = (
        suggestions: suggestions,
        noTargetRows: noTargetRows,
        summaryTexts: summaryTexts,
        uncategorizedRow: uncategorizedRow,
        snapshotDate: snapshotDate,
        totalPortfolioValue: totalPortfolioValue,
        smallAdjustmentResidual: smallAdjustmentResidual,
        goalAssessment: goalAssessment,
        conversionStatus: conversionStatus,
        categories: loadedCategories,
        loadState: state
      )
      refresh.publish {
        self.suggestions = result.suggestions
        self.noTargetRows = result.noTargetRows
        self.summaryTexts = result.summaryTexts
        self.uncategorizedRow = result.uncategorizedRow
        self.snapshotDate = result.snapshotDate
        self.totalPortfolioValue = result.totalPortfolioValue
        self.smallAdjustmentResidual = result.smallAdjustmentResidual
        self.goalAssessment = result.goalAssessment
        self.conversionStatus = result.conversionStatus
        self.categories = result.categories
        self.loadState = result.loadState
      }
    }
    do {
      loadedCategories = try fetchModels(
        FetchDescriptor<Category>(sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)]),
        from: fetcher, operation: "load category goals")
      let snapshot = try SnapshotSummaryService.fetchLatestSnapshot(using: fetcher)
      snapshotDate = snapshot?.date
      let currency = SettingsService.shared.mainCurrency
      goalAssessment = CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: loadedCategories, displayCurrency: currency)
      conversionStatus = goalAssessment.assetConversion
      totalPortfolioValue = goalAssessment.totalValue ?? 0
      guard let snapshot else { return }
      let percentage: (Decimal) -> Decimal = {
        totalPortfolioValue > 0 ? $0 / totalPortfolioValue * 100 : 0
      }
      noTargetRows = loadedCategories.filter {
        $0.targetAllocationPercentage == nil && $0.minimumBalanceAmount == nil
      }.map {
        let value = goalAssessment.values[$0.id] ?? 0
        return NoTargetRowData(
          categoryID: $0.id, categoryName: $0.name, currentValue: value,
          currentPercentage: percentage(value))
      }
      let uncategorized = (snapshot.assetValues ?? []).filter { $0.asset?.category == nil }.reduce(
        Decimal(0)
      ) { total, value in
        total
          + (CurrencyConversionService.convert(
            value: value.marketValue,
            from: value.asset?.currency.isEmpty == false
              ? (value.asset?.currency ?? currency) : currency, to: currency,
            using: snapshot.exchangeRate, forSnapshotDate: snapshot.date) ?? 0)
      }
      if uncategorized > 0 {
        uncategorizedRow = UncategorizedRowData(
          currentValue: uncategorized, currentPercentage: percentage(uncategorized))
      }
      if let plan = goalAssessment.plan, plan.status == .feasible {
        let goals = plan.targets.filter {
          $0.allocation.percentage != nil || $0.allocation.minimum != nil
        }
        let transfers = RebalancingTransferPlanner.calculate(
          targets: goals, total: totalPortfolioValue)
        suggestions = goals.map { target in
          let difference = target.difference
          let actionable = transfers.actionableIDs.contains(target.id)
          let action: RebalancingActionType =
            difference == 0 || !actionable ? .noAction : (difference > 0 ? .buy : .sell)
          let formattedDifference =
            abs(difference) < 1
            ? CategoryGoalPresentation.amount(abs(difference), currency: currency)
            : abs(difference).formatted(currency: currency)
          let text: String
          switch action {
          case .buy: text = String(localized: "Buy \(formattedDifference)", table: "Rebalancing")
          case .sell: text = String(localized: "Sell \(formattedDifference)", table: "Rebalancing")

          case .noAction:
            text =
              difference == 0
              ? String(localized: "No action needed", table: "Rebalancing")
              : String(
                localized:
                  "Small adjustment: \(CategoryGoalPresentation.amount(difference, currency: currency))",
                table: "Rebalancing")
          }
          return RebalancingRowData(
            categoryID: target.id, categoryName: target.allocation.name,
            currentValue: target.allocation.currentValue,
            currentPercentage: percentage(target.allocation.currentValue),
            targetPercentage: target.allocation.percentage, difference: difference,
            actionText: text, actionType: action, targetValue: target.targetValue,
            effectivePercentage: totalPortfolioValue > 0 ? percentage(target.targetValue) : nil,
            minimumIsBinding: target.minimumIsBinding)
        }
        let categoryNames = Dictionary(
          uniqueKeysWithValues: goals.map { ($0.id, $0.allocation.name) })
        summaryTexts = transfers.transfers.map { move in
          guard let source = categoryNames[move.sourceID],
            let destination = categoryNames[move.destinationID]
          else {
            preconditionFailure("Transfers must reference categories from the same allocation plan")
          }
          let amount =
            move.amount < 1
            ? CategoryGoalPresentation.amount(move.amount, currency: currency)
            : move.amount.formatted(currency: currency)
          return String(
            localized: "Move \(amount) from \(source) to \(destination)", table: "Rebalancing")
        }
        smallAdjustmentResidual = transfers.residual
      }

    } catch { state = .failed(error.localizedDescription) }
  }
}
