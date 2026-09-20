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

  init(modelContext: ModelContext) {
    _viewModel = State(wrappedValue: RebalancingViewModel(modelContext: modelContext))
  }

  var body: some View {
    Group {
      if viewModel.isEmpty {
        emptyState
      } else {
        rebalancingContent
      }
    }
    .navigationTitle("Rebalancing")
    .onAppear {
      viewModel.loadRebalancing()
    }
    .accessibilityIdentifier("Rebalancing View")
  }

  // MARK: - Main Content

  private var rebalancingContent: some View {
    VStack(spacing: 0) {
      portfolioValueBar
      Divider()
      allocationTable
      if !viewModel.summaryTexts.isEmpty {
        Divider()
        summaryFooter
      }
    }
    .conversionUnavailable(viewModel.conversionStatus.unavailableMessage)
  }

  // MARK: - Portfolio Value Bar

  private var portfolioValueBar: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Total Portfolio Value")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(
          viewModel.totalPortfolioValue.formatted(
            currency: SettingsService.shared.mainCurrency)
        )
        .font(.title2.bold())
        .monospacedDigit()
      }
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  // MARK: - Allocation Table

  private var allocationTable: some View {
    Table(of: AllocationRow.self) {
      TableColumn("Category") { row in
        Text(row.categoryName)
      }

      TableColumn("Current Value") { row in
        Text(row.currentValue.formatted(currency: SettingsService.shared.mainCurrency))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 100, ideal: 120)

      TableColumn("Current %") { row in
        Text(row.currentPercentage.formattedPercentage())
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 60, ideal: 75)

      TableColumn("Target %") { row in
        Group {
          if let target = row.targetPercentage {
            Text(target.formattedPercentage())
              .monospacedDigit()
          } else {
            Text("—")
              .foregroundStyle(.tertiary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 60, ideal: 75)

      TableColumn("Difference") { row in
        Group {
          if let diff = row.difference {
            Text(diff.formatted(currency: SettingsService.shared.mainCurrency))
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
      .width(min: 80, ideal: 140)

    } rows: {
      if !viewModel.suggestions.isEmpty {
        Section("Categories with Targets") {
          ForEach(suggestionTableRows) { row in
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
  }

  @ViewBuilder
  private func actionCell(for row: AllocationRow) -> some View {
    if let actionText = row.actionText, let actionType = row.actionType {
      switch actionType {
      case .buy:
        Label(actionText, systemImage: "arrow.up.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("Buy: \(actionText)")

      case .sell:
        Label(actionText, systemImage: "arrow.down.circle.fill")
          .foregroundStyle(.red)
          .accessibilityLabel("Sell: \(actionText)")

      case .noAction:
        Text(actionText)
          .foregroundStyle(.secondary)
      }
    } else {
      Text("N/A")
        .foregroundStyle(.tertiary)
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
      Text("Set target allocations on your categories to use the rebalancing calculator.")
    }
  }

  // MARK: - Row Builders

  private var suggestionTableRows: [AllocationRow] {
    viewModel.suggestions.map { suggestion in
      AllocationRow(
        id: suggestion.id,
        categoryName: suggestion.categoryName,
        currentValue: suggestion.currentValue,
        currentPercentage: suggestion.currentPercentage,
        targetPercentage: suggestion.targetPercentage,
        difference: suggestion.difference,
        actionText: suggestion.actionText,
        actionType: suggestion.actionType
      )
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
        actionText: nil,
        actionType: nil
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
        actionText: nil,
        actionType: nil
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
}

// MARK: - Previews

#Preview("Rebalancing") {
  NavigationStack {
    RebalancingView(modelContext: PreviewContainer.container.mainContext)
  }
}
