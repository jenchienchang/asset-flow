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

/// Errors that can occur when fetching exchange rates.
enum ExchangeRateError: Error, LocalizedError {
  case networkUnavailable
  case invalidResponse
  case ratesNotFound

  var errorDescription: String? {
    switch self {
    case .networkUnavailable:
      return String(
        localized: "Network unavailable. Exchange rates could not be fetched.", table: "Services")

    case .invalidResponse:
      return String(localized: "Invalid response from exchange rate service.", table: "Services")

    case .ratesNotFound:
      return String(
        localized: "Exchange rates not found for the requested date.", table: "Services")
    }
  }
}

enum ExchangeRateFetchStatus: Equatable, Sendable {
  case notNeeded
  case cached
  case fetched
  case failed(String)
  case cancelled
}

struct ExchangeRateFetchResult: Equatable, Sendable {
  let snapshotID: UUID
  let status: ExchangeRateFetchStatus
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    nil
  }
}

private struct ExchangeRateAPIResponse: Decodable {
  let date: String
  let ratesByBaseCurrency: [String: [String: Decimal]]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let dateKey = DynamicCodingKey(stringValue: "date")!
    date = try container.decode(String.self, forKey: dateKey)

    var ratesByBaseCurrency: [String: [String: Decimal]] = [:]
    for key in container.allKeys where key.stringValue != "date" {
      let decodedRates = try container.decode([String: Decimal].self, forKey: key)
      ratesByBaseCurrency[key.stringValue.lowercased()] = decodedRates.reduce(
        into: [String: Decimal]()
      ) { result, entry in
        result[entry.key.lowercased()] = entry.value
      }
    }
    self.ratesByBaseCurrency = ratesByBaseCurrency
  }
}

private actor ExchangeRateRequestCoordinator {
  private final class CancellationAwareWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: Decimal], Error>?
    private var result: Result<[String: Decimal], Error>?

    func install(_ continuation: CheckedContinuation<[String: Decimal], Error>) {
      lock.lock()
      if let result {
        lock.unlock()
        continuation.resume(with: result)
      } else {
        self.continuation = continuation
        lock.unlock()
      }
    }

    func complete(_ result: Result<[String: Decimal], Error>) {
      lock.lock()
      let continuation = self.continuation
      if continuation != nil {
        self.continuation = nil
      } else if self.result == nil {
        self.result = result
      }
      lock.unlock()

      continuation?.resume(with: result)
    }

    func cancel() {
      complete(.failure(CancellationError()))
    }
  }

  private struct InFlightRequest {
    let task: Task<[String: Decimal], Error>
    var waiters: Set<UUID>
  }

  private var inFlight: [String: InFlightRequest] = [:]

  func fetch(
    key: String,
    operation: @escaping @Sendable () async throws -> [String: Decimal]
  ) async throws -> [String: Decimal] {
    let waiterID = UUID()
    let task: Task<[String: Decimal], Error>

    if var request = inFlight[key] {
      request.waiters.insert(waiterID)
      task = request.task
      inFlight[key] = request
    } else {
      task = Task { try await operation() }
      inFlight[key] = InFlightRequest(task: task, waiters: [waiterID])
    }

    defer {
      self.release(key: key, waiterID: waiterID)
    }

    let waiter = CancellationAwareWaiter()
    return try await withTaskCancellationHandler(
      operation: {
        try Task.checkCancellation()
        let rates: [String: Decimal] = try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<[String: Decimal], Error>) in
          waiter.install(continuation)
          Task {
            do {
              waiter.complete(.success(try await task.value))
            } catch {
              waiter.complete(.failure(error))
            }
          }
        }
        try Task.checkCancellation()
        return rates
      },
      onCancel: {
        waiter.cancel()
        Task { await self.cancel(key: key, waiterID: waiterID) }
      })
  }

  private func cancel(key: String, waiterID: UUID) {
    release(key: key, waiterID: waiterID)
  }

  private func release(key: String, waiterID: UUID) {
    guard var request = inFlight[key], request.waiters.remove(waiterID) != nil else {
      return
    }

    if request.waiters.isEmpty {
      inFlight[key] = nil
      request.task.cancel()
    } else {
      inFlight[key] = request
    }
  }
}

/// Service for fetching exchange rates from the fawazahmed0 currency API.
///
/// Uses cdn.jsdelivr.net as CDN host. Accepts a `URLSession` for testability.
final class ExchangeRateService: @unchecked Sendable {
  private let session: URLSession
  private static let requestCoordinator = ExchangeRateRequestCoordinator()
  private static let apiTimeZone = TimeZone.current

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// Fetches exchange rates for a given date and base currency.
  ///
  /// - Parameters:
  ///   - date: The date to fetch rates for (uses YYYY-MM-DD format)
  ///   - baseCurrency: The base currency code (lowercase, e.g., "usd")
  /// - Returns: Dictionary of currency code to rate
  /// - Throws: `ExchangeRateError`
  func fetchRates(for date: Date, baseCurrency: String) async throws -> [String: Decimal] {
    let base = baseCurrency.lowercased()
    let dateString = Self.apiDateString(for: date, timeZone: Self.apiTimeZone)

    guard !base.isEmpty else {
      throw ExchangeRateError.invalidResponse
    }

    let rates = try await Self.requestCoordinator.fetch(key: "\(dateString)|\(base)") {
      try await Self.performFetch(
        session: self.session,
        dateString: dateString,
        baseCurrency: base
      )
    }
    try Task.checkCancellation()
    return rates
  }

  static func apiDateString(for date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    func padded(_ value: Int, toLength length: Int) -> String {
      let string = String(value)
      return String(repeating: "0", count: max(0, length - string.count)) + string
    }
    let year = padded(components.year ?? 0, toLength: 4)
    let month = padded(components.month ?? 0, toLength: 2)
    let day = padded(components.day ?? 0, toLength: 2)
    return "\(year)-\(month)-\(day)"
  }

  private static func performFetch(
    session: URLSession,
    dateString: String,
    baseCurrency: String
  ) async throws -> [String: Decimal] {
    let urlString =
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(dateString)/v1/currencies/\(baseCurrency).min.json"

    guard let url = URL(string: urlString) else {
      throw ExchangeRateError.invalidResponse
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        throw CancellationError()
      }
      throw ExchangeRateError.networkUnavailable
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ExchangeRateError.invalidResponse
    }
    if httpResponse.statusCode == 404 {
      throw ExchangeRateError.ratesNotFound
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw ExchangeRateError.invalidResponse
    }

    // Parse JSON: {"date": "...", "{base}": {code: rate, ...}}.
    // Decoding Decimal directly preserves the decimal representation from the
    // response instead of first converting every number through Double.
    guard let response = try? JSONDecoder().decode(ExchangeRateAPIResponse.self, from: data),
      response.date == dateString,
      let ratesDict = response.ratesByBaseCurrency[baseCurrency]
    else {
      throw ExchangeRateError.invalidResponse
    }

    var rates: [String: Decimal] = [:]
    for (key, decimalValue) in ratesDict {
      guard decimalValue.isFinite, decimalValue > 0 else {
        throw ExchangeRateError.invalidResponse
      }
      rates[key.lowercased()] = decimalValue
    }

    guard !rates.isEmpty else {
      throw ExchangeRateError.invalidResponse
    }

    return rates
  }

  /// Batch-fetches missing exchange rates for snapshots that need currency conversion.
  ///
  /// Reuses a cached rate only when it has valid data for every currency used by
  /// the snapshot. Fetches sequentially to avoid API hammering and returns a
  /// result for every snapshot so callers can surface failures.
  ///
  /// - Parameters:
  ///   - snapshots: The snapshots to check and fetch rates for
  ///   - displayCurrency: The user's main display currency code
  ///   - modelContext: The model context to insert new `ExchangeRate` objects into
  @MainActor
  func fetchMissingRates(
    snapshots: [Snapshot],
    displayCurrency: String,
    modelContext: ModelContext
  ) async -> [ExchangeRateFetchResult] {
    let display = displayCurrency.lowercased()
    var results: [ExchangeRateFetchResult] = []

    for snapshot in snapshots {
      // Check if any assets or cash flows use a different currency
      let assetValues = snapshot.assetValues ?? []
      let cashFlows = snapshot.cashFlowOperations ?? []

      let requiredCurrencies = Set(
        assetValues.compactMap { value -> String? in
          let currency =
            value.asset?.currency
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
          return currency.isEmpty || currency == display ? nil : currency
        }
          + cashFlows.compactMap { operation -> String? in
            let currency = operation.currency
              .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return currency.isEmpty || currency == display ? nil : currency
          }
      )

      guard !requiredCurrencies.isEmpty else {
        results.append(ExchangeRateFetchResult(snapshotID: snapshot.id, status: .notNeeded))
        continue
      }

      if let existing = snapshot.exchangeRate,
        existing.baseCurrency.lowercased() == display,
        existing.matchesDate(snapshot.date, timeZone: Self.apiTimeZone),
        existing.supportsAll(requiredCurrencies)
      {
        results.append(ExchangeRateFetchResult(snapshotID: snapshot.id, status: .cached))
        continue
      }

      do {
        let rates = try await fetchRates(for: snapshot.date, baseCurrency: display)
        try Task.checkCancellation()
        guard Self.supportsAll(rates: rates, currencies: requiredCurrencies) else {
          throw ExchangeRateError.invalidResponse
        }
        try Task.checkCancellation()
        let ratesJSON = try JSONEncoder().encode(rates)
        try Task.checkCancellation()
        if let existing = snapshot.exchangeRate {
          existing.updateRates(
            baseCurrency: display,
            ratesJSON: ratesJSON,
            fetchDate: snapshot.date
          )
        } else {
          let exchangeRate = ExchangeRate(
            baseCurrency: display,
            ratesJSON: ratesJSON,
            fetchDate: snapshot.date
          )
          exchangeRate.snapshot = snapshot
          modelContext.insert(exchangeRate)
        }
        results.append(ExchangeRateFetchResult(snapshotID: snapshot.id, status: .fetched))
      } catch is CancellationError {
        results.append(ExchangeRateFetchResult(snapshotID: snapshot.id, status: .cancelled))
        break
      } catch {
        results.append(
          ExchangeRateFetchResult(
            snapshotID: snapshot.id,
            status: .failed(error.localizedDescription)
          )
        )
      }
    }

    return results
  }

  private static func supportsAll(
    rates: [String: Decimal], currencies: Set<String>
  ) -> Bool {
    currencies.allSatisfy { currency in
      guard let rate = rates[currency.lowercased()] else { return false }
      return rate.isFinite && rate > 0
    }
  }

  /// Fetches the full list of supported currencies.
  ///
  /// - Returns: Dictionary of currency code to currency name
  /// - Throws: `ExchangeRateError`
  func fetchCurrencyList() async throws -> [String: String] {
    let urlString =
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.min.json"

    guard let url = URL(string: urlString) else {
      throw ExchangeRateError.invalidResponse
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      throw ExchangeRateError.networkUnavailable
    }

    if let httpResponse = response as? HTTPURLResponse {
      guard (200...299).contains(httpResponse.statusCode) else {
        throw ExchangeRateError.invalidResponse
      }
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
      throw ExchangeRateError.invalidResponse
    }

    return json
  }
}
