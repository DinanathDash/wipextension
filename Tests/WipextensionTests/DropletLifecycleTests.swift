//
//  DropletLifecycleTests.swift
//  WipextensionTests
//

import AppKit
import Combine
import DroppyKit
import DroppyKitHarness
import Foundation
import Testing
@testable import Wipextension

@MainActor
@Suite("Droplet Lifecycle & Engine Tests")
struct DropletLifecycleTests {
    @Test("Fresh droplet has safe defaults")
    func initialDefaults() {
        let droplet = WipextensionDroplet()
        #expect(droplet.mode == .keyboard)
        #expect(droplet.selectedDuration == 5)
        #expect(droplet.remainingSeconds == 300)
        #expect(!droplet.isCleaning)
        #expect(!droplet.includeTrackpad)
        #expect(!droplet.isShowingUnlockConfirmation)
        #expect(droplet.formattedRemainingTime == "5:00")
    }

    @Test("Principal class instantiates WipextensionDroplet instance")
    func principalInstantiation() {
        let principal = WipextensionPrincipal()
        let droplet = principal.makeDroplet()
        #expect(droplet is WipextensionDroplet)
    }

    @Test("Settings pane view instantiates cleanly across presentation contexts")
    func settingsPaneInstantiation() {
        let droplet = WipextensionDroplet()
        let context = SettingsPaneContext(presentation: .harness, preferredContentWidth: 400)
        _ = droplet.makeSettingsPane(context: context)
    }

    @Test("Widget view instantiates cleanly for solo and paired shelf contexts")
    func widgetViewInstantiation() {
        let droplet = WipextensionDroplet()
        let soloContext = ShelfWidgetContext(
            availableSize: CGSize(width: 350, height: 80),
            isPaired: false
        )
        let pairedContext = ShelfWidgetContext(
            availableSize: CGSize(width: 175, height: 80),
            isPaired: true
        )
        _ = droplet.makeWidgetView("wipextension", context: soloContext)
        _ = droplet.makeWidgetView("wipextension", context: pairedContext)
        #expect(droplet.makeWidgetSettingsPopover("wipextension") == nil)
    }

    @Test("Activation loads and respects stored preferences")
    func activationWithPreferences() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost(initialPreferences: [
            "cleaningMode": CleaningMode.display.rawValue,
            "includeTrackpad": true,
            "selectedDuration": 15
        ])

        try droplet.activate(host: host)
        #expect(droplet.mode == .display)
        #expect(droplet.includeTrackpad == true)
        #expect(droplet.selectedDuration == 15)
        #expect(droplet.remainingSeconds == 900)
    }

    @Test("Activation sanitizes out-of-bound or corrupted preferences")
    func activationWithCorruptedPreferences() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost(initialPreferences: [
            "cleaningMode": "non_existent_mode",
            "selectedDuration": 999
        ])

        try droplet.activate(host: host)
        #expect(droplet.mode == .keyboard) // falls back to keyboard
        #expect(droplet.selectedDuration == 30) // clamped to 30
        #expect(droplet.remainingSeconds == 1800)
    }

    @Test("Setting selectedDuration strictly enforces 1...30 minute bounds")
    func durationClamping() {
        let droplet = WipextensionDroplet()

        droplet.selectedDuration = 0
        #expect(droplet.selectedDuration == 1)
        #expect(droplet.remainingSeconds == 60)

        droplet.selectedDuration = -10
        #expect(droplet.selectedDuration == 1)

        droplet.selectedDuration = 45
        #expect(droplet.selectedDuration == 30)
        #expect(droplet.remainingSeconds == 1800)

        droplet.updateSelectedDuration(20)
        #expect(droplet.selectedDuration == 20)
        #expect(droplet.remainingSeconds == 1200)
    }

    @Test("formattedRemainingTime handles edge cases correctly", arguments: [
        (-5, "0:00"),
        (0, "0:00"),
        (5, "0:05"),
        (59, "0:59"),
        (60, "1:00"),
        (65, "1:05"),
        (600, "10:00"),
        (1800, "30:00")
    ])
    func formattedRemainingTimeCases(seconds: Int, expected: String) {
        let total = max(0, seconds)
        let formatted = String(format: "%d:%02d", total / 60, total % 60)
        #expect(formatted == expected)
    }

    @Test("Detent feedback plays host tick sound")
    func detentFeedback() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.playDetentFeedback()
    }

    @Test("autoStopDuration preference get and set roundtrip")
    func autoStopDurationPersistence() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        #expect(droplet.autoStopDuration() == 60)
        droplet.setAutoStopDuration(120)
        #expect(droplet.autoStopDuration() == 120)
    }

    @Test("startCleaning requires accessibility permission")
    func startCleaningPermissionCheck() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost(capabilities: [.globalShortcuts])
        try droplet.activate(host: host)

        droplet.startCleaning()
        #expect(!droplet.isCleaning)
    }

    @Test("stopCleaning triggers unlock confirmation state")
    func stopCleaningConfirmation() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.startCleaning()
        if droplet.isCleaning {
            #expect(!droplet.isShowingUnlockConfirmation)
            droplet.stopCleaning()
            #expect(!droplet.isCleaning)
            #expect(droplet.isShowingUnlockConfirmation)
        }
    }

    @Test("System sleep notification triggers auto-stop")
    func systemSleepNotificationAutoStop() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.startCleaning()
        if droplet.isCleaning {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            #expect(!droplet.isCleaning)
        }
    }

    @Test("Screen lock notification triggers auto-stop")
    func screenLockNotificationAutoStop() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.startCleaning()
        if droplet.isCleaning {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            #expect(!droplet.isCleaning)
        }
    }

    @Test("Deactivation stops cleaning and clears unlock confirmation")
    func deactivation() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.startCleaning()
        droplet.deactivate()

        #expect(!droplet.isCleaning)
        #expect(!droplet.isShowingUnlockConfirmation)
    }
}
