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

/// ViewModel for the Settings screen
///
/// Manages form state for settings including:
/// - Main currency selection (saved immediately)
/// - App lock and re-lock timeout (via AuthenticationService)
@Observable
@MainActor
final class SettingsViewModel {
  /// The settings service for persistence
  private let settingsService: SettingsService

  /// The authentication service for app lock settings
  private let authService: AuthenticationService

  /// Selected currency code
  var selectedCurrency: String {
    didSet {
      guard selectedCurrency != oldValue else { return }
      settingsService.mainCurrency = selectedCurrency
    }
  }

  /// Selected date format
  var selectedDateFormat: DateFormatStyle {
    didSet {
      guard selectedDateFormat != oldValue else { return }
      settingsService.dateFormat = selectedDateFormat
    }
  }

  /// Default platform for imports
  var defaultPlatformString: String {
    didSet {
      guard defaultPlatformString != oldValue else { return }
      settingsService.defaultPlatform = defaultPlatformString
    }
  }

  /// Task handle for the in-flight authentication request, exposed for testability.
  private(set) var authTask: Task<Void, Never>?

  /// Whether app lock is enabled
  var isAppLockEnabled: Bool {
    didSet {
      guard isAppLockEnabled != oldValue else { return }
      if isAppLockEnabled {
        // Reset timeouts to default if both were .never (from auto-disable).
        // Done before auth so the pickers update instantly.
        if authService.appSwitchTimeout == .never
          && authService.screenLockTimeout == .never
        {
          authService.appSwitchTimeout = .immediately
          authService.screenLockTimeout = .immediately
          appSwitchTimeout = .immediately
          screenLockTimeout = .immediately
        }
        // Verify identity before enabling — revert if auth fails
        authTask = Task {
          let success = await authService.authenticate()
          if success {
            authService.isAppLockEnabled = true
          } else {
            isAppLockEnabled = false
          }
        }
      } else {
        authService.isAppLockEnabled = false
        authService.isLocked = false
      }
    }
  }

  /// How long after switching apps before the app re-locks
  var appSwitchTimeout: ReLockTimeout {
    didSet {
      guard appSwitchTimeout != oldValue else { return }
      authService.appSwitchTimeout = appSwitchTimeout
      if appSwitchTimeout == .never && screenLockTimeout == .never {
        authService.isAppLockEnabled = false
        authService.isLocked = false
        isAppLockEnabled = false
      }
    }
  }

  /// How long after screen lock or sleep before the app re-locks
  var screenLockTimeout: ReLockTimeout {
    didSet {
      guard screenLockTimeout != oldValue else { return }
      authService.screenLockTimeout = screenLockTimeout
      if appSwitchTimeout == .never && screenLockTimeout == .never {
        authService.isAppLockEnabled = false
        authService.isLocked = false
        isAppLockEnabled = false
      }
    }
  }

  /// Available currencies for picker
  var availableCurrencies: [Currency] {
    CurrencyService.shared.currencies
  }

  /// Available date formats for picker, deduplicated by preview output
  /// (e.g., in Traditional Chinese, abbreviated and long produce identical strings)
  var availableDateFormats: [DateFormatStyle] {
    let referenceDate = Date()
    var seenPreviews: Set<String> = []
    return DateFormatStyle.allCases.filter { format in
      let preview = format.preview(for: referenceDate)
      return seenPreviews.insert(preview).inserted
    }
  }

  init(
    settingsService: SettingsService? = nil,
    authenticationService: AuthenticationService? = nil
  ) {
    let resolvedSettingsService = settingsService ?? SettingsService.shared
    let resolvedAuthService = authenticationService ?? AuthenticationService.shared
    self.settingsService = resolvedSettingsService
    self.authService = resolvedAuthService
    self.selectedCurrency = resolvedSettingsService.mainCurrency
    self.selectedDateFormat = resolvedSettingsService.dateFormat
    self.defaultPlatformString = resolvedSettingsService.defaultPlatform
    self.isAppLockEnabled = resolvedAuthService.isAppLockEnabled
    self.appSwitchTimeout = resolvedAuthService.appSwitchTimeout
    self.screenLockTimeout = resolvedAuthService.screenLockTimeout
  }
}
