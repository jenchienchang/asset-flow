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

/// A reusable single-series line chart with hover tooltip, RuleMark annotation,
/// and optional extra chart content (e.g., target allocation lines).
///
/// Handles single-point vs multi-point rendering, Y-axis domain computation,
/// three-way tooltip alignment (leading/center/trailing), and optional tap-to-navigate.
struct SingleSeriesLineChart<
  DataPoint: Identifiable, TooltipContent: View, ExtraContent: ChartContent
>: View {
  let data: [DataPoint]
  let dateKeyPath: KeyPath<DataPoint, Date>
  let valueOf: (DataPoint) -> Double
  let seriesOf: (DataPoint) -> Int
  let color: Color
  let height: CGFloat
  let yAxisLabel: (Double) -> String
  let tooltipContent: (DataPoint) -> TooltipContent
  let yDomain: ((Double, Double) -> (Double, Double))?
  let xDomain: ClosedRange<Date>?
  let unavailableDates: [Date]
  let extraContent: ExtraContent
  let onTapDate: ((Date) -> Void)?
  let symbolSize: CGFloat

  @State private var hoveredDate: Date?

  init(
    data: [DataPoint],
    dateKeyPath: KeyPath<DataPoint, Date>,
    valueOf: @escaping (DataPoint) -> Double,
    seriesOf: @escaping (DataPoint) -> Int = { _ in 0 },
    color: Color,
    height: CGFloat,
    yAxisLabel: @escaping (Double) -> String = { ChartDataService.abbreviatedLabel(for: $0) },
    tooltipContent: @escaping (DataPoint) -> TooltipContent,
    yDomain: ((Double, Double) -> (Double, Double))? = nil,
    xDomain: ClosedRange<Date>? = nil,
    unavailableDates: [Date] = [],
    onTapDate: ((Date) -> Void)? = nil,
    symbolSize: CGFloat = 20,
    @ChartContentBuilder extraContent: () -> ExtraContent
  ) {
    self.data = data
    self.dateKeyPath = dateKeyPath
    self.valueOf = valueOf
    self.seriesOf = seriesOf
    self.color = color
    self.height = height
    self.yAxisLabel = yAxisLabel
    self.tooltipContent = tooltipContent
    self.yDomain = yDomain
    self.xDomain = xDomain
    self.unavailableDates = unavailableDates
    self.onTapDate = onTapDate
    self.symbolSize = symbolSize
    self.extraContent = extraContent()
  }

  var body: some View {
    if data.count == 1 {
      singlePointChart
    } else {
      lineChart
    }
  }

  private var singlePointChart: some View {
    let point = data[0]
    let date = point[keyPath: dateKeyPath]
    let value = valueOf(point)
    let domain = yDomain?(value, value) ?? (value, value)
    let yPadding = domain.0 == domain.1 ? max(abs(domain.0) * 0.1, 1) : 0.0
    let dayInterval: TimeInterval = 86_400
    return Chart {
      extraContent

      PointMark(
        x: .value("Date", date),
        y: .value("Value", value)
      )
      .foregroundStyle(color)
      .symbolSize(symbolSize)

      if hoveredDate == date {
        RuleMark(x: .value("Date", date))
          .foregroundStyle(.secondary.opacity(0.5))
          .lineStyle(StrokeStyle(dash: [4, 4]))
          .annotation(position: .top, alignment: .center) {
            tooltipContent(point)
          }
      }
    }
    .chartXScale(
      domain: xDomain
        ?? date.addingTimeInterval(-dayInterval)...date.addingTimeInterval(dayInterval)
    )
    .chartXAxis {
      AxisMarks(values: [date]) { _ in
        AxisGridLine()
        AxisValueLabel {
          Text(date.settingsFormatted())
        }
      }
    }
    .chartYScale(domain: (domain.0 - yPadding)...(domain.1 + yPadding))
    .chartYAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
          if let val = value.as(Double.self) {
            Text(yAxisLabel(val))
          }
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { _ in
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .onContinuousHoverWhenUnlocked { phase in
            switch phase {
            case .active(let location):
              hoveredDate = ChartHelpers.findNearestDate(
                at: location, in: proxy, points: data, dateKeyPath: dateKeyPath,
                unavailableDates: unavailableDates)

            case .ended:
              hoveredDate = nil
            }
          }
          .onTapGesture { location in
            if let onTapDate,
              let tappedDate = ChartHelpers.findNearestDate(
                at: location, in: proxy, points: data, dateKeyPath: dateKeyPath,
                unavailableDates: unavailableDates)
            {
              onTapDate(tappedDate)
            }
          }
      }
    }
    .frame(height: height)
  }

  private var lineChart: some View {
    let firstDate = data.first![keyPath: dateKeyPath]
    let lastDate = data.last![keyPath: dateKeyPath]
    let yValues = data.map { valueOf($0) }
    let yMin = yValues.min()!
    let yMax = yValues.max()!
    let domain = yDomain?(yMin, yMax) ?? (yMin, yMax)
    return Chart {
      extraContent

      ForEach(data) { point in
        LineMark(
          x: .value("Date", point[keyPath: dateKeyPath]),
          y: .value("Value", valueOf(point)),
          series: .value("Segment", seriesOf(point))
        )
        .foregroundStyle(color)

        PointMark(
          x: .value("Date", point[keyPath: dateKeyPath]),
          y: .value("Value", valueOf(point))
        )
        .foregroundStyle(color)
        .symbolSize(symbolSize)

        if let hoveredDate, point[keyPath: dateKeyPath] == hoveredDate {
          RuleMark(x: .value("Date", hoveredDate))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(dash: [4, 4]))
            .annotation(
              position: .top,
              alignment: point[keyPath: dateKeyPath] == firstDate
                ? .leading
                : point[keyPath: dateKeyPath] == lastDate ? .trailing : .center
            ) {
              tooltipContent(point)
            }
        }
      }
    }
    .chartXScale(domain: xDomain ?? firstDate...lastDate)
    .chartYScale(domain: domain.0...domain.1)
    .chartYAxis {
      AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
          if let val = value.as(Double.self) {
            Text(yAxisLabel(val))
          }
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { _ in
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .onContinuousHoverWhenUnlocked { phase in
            switch phase {
            case .active(let location):
              hoveredDate = ChartHelpers.findNearestDate(
                at: location, in: proxy, points: data, dateKeyPath: dateKeyPath,
                unavailableDates: unavailableDates)

            case .ended:
              hoveredDate = nil
            }
          }
          .onTapGesture { location in
            if let onTapDate,
              let date = ChartHelpers.findNearestDate(
                at: location, in: proxy, points: data, dateKeyPath: dateKeyPath,
                unavailableDates: unavailableDates)
            {
              onTapDate(date)
            }
          }
      }
    }
    .frame(height: height)
  }
}

// MARK: - Empty Extra Content

/// No-op chart content for ``SingleSeriesLineChart`` callers without extra marks.
struct EmptyChartContent: ChartContent {
  var body: some ChartContent {
    ForEach(0..<0, id: \.self) { _ in
      RuleMark(x: .value("", 0)).opacity(0)
    }
  }
}

extension SingleSeriesLineChart where ExtraContent == EmptyChartContent {
  init(
    data: [DataPoint],
    dateKeyPath: KeyPath<DataPoint, Date>,
    valueOf: @escaping (DataPoint) -> Double,
    seriesOf: @escaping (DataPoint) -> Int = { _ in 0 },
    color: Color,
    height: CGFloat,
    yAxisLabel: @escaping (Double) -> String = { ChartDataService.abbreviatedLabel(for: $0) },
    tooltipContent: @escaping (DataPoint) -> TooltipContent,
    yDomain: ((Double, Double) -> (Double, Double))? = nil,
    xDomain: ClosedRange<Date>? = nil,
    unavailableDates: [Date] = [],
    onTapDate: ((Date) -> Void)? = nil,
    symbolSize: CGFloat = 20
  ) {
    self.data = data
    self.dateKeyPath = dateKeyPath
    self.valueOf = valueOf
    self.seriesOf = seriesOf
    self.color = color
    self.height = height
    self.yAxisLabel = yAxisLabel
    self.tooltipContent = tooltipContent
    self.yDomain = yDomain
    self.xDomain = xDomain
    self.unavailableDates = unavailableDates
    self.onTapDate = onTapDate
    self.symbolSize = symbolSize
    self.extraContent = EmptyChartContent()
  }
}
