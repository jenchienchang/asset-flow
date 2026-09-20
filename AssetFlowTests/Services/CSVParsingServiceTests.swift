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

@Suite("CSVParsingService Tests")
@MainActor
struct CSVParsingServiceTests {

  // MARK: - Helpers

  private func csvData(_ string: String) -> Data {
    string.data(using: .utf8)!
  }

  private func localizedImportMessage(
    _ value: String.LocalizationValue
  ) -> String {
    CSVParsingService.localizedImportMessage(value)
  }

  @Test("CSV parser diagnostics include Traditional Chinese localizations")
  func csvParserDiagnosticsIncludeTraditionalChineseLocalizations() throws {
    let repositoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let catalogURL =
      repositoryURL
      .appending(path: "AssetFlow/Resources/Import.xcstrings")
    let data = try Data(contentsOf: catalogURL)
    let root = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    let keys = [
      "Expected UTF-8 encoded text.",
      "Malformed CSV quoting.",
      "Expected %lld fields but found %lld.",
      "The CSV value could not be parsed.",
      "The CSV file is missing a column.",
      "The CSV row is out of bounds.",
      "Unable to read CSV data.",
      "Missing required column: Asset Name",
      "Missing required column: Market Value",
      "Missing required column: Description",
      "Missing required column: Amount",
      "Asset name is empty.",
      "Cannot parse '%@' as a number.",
      "Description is empty.",
      "File is empty or contains no data.",
      "File contains no data rows.",
      "Mapping missing required columns.",
      "Duplicate asset '%@' (platform: '%@') — first appeared in row %lld.",
      "Duplicate description '%@' — first appeared in row %lld.",
    ]

    for key in keys {
      let entry = try #require(strings[key] as? [String: Any], "Missing key: \(key)")
      let localizations = try #require(
        entry["localizations"] as? [String: Any],
        "Missing localizations: \(key)")
      let traditionalChinese = try #require(
        localizations["zh-Hant"] as? [String: Any],
        "Missing zh-Hant localization: \(key)")
      let unit = try #require(
        traditionalChinese["stringUnit"] as? [String: Any],
        "Missing zh-Hant string unit: \(key)")
      #expect(unit["state"] as? String == "translated")
      #expect((unit["value"] as? String)?.isEmpty == false)
    }
  }

  // MARK: - Asset CSV: Valid Parsing

  @Test("Valid asset CSV parses correctly")
  func testValidAssetCSV() {
    let csv = """
      Asset Name,Market Value,Platform
      AAPL,15000,Interactive Brokers
      VTI,28000,Interactive Brokers
      Bitcoin,5000,Coinbase
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 3)
    #expect(result.rows[0].assetName == "AAPL")
    #expect(result.rows[0].marketValue == Decimal(15000))
    #expect(result.rows[0].platform == "Interactive Brokers")
    #expect(result.rows[2].assetName == "Bitcoin")
    #expect(result.rows[2].platform == "Coinbase")
  }

  @Test("Asset CSV without platform column")
  func testAssetCSVWithoutPlatformColumn() {
    let csv = """
      Asset Name,Market Value
      AAPL,15000
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows[0].platform == "")
  }

  // MARK: - Asset CSV: Missing Required Columns

  @Test("Missing Asset Name column returns error")
  func testMissingAssetNameColumn() {
    let csv = """
      Market Value,Platform
      15000,Firstrade
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(result.errors[0].message.contains("Asset Name"))
  }

  @Test("Missing Market Value column returns error")
  func testMissingMarketValueColumn() {
    let csv = """
      Asset Name,Platform
      AAPL,Firstrade
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(result.errors[0].message.contains("Market Value"))
  }

  @Test("Missing both Asset Name and Market Value columns reports 2 errors")
  func testMissingBothAssetColumns() {
    let csv = """
      Platform,Extra
      Firstrade,ignored
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(result.errors.count == 2)
    #expect(result.errors.contains(where: { $0.message.contains("Asset Name") }))
    #expect(result.errors.contains(where: { $0.message.contains("Market Value") }))
  }

  // MARK: - Asset CSV: Row Validation

  @Test("Empty asset name returns error")
  func testEmptyAssetName() {
    let csv = """
      Asset Name,Market Value
      ,15000
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(
      result.errors[0].message
        == localizedImportMessage("Asset name is empty."))
  }

  @Test("Unparseable market value returns error")
  func testUnparseableMarketValue() {
    let csv = """
      Asset Name,Market Value
      AAPL,abc
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(
      result.errors[0].message
        == localizedImportMessage("Cannot parse '\("abc")' as a number."))
  }

  @Test("Empty file returns error")
  func testEmptyFile() {
    let result = CSVParsingService.parseAssetCSV(data: csvData(""), importPlatform: nil)

    #expect(result.hasErrors)
  }

  @Test("Header only returns error")
  func testHeaderOnlyFile() {
    let csv = "Asset Name,Market Value\n"
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(
      result.errors[0].message
        == localizedImportMessage("File contains no data rows."))
  }

  // MARK: - Asset CSV: Platform Handling (SPEC 4.5)

  @Test("Import-level platform overrides CSV column")
  func testImportPlatformOverrides() {
    let csv = """
      Asset Name,Market Value,Platform
      AAPL,15000,Some Other Broker
      """
    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), importPlatform: "Firstrade")

    #expect(result.rows[0].platform == "Firstrade")
  }

  @Test("No platform column and no import platform gives empty platform")
  func testNoPlatformAtAll() {
    let csv = """
      Asset Name,Market Value
      AAPL,15000
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.rows[0].platform == "")
  }

  // MARK: - Asset CSV: Warnings

  @Test("Zero market value generates warning")
  func testZeroMarketValueWarning() {
    let csv = """
      Asset Name,Market Value
      AAPL,0
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(
      result.warnings.contains {
        $0.message
          == localizedImportMessage("Market value is zero for '\("AAPL")'.")
      })
  }

  @Test("Negative market value generates warning")
  func testNegativeMarketValueWarning() {
    let csv = """
      Asset Name,Market Value
      AAPL,-500
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(
      result.warnings.contains {
        $0.message
          == localizedImportMessage("Market value is negative for '\("AAPL")'.")
      })
  }

  @Test("Unrecognized columns generate warning")
  func testUnrecognizedColumnsWarning() {
    let csv = """
      Asset Name,Market Value,Extra Column
      AAPL,15000,ignored
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.warnings.contains(where: { $0.column == "Extra Column" }))
  }

  // MARK: - Asset CSV: Duplicate Detection (SPEC 4.6)

  @Test("Duplicate assets within CSV returns error")
  func testDuplicateAssetsInCSV() {
    let csv = """
      Asset Name,Market Value,Platform
      AAPL,15000,Firstrade
      AAPL,16000,Firstrade
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(
      result.errors.contains {
        $0.message
          == localizedImportMessage(
            "Duplicate asset '\("AAPL")' (platform: '\("Firstrade")') — first appeared in row \(2)."
          )
      })
  }

  @Test("Same asset name on different platforms is not a duplicate")
  func testSameNameDifferentPlatformNotDuplicate() {
    let csv = """
      Asset Name,Market Value,Platform
      AAPL,15000,Firstrade
      AAPL,16000,Schwab
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 2)
  }

  @Test("Case-insensitive duplicate detection")
  func testCaseInsensitiveDuplicateDetection() {
    let csv = """
      Asset Name,Market Value,Platform
      AAPL,15000,Firstrade
      aapl,16000,firstrade
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(
      result.errors.contains {
        $0.message
          == localizedImportMessage(
            "Duplicate asset '\("aapl")' (platform: '\("firstrade")') — first appeared in row \(2)."
          )
      })
  }

  // MARK: - Asset CSV: Number Parsing

  @Test("BOM tolerance")
  func testBOMTolerance() {
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    let csvString = "Asset Name,Market Value\nAAPL,15000\n"
    var data = Data(bom)
    data.append(csvString.data(using: .utf8)!)

    let result = CSVParsingService.parseAssetCSV(data: data, importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 1)
  }

  @Test("Thousand separator stripping")
  func testThousandSeparatorStripping() {
    let csv = """
      Asset Name,Market Value
      AAPL,"15,000.50"
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows[0].marketValue == Decimal(string: "15000.50"))
  }

  @Test("Asset CSV preserves RFC quoted commas, escaped quotes, and multiline fields")
  func testAssetCSVPreservesRFCQuotedFields() {
    let csv =
      "Asset Name,Market Value,Platform,Currency\r\n"
      + "\"Fund, \"\"A\"\"\r\nSeries 1\",15000,\"Broker, One\",USD\r\n"

    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows.count == 1)
    guard let row = result.rows.first else { return }
    #expect(row.assetName == "Fund, \"A\"\r\nSeries 1")
    #expect(row.platform == "Broker, One")
    #expect(row.currency == "USD")
  }

  @Test("Asset CSV rejects rows with an incorrect number of fields")
  func testAssetCSVRejectsIncorrectFieldCount() {
    let csv = "Asset Name,Market Value\nAAPL,15000,Unexpected\n"

    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(result.rows.isEmpty)
  }

  @Test("Asset CSV rejects quotes in unquoted fields")
  func testAssetCSVRejectsMisplacedQuote() {
    let csv = "Asset Name,Market Value\nA\"APL,15000\n"

    let result = CSVParsingService.parseAssetCSV(
      data: csvData(csv), importPlatform: nil)

    #expect(result.hasErrors)
    #expect(result.rows.isEmpty)
  }

  @Test("Currency symbol stripping")
  func testCurrencySymbolStripping() {
    let csv = """
      Asset Name,Market Value
      AAPL,$15000
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows[0].marketValue == Decimal(15000))
  }

  @Test("Whitespace trimming in values")
  func testWhitespaceTrimming() {
    let csv = """
      Asset Name,Market Value
       AAPL , 15000
      """
    let result = CSVParsingService.parseAssetCSV(data: csvData(csv), importPlatform: nil)

    #expect(result.isValid)
    #expect(result.rows[0].assetName == "AAPL")
    #expect(result.rows[0].marketValue == Decimal(15000))
  }

  // MARK: - Cash Flow CSV: Valid Parsing

  @Test("Valid cash flow CSV parses correctly")
  func testValidCashFlowCSV() {
    let csv = """
      Description,Amount
      Salary deposit,50000
      Emergency fund transfer,-10000
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.isValid)
    #expect(result.rows.count == 2)
    #expect(result.rows[0].description == "Salary deposit")
    #expect(result.rows[0].amount == Decimal(50000))
    #expect(result.rows[1].amount == Decimal(-10000))
  }

  @Test("Cash flow CSV preserves escaped quotes and multiline descriptions")
  func testCashFlowCSVPreservesRFCQuotedFields() {
    let csv =
      "Description,Amount,Currency\r\n"
      + "\"Transfer, \"\"special\"\"\r\nSecond line\",25,USD\r\n"

    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.isValid)
    #expect(result.rows.count == 1)
    guard let row = result.rows.first else { return }
    #expect(row.description == "Transfer, \"special\"\r\nSecond line")
    #expect(row.amount == Decimal(25))
    #expect(row.currency == "USD")
  }

  // MARK: - Cash Flow CSV: Missing Columns

  @Test("Missing Description column returns error")
  func testMissingDescriptionColumn() {
    let csv = """
      Amount
      50000
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(result.errors[0].message.contains("Description"))
  }

  @Test("Missing Amount column returns error")
  func testMissingAmountColumn() {
    let csv = """
      Description
      Salary deposit
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(result.errors[0].message.contains("Amount"))
  }

  @Test("Missing both Description and Amount columns reports 2 errors")
  func testMissingBothCashFlowColumns() {
    let csv = """
      Extra
      ignored
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(result.errors.count == 2)
    #expect(result.errors.contains(where: { $0.message.contains("Description") }))
    #expect(result.errors.contains(where: { $0.message.contains("Amount") }))
  }

  // MARK: - Cash Flow CSV: Row Validation

  @Test("Empty description returns error")
  func testEmptyDescription() {
    let csv = """
      Description,Amount
      ,50000
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(
      result.errors[0].message
        == localizedImportMessage("Description is empty."))
  }

  @Test("Unparseable amount returns error")
  func testUnparseableAmount() {
    let csv = """
      Description,Amount
      Deposit,abc
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(
      result.errors[0].message
        == localizedImportMessage("Cannot parse '\("abc")' as a number."))
  }

  @Test("Zero amount generates warning")
  func testZeroAmountWarning() {
    let csv = """
      Description,Amount
      No-op,0
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.isValid)
    #expect(
      result.warnings.contains {
        $0.message == localizedImportMessage("Amount is zero for '\("No-op")'.")
      })
  }

  // MARK: - Cash Flow CSV: Duplicate Detection

  @Test("Duplicate cash flow descriptions returns error")
  func testDuplicateCashFlowDescriptions() {
    let csv = """
      Description,Amount
      Salary deposit,50000
      Salary deposit,30000
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(
      result.errors.contains {
        $0.message
          == localizedImportMessage(
            "Duplicate description '\("Salary deposit")' — first appeared in row \(2).")
      })
  }

  @Test("Case-insensitive cash flow duplicate detection")
  func testCaseInsensitiveCashFlowDuplicates() {
    let csv = """
      Description,Amount
      Salary Deposit,50000
      salary deposit,30000
      """
    let result = CSVParsingService.parseCashFlowCSV(data: csvData(csv))

    #expect(result.hasErrors)
    #expect(
      result.errors.contains {
        $0.message
          == localizedImportMessage(
            "Duplicate description '\("salary deposit")' — first appeared in row \(2).")
      })
  }
}
