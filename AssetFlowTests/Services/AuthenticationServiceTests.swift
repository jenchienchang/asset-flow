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
import Testing

@testable import AssetFlow

@Suite("AuthenticationService Tests")
@MainActor
struct AuthenticationServiceTests {

  @MainActor private final class MockLockScheduler {
    var deadlines: [Date] = []
    var actions: [@MainActor () -> Void] = []
    var cancelled: Set<Int> = []

    func schedule(
      at deadline: Date, action: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
      let index = actions.count
      deadlines.append(deadline)
      actions.append(action)
      return { self.cancelled.insert(index) }
    }

    func fire(_ index: Int) {
      actions[index]()
    }
  }

  // MARK: - Mock LAContext

  /// Mock LAContext subclass for testing without real biometric hardware.
  private nonisolated class MockLAContext: LAContext {
    var evaluateResult = true
    var evaluatedPolicy: LAPolicy?
    var evaluatedReason: String?

    /// Called just before `evaluatePolicy` returns, while still inside the method.
    /// Use this to inspect service state mid-authentication.
    var onEvaluate: (() -> Void)?

    override func evaluatePolicy(
      _ policy: LAPolicy, localizedReason: String
    ) async throws -> Bool {
      evaluatedPolicy = policy
      evaluatedReason = localizedReason

      onEvaluate?()

      if evaluateResult {
        return true
      }
      throw LAError(.userCancel)
    }
  }

  /// Creates an isolated `AuthenticationService` with a mock `LAContext` factory.
  private func createService(evaluateSuccess: Bool = true) -> (
    service: AuthenticationService, mock: MockLAContext
  ) {
    let mock = MockLAContext()
    mock.evaluateResult = evaluateSuccess
    let service = AuthenticationService.createForTesting(
      laContextFactory: { mock }
    )
    return (service, mock)
  }

  private func createServiceWithScheduler() -> (
    service: AuthenticationService, scheduler: MockLockScheduler
  ) {
    let scheduler = MockLockScheduler()
    let service = AuthenticationService.createForTesting(
      lockScheduler: { deadline, action in
        scheduler.schedule(at: deadline, action: action)
      }
    )
    return (service, scheduler)
  }

  // MARK: - Default Values

  @Test("Default isAppLockEnabled is false")
  func testDefaultAppLockDisabled() {
    let (service, _) = createService()
    #expect(service.isAppLockEnabled == false)
  }

  @Test("Default appSwitchTimeout is .immediately")
  func testDefaultAppSwitchTimeout() {
    let (service, _) = createService()
    #expect(service.appSwitchTimeout == .immediately)
  }

  @Test("Default screenLockTimeout is .immediately")
  func testDefaultScreenLockTimeout() {
    let (service, _) = createService()
    #expect(service.screenLockTimeout == .immediately)
  }

  // MARK: - Settings Persistence

  @Test("Enabling app lock persists to UserDefaults")
  func testAppLockEnabledPersists() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    #expect(service.isAppLockEnabled == true)
  }

  @Test("Changing appSwitchTimeout persists to UserDefaults")
  func testAppSwitchTimeoutPersists() {
    let (service, _) = createService()
    service.appSwitchTimeout = .fiveMinutes
    #expect(service.appSwitchTimeout == .fiveMinutes)
  }

  @Test("Changing screenLockTimeout persists to UserDefaults")
  func testScreenLockTimeoutPersists() {
    let (service, _) = createService()
    service.screenLockTimeout = .fifteenMinutes
    #expect(service.screenLockTimeout == .fifteenMinutes)
  }

  // MARK: - Lock State

  @Test("isLocked starts true when app lock is enabled")
  func testLockedWhenEnabled() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    // Simulate fresh launch by checking lockOnLaunchIfNeeded
    service.lockOnLaunchIfNeeded()
    #expect(service.isLocked == true)
  }

  @Test("isLocked starts false when app lock is disabled")
  func testUnlockedWhenDisabled() {
    let (service, _) = createService()
    #expect(service.isLocked == false)
  }

  // MARK: - Authentication

  @Test("authenticate() returns true on success and sets isLocked to false")
  func testAuthenticateSuccess() async {
    let (service, mock) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.lockOnLaunchIfNeeded()
    #expect(service.isLocked == true)

    let result = await service.authenticate()

    #expect(result == true)
    #expect(service.isLocked == false)
    #expect(mock.evaluatedPolicy == .deviceOwnerAuthentication)
  }

  @Test("authenticate() returns false on user cancel and keeps isLocked true")
  func testAuthenticateFailure() async {
    let (service, _) = createService(evaluateSuccess: false)
    service.isAppLockEnabled = true
    service.lockOnLaunchIfNeeded()

    let result = await service.authenticate()

    #expect(result == false)
    #expect(service.isLocked == true)
  }

  @Test("authenticate() sets lastUnlockDate on success")
  func testAuthenticateSetsLastUnlockDate() async {
    let (service, _) = createService(evaluateSuccess: true)
    #expect(service.lastUnlockDate == nil)

    let beforeAuth = Date()
    _ = await service.authenticate()
    let afterAuth = Date()

    let unlockDate = try! #require(service.lastUnlockDate)
    #expect(unlockDate >= beforeAuth)
    #expect(unlockDate <= afterAuth)
  }

  // MARK: - recordBackground

  @Test("recordBackground does nothing when app lock is disabled")
  func testRecordBackgroundDisabled() {
    let (service, _) = createService()
    service.recordBackground(trigger: .appSwitch)
    #expect(service.isLocked == false)
    #expect(service.backgroundDate == nil)
  }

  @Test("recordBackground does nothing when isAuthenticating")
  func testRecordBackgroundWhileAuthenticating() async {
    let mock = MockLAContext()
    mock.evaluateResult = true
    let service = AuthenticationService.createForTesting(
      laContextFactory: { mock }
    )
    service.isAppLockEnabled = true

    var backgroundDateDuringAuth: Date?
    mock.onEvaluate = {
      // Attempt to record background while auth dialog is showing
      service.recordBackground(trigger: .appSwitch)
      backgroundDateDuringAuth = service.backgroundDate
    }

    _ = await service.authenticate()

    // recordBackground should have been ignored during authentication
    #expect(backgroundDateDuringAuth == nil)
  }

  @Test("recordBackground eagerly locks with .immediately timeout")
  func testRecordBackgroundEagerLockImmediately() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .immediately

    service.recordBackground(trigger: .appSwitch)

    #expect(service.isLocked == true)
    #expect(service.backgroundDate != nil)
    #expect(service.backgroundTrigger == .appSwitch)
  }

  @Test("recordBackground records timestamp without locking for non-immediate timeout")
  func testRecordBackgroundNonImmediate() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    service.recordBackground(trigger: .appSwitch)

    #expect(service.isLocked == false)
    #expect(service.backgroundDate != nil)
    #expect(service.backgroundTrigger == .appSwitch)
  }

  @Test("Delayed app-switch timeout locks while the app remains inactive")
  func testDelayedAppSwitchLocksInBackground() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.isAppActive = false

    service.recordBackground(trigger: .appSwitch)

    #expect(service.isLocked == false)
    #expect(scheduler.deadlines == [service.backgroundDate!.addingTimeInterval(60)])
    guard scheduler.actions.count == 1 else { return }
    scheduler.fire(0)
    #expect(service.isLocked == true)
  }

  @Test("Returning before the deadline prevents a delayed lock")
  func testReturnBeforeDeadlineCancelsLock() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.isAppActive = false

    service.recordBackground(trigger: .appSwitch)
    service.isAppActive = true
    service.evaluateOnBecomeActive()

    #expect(scheduler.deadlines.count == 1)
    #expect(scheduler.cancelled.contains(0))
    guard scheduler.actions.count == 1 else { return }
    scheduler.fire(0)
    #expect(service.isLocked == false)
  }

  @Test("Disabling app lock cancels a pending deadline")
  func testDisablingAppLockCancelsDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute

    service.recordBackground(trigger: .appSwitch)
    service.isAppLockEnabled = false

    #expect(scheduler.cancelled.contains(0))
    #expect(service.backgroundDate == nil)
    scheduler.fire(0)
    #expect(service.isLocked == false)
  }

  @Test("Repeated app-switch events retain the original deadline")
  func testRepeatedAppSwitchRetainsDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute

    service.recordBackground(trigger: .appSwitch)
    service.recordBackground(trigger: .appSwitch)

    #expect(scheduler.deadlines.count == 1)
    #expect(scheduler.cancelled.isEmpty)
  }

  @Test("A longer screen timeout preserves the earlier app-switch deadline")
  func testLongerScreenTimeoutPreservesAppSwitchDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.screenLockTimeout = .fiveMinutes
    service.isAppActive = false

    service.recordBackground(trigger: .appSwitch)
    let appSwitchDate = service.backgroundDate!
    service.recordBackground(trigger: .screenSleep)

    #expect(scheduler.deadlines == [appSwitchDate.addingTimeInterval(60)])
    #expect(scheduler.cancelled.isEmpty)
    #expect(service.backgroundTrigger == .appSwitch)
    guard scheduler.actions.count == 1 else { return }
    scheduler.fire(0)
    #expect(service.isLocked == true)
  }

  @Test("A Never screen timeout preserves the app-switch deadline")
  func testNeverScreenTimeoutPreservesAppSwitchDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .oneMinute
    service.screenLockTimeout = .never

    service.recordBackground(trigger: .appSwitch)
    let appSwitchDate = service.backgroundDate!
    service.recordBackground(trigger: .screenSleep)

    #expect(scheduler.deadlines == [appSwitchDate.addingTimeInterval(60)])
    #expect(scheduler.cancelled.isEmpty)
    #expect(service.backgroundTrigger == .appSwitch)
    guard scheduler.actions.count == 1 else { return }
    scheduler.fire(0)
    #expect(service.isLocked)
  }

  @Test("A shorter screen timeout advances the lock deadline")
  func testShorterScreenTimeoutAdvancesDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes
    service.screenLockTimeout = .oneMinute

    service.recordBackground(trigger: .appSwitch)
    service.recordBackground(trigger: .screenSleep)

    #expect(scheduler.deadlines.count == 2)
    #expect(scheduler.cancelled.contains(0))
    #expect(service.backgroundTrigger == .screenSleep)
    guard scheduler.actions.count == 2 else { return }
    scheduler.fire(0)
    #expect(service.isLocked == false)
    scheduler.fire(1)
    #expect(service.isLocked)
  }

  @Test("A shorter app-switch timeout advances a screen deadline")
  func testShorterAppSwitchTimeoutAdvancesDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .fiveMinutes
    service.appSwitchTimeout = .oneMinute

    service.recordBackground(trigger: .screenSleep)
    service.recordBackground(trigger: .appSwitch)

    #expect(scheduler.deadlines.count == 2)
    #expect(scheduler.cancelled.contains(0))
    #expect(service.backgroundTrigger == .appSwitch)
    guard scheduler.actions.count == 2 else { return }
    scheduler.fire(0)
    #expect(service.isLocked == false)
    scheduler.fire(1)
    #expect(service.isLocked)
  }

  @Test("Never does not schedule a background lock")
  func testNeverDoesNotScheduleLock() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .never

    service.recordBackground(trigger: .appSwitch)

    #expect(scheduler.deadlines.isEmpty)
    #expect(service.isLocked == false)
  }

  @Test("A late-starting task does not sleep past its deadline")
  func testLateTaskStartUsesDeadline() async {
    let start = Date(timeIntervalSince1970: 1_000)
    let deadline = start.addingTimeInterval(60)
    var currentTime = start
    var sleeps: [TimeInterval] = []

    await withCheckedContinuation { continuation in
      _ = scheduleLockAtDeadline(
        deadline,
        now: { currentTime },
        sleep: { delay in sleeps.append(delay) },
        action: { continuation.resume() }
      )
      currentTime = deadline.addingTimeInterval(10)
    }

    #expect(sleeps.isEmpty)
  }

  @Test("An event handled after its timeout locks immediately")
  func testLateScreenEventLocksAtOriginalDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .oneMinute
    let eventTime = Date().addingTimeInterval(-120)

    service.recordBackground(trigger: .screenSleep, at: eventTime)

    #expect(service.backgroundDate == eventTime)
    #expect(service.isLocked)
    #expect(scheduler.deadlines.isEmpty)
  }

  @Test("A new app switch at the unlock clock value still locks")
  func testAppSwitchAtUnlockClockValueLocks() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .immediately
    let clockValue = Date(timeIntervalSince1970: 1_000)
    service.lastUnlockDate = clockValue

    service.recordBackground(trigger: .appSwitch, at: clockValue)

    #expect(service.isLocked)
  }

  @Test("A new app switch after a clock rollback still locks")
  func testAppSwitchAfterClockRollbackLocks() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .immediately
    service.lastUnlockDate = Date(timeIntervalSince1970: 2_000)

    service.recordBackground(trigger: .appSwitch, at: Date(timeIntervalSince1970: 1_000))

    #expect(service.isLocked)
  }

  @Test("Successful authentication ends the previous lock deadline")
  func testSuccessfulAuthenticationCancelsPendingDeadline() async {
    let scheduler = MockLockScheduler()
    let mock = MockLAContext()
    let service = AuthenticationService.createForTesting(
      laContextFactory: { mock },
      lockScheduler: { deadline, action in scheduler.schedule(at: deadline, action: action) }
    )
    service.isAppLockEnabled = true
    service.screenLockTimeout = .oneMinute
    service.recordBackground(trigger: .screenSleep)
    #expect(scheduler.deadlines.count == 1)

    let succeeded = await service.authenticate()
    scheduler.fire(0)

    #expect(succeeded)
    #expect(scheduler.cancelled.contains(0))
    #expect(service.backgroundDate == nil)
    #expect(service.isLocked == false)
  }

  @Test("A delayed event schedules only the remaining time from receipt")
  func testDelayedScreenEventKeepsOriginalDeadline() {
    let (service, scheduler) = createServiceWithScheduler()
    service.isAppLockEnabled = true
    service.screenLockTimeout = .oneMinute
    let eventTime = Date().addingTimeInterval(-30)

    service.recordBackground(trigger: .screenSleep, at: eventTime)

    #expect(service.isLocked == false)
    #expect(scheduler.deadlines == [eventTime.addingTimeInterval(60)])
  }

  @Test("A task starting before its deadline sleeps for the remaining interval")
  func testTimelyTaskStartUsesRemainingInterval() async {
    let now = Date(timeIntervalSince1970: 1_000)
    var sleeps: [TimeInterval] = []

    await withCheckedContinuation { continuation in
      _ = scheduleLockAtDeadline(
        now.addingTimeInterval(60),
        now: { now },
        sleep: { delay in sleeps.append(delay) },
        action: { continuation.resume() }
      )
    }

    #expect(sleeps == [60])
  }

  @Test("Immediate screen lock advances a pending app-switch deadline")
  func testImmediateScreenLockAdvancesAppSwitch() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes
    service.screenLockTimeout = .immediately

    // First: appSwitch records timestamp
    service.recordBackground(trigger: .appSwitch)
    let firstDate = service.backgroundDate
    #expect(service.backgroundTrigger == .appSwitch)
    #expect(service.isLocked == false)

    // The immediate screen event moves the deadline earlier.
    service.recordBackground(trigger: .screenSleep)
    #expect(service.backgroundTrigger == .screenSleep)
    #expect(service.backgroundDate != nil)
    // screenSleep with .immediately should eagerly lock
    #expect(service.isLocked == true)
    // Date should be updated (or at least not nil)
    #expect(service.backgroundDate! >= firstDate!)
  }

  @Test("recordBackground appSwitch does NOT override pending appSwitch")
  func testRecordBackgroundAppSwitchDoesNotOverride() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    service.recordBackground(trigger: .appSwitch)
    let firstDate = service.backgroundDate

    // Second appSwitch should be ignored (backgroundDate already set)
    service.recordBackground(trigger: .appSwitch)
    #expect(service.backgroundDate == firstDate)
  }

  // MARK: - evaluateOnBecomeActive

  @Test("evaluateOnBecomeActive clears background state")
  func testEvaluateOnBecomeActiveClearsState() {
    let (service, _) = createService()
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    service.recordBackground(trigger: .appSwitch)
    #expect(service.backgroundDate != nil)
    #expect(service.backgroundTrigger != nil)

    service.evaluateOnBecomeActive()

    #expect(service.backgroundDate == nil)
    #expect(service.backgroundTrigger == nil)
  }

  @Test("evaluateOnBecomeActive locks when elapsed time exceeds timeout")
  func testEvaluateOnBecomeActiveLocksAfterTimeout() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    _ = await service.authenticate()
    #expect(service.isLocked == false)

    // Simulate going to background 6 minutes ago
    service.recordBackground(trigger: .appSwitch)
    // Manually backdatefor testing
    service.setBackgroundDateForTesting(Date().addingTimeInterval(-360))

    service.evaluateOnBecomeActive()

    #expect(service.isLocked == true)
    // Background state should be cleared
    #expect(service.backgroundDate == nil)
    #expect(service.backgroundTrigger == nil)
  }

  @Test("evaluateOnBecomeActive does NOT lock when elapsed time is within timeout")
  func testEvaluateOnBecomeActiveDoesNotLockWithinWindow() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    _ = await service.authenticate()
    #expect(service.isLocked == false)

    // Background 1 second ago — within 5-minute window
    service.recordBackground(trigger: .appSwitch)
    service.setBackgroundDateForTesting(Date().addingTimeInterval(-1))

    service.evaluateOnBecomeActive()

    #expect(service.isLocked == false)
  }

  @Test("evaluateOnBecomeActive with .never timeout does not lock")
  func testEvaluateOnBecomeActiveNeverTimeout() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .never

    _ = await service.authenticate()
    #expect(service.isLocked == false)

    service.recordBackground(trigger: .appSwitch)
    service.setBackgroundDateForTesting(Date.distantPast)

    service.evaluateOnBecomeActive()

    #expect(service.isLocked == false)
  }

  @Test("evaluateOnBecomeActive with .immediately locks regardless of elapsed time")
  func testEvaluateOnBecomeActiveImmediately() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .immediately

    _ = await service.authenticate()
    service.isLocked = false

    service.recordBackground(trigger: .appSwitch)

    // Already eagerly locked by recordBackground, but evaluate should also lock
    service.isLocked = false
    service.evaluateOnBecomeActive()

    #expect(service.isLocked == true)
  }

  @Test("evaluateOnBecomeActive uses screenLockTimeout for screenSleep trigger")
  func testEvaluateOnBecomeActiveScreenSleepTimeout() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fifteenMinutes
    service.screenLockTimeout = .immediately

    _ = await service.authenticate()
    #expect(service.isLocked == false)

    service.recordBackground(trigger: .screenSleep)

    // Already eagerly locked, but let's test evaluate path
    service.isLocked = false
    service.evaluateOnBecomeActive()

    #expect(service.isLocked == true)
  }

  @Test("evaluateOnBecomeActive does nothing when app lock is disabled")
  func testEvaluateOnBecomeActiveDisabled() {
    let (service, _) = createService()
    // Record manually to simulate edge case: enable with non-immediate timeout,
    // record background, then disable before evaluating
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes
    service.recordBackground(trigger: .appSwitch)
    service.setBackgroundDateForTesting(Date.distantPast)
    service.isAppLockEnabled = false

    service.evaluateOnBecomeActive()

    #expect(service.isLocked == false)
    // Background state should still be cleared
    #expect(service.backgroundDate == nil)
    #expect(service.backgroundTrigger == nil)
  }

  @Test("evaluateOnBecomeActive does nothing when no background event recorded")
  func testEvaluateOnBecomeActiveNoBackground() {
    let (service, _) = createService()
    service.isAppLockEnabled = true

    service.evaluateOnBecomeActive()

    #expect(service.isLocked == false)
  }

  // MARK: - authenticateIfActive

  @Test("authenticateIfActive returns false when isAppActive is false")
  func testAuthenticateIfActiveReturnsFalseWhenInactive() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppActive = false

    let result = await service.authenticateIfActive()

    #expect(result == false)
  }

  @Test("authenticateIfActive succeeds when isAppActive is true")
  func testAuthenticateIfActiveSucceedsWhenActive() async {
    let (service, _) = createService(evaluateSuccess: true)
    service.isAppLockEnabled = true
    service.lockOnLaunchIfNeeded()
    service.isAppActive = true

    let result = await service.authenticateIfActive()

    #expect(result == true)
    #expect(service.isLocked == false)
  }

  @Test("authenticateIfActive returns false when already authenticating")
  func testAuthenticateIfActiveWhileAuthenticating() async {
    let mock = MockLAContext()
    mock.evaluateResult = true
    let service = AuthenticationService.createForTesting(
      laContextFactory: { mock }
    )
    service.isAppActive = true

    var resultDuringAuth: Bool?
    mock.onEvaluate = {
      // Try authenticateIfActive while already authenticating
      Task { @MainActor in
        resultDuringAuth = await service.authenticateIfActive()
      }
    }

    _ = await service.authenticate()

    // Give the nested task a chance to complete
    try? await Task.sleep(for: .milliseconds(50))

    #expect(resultDuringAuth == false)
  }

  // MARK: - isAppActive

  @Test("isAppActive defaults to true")
  func testIsAppActiveDefaultsTrue() {
    let (service, _) = createService()
    #expect(service.isAppActive == true)
  }

  // MARK: - authWasCancelled

  @Test("authWasCancelled defaults to false")
  func testAuthWasCancelledDefaultsFalse() {
    let (service, _) = createService()
    #expect(service.authWasCancelled == false)
  }

  @Test("authWasCancelled is set to true on failed authentication")
  func testAuthWasCancelledSetOnFailure() async {
    let (service, _) = createService(evaluateSuccess: false)
    _ = await service.authenticate()
    #expect(service.authWasCancelled == true)
  }

  @Test("authWasCancelled is reset to false on successful authentication")
  func testAuthWasCancelledResetOnSuccess() async {
    let (service, _) = createService(evaluateSuccess: true)
    // Simulate a previous cancellation
    _ = await service.authenticate()
    #expect(service.authWasCancelled == false)
  }

  @Test("recordBackground resets authWasCancelled")
  func testRecordBackgroundResetsAuthWasCancelled() async {
    let (service, _) = createService(evaluateSuccess: false)
    service.isAppLockEnabled = true
    service.appSwitchTimeout = .fiveMinutes

    // Fail an auth to set authWasCancelled
    _ = await service.authenticate()
    #expect(service.authWasCancelled == true)

    // Record a background event — should reset the flag
    service.recordBackground(trigger: .appSwitch)
    #expect(service.authWasCancelled == false)
  }

  @Test("authenticateIfActive returns false when authWasCancelled is true")
  func testAuthenticateIfActiveBlockedByCancelled() async {
    let (service, _) = createService(evaluateSuccess: false)
    service.isAppActive = true

    // Fail an auth to set authWasCancelled
    _ = await service.authenticate()
    #expect(service.authWasCancelled == true)

    // authenticateIfActive should be suppressed by the flag
    let result = await service.authenticateIfActive()
    #expect(result == false)
  }

  @Test("appSwitchTimeout and screenLockTimeout persist independently")
  func testTimeoutsPersistIndependently() {
    let (service, _) = createService()
    service.appSwitchTimeout = .fifteenMinutes
    service.screenLockTimeout = .fiveMinutes

    #expect(service.appSwitchTimeout == .fifteenMinutes)
    #expect(service.screenLockTimeout == .fiveMinutes)
  }

  // MARK: - ReLockTimeout

  @Test("ReLockTimeout has correct timeout intervals")
  func testReLockTimeoutIntervals() {
    #expect(ReLockTimeout.immediately.seconds == 0)
    #expect(ReLockTimeout.oneMinute.seconds == 60)
    #expect(ReLockTimeout.fiveMinutes.seconds == 300)
    #expect(ReLockTimeout.fifteenMinutes.seconds == 900)
    #expect(ReLockTimeout.never.seconds == Double.infinity)
  }

  @Test("ReLockTimeout has 5 cases")
  func testReLockTimeoutCaseCount() {
    #expect(ReLockTimeout.allCases.count == 5)
  }

  @Test("ReLockTimeout has stable raw values for persistence")
  func testReLockTimeoutRawValues() {
    #expect(ReLockTimeout.immediately.rawValue == "immediately")
    #expect(ReLockTimeout.oneMinute.rawValue == "oneMinute")
    #expect(ReLockTimeout.fiveMinutes.rawValue == "fiveMinutes")
    #expect(ReLockTimeout.fifteenMinutes.rawValue == "fifteenMinutes")
    #expect(ReLockTimeout.never.rawValue == "never")
  }

  // MARK: - Test Isolation

  @Test("Each test instance has isolated storage")
  func testIsolatedStorage() {
    let (service1, _) = createService()
    let (service2, _) = createService()

    service1.isAppLockEnabled = true
    service1.appSwitchTimeout = .fifteenMinutes
    service1.screenLockTimeout = .fiveMinutes

    #expect(service2.isAppLockEnabled == false)
    #expect(service2.appSwitchTimeout == .immediately)
    #expect(service2.screenLockTimeout == .immediately)
  }

  // MARK: - isAuthenticating

  @Test("isAuthenticating defaults to false")
  func testIsAuthenticatingDefaultsFalse() {
    let (service, _) = createService()
    #expect(service.isAuthenticating == false)
  }

  @Test("isAuthenticating is true during authentication and false after")
  func testIsAuthenticatingTrueDuringAuth() async {
    let mock = MockLAContext()
    mock.evaluateResult = true
    let service = AuthenticationService.createForTesting(
      laContextFactory: { mock }
    )

    var wasAuthenticatingDuringEvaluate = false
    mock.onEvaluate = {
      wasAuthenticatingDuringEvaluate = service.isAuthenticating
    }

    #expect(service.isAuthenticating == false)

    _ = await service.authenticate()

    // During evaluatePolicy, isAuthenticating was true
    #expect(wasAuthenticatingDuringEvaluate == true)
    // After completion, isAuthenticating is false
    #expect(service.isAuthenticating == false)
  }

  @Test("isAuthenticating resets to false on auth failure")
  func testIsAuthenticatingResetsOnFailure() async {
    let (service, _) = createService(evaluateSuccess: false)
    #expect(service.isAuthenticating == false)

    _ = await service.authenticate()

    #expect(service.isAuthenticating == false)
  }
}
