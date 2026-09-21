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

/// Errors raised when a SwiftData read cannot be completed.
enum PersistenceError: LocalizedError {
  case fetchFailed(operation: String, underlying: any Error)

  var operation: String {
    switch self {
    case .fetchFailed(let operation, _): return operation
    }
  }

  var underlyingError: any Error {
    switch self {
    case .fetchFailed(_, let underlying): return underlying
    }
  }

  var errorDescription: String? {
    String(
      localized: "Unable to load portfolio data. Please try again.",
      table: "Services")
  }
}

/// Narrow abstraction around SwiftData reads so persistence failures can be tested.
@MainActor
protocol ModelFetching {
  func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] where T: PersistentModel
}

/// Production adapter for SwiftData model-context fetches.
@MainActor
struct ModelContextFetcher: ModelFetching {
  let modelContext: ModelContext

  func fetch<T>(_ descriptor: FetchDescriptor<T>) throws -> [T] where T: PersistentModel {
    try modelContext.fetch(descriptor)
  }
}

/// Performs a model fetch while preserving operation context for diagnostics.
@MainActor
func fetchModels<T: PersistentModel>(
  _ descriptor: FetchDescriptor<T>,
  from fetcher: any ModelFetching,
  operation: String
) throws -> [T] {
  do {
    return try fetcher.fetch(descriptor)
  } catch {
    throw PersistenceError.fetchFailed(operation: operation, underlying: error)
  }
}

/// State of a view-model read operation.
enum DataLoadState: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}
