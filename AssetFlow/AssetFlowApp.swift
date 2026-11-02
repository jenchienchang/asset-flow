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
import Combine
import SwiftData
import SwiftUI

typealias ScreenEventDispatcher = @Sendable (@escaping @MainActor () -> Void) -> Void

@MainActor
final class AppLockLifecycleDelegate: NSObject, NSApplicationDelegate {
  let authService: AuthenticationService
  private let workspaceNotificationCenter: NotificationCenter
  private let screenLockNotificationCenter: NotificationCenter
  private let eventTime: @Sendable () -> Date
  private let dispatchScreenEvent: ScreenEventDispatcher
  private let screenEventInbox: LockEventInbox
  private var screenSubscriptions: [AnyCancellable] = []

  override convenience init() {
    self.init(authService: .shared)
  }

  init(
    authService: AuthenticationService,
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    screenLockNotificationCenter: NotificationCenter = DistributedNotificationCenter.default(),
    eventTime: (@Sendable () -> Date)? = nil,
    dispatchScreenEvent: @escaping ScreenEventDispatcher = { action in
      Task { @MainActor in action() }
    }
  ) {
    self.authService = authService
    self.workspaceNotificationCenter = workspaceNotificationCenter
    self.screenLockNotificationCenter = screenLockNotificationCenter
    self.eventTime = eventTime ?? authService.clock.now
    self.screenEventInbox = authService.eventInbox
    self.dispatchScreenEvent = dispatchScreenEvent
    super.init()
  }

  func applicationDidFinishLaunching(_: Notification) {
    authService.lockOnLaunchIfNeeded()
    let eventTime = eventTime
    let dispatchScreenEvent = dispatchScreenEvent
    let screenEventInbox = screenEventInbox
    screenSubscriptions = [
      workspaceNotificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
        .sink { [weak self] _ in
          screenEventInbox.record(at: eventTime)
          dispatchScreenEvent { [weak self] in self?.processPendingScreenEvents() }
        },
      screenLockNotificationCenter.publisher(for: Notification.Name("com.apple.screenIsLocked"))
        .sink { [weak self] _ in
          screenEventInbox.record(at: eventTime)
          dispatchScreenEvent { [weak self] in self?.processPendingScreenEvents() }
        },
    ]
  }

  func applicationDidResignActive(_: Notification) {
    authService.isAppActive = false
    authService.recordBackground(trigger: .appSwitch)
  }

  func applicationDidBecomeActive(_: Notification) {
    authService.isAppActive = true
    authService.evaluateOnBecomeActive()
  }

  func screenDidLockOrSleep(at eventDate: Date? = nil) {
    authService.recordBackground(trigger: .screenSleep, at: eventDate)
  }

  private func processPendingScreenEvents() {
    authService.processPendingScreenEvents()
  }
}

@main
struct AssetFlowApp: App {
  @NSApplicationDelegateAdaptor(AppLockLifecycleDelegate.self) private var appLockLifecycle

  let sharedModelContainer: ModelContainer

  init() {
    let schema = CurrentSchema.schema
    #if DEBUG
      let showMissingRatePreview =
        ProcessInfo.processInfo.arguments.contains("--preview-missing-rates")
      let showBulkEntryCSVLoadingPreview =
        ProcessInfo.processInfo.arguments.contains("--preview-bulk-entry-csv-loading")
      let usePreviewData =
        showMissingRatePreview || showBulkEntryCSVLoadingPreview
        || ProcessInfo.processInfo.arguments.contains("--preview-data")
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
          if showMissingRatePreview {
            Self.seedMissingRatePreviewData(in: sharedModelContainer.mainContext)
          } else {
            Self.seedPreviewData(in: sharedModelContainer.mainContext)
          }
        }
      #endif
    } catch {
      Self.showDatabaseErrorAndExit(error)
    }
  }

  #if DEBUG
    /// Seeds an in-memory asset history with a missing middle exchange rate.
    private static func seedMissingRatePreviewData(in modelContext: ModelContext) {
      do {
        let displayCurrency = SettingsService.shared.mainCurrency.lowercased()
        let assetCurrency = displayCurrency == "twd" ? "eur" : "twd"
        let asset = Asset(name: "Exchange Rate Gap", platform: "Preview Brokerage")
        asset.currency = assetCurrency
        modelContext.insert(asset)

        for (month, value) in [(1, 1000), (2, 1200), (3, 1300), (4, 1400), (5, 1600)] {
          guard
            let date = Calendar.current.date(
              from: DateComponents(year: 2026, month: month, day: 1))
          else {
            fatalError("Could not create missing-rate preview date.")
          }
          let snapshot = Snapshot(date: date)
          modelContext.insert(snapshot)

          let sav = SnapshotAssetValue(marketValue: Decimal(value))
          sav.snapshot = snapshot
          sav.asset = asset
          modelContext.insert(sav)

          if month != 3 {
            let ratesJSON = try JSONEncoder().encode([assetCurrency: Decimal(10)])
            let rate = ExchangeRate(
              baseCurrency: displayCurrency, ratesJSON: ratesJSON, fetchDate: date)
            rate.snapshot = snapshot
            modelContext.insert(rate)
          }
        }

        try modelContext.save()
      } catch {
        fatalError("Could not seed missing-rate preview data: \(error)")
      }
    }

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
      AboutCommands()
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

    Window("About AssetFlow", id: "about") {
      AboutView()
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)

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

private struct AboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About AssetFlow") {
        openWindow(id: "about")
      }
    }
  }
}
