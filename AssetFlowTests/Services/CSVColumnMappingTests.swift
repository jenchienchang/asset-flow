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

@Suite("CSVColumnMapping Tests")
@MainActor
struct CSVColumnMappingTests {

  // MARK: - Helpers

  private func csvData(_ string: String) -> Data {
    string.data(using: .utf8)!
  }

  // MARK: - extractHeaders

  @Test("extractHeaders returns correct headers from CSV data")
  func testExtractHeadersValid() {
    let csv = "Symbol,Price,Quantity,Ccy,Account\nAAPL,150,100,USD,Schwab"
    let headers = CSVParsingService.extractHeaders(from: csvData(csv))
    #expect(headers == ["Symbol", "Price", "Quantity", "Ccy", "Account"])
  }

  @Test("extractHeaders returns empty for empty data")
  func testExtractHeadersEmpty() {
    let headers = CSVParsingService.extractHeaders(from: Data())
    #expect(headers.isEmpty)
  }

  @Test("extractHeaders handles BOM")
  func testExtractHeadersBOM() {
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    var data = Data(bom)
    data.append("Name,Value\nA,1".data(using: .utf8)!)
    let headers = CSVParsingService.extractHeaders(from: data)
    #expect(headers == ["Name", "Value"])
  }

  // MARK: - extractSampleRows

  @Test("extractSampleRows returns first N data rows as string arrays")
  func testExtractSampleRows() {
    let csv = "A,B,C\n1,2,3\n4,5,6\n7,8,9\n10,11,12"
    let rows = CSVParsingService.extractSampleRows(from: csvData(csv), count: 3)
    #expect(rows.count == 3)
    #expect(rows[0] == ["1", "2", "3"])
    #expect(rows[1] == ["4", "5", "6"])
    #expect(rows[2] == ["7", "8", "9"])
  }

  @Test("extractSampleRows keeps multiline quoted records together")
  func testExtractSampleRowsPreservesMultilineRecords() {
    let csv =
      "Name,Value\r\n"
      + "\"First line\r\nSecond line\",100\r\n"
      + "Third,200\r\n"

    let rows = CSVParsingService.extractSampleRows(from: csvData(csv), count: nil)

    #expect(rows == [["First line\r\nSecond line", "100"], ["Third", "200"]])
  }

  @Test("extractSampleRows returns empty for header-only CSV")
  func testExtractSampleRowsHeaderOnly() {
    let csv = "A,B,C"
    let rows = CSVParsingService.extractSampleRows(from: csvData(csv))
    #expect(rows.isEmpty)
  }

  // MARK: - autoDetectMapping

  @Test("autoDetectMapping returns matched for exact asset headers (case-insensitive)")
  func testAutoDetectMatchedAsset() {
    let headers = ["asset name", "MARKET VALUE"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .matched(let mapping) = result else {
      Issue.record("Expected .matched")
      return
    }
    #expect(mapping.columnMap[.assetName] == 0)
    #expect(mapping.columnMap[.marketValue] == 1)
  }

  @Test("autoDetectMapping returns matched including optional columns when present")
  func testAutoDetectMatchedWithOptionals() {
    let headers = ["Asset Name", "Market Value", "Platform", "Currency"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .matched(let mapping) = result else {
      Issue.record("Expected .matched")
      return
    }
    #expect(mapping.columnMap[.platform] == 2)
    #expect(mapping.columnMap[.currency] == 3)
  }

  @Test("autoDetectMapping returns needsUserMapping when required column missing")
  func testAutoDetectNeedsMapping() {
    let headers = ["Symbol", "Price", "Platform"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .needsUserMapping = result else {
      Issue.record("Expected .needsUserMapping")
      return
    }
  }

  @Test("autoDetectMapping partial map contains matched optional columns")
  func testAutoDetectPartialMapOptionals() {
    let headers = ["Symbol", "Price", "Platform"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .needsUserMapping(_, let partialMap) = result else {
      Issue.record("Expected .needsUserMapping")
      return
    }
    #expect(partialMap[.platform] == 2)
    #expect(partialMap[.assetName] == nil)
    #expect(partialMap[.marketValue] == nil)
  }

  @Test("autoDetectMapping ignores extra unrecognized columns")
  func testAutoDetectIgnoresExtras() {
    let headers = ["Asset Name", "Market Value", "Quantity", "Notes"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .matched(let mapping) = result else {
      Issue.record("Expected .matched")
      return
    }
    #expect(mapping.columnMap.count == 2)
  }

  @Test("autoDetectMapping works for cash flow schema")
  func testAutoDetectCashFlow() {
    let headers = ["Description", "Amount", "Currency"]
    let result = CSVParsingService.autoDetectMapping(headers: headers, schema: .cashFlow)
    guard case .matched(let mapping) = result else {
      Issue.record("Expected .matched")
      return
    }
    #expect(mapping.columnMap[.description] == 0)
    #expect(mapping.columnMap[.amount] == 1)
    #expect(mapping.columnMap[.currency] == 2)
  }

  // MARK: - parseAssetCSV with mapping

  @Test("parseAssetCSV with mapping parses correctly with remapped columns")
  func testParseAssetCSVWithMapping() {
    let csv = "Symbol,Price,Account\nAAPL,15000,Schwab\nVTI,28000,Fidelity"
    let mapping = CSVColumnMapping(
      schema: .asset,
      columnMap: [.assetName: 0, .marketValue: 1, .platform: 2],
      rawHeaders: ["Symbol", "Price", "Account"]
    )
    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), mapping: mapping, importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 2)
    #expect(result.rows[0].assetName == "AAPL")
    #expect(result.rows[0].marketValue == Decimal(15000))
    #expect(result.rows[0].platform == "Schwab")
    #expect(result.rows[1].assetName == "VTI")
    #expect(result.rows[1].platform == "Fidelity")
  }

  @Test("parseAssetCSV with mapping preserves multiline quoted fields")
  func testParseAssetCSVWithMappingPreservesMultilineFields() {
    let csv =
      "Symbol,Price,Account\r\n"
      + "\"Fund, \"\"A\"\"\r\nSeries 1\",15000,\"Broker, One\"\r\n"
    let mapping = CSVColumnMapping(
      schema: .asset,
      columnMap: [.assetName: 0, .marketValue: 1, .platform: 2],
      rawHeaders: ["Symbol", "Price", "Account"])

    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), mapping: mapping, importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 1)
    guard let row = result.rows.first else { return }
    #expect(row.assetName == "Fund, \"A\"\r\nSeries 1")
    #expect(row.platform == "Broker, One")
  }

  // MARK: - parseCashFlowCSV with mapping

  @Test("parseCashFlowCSV with mapping parses correctly with remapped columns")
  func testParseCashFlowCSVWithMapping() {
    let csv = "Label,Value\nDeposit,5000\nWithdrawal,-2000"
    let mapping = CSVColumnMapping(
      schema: .cashFlow,
      columnMap: [.description: 0, .amount: 1],
      rawHeaders: ["Label", "Value"]
    )
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv), mapping: mapping)

    #expect(result.rows.count == 2)
    #expect(result.rows[0].description == "Deposit")
    #expect(result.rows[0].amount == Decimal(5000))
    #expect(result.rows[1].description == "Withdrawal")
    #expect(result.rows[1].amount == Decimal(-2000))
  }

  // MARK: - Round-trip

  @Test("Round-trip: auto-detect on canonical CSV produces same results as direct parse")
  func testRoundTrip() {
    let csv =
      "Asset Name,Market Value,Platform,Currency\nAAPL,15000,Schwab,USD\nVTI,28000,Fidelity,USD"
    let data = csvData(csv)

    // Direct parse
    let directResult = CSVParsingService.parseAssetCSV(data: data, importPlatform: nil)

    // Auto-detect then parse with mapping
    let headers = CSVParsingService.extractHeaders(from: data)
    let detectResult = CSVParsingService.autoDetectMapping(headers: headers, schema: .asset)
    guard case .matched(let mapping) = detectResult else {
      Issue.record("Expected .matched for canonical headers")
      return
    }
    let mappedResult = CSVParsingService.parseAssetCSV(
      data: data, mapping: mapping, importPlatform: nil)

    #expect(directResult.rows.count == mappedResult.rows.count)
    for i in directResult.rows.indices {
      #expect(directResult.rows[i].assetName == mappedResult.rows[i].assetName)
      #expect(directResult.rows[i].marketValue == mappedResult.rows[i].marketValue)
      #expect(directResult.rows[i].platform == mappedResult.rows[i].platform)
      #expect(directResult.rows[i].currency == mappedResult.rows[i].currency)
    }
  }
}
