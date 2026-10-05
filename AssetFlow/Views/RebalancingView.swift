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

import SwiftData
import SwiftUI

struct RebalancingView: View {
  @State private var viewModel: RebalancingViewModel
  @Query private var querySnapshots: [Snapshot]
  @Query private var queryCategories: [Category]

  init(modelContext: ModelContext) {
    _viewModel = State(wrappedValue: RebalancingViewModel(modelContext: modelContext))
  }

  var body: some View {
    Group {
      if case .failed(let message) = viewModel.loadState {
        DataLoadErrorView(message: message) { viewModel.loadRebalancing() }
      } else if viewModel.isEmpty {
        emptyState
      } else {
        rebalancingContent
      }
    }
    .navigationTitle("Rebalancing")
    .refreshOnStoreChanges { viewModel.requestRefresh() }
    .onAppear {
      viewModel.loadRebalancing()
    }
    .onChange(of: querySnapshots) {
      viewModel.requestRefresh()
    }
    .onChange(of: queryCategories) {
      viewModel.requestRefresh()
    }
    .accessibilityIdentifier("Rebalancing View")
  }

  // MARK: - Main Content

  private var rebalancingContent: some View {
    VStack(spacing: 0) {
      portfolioValueBar
      if let message = viewModel.goalAssessment.goalConversion.unavailableMessage {
        Text(message).font(.callout).padding()
      }
      if let message = CategoryGoalPresentation.diagnostic(
        viewModel.goalAssessment.plan, currency: SettingsService.shared.mainCurrency)
      {
        Label(message, systemImage: "exclamationmark.triangle").padding()
      }
      Divider()
      allocationTable
      if !viewModel.summaryTexts.isEmpty {
        Divider()
        summaryFooter
      }
      if viewModel.smallAdjustmentResidual > 0 {
        Text(
          "Small or unmatched adjustments remain: \(CategoryGoalPresentation.amount(viewModel.smallAdjustmentResidual, currency: SettingsService.shared.mainCurrency))"
        )
        .font(.caption).padding()
      }
    }
    .conversionUnavailable(viewModel.conversionStatus.unavailableMessage)
  }

  // MARK: - Portfolio Value Bar

  private var portfolioValueBar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) {
        portfolioSummary
        Spacer()
        snapshotLabel
        calculationHelp
      }
      VStack(alignment: .leading, spacing: 8) {
        portfolioSummary
        HStack {
          snapshotLabel
          Spacer()
          calculationHelp
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private var portfolioSummary: some View {
    HStack(spacing: 8) {
      Text("Total Portfolio Value").foregroundStyle(.secondary)
      Text(viewModel.totalPortfolioValue.formatted(currency: SettingsService.shared.mainCurrency))
        .font(.headline).monospacedDigit()
    }
  }

  @ViewBuilder
  private var snapshotLabel: some View {
    if let date = viewModel.snapshotDate {
      Text("Snapshot: \(date.settingsFormatted())").font(.caption).foregroundStyle(.secondary)
    }
  }

  private var calculationHelp: some View {
    HStack(spacing: 4) {
      Text("Calculation details").font(.caption)
      GoalHelpButton(title: "Calculation details", showsTitle: false, fitsContent: true) {
        RebalancingHelpView(
          content: RebalancingHelpPresentation.calculation(
            assessment: viewModel.goalAssessment, currency: SettingsService.shared.mainCurrency))
      }
    }
  }

  // MARK: - Allocation Table

  private var allocationTable: some View {
    Table(of: AllocationRow.self) {
      TableColumn("Category") { row in
        HStack(spacing: 6) {
          Text(row.categoryName).lineLimit(1)
          GoalHelpButton(
            title: "Details for \(row.categoryName)", showsTitle: false, fitsContent: true
          ) {
            RebalancingHelpView(
              content: RebalancingHelpPresentation.category(
                helpInput(for: row), diagnostic: helpUnavailableReason,
                currency: SettingsService.shared.mainCurrency, assessment: viewModel.goalAssessment)
            )
          }
        }
      }
      .width(min: 120, ideal: 150)

      TableColumn("Current balance") { row in
        Text(row.currentValue.formatted(currency: SettingsService.shared.mainCurrency))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 100, ideal: 120)

      TableColumn("Current %") { row in
        Text(viewModel.totalPortfolioValue > 0 ? row.currentPercentage.formattedPercentage() : "—")
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 60, ideal: 75)

      TableColumn("Effective target balance") { row in
        Text(
          row.targetValue.map { $0.formatted(currency: SettingsService.shared.mainCurrency) } ?? "—"
        )
        .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 150, ideal: 170)

      TableColumn("Effective target %") { row in
        Text(row.effectivePercentage.map { $0.formattedPercentage() } ?? "—")
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
          .helpWhenUnlocked(
            "Effective targets are shares of the whole portfolio. Minimum-only categories retain any balance above their minimum."
          )
      }
      .width(min: 115, ideal: 125)

      TableColumn("Change") { row in
        Group {
          if let diff = row.difference {
            Text(
              abs(diff) < 1 && diff != 0
                ? CategoryGoalPresentation.amount(
                  diff, currency: SettingsService.shared.mainCurrency)
                : diff.formatted(currency: SettingsService.shared.mainCurrency)
            )
            .monospacedDigit()
          } else {
            Text("—")
              .foregroundStyle(.tertiary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 100, ideal: 120)

      TableColumn("Action") { row in
        actionCell(for: row)
      }
      .width(min: 100, ideal: 120)

      TableColumn("Minimum") { row in
        HStack(spacing: 6) {
          Text(row.minimumText ?? "—").lineLimit(1).monospacedDigit()
          if let status = row.minimumAssessment, status != .met, status != .notSet {
            GoalHelpButton(
              title: "Minimum balance status", showsTitle: false, fitsContent: true,
              systemImage: "exclamationmark.circle", symbolColor: .orange
            ) {
              RebalancingHelpView(
                content: RebalancingHelpPresentation.minimum(
                  helpInput(for: row), currency: SettingsService.shared.mainCurrency,
                  snapshotDate: viewModel.snapshotDate,
                  unavailableReason: viewModel.goalAssessment.assetConversion.unavailableMessage
                    ?? viewModel.goalAssessment.goalConversion.unavailableMessage))
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 130, ideal: 150)

    } rows: {
      if !goalTableRows.isEmpty {
        Section("Categories with Targets") {
          ForEach(goalTableRows) { row in
            TableRow(row)
          }
        }
      }

      if !viewModel.noTargetRows.isEmpty {
        Section("No Target Set") {
          ForEach(noTargetTableRows) { row in
            TableRow(row)
          }
        }
      }

      if !uncategorizedTableRows.isEmpty {
        Section("Uncategorized") {
          ForEach(uncategorizedTableRows) { row in
            TableRow(row)
          }
        }
      }
    }
    .lineLimit(1)
  }

  @ViewBuilder
  private func actionCell(for row: AllocationRow) -> some View {
    if let actionType = row.actionType {
      switch actionType {
      case .buy:
        Label("Buy", systemImage: "arrow.up.circle.fill").foregroundStyle(.green)

      case .sell:
        Label("Sell", systemImage: "arrow.down.circle.fill").foregroundStyle(.red)

      case .noAction:
        if row.targetPercentage == nil {
          Label("Protected", systemImage: "minus.circle.fill").foregroundStyle(.secondary)
        } else if row.difference != nil && row.difference != 0 {
          Text("Small adjustment").foregroundStyle(.secondary)
        } else {
          Text("No action").foregroundStyle(.secondary)
        }
      }
    } else {
      Text("—").foregroundStyle(.tertiary)
    }
  }

  // MARK: - Summary Footer

  private var summaryFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Suggested Moves")
        .font(.headline)

      ForEach(viewModel.summaryTexts, id: \.self) { text in
        Label(text, systemImage: "arrow.right.circle")
          .font(.callout)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No Rebalancing Data", systemImage: "chart.bar.doc.horizontal")
    } description: {
      Text("Add a snapshot to calculate rebalancing from your category goals.")
    }
  }

  private var helpUnavailableReason: String? {
    RebalancingHelpPresentation.unavailableReason(
      assessment: viewModel.goalAssessment, currency: SettingsService.shared.mainCurrency)
  }

  private func helpInput(for row: AllocationRow) -> RebalancingCategoryHelpInput {
    let category = viewModel.categories.first { $0.id.uuidString == row.id }
    return RebalancingCategoryHelpInput(
      name: row.categoryName,
      current: viewModel.goalAssessment.totalValue != nil
        && viewModel.goalAssessment.assetConversion.isComplete ? row.currentValue : nil,
      percentage: row.targetPercentage,
      minimum: category?.minimumBalanceAmount,
      minimumCurrency: category?.minimumBalanceCurrency,
      convertedMinimum: category.flatMap { viewModel.goalAssessment.minimums[$0.id] },
      status: row.minimumAssessment ?? .notSet,
      target: row.targetValue, difference: row.difference, share: row.effectivePercentage,
      minimumIsBinding: row.minimumIsBinding)
  }

  // MARK: - Row Builders

  private var goalTableRows: [AllocationRow] {
    viewModel.categories.filter {
      $0.targetAllocationPercentage != nil || $0.minimumBalanceAmount != nil
    }.map { category in
      let suggestion = viewModel.suggestions.first { $0.categoryID == category.id }
      let current = viewModel.goalAssessment.values[category.id] ?? 0
      var row = AllocationRow(
        id: category.id.uuidString, categoryName: category.name, currentValue: current,
        currentPercentage: viewModel.totalPortfolioValue > 0
          ? current / viewModel.totalPortfolioValue * 100 : 0,
        targetPercentage: category.targetAllocationPercentage, difference: suggestion?.difference,
        actionText: suggestion?.actionText, actionType: suggestion?.actionType)
      row.targetValue = suggestion?.targetValue
      row.effectivePercentage = suggestion?.effectivePercentage
      row.minimumIsBinding = suggestion?.minimumIsBinding ?? false
      if let minimum = category.minimumBalanceAmount, let currency = category.minimumBalanceCurrency
      {
        row.minimumText = CategoryGoalPresentation.amount(minimum, currency: currency)
        row.minimumAssessment = viewModel.goalAssessment.statuses[category.id] ?? .unavailable
        row.minimumStatus = CategoryGoalPresentation.minimumStatus(
          viewModel.goalAssessment.statuses[category.id] ?? .unavailable,
          currency: SettingsService.shared.mainCurrency)
      }
      return row
    }.sorted {
      if abs($0.difference ?? 0) != abs($1.difference ?? 0) {
        return abs($0.difference ?? 0) > abs($1.difference ?? 0)
      }
      return $0.id < $1.id
    }
  }

  private var noTargetTableRows: [AllocationRow] {
    viewModel.noTargetRows.map { row in
      AllocationRow(
        id: row.id,
        categoryName: row.categoryName,
        currentValue: row.currentValue,
        currentPercentage: row.currentPercentage,
        targetPercentage: nil,
        difference: nil,
        actionText: String(localized: "Protected balance"),
        actionType: .noAction
      )
    }
  }

  private var uncategorizedTableRows: [AllocationRow] {
    guard let unc = viewModel.uncategorizedRow else { return [] }
    return [
      AllocationRow(
        id: "uncategorized",
        categoryName: String(localized: "Uncategorized"),
        currentValue: unc.currentValue,
        currentPercentage: unc.currentPercentage,
        targetPercentage: nil,
        difference: nil,
        actionText: String(localized: "Protected balance"),
        actionType: .noAction
      )
    ]
  }
}

// MARK: - Private Types

private struct AllocationRow: Identifiable {
  let id: String
  let categoryName: String
  let currentValue: Decimal
  let currentPercentage: Decimal
  let targetPercentage: Decimal?
  let difference: Decimal?
  let actionText: String?
  let actionType: RebalancingActionType?
  var targetValue: Decimal?
  var effectivePercentage: Decimal?
  var minimumText: String?
  var minimumStatus: String?
  var minimumAssessment: MinimumBalanceStatus?
  var minimumIsBinding = false
}

// MARK: - Previews

#Preview("Rebalancing") {
  NavigationStack {
    RebalancingView(modelContext: PreviewContainer.container.mainContext)
  }
}
