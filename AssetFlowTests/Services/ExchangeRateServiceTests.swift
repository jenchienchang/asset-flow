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
import Testing

@testable import AssetFlow

private final class MockHTTPClient: @unchecked Sendable {
  private let lock = NSLock()
  private var callCount = 0
  private let handler: @Sendable (URLRequest, Int) async throws -> (HTTPURLResponse, Data)

  init(handler: @escaping @Sendable (URLRequest, Int) async throws -> (HTTPURLResponse, Data)) {
    self.handler = handler
  }

  var requestCount: Int { lock.withLock { callCount } }

  func loadData(from url: URL) async throws -> (Data, URLResponse) {
    let requestNumber = lock.withLock {
      callCount += 1
      return callCount
    }
    let (response, data) = try await handler(URLRequest(url: url), requestNumber)
    return (data, response)
  }
}

private actor CancellationSignal {
  private var pendingSignals = 0

  func signal() {
    pendingSignals += 1
  }

  func consumeIfSignaled() -> Bool {
    guard pendingSignals > 0 else { return false }
    pendingSignals -= 1
    return true
  }

  func reset() {
    pendingSignals = 0
  }
}

private actor RequestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters {
      waiter.resume()
    }
    waiters.removeAll()
  }
}

private final class CancellationTrackingURLProtocol: URLProtocol, @unchecked Sendable {
  static let started = CancellationSignal()
  static let stopped = CancellationSignal()

  static func reset() async {
    await started.reset()
    await stopped.reset()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Task { await Self.started.signal() }
  }

  override func stopLoading() {
    Task { await Self.stopped.signal() }
  }
}

private func requestedAPIResponseDate(from request: URLRequest) -> String {
  guard
    let component = request.url?.pathComponents.first(where: {
      $0.hasPrefix("currency-api@")
    }),
    let atIndex = component.lastIndex(of: "@")
  else {
    return ""
  }
  return String(component[component.index(after: atIndex)...])
}

@Suite("ExchangeRate Service Tests")
@MainActor
struct ExchangeRateServiceTests {

  private func createMockService(
    handler: @escaping @Sendable (URLRequest, Int) async throws -> (HTTPURLResponse, Data)
  ) -> ExchangeRateService {
    createMockService(client: MockHTTPClient(handler: handler))
  }

  private func createMockService(
    client: MockHTTPClient,
    requestCoordinator: ExchangeRateRequestCoordinator = ExchangeRateRequestCoordinator()
  ) -> ExchangeRateService {
    ExchangeRateService(
      requestCoordinator: requestCoordinator,
      loadData: { url in try await client.loadData(from: url) }
    )
  }

  private func coordinator(signalingSecondWaiter signal: CancellationSignal)
    -> ExchangeRateRequestCoordinator
  {
    ExchangeRateRequestCoordinator(onWaiterRegistered: { _, count in
      if count == 2 {
        Task { await signal.signal() }
      }
    })
  }

  private func waitForSignal(_ signal: CancellationSignal, attempts: Int = 200) async -> Bool {
    for _ in 0..<attempts {
      if await signal.consumeIfSignaled() {
        return true
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
  }

  @Test("Goal-only currency triggers fetching even with no foreign-currency assets")
  func goalOnlyCurrencyFetch() async throws {
    let service = createMockService { request, _ in
      let json =
        "{\"date\": \"\(requestedAPIResponseDate(from: request))\", \"usd\": {\"twd\": 30}}"
      return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(json.utf8)
      )
    }
    let container = TestDataManager.createInMemoryContainer()
    let category = AssetFlow.Category(name: "Reserve")
    category.minimumBalanceAmount = 300000
    category.minimumBalanceCurrency = "TWD"
    let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
    container.mainContext.insert(category)
    container.mainContext.insert(snapshot)
    let result = await service.fetchMissingRates(
      snapshots: [snapshot], displayCurrency: "USD", modelContext: container.mainContext)
    #expect(result.count == 1)
    #expect(snapshot.exchangeRate?.rates["twd"] == 30)
    #expect(
      CategoryGoalAssessmentService.assess(
        snapshot: snapshot, categories: [category], displayCurrency: "USD"
      ).goalConversion.isComplete)
  }

  // MARK: - Fetch Rates Tests

  @Test("Fetch rates returns valid parsed rates")
  func testFetchRatesSuccess() async throws {
    let service = createMockService { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.92, "twd": 31.5, "jpy": 149.5}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let rates = try await service.fetchRates(
      for: Date(), baseCurrency: "usd")

    #expect(rates["eur"] == Decimal(string: "0.92")!)
    #expect(rates["twd"] == Decimal(string: "31.5")!)
    #expect(rates["jpy"] == Decimal(string: "149.5")!)
  }

  @Test("Fetch rates preserves high-precision decimal values")
  func testFetchRatesPreservesPrecision() async throws {
    let service = createMockService { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.920000000000000000123456789}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let rates = try await service.fetchRates(for: Date(), baseCurrency: "usd")

    #expect(rates["eur"] == Decimal(string: "0.920000000000000000123456789")!)
  }

  @Test("Fetch rates throws networkUnavailable on error")
  func testFetchRatesNetworkError() async throws {
    let service = createMockService { _, _ in
      throw URLError(.notConnectedToInternet)
    }

    await #expect(throws: ExchangeRateError.self) {
      _ = try await service.fetchRates(for: Date(), baseCurrency: "usd")
    }
  }

  @Test("Fetch rates throws ratesNotFound on 404")
  func testFetchRatesNotFound() async throws {
    let service = createMockService { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data())
    }

    await #expect(throws: ExchangeRateError.ratesNotFound) {
      _ = try await service.fetchRates(for: Date(), baseCurrency: "usd")
    }
  }

  @Test("Fetch rates throws invalidResponse on malformed JSON")
  func testFetchRatesInvalidJSON() async throws {
    let service = createMockService { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, "not json".data(using: .utf8)!)
    }

    await #expect(throws: ExchangeRateError.invalidResponse) {
      _ = try await service.fetchRates(for: Date(), baseCurrency: "usd")
    }
  }

  @Test("Fetch rates rejects an empty rates dictionary")
  func testFetchRatesRejectsEmptyRates() async throws {
    let service = createMockService { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    await #expect(throws: ExchangeRateError.invalidResponse) {
      _ = try await service.fetchRates(for: Date(), baseCurrency: "usd")
    }
  }

  @Test("Fetch rates rejects non-positive rates")
  func testFetchRatesRejectsNonPositiveRates() async throws {
    let service = createMockService { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0, "twd": -1}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    await #expect(throws: ExchangeRateError.invalidResponse) {
      _ = try await service.fetchRates(for: Date(), baseCurrency: "usd")
    }
  }

  @Test("Fetch rates rejects a response for a different date")
  func testFetchRatesRejectsWrongResponseDate() async throws {
    let json = """
      {"date": "2000-01-01", "usd": {"eur": 0.92}}
      """
    let service = createMockService { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let date = Date(timeIntervalSince1970: 1_771_747_200)

    await #expect(throws: ExchangeRateError.invalidResponse) {
      _ = try await service.fetchRates(for: date, baseCurrency: "usd")
    }
  }

  @Test("API date formatting always uses Gregorian calendar components")
  func testFetchRatesUsesFixedGregorianDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 22))!

    let dateString = ExchangeRateService.apiDateString(
      for: date,
      timeZone: TimeZone(secondsFromGMT: 0)!
    )

    #expect(dateString == "2026-02-22")
  }

  @Test("Concurrent requests for the same date and base share one network request")
  func testFetchRatesDoesNotDuplicateConcurrentRequests() async throws {
    let gate = RequestGate()
    let requestStarted = CancellationSignal()
    let secondWaiterRegistered = CancellationSignal()
    let client = MockHTTPClient { request, _ in
      await requestStarted.signal()
      await gate.wait()
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.92}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let service = createMockService(
      client: client,
      requestCoordinator: coordinator(signalingSecondWaiter: secondWaiterRegistered)
    )
    let date = Date(timeIntervalSince1970: 1_771_747_200)
    let firstTask = Task { try await service.fetchRates(for: date, baseCurrency: "USD") }
    let firstRequestStarted = await waitForSignal(requestStarted)
    let secondTask = Task { try await service.fetchRates(for: date, baseCurrency: "USD") }
    let secondWaiterJoined = await waitForSignal(secondWaiterRegistered)
    await gate.open()
    let firstResult = await firstTask.result
    let secondResult = await secondTask.result

    #expect(firstRequestStarted)
    #expect(secondWaiterJoined)
    #expect(try firstResult.get()["eur"] == Decimal(string: "0.92")!)
    #expect(try secondResult.get()["eur"] == Decimal(string: "0.92")!)
    #expect(client.requestCount == 1)
  }

  @Test("Separate coordinators use their own handlers for concurrent same-key requests")
  func testSeparateCoordinatorsKeepHandlersIsolated() async throws {
    let gate = RequestGate()
    let firstStarted = CancellationSignal()
    let secondStarted = CancellationSignal()
    let firstClient = MockHTTPClient { request, _ in
      await firstStarted.signal()
      await gate.wait()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let json =
        "{\"date\":\"\(requestedAPIResponseDate(from: request))\",\"usd\":{\"eur\":0.92}}"
      return (response, Data(json.utf8))
    }
    let secondClient = MockHTTPClient { request, _ in
      await secondStarted.signal()
      await gate.wait()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let json =
        "{\"date\":\"\(requestedAPIResponseDate(from: request))\",\"usd\":{\"eur\":0.85}}"
      return (response, Data(json.utf8))
    }
    let firstService = createMockService(client: firstClient)
    let secondService = createMockService(client: secondClient)
    let date = Date(timeIntervalSince1970: 1_771_747_200)

    let firstTask = Task { try await firstService.fetchRates(for: date, baseCurrency: "USD") }
    #expect(await waitForSignal(firstStarted))
    let secondTask = Task { try await secondService.fetchRates(for: date, baseCurrency: "USD") }
    let secondHandlerStarted = await waitForSignal(secondStarted)
    await gate.open()

    #expect(secondHandlerStarted)
    #expect(try await firstTask.value["eur"] == Decimal(string: "0.92")!)
    #expect(try await secondTask.value["eur"] == Decimal(string: "0.85")!)
    #expect(firstClient.requestCount == 1)
    #expect(secondClient.requestCount == 1)
  }

  // MARK: - Currency List Tests

  @Test("Fetch currency list returns valid dict")
  func testFetchCurrencyListSuccess() async throws {
    let json = """
      {"usd": "United States Dollar", "eur": "Euro", "twd": "New Taiwan Dollar"}
      """
    let service = createMockService { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let list = try await service.fetchCurrencyList()

    #expect(list["usd"] == "United States Dollar")
    #expect(list["eur"] == "Euro")
    #expect(list.count == 3)
  }

  // MARK: - Fetch Missing Rates Tests

  private func createSnapshotWithAsset(
    currency: String,
    container: ModelContainer
  ) -> Snapshot {
    let context = container.mainContext
    let snapshot = Snapshot(date: Date())
    context.insert(snapshot)

    let asset = Asset(name: "Test Asset \(UUID().uuidString)")
    asset.currency = currency
    context.insert(asset)

    let assetValue = SnapshotAssetValue(marketValue: 1000)
    assetValue.snapshot = snapshot
    assetValue.asset = asset
    context.insert(assetValue)

    return snapshot
  }

  private func mockSuccessHandler(baseCurrency: String)
    -> @Sendable (URLRequest, Int) throws -> (
      HTTPURLResponse, Data
    )
  {
    { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "\(baseCurrency)": {"eur": 0.92, "twd": 31.5, "jpy": 149.5, "usd": 1.0}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }
  }

  @Test("fetchMissingRates skips snapshots that already have exchange rates")
  func testFetchMissingRatesSkipsSnapshotsWithExistingRates() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "EUR", container: container)

    // Attach an existing ExchangeRate
    let ratesJSON = try! JSONEncoder().encode(["eur": 0.92])
    let er = ExchangeRate(baseCurrency: "usd", ratesJSON: ratesJSON, fetchDate: snapshot.date)
    er.snapshot = snapshot
    context.insert(er)

    let client = MockHTTPClient { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, "{}".data(using: .utf8)!)
    }

    let service = createMockService(client: client)
    _ = await service.fetchMissingRates(
      snapshots: [snapshot],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(client.requestCount == 0)
  }

  @Test("fetchMissingRates retries malformed cached rates")
  func testFetchMissingRatesRetriesMalformedCachedRates() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "EUR", container: container)

    let er = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: Data("not-json".utf8),
      fetchDate: snapshot.date
    )
    er.snapshot = snapshot
    context.insert(er)

    let client = MockHTTPClient { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.92}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let service = createMockService(client: client)
    _ = await service.fetchMissingRates(
      snapshots: [snapshot],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(client.requestCount == 1)
    #expect(snapshot.exchangeRate?.rates["eur"] == Decimal(string: "0.92")!)
  }

  @Test("fetchMissingRates refreshes a complete cached record with the wrong date")
  func testFetchMissingRatesRefreshesWrongDateCachedRates() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "EUR", container: container)

    let ratesJSON = try! JSONEncoder().encode(["eur": 0.92])
    let er = ExchangeRate(
      baseCurrency: "usd",
      ratesJSON: ratesJSON,
      fetchDate: Date(timeIntervalSince1970: 0)
    )
    er.snapshot = snapshot
    context.insert(er)

    let client = MockHTTPClient { request, _ in
      let json = """
        {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.92}}
        """
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json.data(using: .utf8)!)
    }

    let service = createMockService(client: client)
    let results = await service.fetchMissingRates(
      snapshots: [snapshot],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(client.requestCount == 1)
    #expect(results.first?.status == .fetched)
    #expect(snapshot.exchangeRate?.fetchDate == snapshot.date)
  }

  @Test("fetchMissingRates propagates cancellation and does not cache rates")
  func testFetchMissingRatesPropagatesCancellation() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "EUR", container: container)

    await CancellationTrackingURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CancellationTrackingURLProtocol.self]
    let service = ExchangeRateService(
      session: URLSession(configuration: configuration),
      requestCoordinator: ExchangeRateRequestCoordinator()
    )

    let fetchTask = Task {
      await service.fetchMissingRates(
        snapshots: [snapshot],
        displayCurrency: "USD",
        modelContext: context
      )
    }

    #expect(await waitForSignal(CancellationTrackingURLProtocol.started))
    fetchTask.cancel()
    let results = await fetchTask.value

    #expect(results.first?.status == .cancelled)
    #expect(snapshot.exchangeRate == nil)
    #expect(await waitForSignal(CancellationTrackingURLProtocol.stopped))
  }

  @Test("cancelling one coalesced waiter does not block or cancel the other")
  func testCancellingOneCoalescedWaiterDoesNotCancelTheOther() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot1 = createSnapshotWithAsset(currency: "EUR", container: container)
    let snapshot2 = createSnapshotWithAsset(currency: "EUR", container: container)
    snapshot2.date = snapshot1.date

    let gate = RequestGate()
    let requestStarted = CancellationSignal()
    let firstTaskCompleted = CancellationSignal()
    let secondWaiterRegistered = CancellationSignal()
    let client = MockHTTPClient { request, _ in
      await requestStarted.signal()
      await gate.wait()
      try Task.checkCancellation()
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      let json =
        "{\"date\":\"\(requestedAPIResponseDate(from: request))\",\"usd\":{\"eur\":0.92}}"
      return (response, Data(json.utf8))
    }
    let service = createMockService(
      client: client,
      requestCoordinator: coordinator(signalingSecondWaiter: secondWaiterRegistered)
    )

    let firstTask = Task {
      let results = await service.fetchMissingRates(
        snapshots: [snapshot1],
        displayCurrency: "USD",
        modelContext: context
      )
      await firstTaskCompleted.signal()
      return results
    }
    let firstRequestStarted = await waitForSignal(requestStarted)

    let secondTask = Task {
      await service.fetchMissingRates(
        snapshots: [snapshot2],
        displayCurrency: "USD",
        modelContext: context
      )
    }
    let secondWaiterJoined = await waitForSignal(secondWaiterRegistered)

    firstTask.cancel()
    let firstCompletedBeforeRelease = await waitForSignal(firstTaskCompleted)
    await gate.open()
    let firstResults = await firstTask.value
    let secondResults = await secondTask.value

    #expect(firstRequestStarted)
    #expect(secondWaiterJoined)
    #expect(firstCompletedBeforeRelease)
    #expect(firstResults.first?.status == .cancelled)
    #expect(secondResults.first?.status == .fetched)
    #expect(snapshot1.exchangeRate == nil)
    #expect(snapshot2.exchangeRate != nil)
    #expect(client.requestCount == 1)
  }

  @Test("fetchMissingRates skips snapshots that don't need conversion")
  func testFetchMissingRatesSkipsSnapshotsWithNoConversionNeeded() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "USD", container: container)

    let client = MockHTTPClient { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, "{}".data(using: .utf8)!)
    }

    let service = createMockService(client: client)
    _ = await service.fetchMissingRates(
      snapshots: [snapshot],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(client.requestCount == 0)
    #expect(snapshot.exchangeRate == nil)
  }

  @Test("fetchMissingRates fetches for snapshot missing rates with multi-currency assets")
  func testFetchMissingRatesFetchesForSnapshotMissingRates() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    let snapshot = createSnapshotWithAsset(currency: "EUR", container: container)

    let service = createMockService(handler: mockSuccessHandler(baseCurrency: "usd"))
    _ = await service.fetchMissingRates(
      snapshots: [snapshot],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(snapshot.exchangeRate != nil)
    #expect(snapshot.exchangeRate?.baseCurrency == "usd")
    #expect(snapshot.exchangeRate?.rates["eur"] == Decimal(string: "0.92")!)
  }

  @Test("fetchMissingRates continues on per-snapshot failure")
  func testFetchMissingRatesContinuesOnPerSnapshotFailure() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    // First snapshot — will fail (different date triggers different URL)
    let snapshot1 = Snapshot(date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
    context.insert(snapshot1)
    let asset1 = Asset(name: "Fail Asset")
    asset1.currency = "EUR"
    context.insert(asset1)
    let av1 = SnapshotAssetValue(marketValue: 500)
    av1.snapshot = snapshot1
    av1.asset = asset1
    context.insert(av1)

    // Second snapshot — will succeed
    let snapshot2 = Snapshot(date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
    context.insert(snapshot2)
    let asset2 = Asset(name: "Success Asset")
    asset2.currency = "TWD"
    context.insert(asset2)
    let av2 = SnapshotAssetValue(marketValue: 1000)
    av2.snapshot = snapshot2
    av2.asset = asset2
    context.insert(av2)

    let service = createMockService { request, requestNumber in
      if requestNumber == 1 {
        // First request fails with 404
        let response = HTTPURLResponse(
          url: URL(string: "https://example.com")!,
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      } else {
        // Second request succeeds
        let json = """
          {"date": "\(requestedAPIResponseDate(from: request))", "usd": {"eur": 0.92, "twd": 31.5, "jpy": 149.5}}
          """
        let response = HTTPURLResponse(
          url: URL(string: "https://example.com")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, json.data(using: .utf8)!)
      }
    }

    _ = await service.fetchMissingRates(
      snapshots: [snapshot1, snapshot2],
      displayCurrency: "USD",
      modelContext: context
    )

    // First snapshot should have no exchange rate (failed)
    #expect(snapshot1.exchangeRate == nil)
    // Second snapshot should have exchange rate (succeeded despite first failing)
    #expect(snapshot2.exchangeRate != nil)
    #expect(snapshot2.exchangeRate?.baseCurrency == "usd")
  }

  @Test("fetchMissingRates handles empty snapshot list")
  func testFetchMissingRatesHandlesEmptySnapshotList() async {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext

    let client = MockHTTPClient { _, _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, "{}".data(using: .utf8)!)
    }

    let service = createMockService(client: client)
    _ = await service.fetchMissingRates(
      snapshots: [],
      displayCurrency: "USD",
      modelContext: context
    )

    #expect(client.requestCount == 0)
  }
}
