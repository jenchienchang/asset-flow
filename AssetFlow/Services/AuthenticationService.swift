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
import LocalAuthentication
import SwiftUI
import Synchronization

/// User-selectable timeout before the app re-locks after going to background.
///
/// Uses stable `String` raw values for UserDefaults persistence.
enum ReLockTimeout: String, CaseIterable {
  case immediately
  case oneMinute
  case fiveMinutes
  case fifteenMinutes
  case never

  /// The timeout interval in seconds.
  var seconds: TimeInterval {
    switch self {
    case .immediately: 0
    case .oneMinute: 60
    case .fiveMinutes: 300
    case .fifteenMinutes: 900
    case .never: .infinity
    }
  }

  /// Localized display name for pickers.
  var localizedName: String {
    switch self {
    case .immediately:
      String(localized: "Immediately", table: "Settings")

    case .oneMinute:
      String(localized: "After 1 Minute", table: "Settings")

    case .fiveMinutes:
      String(localized: "After 5 Minutes", table: "Settings")

    case .fifteenMinutes:
      String(localized: "After 15 Minutes", table: "Settings")

    case .never:
      String(localized: "Never", table: "Settings")
    }
  }
}

/// The type of event that triggered the app going to background.
enum LockTrigger {
  case appSwitch
  case screenSleep
}

typealias LockScheduler =
  @MainActor (
    Date, @escaping @MainActor () -> Void
  ) -> @MainActor () -> Void

typealias LockSleeper = @MainActor (TimeInterval) async throws -> Void

@MainActor
func scheduleLockAtDeadline(
  _ deadline: Date,
  now: @escaping @MainActor () -> Date = { Date() },
  sleep: @escaping LockSleeper = { delay in try await Task.sleep(for: .seconds(delay)) },
  action: @escaping @MainActor () -> Void
) -> @MainActor () -> Void {
  let task = Task { @MainActor in
    let remaining = deadline.timeIntervalSince(now())
    if remaining > 0 {
      do {
        try await sleep(remaining)
      } catch {
        return
      }
    }
    guard !Task.isCancelled else { return }
    action()
  }
  return { task.cancel() }
}

/// Thread-safe receipt boundary owned by the authentication service. The mutex
/// orders receipt against successful authentication and captures settings before
/// main-actor delivery. No timestamp comparison defines a session boundary.
final class LockEventInbox: Sendable {
  struct Event: Sendable {
    let date: Date
    let timeout: ReLockTimeout
  }

  private struct State {
    var enabled = false
    var authenticating = false
    var timeout = ReLockTimeout.immediately
    var events: [Event] = []
  }

  private let state = Mutex(State())

  func configure(enabled: Bool, authenticating: Bool, timeout: ReLockTimeout) {
    state.withLock {
      $0.enabled = enabled
      $0.authenticating = authenticating
      $0.timeout = timeout
      if !enabled { $0.events.removeAll() }
    }
  }

  func record(at now: @Sendable () -> Date) {
    state.withLock {
      guard $0.enabled, !$0.authenticating else { return }
      $0.events.append(Event(date: now(), timeout: $0.timeout))
    }
  }

  func drain() -> [Event] {
    state.withLock {
      let events = $0.events
      $0.events.removeAll()
      return events
    }
  }

  func authenticationSucceeded() {
    state.withLock {
      $0.events.removeAll()
      $0.authenticating = false
    }
  }
}

/// A date-shaped elapsed-time coordinate for the lock policy. ContinuousClock
/// advances during sleep; the fixed origin means wall-clock changes have no
/// effect. The same source is used at notification receipt and timer startup.
struct LockClock: Sendable {
  let now: @Sendable () -> Date

  static func continuous() -> LockClock {
    let clock = ContinuousClock()
    let origin = clock.now
    let date = Date()
    return LockClock(now: {
      let elapsed = origin.duration(to: clock.now).components
      return date.addingTimeInterval(
        Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    })
  }
}

/// Service for managing app-level authentication using LocalAuthentication.
///
/// Requests `LAPolicy.deviceOwnerAuthentication`. macOS chooses among the
/// available Touch ID, Apple Watch, and password methods; the app does not
/// select or promise an order.
///
/// Supports dependency injection for test isolation via `createForTesting()`.
@Observable
@MainActor
class AuthenticationService {
  static let shared: AuthenticationService = {
    #if TESTING
      return AuthenticationService(laContextFactory: { PassthroughLAContext() })
    #else
      return AuthenticationService()
    #endif
  }()

  /// The UserDefaults instance used for persistence.
  private let userDefaults: UserDefaults

  /// Factory that creates a fresh `LAContext` per authentication attempt.
  private let laContextFactory: () -> LAContext

  /// Schedules a deadline and returns a cancellation action.
  private let lockScheduler: LockScheduler

  nonisolated let eventInbox = LockEventInbox()
  nonisolated let clock: LockClock

  private struct PendingLock {
    let id: UUID
    let date: Date
    let trigger: LockTrigger
    let deadline: Date
  }
  private var pending: PendingLock?

  /// Cancels the effect associated with the pending generation.
  private var cancelPendingLock: (@MainActor () -> Void)?

  /// Whether app lock is enabled by the user.
  var isAppLockEnabled: Bool {
    didSet {
      userDefaults.set(isAppLockEnabled, forKey: Constants.UserDefaultsKeys.appLockEnabled)
      if !isAppLockEnabled {
        cancelScheduledLock()
        isLocked = false
      }
      updateInboxConfiguration()
    }
  }

  /// How long after switching apps before the app re-locks.
  var appSwitchTimeout: ReLockTimeout {
    didSet {
      userDefaults.set(
        appSwitchTimeout.rawValue, forKey: Constants.UserDefaultsKeys.appSwitchTimeout)
    }
  }

  /// How long after screen lock or sleep before the app re-locks.
  var screenLockTimeout: ReLockTimeout {
    didSet {
      userDefaults.set(
        screenLockTimeout.rawValue, forKey: Constants.UserDefaultsKeys.screenLockTimeout)
      updateInboxConfiguration()
    }
  }

  /// Whether the app is currently locked. Not persisted — determined at launch.
  var isLocked: Bool = false

  /// Whether the app is currently the active (frontmost) application.
  /// Maintained by the app's notification handlers.
  /// Initialized to `true` so launch-time authentication can start before
  /// the first `didBecomeActiveNotification` is delivered.
  var isAppActive: Bool = true

  /// The event date that currently determines the earliest lock deadline.
  var backgroundDate: Date? { pending?.date }

  /// The trigger that currently determines the earliest lock deadline.
  var backgroundTrigger: LockTrigger? { pending?.trigger }

  /// Whether an authentication dialog is currently being presented.
  /// Used to suppress background-date recording so the auth dialog
  /// does not trigger a re-lock cycle.
  private(set) var isAuthenticating: Bool = false {
    didSet { updateInboxConfiguration() }
  }

  /// Whether the last authentication attempt was cancelled or failed.
  /// Suppresses auto-auth retries until a new background event resets it.
  private(set) var authWasCancelled: Bool = false

  /// When the user last successfully authenticated.
  var lastUnlockDate: Date?

  private init(
    userDefaults: UserDefaults = .standard,
    laContextFactory: @escaping () -> LAContext = { LAContext() },
    clock: LockClock = .continuous(),
    lockScheduler: LockScheduler? = nil
  ) {
    self.userDefaults = userDefaults
    self.laContextFactory = laContextFactory
    self.clock = clock
    self.lockScheduler =
      lockScheduler ?? { deadline, action in
        scheduleLockAtDeadline(deadline, now: { clock.now() }, action: action)
      }

    self.isAppLockEnabled =
      userDefaults.object(forKey: Constants.UserDefaultsKeys.appLockEnabled) as? Bool
      ?? Constants.DefaultValues.defaultAppLockEnabled

    if let raw = userDefaults.string(forKey: Constants.UserDefaultsKeys.appSwitchTimeout),
      let timeout = ReLockTimeout(rawValue: raw)
    {
      self.appSwitchTimeout = timeout
    } else {
      self.appSwitchTimeout = .immediately
    }

    if let raw = userDefaults.string(forKey: Constants.UserDefaultsKeys.screenLockTimeout),
      let timeout = ReLockTimeout(rawValue: raw)
    {
      self.screenLockTimeout = timeout
    } else {
      self.screenLockTimeout = .immediately
    }
    updateInboxConfiguration()
  }

  private func updateInboxConfiguration() {
    eventInbox.configure(
      enabled: isAppLockEnabled, authenticating: isAuthenticating, timeout: screenLockTimeout)
  }

  func processPendingScreenEvents() {
    for event in eventInbox.drain() {
      recordBackground(trigger: .screenSleep, at: event.date, timeout: event.timeout)
    }
  }

  /// Creates an isolated instance for testing purposes.
  ///
  /// Each call creates a new instance with its own temporary UserDefaults suite,
  /// ensuring complete test isolation with no shared state between tests.
  static func createForTesting(
    laContextFactory: @escaping () -> LAContext = { LAContext() },
    lockScheduler: @escaping LockScheduler = { _, _ in {} },
    clock: LockClock = LockClock(now: { Date() })
  ) -> AuthenticationService {
    let suiteName = "com.assetflow.testing.\(UUID().uuidString)"
    guard let testDefaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Failed to create UserDefaults suite for testing")
    }
    return AuthenticationService(
      userDefaults: testDefaults,
      laContextFactory: laContextFactory,
      clock: clock,
      lockScheduler: lockScheduler
    )
  }

  /// Sets `isLocked` to `true` if app lock is enabled. Call on app launch.
  func lockOnLaunchIfNeeded() {
    if isAppLockEnabled {
      isLocked = true
    }
  }

  /// Attempts to authenticate the user using the system authentication dialog.
  ///
  /// Uses `LAPolicy.deviceOwnerAuthentication`; macOS determines which
  /// authentication methods are available for this attempt.
  ///
  /// - Returns: `true` if authentication succeeded, `false` otherwise.
  func authenticate() async -> Bool {
    guard !isAuthenticating else { return false }
    isAuthenticating = true
    defer { isAuthenticating = false }

    let context = laContextFactory()
    let reason = String(
      localized: "Unlock AssetFlow to access your portfolio data",
      table: "Settings"
    )

    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthentication,
        localizedReason: reason
      )
      if success {
        cancelScheduledLock()
        eventInbox.authenticationSucceeded()
        withAnimation(.easeOut(duration: 0.2)) {
          isLocked = false
        }
        lastUnlockDate = Date()
        authWasCancelled = false
      } else {
        authWasCancelled = true
      }
      return success
    } catch {
      authWasCancelled = true
      return false
    }
  }

  /// Records a background event. Called by notification handlers.
  ///
  /// - The earliest applicable lock deadline wins across both triggers.
  /// - A `never` timeout does not change an existing deadline.
  /// - Ignored while `isAuthenticating` (prevents re-lock loops).
  /// - Eagerly locks if the relevant timeout has already elapsed.
  func recordBackground(trigger: LockTrigger, at date: Date? = nil) {
    let timeout = trigger == .appSwitch ? appSwitchTimeout : screenLockTimeout
    recordBackground(trigger: trigger, at: date ?? clock.now(), timeout: timeout)
  }

  private func recordBackground(trigger: LockTrigger, at date: Date, timeout: ReLockTimeout) {
    guard isAppLockEnabled, !isAuthenticating else { return }
    authWasCancelled = false

    if timeout != .never {
      let deadline = date.addingTimeInterval(timeout.seconds)
      if pending.map({ deadline < $0.deadline }) ?? true {
        cancelScheduledLock()
        let next = PendingLock(id: UUID(), date: date, trigger: trigger, deadline: deadline)
        pending = next
        if clock.now() < deadline {
          cancelPendingLock = lockScheduler(deadline) { [weak self] in
            guard let self, self.pending?.id == next.id, self.isAppLockEnabled else { return }
            self.cancelPendingLock = nil
            self.isLocked = true
          }
        }
      }
    }
    if let pending, clock.now() >= pending.deadline { isLocked = true }
  }

  private func cancelScheduledLock() {
    // Invalidate before cancellation, including synchronous custom schedulers.
    pending = nil
    let cancel = cancelPendingLock
    cancelPendingLock = nil
    cancel?()
  }

  /// Drains received notifications before deciding whether activation beat the
  /// deadline. Ending the pending generation invalidates every old timer.
  func evaluateOnBecomeActive() {
    processPendingScreenEvents()
    if isAppLockEnabled, let pending, clock.now() >= pending.deadline {
      isLocked = true
    }
    cancelScheduledLock()
  }

  /// Authenticates ONLY if the app is active. Returns `false` without
  /// showing any dialog when inactive.
  func authenticateIfActive() async -> Bool {
    guard isAppActive, !isAuthenticating, !authWasCancelled else { return false }
    return await authenticate()
  }
}

// MARK: - Testing Support

#if TESTING
  /// An `LAContext` subclass that always succeeds without showing any system dialog.
  /// Only compiled into the Testing build configuration.
  private nonisolated class PassthroughLAContext: LAContext {
    override func evaluatePolicy(_: LAPolicy, localizedReason _: String) async throws -> Bool {
      true
    }
  }
#endif
