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

  /// Identifies the current deadline so an obsolete callback cannot lock a new session.
  private var pendingLockID: UUID?
  private var cancelPendingLock: (@MainActor () -> Void)?

  /// Lets the app clear lifecycle notifications queued before a successful unlock.
  @ObservationIgnored var onSuccessfulAuthentication: (@MainActor () -> Void)?

  /// Whether app lock is enabled by the user.
  var isAppLockEnabled: Bool {
    didSet {
      userDefaults.set(isAppLockEnabled, forKey: Constants.UserDefaultsKeys.appLockEnabled)
      if !isAppLockEnabled {
        cancelScheduledLock()
        backgroundDate = nil
        backgroundTrigger = nil
      }
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
  private(set) var backgroundDate: Date?

  /// The trigger that currently determines the earliest lock deadline.
  private(set) var backgroundTrigger: LockTrigger?

  /// Whether an authentication dialog is currently being presented.
  /// Used to suppress background-date recording so the auth dialog
  /// does not trigger a re-lock cycle.
  private(set) var isAuthenticating: Bool = false

  /// Whether the last authentication attempt was cancelled or failed.
  /// Suppresses auto-auth retries until a new background event resets it.
  private(set) var authWasCancelled: Bool = false

  /// When the user last successfully authenticated.
  var lastUnlockDate: Date?

  private init(
    userDefaults: UserDefaults = .standard,
    laContextFactory: @escaping () -> LAContext = { LAContext() },
    lockScheduler: @escaping LockScheduler = { deadline, action in
      scheduleLockAtDeadline(deadline, action: action)
    }
  ) {
    self.userDefaults = userDefaults
    self.laContextFactory = laContextFactory
    self.lockScheduler = lockScheduler

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
  }

  /// Creates an isolated instance for testing purposes.
  ///
  /// Each call creates a new instance with its own temporary UserDefaults suite,
  /// ensuring complete test isolation with no shared state between tests.
  static func createForTesting(
    laContextFactory: @escaping () -> LAContext = { LAContext() },
    lockScheduler: @escaping LockScheduler = { _, _ in {} }
  ) -> AuthenticationService {
    let suiteName = "com.assetflow.testing.\(UUID().uuidString)"
    guard let testDefaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Failed to create UserDefaults suite for testing")
    }
    return AuthenticationService(
      userDefaults: testDefaults,
      laContextFactory: laContextFactory,
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
        backgroundDate = nil
        backgroundTrigger = nil
        onSuccessfulAuthentication?()
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
  func recordBackground(trigger: LockTrigger, at date: Date = Date()) {
    guard isAppLockEnabled, !isAuthenticating else { return }
    authWasCancelled = false

    let timeout = trigger == .appSwitch ? appSwitchTimeout : screenLockTimeout
    if let previousDate = backgroundDate, let previousTrigger = backgroundTrigger {
      let previousTimeout =
        previousTrigger == .appSwitch ? appSwitchTimeout : screenLockTimeout
      if previousTimeout != .never {
        let previousDeadline = previousDate.addingTimeInterval(previousTimeout.seconds)
        if timeout == .never || previousDeadline <= date.addingTimeInterval(timeout.seconds) {
          if Date() >= previousDeadline { isLocked = true }
          return
        }
      }
    }

    guard timeout != .never else { return }
    backgroundDate = date
    backgroundTrigger = trigger
    cancelScheduledLock()

    if timeout == .immediately {
      isLocked = true
    } else {
      let deadline = date.addingTimeInterval(timeout.seconds)
      if Date() >= deadline {
        isLocked = true
      } else {
        let id = UUID()
        pendingLockID = id
        cancelPendingLock = lockScheduler(deadline) { [weak self] in
          guard let self, self.pendingLockID == id, self.isAppLockEnabled else { return }
          self.pendingLockID = nil
          self.cancelPendingLock = nil
          self.isLocked = true
        }
      }
    }
  }

  private func cancelScheduledLock() {
    cancelPendingLock?()
    cancelPendingLock = nil
    pendingLockID = nil
  }

  /// Evaluates the pending background event on return to foreground.
  /// Clears background state regardless of outcome.
  func evaluateOnBecomeActive() {
    defer {
      cancelScheduledLock()
      backgroundDate = nil
      backgroundTrigger = nil
    }

    guard isAppLockEnabled,
      let date = backgroundDate,
      let trigger = backgroundTrigger
    else { return }

    let timeout = trigger == .appSwitch ? appSwitchTimeout : screenLockTimeout
    if timeout == .never { return }

    if timeout == .immediately {
      isLocked = true
      return
    }

    if Date().timeIntervalSince(date) >= timeout.seconds {
      isLocked = true
    }
  }

  /// Authenticates ONLY if the app is active. Returns `false` without
  /// showing any dialog when inactive.
  func authenticateIfActive() async -> Bool {
    guard isAppActive, !isAuthenticating, !authWasCancelled else { return false }
    return await authenticate()
  }

  /// Allows tests to backdate the background timestamp for elapsed-time testing.
  func setBackgroundDateForTesting(_ date: Date) {
    backgroundDate = date
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
