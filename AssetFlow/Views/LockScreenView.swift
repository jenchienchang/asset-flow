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

import SwiftUI

/// Full-window opaque overlay displayed when the app is locked.
///
/// Uses the system `LAContext.evaluatePolicy` dialog for authentication —
/// no custom biometric UI (Apple HIG compliant).
struct LockScreenView: View {
  let authService: AuthenticationService

  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 20) {
      if let appIcon = NSApplication.shared.applicationIconImage {
        Image(nsImage: appIcon)
          .resizable().scaledToFit()
          .frame(width: 128, height: 128)
      }

      Text("AssetFlow is Locked")
        .font(.title)
        .fontWeight(.semibold)

      Button("Unlock") {
        Task { await unlock() }
      }
      .keyboardShortcut(.defaultAction)
      .controlSize(.large)
      .disabled(authService.isAuthenticating)

      if let errorMessage {
        Text(errorMessage)
          .foregroundStyle(.secondary)
          .font(.callout)
          .transition(.opacity)
      }
    }
    .animation(AnimationConstants.standard, value: errorMessage)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.regularMaterial)
    .task(id: authService.isLocked) {
      // Auto-auth on view appear, but only if app is active (e.g., lock on launch).
      // When locked eagerly in background, this returns false and does nothing.
      guard authService.isLocked else { return }
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      await autoUnlockIfActive()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      // When user returns to a locked app, auto-trigger auth.
      // This is the PRIMARY deferred auth mechanism.
      guard authService.isLocked, !authService.isAuthenticating else { return }
      Task {
        try? await Task.sleep(for: .milliseconds(300))
        await autoUnlockIfActive()
      }
    }
  }

  /// Auto-attempts authentication only if the app is active.
  /// No error message for auto-attempts — user didn't explicitly request unlock.
  private func autoUnlockIfActive() async {
    guard authService.isLocked, !authService.isAuthenticating else { return }
    _ = await authService.authenticateIfActive()
  }

  /// Manual unlock triggered by the "Unlock" button. Shows error on failure.
  private func unlock() async {
    errorMessage = nil
    let success = await authService.authenticate()
    if !success {
      errorMessage = String(
        localized: "Authentication failed. Try again.",
        table: "Settings"
      )
    }
  }
}
