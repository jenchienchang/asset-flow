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

@Suite("CalculationService Tests")
@MainActor
struct CalculationServiceTests {

  // MARK: - Growth Rate

  @Test("Growth rate normal case")
  func testGrowthRateNormal() {
    let result = CalculationService.growthRate(
      beginValue: Decimal(100000), endValue: Decimal(110000))
    #expect(result == Decimal(string: "0.1"))
  }

  @Test("Growth rate with loss")
  func testGrowthRateWithLoss() {
    let result = CalculationService.growthRate(
      beginValue: Decimal(100000), endValue: Decimal(90000))
    #expect(result == Decimal(string: "-0.1"))
  }

  @Test("Growth rate with zero beginning value returns nil")
  func testGrowthRateZeroBeginning() {
    let result = CalculationService.growthRate(
      beginValue: Decimal(0), endValue: Decimal(10000))
    #expect(result == nil)
  }

  @Test("Growth rate with negative beginning value returns nil")
  func testGrowthRateNegativeBeginning() {
    let result = CalculationService.growthRate(
      beginValue: Decimal(-5000), endValue: Decimal(10000))
    #expect(result == nil)
  }

  @Test("Growth rate with no change returns zero")
  func testGrowthRateNoChange() {
    let result = CalculationService.growthRate(
      beginValue: Decimal(100000), endValue: Decimal(100000))
    #expect(result == Decimal(0))
  }

  // MARK: - Modified Dietz Return

  @Test("Modified Dietz return with no cash flows")
  func testModifiedDietzNoCashFlows() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100000),
      endValue: Decimal(110000),
      cashFlows: [],
      totalDays: 90
    )
    // (110000 - 100000 - 0) / (100000 + 0) = 0.1
    #expect(result == Decimal(string: "0.1"))
  }

  @Test("Modified Dietz return with cash flow at start of period")
  func testModifiedDietzCashFlowAtStart() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100000),
      endValue: Decimal(215000),
      cashFlows: [(amount: Decimal(100000), daysSinceStart: 0)],
      totalDays: 90
    )
    // weight = (90-0)/90 = 1.0
    // R = (215000 - 100000 - 100000) / (100000 + 1.0 * 100000) = 15000/200000 = 0.075
    #expect(result == Decimal(string: "0.075"))
  }

  @Test("Modified Dietz return with cash flow mid-period")
  func testModifiedDietzCashFlowMidPeriod() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100000),
      endValue: Decimal(215000),
      cashFlows: [(amount: Decimal(100000), daysSinceStart: 30)],
      totalDays: 90
    )
    // weight = (90-30)/90 = 60/90 = 2/3
    // R = (215000 - 100000 - 100000) / (100000 + (2/3)*100000) = 15000/166666.67
    let expected = Decimal(15000) / (Decimal(100000) + Decimal(2) / Decimal(3) * Decimal(100000))
    #expect(result != nil)
    // Compare with tolerance since Decimal division may have precision differences
    if let r = result {
      let diff = abs(r - expected)
      #expect(diff < Decimal(string: "0.0001")!)
    }
  }

  @Test("Modified Dietz return with cash flow at end of period")
  func testModifiedDietzCashFlowAtEnd() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100000),
      endValue: Decimal(215000),
      cashFlows: [(amount: Decimal(100000), daysSinceStart: 90)],
      totalDays: 90
    )
    // weight = (90-90)/90 = 0
    // R = (215000 - 100000 - 100000) / (100000 + 0) = 15000/100000 = 0.15
    #expect(result == Decimal(string: "0.15"))
  }

  @Test("Modified Dietz return with zero beginning value returns nil")
  func testModifiedDietzZeroBeginning() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(0),
      endValue: Decimal(10000),
      cashFlows: [],
      totalDays: 90
    )
    #expect(result == nil)
  }

  @Test("Modified Dietz return with zero denominator returns nil")
  func testModifiedDietzZeroDenominator() {
    // BMV=100, cash flow of -100 at start (weight=1.0) -> denom = 100 + 1*(-100) = 0
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100),
      endValue: Decimal(50),
      cashFlows: [(amount: Decimal(-100), daysSinceStart: 0)],
      totalDays: 90
    )
    #expect(result == nil)
  }

  @Test("Modified Dietz return with negative denominator returns nil")
  func testModifiedDietzNegativeDenominator() {
    // BMV=100, cash flow of -200 at start -> denom = 100 + 1*(-200) = -100
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100),
      endValue: Decimal(50),
      cashFlows: [(amount: Decimal(-200), daysSinceStart: 0)],
      totalDays: 90
    )
    #expect(result == nil)
  }

  @Test("Modified Dietz return with multiple cash flows")
  func testModifiedDietzMultipleCashFlows() {
    let result = CalculationService.modifiedDietzReturn(
      beginValue: Decimal(100000),
      endValue: Decimal(280000),
      cashFlows: [
        (amount: Decimal(50000), daysSinceStart: 30),
        (amount: Decimal(100000), daysSinceStart: 60),
      ],
      totalDays: 90
    )
    // CF total = 150000
    // w1 = (90-30)/90 = 2/3, w2 = (90-60)/90 = 1/3
    // weighted = (2/3)*50000 + (1/3)*100000 = 33333.33 + 33333.33 = 66666.67
    // R = (280000 - 100000 - 150000) / (100000 + 66666.67) = 30000/166666.67
    #expect(result != nil)
  }

  // MARK: - Cumulative TWR

  @Test("Cumulative TWR chains returns correctly")
  func testCumulativeTWRChains() {
    // (1+0.10) * (1+0.05) * (1-0.02) - 1
    let result = CalculationService.cumulativeTWR(
      periodReturns: [
        Decimal(string: "0.10")!,
        Decimal(string: "0.05")!,
        Decimal(string: "-0.02")!,
      ])
    // 1.10 * 1.05 * 0.98 - 1 = 1.1319 - 1 = 0.1319
    let expected =
      Decimal(string: "1.10")! * Decimal(string: "1.05")! * Decimal(string: "0.98")!
      - 1
    #expect(result == expected)
  }

  @Test("Cumulative TWR with empty returns is zero")
  func testCumulativeTWREmpty() {
    let result = CalculationService.cumulativeTWR(periodReturns: [])
    #expect(result == Decimal(0))
  }

  @Test("Cumulative TWR with single period equals that period")
  func testCumulativeTWRSinglePeriod() {
    let result = CalculationService.cumulativeTWR(
      periodReturns: [Decimal(string: "0.15")!])
    #expect(result == Decimal(string: "0.15")!)
  }

  // MARK: - CAGR

  @Test("CAGR normal case")
  func testCAGRNormal() {
    // 100000 -> 121000 over 2 years: CAGR = (1.21)^0.5 - 1 = 0.1 (10%)
    let result = CalculationService.cagr(
      beginValue: Decimal(100000), endValue: Decimal(121000), years: 2.0)
    #expect(result != nil)
    if let r = result {
      let diff = abs(r - Decimal(string: "0.1")!)
      #expect(diff < Decimal(string: "0.001")!)
    }
  }

  @Test("CAGR with fractional years")
  func testCAGRFractionalYears() {
    let result = CalculationService.cagr(
      beginValue: Decimal(100000), endValue: Decimal(110000), years: 0.5)
    #expect(result != nil)
    if let result {
      let expected = Decimal(string: "0.21")!
      let tolerance = Decimal(string: "0.000000000000000000000000000001")!
      #expect(abs(result - expected) < tolerance)
    }
  }

  @Test("CAGR preserves a sub-Double increment in a large portfolio")
  func testCAGRPreservesPrecisionForLargeValues() {
    let beginValue = Decimal(string: "10000000000000000")!
    let endValue = Decimal(string: "10000000000000001")!
    let expected = Decimal(string: "0.0000000000000001")!

    let result = CalculationService.cagr(
      beginValue: beginValue, endValue: endValue, years: 1.0)

    #expect(result != nil)
    if let result {
      #expect(abs(result - expected) < Decimal(string: "0.00000000000000000001")!)
    }
  }

  @Test("CAGR with zero beginning value returns nil")
  func testCAGRZeroBeginning() {
    let result = CalculationService.cagr(
      beginValue: Decimal(0), endValue: Decimal(10000), years: 1.0)
    #expect(result == nil)
  }

  @Test("CAGR with negative beginning value returns nil")
  func testCAGRNegativeBeginning() {
    let result = CalculationService.cagr(
      beginValue: Decimal(-5000), endValue: Decimal(10000), years: 1.0)
    #expect(result == nil)
  }

  @Test("CAGR with zero years returns nil")
  func testCAGRZeroYears() {
    let result = CalculationService.cagr(
      beginValue: Decimal(100000), endValue: Decimal(110000), years: 0.0)
    #expect(result == nil)
  }

  // MARK: - Category Allocation

  @Test("Category allocation percentage")
  func testCategoryAllocation() {
    let result = CalculationService.categoryAllocation(
      categoryValue: Decimal(60000), totalValue: Decimal(100000))
    #expect(result == Decimal(60))
  }

  @Test("Category allocation with zero total returns 0")
  func testCategoryAllocationZeroTotal() {
    let result = CalculationService.categoryAllocation(
      categoryValue: Decimal(1000), totalValue: Decimal(0))
    #expect(result == Decimal(0))
  }

  @Test("Category allocation with zero value returns 0")
  func testCategoryAllocationZeroValue() {
    let result = CalculationService.categoryAllocation(
      categoryValue: Decimal(0), totalValue: Decimal(100000))
    #expect(result == Decimal(0))
  }

  @Test("Category allocation preserves precision")
  func testCategoryAllocationPrecision() {
    let result = CalculationService.categoryAllocation(
      categoryValue: Decimal(33333), totalValue: Decimal(100000))
    #expect(result == Decimal(string: "33.333")!)
  }
}
