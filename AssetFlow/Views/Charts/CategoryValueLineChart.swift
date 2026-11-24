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
  private enum Metric {
    case value
    case allocation
  }

  let valueHistory: [String: [DashboardDataPoint]]
  let allocationHistory: [String: [DashboardDataPoint]]
  let latestSnapshotDate: Date?
  @Binding var timeRange: ChartTimeRange
  let scrollbarInset: CGFloat

  @State private var metric: Metric = .value
  @State private var disabledCategories: Set<String> = []
  @State private var hoveredDate: Date?

  private var categoryHistory: [String: [DashboardDataPoint]] {
    metric == .value ? valueHistory : allocationHistory
  }

  /// Category names sorted alphabetically, with Uncategorized last.
  private var sortedCategoryNames: [String] {
    let names = Array(valueHistory.keys)
    return names.sorted { lhs, rhs in
      if lhs.isEmpty { return false }
      if rhs.isEmpty { return true }
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
    let startDate = latestSnapshotDate.flatMap { timeRange.startDate(from: $0) }
    var result: [CategoryChartPoint] = []
    for name in sortedCategoryNames {
      guard !disabledCategories.contains(name), hasData(name) else { continue }
      guard let points = categoryHistory[name] else { continue }
      for point in points where startDate.map({ point.date >= $0 }) ?? true {
        result.append(
          CategoryChartPoint(
            date: point.date, value: point.value, categoryName: name))
      }
    }
    return result
  }

  var body: some View {
    let data = chartData
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(metric == .value ? "Category Value History" : "Category Allocation History")
          .font(.headline)
          .layoutPriority(1)
        Spacer(minLength: 8)
        Picker("Category chart metric", selection: $metric) {
          Text("Value").tag(Metric.value)
          Text("Allocation %").tag(Metric.allocation)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
      }

      ChartTimeRangeSelector(selection: $timeRange)

      if valueHistory.isEmpty {
        emptyMessage("Create categories to see allocation trends")
      } else if categoryHistory.isEmpty {
        emptyMessage("No allocation history")
      } else {
        chartWithLegend(data: data)
      }
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .glassCard()
    // Keep the tooltip's material outside the card's glass effect.
    .overlayPreferenceValue(CategoryTooltipAnchor.self) { position in
      if let position, let hoveredDate {
        GeometryReader { geometry in
          let plot = geometry[position.plotFrame]
          let viewport =
            geometry.bounds(of: .scrollView(axis: .vertical))
            ?? CGRect(origin: .zero, size: geometry.size)
          CategoryTooltipLayout(
            anchor: CGPoint(x: plot.minX + position.xInPlot, y: plot.minY),
            leftEdge: viewport.minX,
            rightEdge: viewport.maxX - scrollbarInset,
            topEdge: viewport.minY,
            bottomEdge: viewport.maxY
          ) {
            categoryTooltipView(for: hoveredDate, data: data)
          }
        }
        .allowsHitTesting(false)
      }
    }
    .accessibilityLabel(
      metric == .value ? "Category value history chart" : "Category allocation history chart"
    )
    .onChange(of: metric) { hoveredDate = nil }
  }

  private func chartWithLegend(data: [CategoryChartPoint]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
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
        let metricLabel =
          metric == .value ? String(localized: "Value") : String(localized: "Allocation %")
        Chart {
          ForEach(data, id: \.id) { point in
            LineMark(
              x: .value("Date", point.date),
              y: .value(metricLabel, point.value.doubleValue)
            )
            .foregroundStyle(by: .value("Category", point.categoryName))

            PointMark(
              x: .value("Date", point.date),
              y: .value(metricLabel, point.value.doubleValue)
            )
            .foregroundStyle(by: .value("Category", point.categoryName))
            .symbolSize(15)
          }

          if let hoveredDate {
            RuleMark(x: .value("Date", hoveredDate))
              .foregroundStyle(.secondary.opacity(0.5))
              .lineStyle(StrokeStyle(dash: [4, 4]))
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
                if metric == .value {
                  Text(ChartDataService.abbreviatedLabel(for: val))
                } else {
                  Text((val / 100).formatted(.percent.precision(.fractionLength(0...2))))
                }
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
            .preference(key: CategoryTooltipAnchor.self, value: tooltipPosition(in: proxy))
        }
        .frame(height: ChartConstants.dashboardChartHeight)
      }

      legendView
    }
  }

  private func tooltipPosition(in proxy: ChartProxy) -> CategoryTooltipAnchor.Position? {
    guard let hoveredDate, let plotFrame = proxy.plotFrame,
      let x = proxy.position(forX: hoveredDate)
    else { return nil }
    return .init(plotFrame: plotFrame, xInPlot: x)
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
        Text(categoryDisplayName(name))
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
        let nameOrder = categoryDisplayName(lhs.categoryName)
          .localizedCaseInsensitiveCompare(categoryDisplayName(rhs.categoryName))
        if nameOrder != .orderedSame {
          return nameOrder == .orderedAscending
        }
        return lhs.categoryName < rhs.categoryName
      }

    return ChartTooltipView {
      Text(date.settingsFormatted())
        .font(.caption2)
      CategoryTooltipRows {
        ForEach(pointsAtDate, id: \.categoryName) { point in
          HStack(spacing: 4) {
            Circle()
              .fill(colorForCategory(point.categoryName))
              .frame(width: 6, height: 6)
            Text(categoryDisplayName(point.categoryName))
              .font(.caption2)
          }

          Text(
            metric == .value
              ? point.value.formatted(currency: SettingsService.shared.mainCurrency)
              : point.value.formattedPercentage()
          )
          .font(.caption2.bold())
          .monospacedDigit()
        }
      }
    }
  }

  private func emptyMessage(_ text: LocalizedStringKey) -> some View {
    ChartEmptyMessage(text: text, height: ChartConstants.dashboardChartHeight)
  }

  private func categoryDisplayName(_ name: String) -> String {
    guard name.isEmpty else { return name }
    let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive]
    let usedNames = Set(valueHistory.keys.map { $0.folding(options: options, locale: .current) })
    let label = String(localized: "Uncategorized")
    guard usedNames.contains(label.folding(options: options, locale: .current)) else {
      return label
    }

    let fallback = String(localized: "Uncategorized assets")
    var candidate = fallback
    var suffix = 2
    while usedNames.contains(candidate.folding(options: options, locale: .current)) {
      candidate = String(localized: "\(fallback) (\(suffix))")
      suffix += 1
    }
    return candidate
  }

  /// Category name → color dictionary, built in a single O(N) pass.
  private var categoryColorMap: [String: Color] {
    var map: [String: Color] = ["": .gray]
    let sorted = sortedCategoryNames.filter { !$0.isEmpty }
    for (index, name) in sorted.enumerated() {
      map[name] = ChartConstants.color(forIndex: index)
    }
    return map
  }

  private func colorForCategory(_ name: String) -> Color {
    categoryColorMap[name] ?? .gray
  }
}

nonisolated private enum CategoryTooltipAnchor: PreferenceKey {
  struct Position {
    let plotFrame: Anchor<CGRect>
    let xInPlot: CGFloat
  }

  static var defaultValue: Position? { nil }

  static func reduce(value: inout Position?, nextValue: () -> Position?) {
    value = nextValue() ?? value
  }
}

/// Measures each name and value separately so measurement and placement use the same row heights.
private struct CategoryTooltipRows: Layout {
  private let rowSpacing: CGFloat = 2

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let layout = measure(subviews, width: proposal.width)
    let height = layout.rows.reduce(CGFloat(0)) { $0 + $1.height }
    return CGSize(
      width: layout.width, height: height + rowSpacing * CGFloat(max(0, layout.rows.count - 1)))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let layout = measure(subviews, width: proposal.width)
    var y = bounds.minY
    for (index, row) in layout.rows.enumerated() {
      let centerY = y + row.height / 2
      subviews[index * 2].place(
        at: CGPoint(x: bounds.minX, y: centerY), anchor: .leading, proposal: row.nameProposal)
      subviews[index * 2 + 1].place(
        at: CGPoint(x: bounds.maxX, y: centerY), anchor: .trailing, proposal: .unspecified)
      y += row.height + rowSpacing
    }
  }

  private struct Row {
    let nameProposal: ProposedViewSize
    let height: CGFloat
  }

  private func measure(_ subviews: Subviews, width: CGFloat?) -> (width: CGFloat, rows: [Row]) {
    guard !subviews.isEmpty else { return (0, []) }
    let nameIndices = stride(from: 0, to: subviews.count, by: 2)
    let names = nameIndices.map { subviews[$0].sizeThatFits(.unspecified) }
    let values = nameIndices.map { subviews[$0 + 1].sizeThatFits(.unspecified) }
    let idealNameWidth = names.map(\.width).max() ?? 0
    let valueWidth = values.map(\.width).max() ?? 0
    let idealWidth = idealNameWidth + valueWidth + 8
    let availableWidth = width ?? idealWidth
    let spacing: CGFloat = max(4, min(8, availableWidth - idealNameWidth - valueWidth))
    let nameWidth = max(0, min(idealNameWidth, availableWidth - valueWidth - spacing))
    let rows = nameIndices.enumerated().map { index, nameIndex in
      let fits = names[index].width <= nameWidth
      let proposal: ProposedViewSize = fits ? .unspecified : .init(width: nameWidth, height: nil)
      let nameHeight =
        fits ? names[index].height : subviews[nameIndex].sizeThatFits(proposal).height
      return Row(nameProposal: proposal, height: max(nameHeight, values[index].height))
    }
    return (nameWidth + spacing + valueWidth, rows)
  }
}

/// Places the tooltip relative to the plot and keeps it within the viewport when it fits.
private struct CategoryTooltipLayout: Layout {
  let anchor: CGPoint
  let leftEdge: CGFloat
  let rightEdge: CGFloat
  let topEdge: CGFloat
  let bottomEdge: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let tooltip = subviews[0]
    let availableWidth = max(0, rightEdge - leftEdge)
    let idealSize = tooltip.sizeThatFits(.unspecified)
    let fitsViewport = idealSize.width <= availableWidth
    // Keep the grid's natural column widths unless the viewport requires wrapping.
    let tooltipProposal: ProposedViewSize =
      fitsViewport ? .unspecified : .init(width: availableWidth, height: nil)
    let size = fitsViewport ? idealSize : tooltip.sizeThatFits(tooltipProposal)
    let x = max(leftEdge, min(anchor.x - size.width / 2, rightEdge - size.width))
    let spacing: CGFloat = 4
    let above = anchor.y - spacing - size.height
    let fallback = max(topEdge, min(anchor.y + spacing, bottomEdge - size.height))
    let y = above >= topEdge ? above : fallback
    tooltip.place(
      at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
      anchor: .topLeading,
      proposal: tooltipProposal)
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
