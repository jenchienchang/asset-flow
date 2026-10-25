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

import Testing

@testable import AssetFlow

@Suite("Category Value Chart Series Tests")
@MainActor
struct CategoryValueChartSeriesTests {
  @Test("Category values and minimums never share a line series")
  func valueAndMinimumAreSeparate() {
    let minimumSeries = (0...3).map { CategoryValueChartSeries.minimum(segment: $0) }

    #expect(!minimumSeries.contains(CategoryValueChartSeries.value))
  }

  @Test("Missing-rate gaps keep minimum line segments separate")
  func minimumGapsStaySeparate() {
    let beforeGap = CategoryValueChartSeries.minimum(segment: 0)
    let afterGap = CategoryValueChartSeries.minimum(segment: 1)

    #expect(beforeGap != afterGap)
  }
}
