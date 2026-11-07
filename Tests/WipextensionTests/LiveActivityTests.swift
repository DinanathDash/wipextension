//
//  LiveActivityTests.swift
//  WipextensionTests
//

import AppKit
import Combine
import DroppyKit
import DroppyKitHarness
import SwiftUI
import Testing
@testable import Wipextension

@MainActor
@Suite("Live Activity and Notch HUD Tests")
struct LiveActivityTests {
    @Test("Companion detail view is only provided when cleaning is actively in progress")
    func companionDetailSeatAvailability() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        let context = LiveActivityContext(
            surface: .builtInNotch,
            availableWidth: 200
        )

        // When not cleaning, companion detail is nil
        #expect(droplet.makeCompanionDetail(context: context) == nil)

        // When cleaning, companion detail is provided
        droplet.startCleaning()
        if droplet.isCleaning {
            #expect(droplet.makeCompanionDetail(context: context) != nil)
            droplet.stopCleaning()
            #expect(droplet.makeCompanionDetail(context: context) == nil)
        }
    }

    @Test("Compact leading and trailing accessories instantiate without error")
    func compactAccessoriesInstantiation() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        for mode in CleaningMode.allCases {
            droplet.mode = mode
            _ = droplet.makeCompactLeading()
            _ = droplet.makeCompactTrailing()
            _ = droplet.makeCompanionCompact(
                context: CompactLiveActivityContext(
                    surface: .builtInNotch,
                    seat: .secondary,
                    slotSize: CGSize(width: 24, height: 24)
                )
            )
        }
    }

    @Test("LiveActivityState publishes expected priority and title during cleaning and unlock")
    func liveActivityStatePublishing() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        var states: [LiveActivityState?] = []
        var cancellables = Set<AnyCancellable>()

        droplet.liveActivityState
            .sink { states.append($0) }
            .store(in: &cancellables)

        droplet.startCleaning()
        if droplet.isCleaning {
            let activeState = states.compactMap { $0 }.last
            #expect(activeState?.priority == 200)
            #expect(activeState?.accessibilityTitle.contains("Cleaning active") == true)
            #expect(activeState?.expandedWidgetID == "wipextension")

            droplet.stopCleaning()
            let unlockState = states.compactMap { $0 }.last
            #expect(unlockState?.priority == 200)
            #expect(unlockState?.accessibilityTitle == "Cleaning unlocked")
        }
    }

    @Test("Live activity seat change callback runs cleanly")
    func seatChangeCallback() throws {
        let droplet = WipextensionDroplet()
        let host = makeHarnessHost()
        try droplet.activate(host: host)

        droplet.liveActivitySeatDidChange(.compact)
        droplet.liveActivitySeatDidChange(.secondary)
        droplet.liveActivitySeatDidChange(.none("test"))
    }

    @Test("makeExpanded returns empty view adhering to live activity contract")
    func expandedView() {
        let droplet = WipextensionDroplet()
        let context = LiveActivityContext(
            surface: .builtInNotch,
            availableWidth: 350
        )
        _ = droplet.makeExpanded(context: context)
    }
}
