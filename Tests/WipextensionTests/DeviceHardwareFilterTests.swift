//
//  DeviceHardwareFilterTests.swift
//  WipextensionTests
//

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Wipextension

@Suite("Device Hardware Filter Tests")
struct DeviceHardwareFilterTests {
    @Test("Precise pixel scrolling deltas (trackpad gesture) are identified as built-in trackpad in fallback")
    func preciseScrollingFallback() {
        let filter = DeviceHardwareFilter()
        let event = makeSyntheticScrollEvent(deltaY: 10, precise: true, senderID: 0)
        let isTrackpad = filter.isBuiltInTrackpad(event: event)
        #expect(isTrackpad == true)
    }

    @Test("Standard mouse wheel clicks (line scrolling) are identified as external pointing devices")
    func mouseWheelFallback() {
        let filter = DeviceHardwareFilter()
        let event = makeSyntheticScrollEvent(deltaY: 2, precise: false, senderID: 0)
        let isTrackpad = filter.isBuiltInTrackpad(event: event)
        #expect(isTrackpad == false)
    }

    @Test("Generic mouse click events fallback to external pointing device classification")
    func mouseClickFallback() {
        let filter = DeviceHardwareFilter()
        let event = makeSyntheticMouseEvent(type: .leftMouseDown, location: CGPoint(x: 100, y: 100), senderID: 0)
        let isTrackpad = filter.isBuiltInTrackpad(event: event)
        #expect(isTrackpad == false)
    }

    @Test("Hardware filter safely caches sender evaluations across repeated queries")
    func cachingConsistency() {
        let filter = DeviceHardwareFilter()
        let event1 = makeSyntheticScrollEvent(deltaY: 5, precise: true, senderID: 9999)
        let res1 = filter.isBuiltInTrackpad(event: event1)

        let event2 = makeSyntheticScrollEvent(deltaY: 5, precise: true, senderID: 9999)
        let res2 = filter.isBuiltInTrackpad(event: event2)

        #expect(res1 == res2)
    }

    @Test("Concurrent evaluations across multiple threads operate safely without race conditions")
    func concurrentEvaluations() async {
        let filter = DeviceHardwareFilter()

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let sender = UInt64(1000 + (i % 5))
                    let event = makeSyntheticScrollEvent(deltaY: Int32(i), precise: i % 2 == 0, senderID: sender)
                    return filter.isBuiltInTrackpad(event: event)
                }
            }
        }
    }
}
