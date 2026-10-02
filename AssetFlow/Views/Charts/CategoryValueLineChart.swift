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

import Charts
import SwiftUI

/// Multi-category value history line chart (SPEC 12.3).
///
/// Displays one line per category with a legend toggle to show/hide categories.
/// No click-to-navigate behavior per SPEC 12.3.
struct CategoryValueLineChart: View {
  let categoryHistory: [String: [DashboardDataPoint]]
  @Binding var timeRange: ChartTimeRange

  @State private var disabledCategories: Set<String> = []
  @State private var hoveredDate: Date?

  /// Category names sorted alphabetically, with Uncategorized last.
  private var sortedCategoryNames: [String] {
    let names = Array(categoryHistory.keys)
    return names.sorted { lhs, rhs in
      if lhs == "Uncategorized" { return false }
      if rhs == "Uncategorized" { return true }
      return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
  }

  /// Whether a category has all-zero values (should be omitted from chart).
  private func hasData(_ categoryName: String) -> Bool {
    guard let points = categoryHistory[categoryName] else { return false }
    return points.contains { $0.value != 0 }
  }

  /// Flattened and filtered data points for the chart.
  private var chartData: [CategoryChartPoint] {
    var result: [CategoryChartPoint] = []
    for name in sortedCategoryNames {
      guard !disabledCategories.contains(name), hasData(name) else { continue }
      guard let points = categoryHistory[name] else { continue }
      let filtered = ChartDataService.filter(points, range: timeRange)
      for point in filtered {
        result.append(
          CategoryChartPoint(
            date: point.date, value: point.value, categoryName: name))
      }
    }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Category Value History")
        .font(.headline)

      ChartTimeRangeSelector(selection: $timeRange)

      if categoryHistory.isEmpty {
        emptyMessage("Create categories to see allocation trends")
      } else {
        chartWithLegend
      }
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .glassCard()
    .accessibilityLabel("Category value history chart")
  }

  private var chartWithLegend: some View {
    VStack(alignment: .leading, spacing: 8) {
      let data = chartData
      if data.isEmpty {
        emptyMessage("No data for selected period")
      } else {
        let dates = Set(data.map(\.date)).sorted()
        let firstDate = dates.first!
        let lastDate = dates.last!
        let xPadding: TimeInterval = firstDate == lastDate ? 86_400 : 0
        let yValues = data.map { $0.value.doubleValue }
        let yMin = yValues.min()!
        let yMax = yValues.max()!
        let yPadding = yMin == yMax ? max(abs(yMin) * 0.1, 1.0) : 0.0
        Chart {
          ForEach(data, id: \.id) { point in
            LineMark(
              x: .value("Date", point.date),
              y: .value("Value", point.value.doubleValue)
            )
            .foregroundStyle(by: .value("Category", point.categoryName))

            PointMark(
              x: .value("Date", point.date),
              y: .value("Value", point.value.doubleValue)
            )
            .foregroundStyle(by: .value("Category", point.categoryName))
            .symbolSize(15)
          }

          if let hoveredDate {
            RuleMark(x: .value("Date", hoveredDate))
              .foregroundStyle(.secondary.opacity(0.5))
              .lineStyle(StrokeStyle(dash: [4, 4]))
              .annotation(
                position: .top,
                alignment: hoveredDate == firstDate
                  ? .leading
                  : hoveredDate == lastDate ? .trailing : .center,
                spacing: 4,
                overflowResolution: .init(x: .fit, y: .fit)
              ) {
                categoryTooltipView(for: hoveredDate, data: data)
              }
          }
        }
        .chartXScale(
          domain: firstDate.addingTimeInterval(-xPadding)...lastDate.addingTimeInterval(xPadding)
        )
        .chartYScale(domain: (yMin - yPadding)...(yMax + yPadding))
        .chartForegroundStyleScale(
          domain: enabledCategoryNames,
          range: enabledCategoryNames.map { colorForCategory($0) }
        )
        .chartYAxis {
          AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
              if let val = value.as(Double.self) {
                Text(ChartDataService.abbreviatedLabel(for: val))
              }
            }
          }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
          Color.clear
            .contentShape(Rectangle())
            .onContinuousHoverWhenUnlocked { phase in
              switch phase {
              case .active(let location):
                hoveredDate = ChartHelpers.findNearestDate(
                  at: location, in: proxy, points: data, dateKeyPath: \.date)

              case .ended:
                hoveredDate = nil
              }
            }
        }
        .frame(height: ChartConstants.dashboardChartHeight)
      }

      legendView
    }
  }

  /// Category names that are enabled (not disabled) and have data — used for chart color scale.
  private var enabledCategoryNames: [String] {
    sortedCategoryNames.filter { !disabledCategories.contains($0) && hasData($0) }
  }

  private var legendView: some View {
    FlowLayout(spacing: 6) {
      ForEach(sortedCategoryNames, id: \.self) { name in
        legendItem(for: name)
      }
    }
  }

  private func legendItem(for name: String) -> some View {
    let isDisabled = disabledCategories.contains(name)
    let noData = !hasData(name)

    return Button {
      if disabledCategories.contains(name) {
        disabledCategories.remove(name)
      } else {
        disabledCategories.insert(name)
      }
    } label: {
      HStack(spacing: 4) {
        Circle()
          .fill(isDisabled ? .gray.opacity(0.3) : colorForCategory(name))
          .frame(width: 8, height: 8)
        Text(name)
          .font(.caption2)
          .strikethrough(isDisabled)
        if noData {
          Text("(no data)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .foregroundStyle(isDisabled ? .secondary : .primary)
    }
    .buttonStyle(.plain)
    .disabled(noData)
  }

  private func categoryTooltipView(
    for date: Date, data: [CategoryChartPoint]
  ) -> some View {
    let pointsAtDate =
      data
      .filter { $0.date == date }
      .sorted { lhs, rhs in
        if lhs.value != rhs.value {
          return lhs.value > rhs.value
        }
        let nameOrder = lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName)
        if nameOrder != .orderedSame {
          return nameOrder == .orderedAscending
        }
        return lhs.categoryName < rhs.categoryName
      }

    return ChartTooltipView {
      Text(date.settingsFormatted())
        .font(.caption2)
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
        ForEach(pointsAtDate, id: \.categoryName) { point in
          GridRow {
            HStack(spacing: 4) {
              Circle()
                .fill(colorForCategory(point.categoryName))
                .frame(width: 6, height: 6)
              Text(point.categoryName)
                .font(.caption2)
            }

            Text(point.value.formatted(currency: SettingsService.shared.mainCurrency))
              .font(.caption2.bold())
              .monospacedDigit()
              .gridColumnAlignment(.trailing)
          }
        }
      }
    }
  }

  private func emptyMessage(_ text: LocalizedStringKey) -> some View {
    ChartEmptyMessage(text: text, height: ChartConstants.dashboardChartHeight)
  }

  /// Category name → color dictionary, built in a single O(N) pass.
  private var categoryColorMap: [String: Color] {
    var map: [String: Color] = ["Uncategorized": .gray]
    let sorted = sortedCategoryNames.filter { $0 != "Uncategorized" }
    for (index, name) in sorted.enumerated() {
      map[name] = ChartConstants.color(forIndex: index)
    }
    return map
  }

  private func colorForCategory(_ name: String) -> Color {
    categoryColorMap[name] ?? .gray
  }
}

/// Data point for multi-category chart, including category name for color coding.
private struct CategoryChartPoint: Identifiable {
  var id: String { "\(categoryName)-\(date.timeIntervalSince1970)" }
  let date: Date
  let value: Decimal
  let categoryName: String
}

/// Simple flow layout for legend items that wraps to next line.
private struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = layout(in: proposal.width ?? 0, subviews: subviews)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = layout(in: bounds.width, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified)))
    }
  }

  private struct LayoutResult {
    var positions: [CGPoint]
    var size: CGSize
  }

  private func layout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
    var positions: [CGPoint] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX + size.width > maxWidth, currentX > 0 {
        currentX = 0
        currentY += rowHeight + spacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: currentX, y: currentY))
      rowHeight = max(rowHeight, size.height)
      currentX += size.width + spacing
      maxX = max(maxX, currentX)
    }

    return LayoutResult(
      positions: positions,
      size: CGSize(width: maxX, height: currentY + rowHeight))
  }
}
