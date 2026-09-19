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

/// Service for managing app-level authentication using LocalAuthentication.
///
/// Uses `LAPolicy.deviceOwnerAuthentication` for broadest compatibility:
/// Touch ID → Apple Watch → system password fallback.
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

  /// Whether app lock is enabled by the user.
  var isAppLockEnabled: Bool {
    didSet {
      userDefaults.set(isAppLockEnabled, forKey: Constants.UserDefaultsKeys.appLockEnabled)
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
  /// Initialized to `true` because the app starts active — `.onAppear` fires
  /// before `didBecomeActiveNotification`, so `isAppActive` must already be
  /// `true` for lock-on-launch auth to work without timing hacks.
  var isAppActive: Bool = true

  /// The date when the app entered the background. Managed by recordBackground/evaluateOnBecomeActive.
  private(set) var backgroundDate: Date?

  /// Which trigger caused the background event.
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
    laContextFactory: @escaping () -> LAContext = { LAContext() }
  ) {
    self.userDefaults = userDefaults
    self.laContextFactory = laContextFactory

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
    laContextFactory: @escaping () -> LAContext = { LAContext() }
  ) -> AuthenticationService {
    let suiteName = "com.assetflow.testing.\(UUID().uuidString)"
    guard let testDefaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Failed to create UserDefaults suite for testing")
    }
    return AuthenticationService(
      userDefaults: testDefaults,
      laContextFactory: laContextFactory
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
  /// Uses `LAPolicy.deviceOwnerAuthentication` which supports Touch ID,
  /// Apple Watch, and system password fallback.
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
  /// - `screenSleep` always overrides a pending `appSwitch` (higher priority).
  /// - Ignored while `isAuthenticating` (prevents re-lock loops).
  /// - Eagerly locks if the relevant timeout is `.immediately`.
  func recordBackground(trigger: LockTrigger) {
    guard isAppLockEnabled, !isAuthenticating else { return }

    authWasCancelled = false

    if backgroundDate == nil || trigger == .screenSleep {
      backgroundDate = Date()
      backgroundTrigger = trigger
    }

    let timeout = trigger == .appSwitch ? appSwitchTimeout : screenLockTimeout
    if timeout == .immediately {
      isLocked = true
    }
  }

  /// Evaluates the pending background event on return to foreground.
  /// Clears background state regardless of outcome.
  func evaluateOnBecomeActive() {
    defer {
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

  /// Whether biometric authentication is available on this Mac.
  ///
  /// Use this to adapt the Settings UI footer text.
  func canEvaluatePolicy() -> Bool {
    let context = laContextFactory()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }
}

// MARK: - Testing Support

#if TESTING
  /// An `LAContext` subclass that always succeeds without showing any system dialog.
  /// Only compiled into the Testing build configuration.
  private nonisolated class PassthroughLAContext: LAContext {
    override func canEvaluatePolicy(_: LAPolicy, error _: NSErrorPointer) -> Bool { true }
    override func evaluatePolicy(_: LAPolicy, localizedReason _: String) async throws -> Bool {
      true
    }
  }
#endif
