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
import Foundation
import LocalAuthentication
import Testing

@testable import AssetFlow

@Suite("App Lock Lifecycle Tests")
@MainActor
struct AppLockLifecycleTests {
  private nonisolated final class SuccessfulLAContext: LAContext {
    override func evaluatePolicy(_: LAPolicy, localizedReason _: String) async throws -> Bool {
      true
    }
  }

  private final class DeferredScreenEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [@MainActor () -> Void] = []

    func enqueue(_ action: @escaping @MainActor () -> Void) {
      lock.lock()
      actions.append(action)
      lock.unlock()
    }

    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return actions.count
    }

    @MainActor func runAll() {
      lock.lock()
      let pending = actions
      actions.removeAll()
      lock.unlock()
      for action in pending { action() }
    }
  }

  @Test("Launch locks the app before any main window appears")
  func launchWithoutMainWindow() {
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    let delegate = AppLockLifecycleDelegate(authService: service)

    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(service.isLocked)
  }

  @Test("App deactivation schedules a lock without a main window")
  func deactivationWithoutMainWindow() {
    var scheduledDeadlines: [Date] = []
    let service = AuthenticationService.createForTesting(
      lockScheduler: { deadline, _ in
        scheduledDeadlines.append(deadline)
        return {}
      }
    )
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    let delegate = AppLockLifecycleDelegate(authService: service)

    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))

    #expect(service.isAppActive == false)
    #expect(service.backgroundTrigger == .appSwitch)
    #expect(scheduledDeadlines == [service.backgroundDate!.addingTimeInterval(60)])
  }

  @Test("Screen lock records its trigger without a main window")
  func screenLockWithoutMainWindow() {
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(authService: service)

    delegate.screenDidLockOrSleep()

    #expect(service.backgroundTrigger == .screenSleep)
    #expect(service.isLocked)
  }

  @Test("Screen notifications are observed without a main window")
  func screenNotificationsWithoutMainWindow() async {
    let workspaceCenter = NotificationCenter()
    let screenLockCenter = NotificationCenter()
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      screenLockNotificationCenter: screenLockCenter
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false

    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    for _ in 0..<20 where !service.isLocked {
      await Task.yield()
    }

    #expect(service.isLocked)
  }

  @Test("Distributed screen-lock notifications are observed without a main window")
  func distributedScreenLockNotificationWithoutMainWindow() {
    let screenLockCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      screenLockNotificationCenter: screenLockCenter,
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false

    screenLockCenter.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    #expect(deferredEvents.count == 1)
    deferredEvents.runAll()

    #expect(service.isLocked)
  }

  @Test("A queued screen event from before authentication cannot re-lock")
  func queuedScreenEventBeforeAuthenticationIsIgnored() async {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let service = AuthenticationService.createForTesting(
      laContextFactory: { SuccessfulLAContext() }
    )
    service.isAppLockEnabled = true
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    #expect(await service.authenticate())
    deferredEvents.runAll()

    #expect(service.isLocked == false)
  }

  @Test("A screen event after authentication survives a clock rollback")
  func screenEventAfterAuthenticationWithEarlierDateLocks() async {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let earlierClockValue = Date().addingTimeInterval(-120)
    let service = AuthenticationService.createForTesting(
      laContextFactory: { SuccessfulLAContext() }
    )
    service.isAppLockEnabled = true
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      eventTime: { earlierClockValue },
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(await service.authenticate())
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    deferredEvents.runAll()

    #expect(service.isLocked)
  }

  @Test("A genuine queued screen lock takes effect after app activation")
  func queuedScreenLockAfterActivation() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .never
    service.screenLockTimeout = .immediately
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false

    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    #expect(deferredEvents.count == 1)
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))
    #expect(service.isLocked)
    deferredEvents.runAll()

    #expect(service.backgroundDate == nil)
    #expect(service.isLocked)
  }

  @Test("An unexpired queued screen lock is cleared after activation")
  func queuedScreenLockWithinTimeout() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let receivedAt = Date().addingTimeInterval(-30)
    var scheduledDeadlines: [Date] = []
    var cancellationCount = 0
    let service = AuthenticationService.createForTesting(
      lockScheduler: { deadline, _ in
        scheduledDeadlines.append(deadline)
        return { cancellationCount += 1 }
      }
    )
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .never
    service.screenLockTimeout = .oneMinute
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      eventTime: { receivedAt },
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false
    service.lastUnlockDate = receivedAt.addingTimeInterval(-60)

    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))
    #expect(cancellationCount == 1)
    deferredEvents.runAll()

    #expect(scheduledDeadlines == [receivedAt.addingTimeInterval(60)])
    #expect(cancellationCount == 1)
    #expect(service.backgroundDate == nil)
    #expect(service.isLocked == false)
  }

  @Test("An expired queued screen lock takes effect after app activation")
  func queuedScreenLockAfterTimeout() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let receivedAt = Date().addingTimeInterval(-120)
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .never
    service.screenLockTimeout = .oneMinute
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      eventTime: { receivedAt },
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false
    service.lastUnlockDate = receivedAt.addingTimeInterval(-60)

    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))
    #expect(service.isLocked)
    deferredEvents.runAll()

    #expect(service.isLocked)
    #expect(service.backgroundDate == nil)
  }

  @Test("A Never screen event preserves an overdue app-switch lock")
  func queuedScreenSleepDoesNotCancelAppSwitch() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.screenLockTimeout = .never
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false

    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))
    service.setBackgroundDateForTesting(Date().addingTimeInterval(-120))
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))
    deferredEvents.runAll()

    #expect(service.isLocked)
    #expect(service.backgroundDate == nil)
  }

  @Test("A queued callback cannot overwrite a later app-switch session")
  func queuedCallbackDoesNotOverwriteLaterSession() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.screenLockTimeout = .oneMinute
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false

    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))
    delegate.applicationDidResignActive(
      Notification(name: NSApplication.didResignActiveNotification))
    let newSessionDate = service.backgroundDate
    deferredEvents.runAll()

    #expect(service.backgroundTrigger == .appSwitch)
    #expect(service.backgroundDate == newSessionDate)
    #expect(service.isLocked == false)
  }

  @Test("Queued screen events keep their notification receipt time")
  func screenEventKeepsReceiptTime() {
    let workspaceCenter = NotificationCenter()
    let deferredEvents = DeferredScreenEvents()
    let receivedAt = Date().addingTimeInterval(-120)
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .oneMinute
    let delegate = AppLockLifecycleDelegate(
      authService: service,
      workspaceNotificationCenter: workspaceCenter,
      eventTime: { receivedAt },
      dispatchScreenEvent: { deferredEvents.enqueue($0) }
    )
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    service.isLocked = false
    service.lastUnlockDate = receivedAt.addingTimeInterval(-60)

    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    #expect(deferredEvents.count == 1)
    deferredEvents.runAll()

    #expect(service.backgroundDate == receivedAt)
    #expect(service.isLocked)
  }

  @Test("App activation evaluates a pending timeout without a main window")
  func activationWithoutMainWindow() {
    let service = AuthenticationService.createForTesting()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.isAppActive = false
    service.recordBackground(trigger: .appSwitch)
    service.setBackgroundDateForTesting(Date().addingTimeInterval(-61))
    let delegate = AppLockLifecycleDelegate(authService: service)

    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification))

    #expect(service.isAppActive)
    #expect(service.isLocked)
    #expect(service.backgroundDate == nil)
  }
}
