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

import AppKit
import SwiftData
import SwiftUI

@main
struct AssetFlowApp: App {
  let sharedModelContainer: ModelContainer

  init() {
    let schema = Schema(versionedSchema: SchemaV1.self)
    #if DEBUG
      let usePreviewData = ProcessInfo.processInfo.arguments.contains("--preview-data")
    #else
      let usePreviewData = false
    #endif
    let modelConfiguration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: usePreviewData
    )

    do {
      sharedModelContainer = try ModelContainer(
        for: schema,
        migrationPlan: AssetFlowMigrationPlan.self,
        configurations: [modelConfiguration]
      )
      #if DEBUG
        if usePreviewData {
          Self.seedPreviewData(in: sharedModelContainer.mainContext)
        }
      #endif
    } catch {
      Self.showDatabaseErrorAndExit(error)
    }
  }

  #if DEBUG
    /// Seeds a disposable dashboard dataset for visual review when `--preview-data` is passed.
    private static func seedPreviewData(in modelContext: ModelContext) {
      do {
        guard try modelContext.fetch(FetchDescriptor<Snapshot>()).isEmpty else { return }

        let categories = [
          Category(name: "Equities"),
          Category(name: "Fixed Income"),
          Category(name: "Real Assets"),
          Category(name: "Cash"),
        ]
        for (index, category) in categories.enumerated() {
          category.displayOrder = index
          modelContext.insert(category)
        }

        let assetDefinitions: [(name: String, platform: String, categoryIndex: Int)] = [
          ("US Market ETF", "Brokerage", 0),
          ("Technology ETF", "Brokerage", 0),
          ("Apple", "Brokerage", 0),
          ("Microsoft", "Brokerage", 0),
          ("Global Equity ETF", "Brokerage", 0),
          ("Emerging Markets ETF", "Brokerage", 0),
          ("Healthcare ETF", "Brokerage", 0),
          ("Treasury ETF", "Brokerage", 1),
          ("Total Bond Market ETF", "Brokerage", 1),
          ("Investment Grade Bonds", "Brokerage", 1),
          ("Real Estate ETF", "Brokerage", 2),
          ("Money Market Fund", "Bank", 3),
          ("Cash Reserve", "Bank", 3),
        ]
        let assets = assetDefinitions.map { definition in
          let asset = Asset(name: definition.name, platform: definition.platform)
          asset.currency = "USD"
          asset.category = categories[definition.categoryIndex]
          modelContext.insert(asset)
          return asset
        }

        let latestValues: [Decimal] = [
          34_200, 26_500, 24_800, 20_500, 18_000, 12_000, 16_200,
          16_000, 14_000, 8_000, 6_500, 7_000, 6_288.06,
        ]
        let dateComponents = [
          DateComponents(year: 2025, month: 3, day: 9),
          DateComponents(year: 2025, month: 9, day: 9),
          DateComponents(year: 2026, month: 3, day: 9),
        ]
        let dates = dateComponents.compactMap { Calendar.current.date(from: $0) }
        guard dates.count == dateComponents.count else {
          fatalError("Could not create dates for dashboard preview data.")
        }
        let growthFactors: [Decimal] = [0.843, 0.93, 1]

        for (date, growthFactor) in zip(dates, growthFactors) {
          let snapshot = Snapshot(date: date)
          modelContext.insert(snapshot)

          for (asset, latestValue) in zip(assets, latestValues) {
            let assetValue = SnapshotAssetValue(marketValue: latestValue * growthFactor)
            assetValue.snapshot = snapshot
            assetValue.asset = asset
            modelContext.insert(assetValue)
          }
        }

        try modelContext.save()
      } catch {
        fatalError("Could not seed dashboard preview data: \(error)")
      }
    }
  #endif

  /// Shows a modal alert about the database error and terminates the app after dismissal.
  private static func showDatabaseErrorAndExit(_ error: Error) -> Never {
    let alert = NSAlert()
    alert.messageText = String(
      localized: "Unable to Open Database",
      table: "Services"
    )
    alert.informativeText = String(
      localized: """
        AssetFlow could not open its database due to an incompatible schema. \
        Your data has not been deleted.

        Please file an issue at the GitHub repository so we can help resolve this.

        Error: \(error.localizedDescription)
        """,
      table: "Services"
    )
    alert.alertStyle = .critical
    alert.addButton(withTitle: String(localized: "Open GitHub Issues", table: "Services"))
    alert.addButton(withTitle: String(localized: "Quit", table: "Services"))

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      NSWorkspace.shared.open(Constants.AppInfo.issuesURL)
    }

    NSApp.terminate(nil)
    fatalError("Could not create ModelContainer: \(error)")
  }

  @FocusedValue(\.newSnapshotAction) private var newSnapshotAction
  @FocusedValue(\.importCSVAction) private var importCSVAction

  private let authService = AuthenticationService.shared

  var body: some Scene {
    WindowGroup {
      ZStack {
        ContentView()
        if authService.isLocked {
          LockScreenView(authService: authService)
            .transition(.opacity)
        }
      }
      .environment(\.isAppLocked, authService.isLocked)
      .onAppear {
        authService.lockOnLaunchIfNeeded()
      }
      // ── App Activation Lifecycle ──
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
      ) { _ in
        authService.isAppActive = false
        authService.recordBackground(trigger: .appSwitch)
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        authService.isAppActive = true
        authService.evaluateOnBecomeActive()
      }
      // ── Screen Lock / Sleep ──
      .onReceive(
        NSWorkspace.shared.notificationCenter.publisher(
          for: NSWorkspace.screensDidSleepNotification)
      ) { _ in
        authService.recordBackground(trigger: .screenSleep)
      }
      .onReceive(
        DistributedNotificationCenter.default().publisher(
          for: Notification.Name("com.apple.screenIsLocked"))
      ) { _ in
        authService.recordBackground(trigger: .screenSleep)
      }
    }
    .modelContainer(sharedModelContainer)
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Snapshot...") {
          newSnapshotAction?()
        }
        .keyboardShortcut("n")
        .disabled(newSnapshotAction == nil || authService.isLocked)

        Divider()

        Button("Import CSV...") {
          importCSVAction?()
        }
        .keyboardShortcut("i")
        .disabled(importCSVAction == nil || authService.isLocked)
      }
      CommandGroup(replacing: .appInfo) {
        Button("About AssetFlow") {
          let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
          let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
          let center = NSMutableParagraphStyle()
          center.alignment = .center

          let credits = NSMutableAttributedString()

          // License
          credits.append(
            NSAttributedString(
              string: "\(Constants.AppInfo.license)\n",
              attributes: [.font: body, .paragraphStyle: center]
            ))

          // Source code link
          credits.append(
            NSAttributedString(
              string: String(localized: "View Source Code on GitHub"),
              attributes: [
                .font: body,
                .link: Constants.AppInfo.repositoryURL,
                .paragraphStyle: center,
              ]
            ))

          // Privacy statement — small, secondary
          credits.append(
            NSAttributedString(
              string:
                "\n\n"
                + String(
                  localized:
                    """
                    All data is stored locally on your Mac.
                    Exchange rates are fetched from cdn.jsdelivr.net.
                    No personal data is collected or transmitted.
                    """
                ),
              attributes: [
                .font: small,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: center,
              ]
            ))

          NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "AssetFlow",
            .applicationIcon: NSApp.applicationIconImage as Any,
            .credits: credits,
          ])
        }
      }
      CommandGroup(replacing: .help) {
        Button("AssetFlow User Guide") {
          NSWorkspace.shared.open(Constants.AppInfo.documentationURL)
        }
        Divider()
        Button("Report an Issue") {
          NSWorkspace.shared.open(Constants.AppInfo.issuesURL)
        }
      }
    }

    Settings {
      ZStack {
        SettingsView()
        if authService.isLocked {
          LockScreenView(authService: authService)
            .transition(.opacity)
        }
      }
      .environment(\.isAppLocked, authService.isLocked)
    }
    .modelContainer(sharedModelContainer)
  }
}
