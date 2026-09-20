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

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings View - App-wide settings configuration
///
/// Allows users to configure:
/// - Main currency for displaying portfolio values
/// - Date display format
/// - Default platform for imports
/// - Data management (backup/restore)
///
/// All settings save immediately on change.
struct SettingsView: View {
  @State private var viewModel: SettingsViewModel
  @Environment(\.modelContext) private var modelContext

  @State private var showRestoreConfirmation = false
  @State private var showResultAlert = false
  @State private var resultMessage = ""
  @State private var isError = false
  @State private var pendingRestoreURL: URL?

  private let settingsService: SettingsService

  init(
    settingsService: SettingsService? = nil,
    authenticationService: AuthenticationService? = nil
  ) {
    let resolved = settingsService ?? SettingsService.shared
    self.settingsService = resolved
    _viewModel = State(
      wrappedValue: SettingsViewModel(
        settingsService: resolved,
        authenticationService: authenticationService
      ))
  }

  var body: some View {
    Form {
      currencySection
      dateFormatSection
      importDefaultsSection
      securitySection
      dataManagementSection
      aboutSection
    }
    .formStyle(.grouped)
    .navigationTitle("Settings")
    .frame(
      minWidth: 450, idealWidth: 800, maxWidth: .infinity,
      minHeight: 400, idealHeight: 650, maxHeight: .infinity
    )
    .windowResizable(initialContentSize: NSSize(width: 800, height: 650))
    .alert(
      isError ? "Error" : "Success",
      isPresented: $showResultAlert
    ) {
      Button("OK") {}
    } message: {
      Text(resultMessage)
    }
    .confirmationDialog(
      "Restore from Backup",
      isPresented: $showRestoreConfirmation
    ) {
      Button("Restore", role: .destructive) {
        performRestore()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Restoring from backup will replace ALL existing data. This cannot be undone. Continue?"
      )
    }
  }

  // MARK: - Currency Section

  private var currencySection: some View {
    Section {
      Picker("Main Currency", selection: $viewModel.selectedCurrency) {
        ForEach(viewModel.availableCurrencies) { currency in
          Text(currency.displayName)
            .tag(currency.code)
        }
      }
      .accessibilityIdentifier("Main Currency Picker")
    } header: {
      Text("Display Currency")
    } footer: {
      Text("The currency used to display total portfolio values across the app.")
    }
  }

  // MARK: - Date Format Section

  private var dateFormatSection: some View {
    Section {
      Picker("Date Format", selection: $viewModel.selectedDateFormat) {
        ForEach(viewModel.availableDateFormats, id: \.self) { format in
          Text(format.preview(for: Date()))
            .tag(format)
        }
      }
      .accessibilityIdentifier("Date Format Picker")
    } header: {
      Text("Date Format")
    } footer: {
      Text("How dates are displayed throughout the app.")
    }
  }

  // MARK: - Import Defaults Section

  private var importDefaultsSection: some View {
    Section {
      TextField("Default Platform", text: $viewModel.defaultPlatformString)
        .accessibilityIdentifier("Default Platform Field")
    } header: {
      Text("Import Defaults")
    } footer: {
      Text("Pre-fills the platform field when importing CSV files. Leave empty for no default.")
    }
  }

  // MARK: - Security Section

  private var securitySection: some View {
    Section {
      Toggle(
        "Require Authentication",
        isOn: Binding(
          get: { viewModel.isAppLockEnabled },
          set: { newValue in
            withAnimation(AnimationConstants.standard) {
              viewModel.isAppLockEnabled = newValue
            }
          }
        )
      )
      .accessibilityIdentifier("App Lock Toggle")

      if viewModel.isAppLockEnabled {
        Picker("When Switching Apps", selection: $viewModel.appSwitchTimeout) {
          ForEach(ReLockTimeout.allCases, id: \.self) { timeout in
            Text(timeout.localizedName).tag(timeout)
          }
        }
        .accessibilityIdentifier("App Switch Timeout Picker")
        .transition(.opacity)

        Picker("When Locked or Sleeping", selection: $viewModel.screenLockTimeout) {
          ForEach(ReLockTimeout.allCases, id: \.self) { timeout in
            Text(timeout.localizedName).tag(timeout)
          }
        }
        .accessibilityIdentifier("Screen Lock Timeout Picker")
        .transition(.opacity)
      }
    } header: {
      Text("Security")
    } footer: {
      if viewModel.isAppLockEnabled {
        if viewModel.canUseBiometrics {
          Text(
            "Configure when AssetFlow requires authentication. \"When Switching Apps\" applies when you Cmd+Tab or click another window. \"When Locked or Sleeping\" applies when you lock the screen or your Mac sleeps. Set either to \"Never\" to skip locking for that trigger. Uses Touch ID, Apple Watch, or your system password.",
            tableName: "Settings"
          )
        } else {
          Text(
            "Configure when AssetFlow requires authentication. \"When Switching Apps\" applies when you Cmd+Tab or click another window. \"When Locked or Sleeping\" applies when you lock the screen or your Mac sleeps. Set either to \"Never\" to skip locking for that trigger. Uses your system password. Touch ID is not available on this Mac.",
            tableName: "Settings"
          )
        }
      } else {
        Text(
          "When enabled, AssetFlow will require authentication after switching apps, locking the screen, or waking from sleep.",
          tableName: "Settings"
        )
      }
    }
  }

  // MARK: - Data Management Section

  private var dataManagementSection: some View {
    Section {
      Button("Export Backup...") {
        performExport()
      }
      .helpWhenUnlocked("Export all data as a ZIP archive")
      .accessibilityIdentifier("Export Backup Button")

      Button("Restore from Backup...") {
        openRestorePanel()
      }
      .helpWhenUnlocked("Restore data from a previous backup")
      .accessibilityIdentifier("Restore Backup Button")
    } header: {
      Text("Data Management")
    } footer: {
      Text("Export all data as a ZIP archive or restore from a previous backup.")
    }
  }

  // MARK: - About Section

  private var aboutSection: some View {
    Section {
      HStack(alignment: .top, spacing: 12) {
        if let appIcon = NSApplication.shared.applicationIconImage {
          Image(nsImage: appIcon)
            .resizable()
            .frame(width: 48, height: 48)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(Constants.AppInfo.name)
            .font(.headline)
          Text("Version \(Constants.AppInfo.version) (\(Constants.AppInfo.buildNumber))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      LabeledContent("Developer", value: Constants.AppInfo.developerName)
      LabeledContent("License", value: Constants.AppInfo.license)
      LabeledContent("Privacy") {
        let privacyText: LocalizedStringKey =
          "All data is stored locally. Exchange rates are fetched from cdn.jsdelivr.net. No personal data is collected or transmitted."
        ViewThatFits(in: .horizontal) {
          Text(privacyText)
            .fixedSize(horizontal: true, vertical: false)
          Text(privacyText)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Link("User Guide", destination: Constants.AppInfo.documentationURL)
      Link("View Source Code on GitHub", destination: Constants.AppInfo.repositoryURL)
    } header: {
      Text("About")
    }
  }

  // MARK: - Backup Actions

  @MainActor
  private func performExport() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.zip]
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    panel.nameFieldStringValue =
      "AssetFlow-Backup-\(dateFormatter.string(from: Date())).zip"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try BackupService.exportBackup(
        to: url, modelContext: modelContext,
        settingsService: settingsService)
      resultMessage = String(
        localized: "Backup exported successfully.", table: "Settings")
      isError = false
      showResultAlert = true
    } catch {
      resultMessage = error.localizedDescription
      isError = true
      showResultAlert = true
    }
  }

  @MainActor
  private func openRestorePanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.zip]
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else { return }

    pendingRestoreURL = url
    showRestoreConfirmation = true
  }

  @MainActor
  private func performRestore() {
    guard let url = pendingRestoreURL else { return }
    pendingRestoreURL = nil

    do {
      try BackupService.restoreFromBackup(
        at: url, modelContext: modelContext,
        settingsService: settingsService)
      // Sync ViewModel with restored settings
      viewModel = SettingsViewModel(settingsService: settingsService)
      resultMessage = String(
        localized: "Backup restored successfully.", table: "Settings")
      isError = false
      showResultAlert = true

      // Fetch missing exchange rates for restored snapshots
      Task {
        let service = ExchangeRateService()
        let snapshots = (try? modelContext.fetch(FetchDescriptor<Snapshot>())) ?? []
        _ = await service.fetchMissingRates(
          snapshots: snapshots,
          displayCurrency: settingsService.mainCurrency,
          modelContext: modelContext
        )
      }
    } catch {
      resultMessage = error.localizedDescription
      isError = true
      showResultAlert = true
    }
  }
}

// MARK: - Previews

#Preview("Settings View") {
  NavigationStack {
    SettingsView(settingsService: SettingsService.createForTesting())
  }
}
