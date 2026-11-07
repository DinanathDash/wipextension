//
//  TapeScrubGlowTests.swift
//  WipextensionTests
//

import AppKit
import Foundation
import Testing
@testable import Wipextension

@Suite("Tape Scrub Glow Tests")
struct TapeScrubGlowTests {
    @Test("Fresh glow phase is idle with zero seed and zero span")
    func initialState() {
        let phase = TapeScrubGlowPhase()
        let now = Date()
        #expect(phase.seed == 0)
        #expect(phase.spanTicks == 0)
        #expect(phase.direction == 0)
        #expect(!phase.isActive)
        #expect(phase.level(at: now) == 0)
    }

    @Test("Sub-threshold deltas are rejected and do not activate phase")
    func subThresholdDelta() {
        var phase = TapeScrubGlowPhase()
        let now = Date()
        let fed = phase.feed(delta: 0.0005, at: now)
        #expect(!fed)
        #expect(!phase.isActive)
        #expect(phase.level(at: now) == 0)
    }

    @Test("Direction accurately captures scrub sign (+1 for forward, -1 for reverse)")
    func directionTracking() {
        var forwardPhase = TapeScrubGlowPhase()
        let now = Date()
        _ = forwardPhase.feed(delta: 1.5, at: now)
        #expect(forwardPhase.direction == 1)

        var reversePhase = TapeScrubGlowPhase()
        _ = reversePhase.feed(delta: -1.5, at: now)
        #expect(reversePhase.direction == -1)
    }

    @Test("Continuous feeds accumulate spanTicks up to maximum cap of 8")
    func spanTicksCapping() {
        var phase = TapeScrubGlowPhase()
        var time = Date()
        for _ in 0..<20 {
            time = time.addingTimeInterval(0.01)
            _ = phase.feed(delta: 1.0, at: time)
        }
        #expect(phase.spanTicks == 8)
    }

    @Test("A pause longer than runGap (0.12s) resets spanTicks for a fresh run")
    func runGapResetsSpanTicks() {
        var phase = TapeScrubGlowPhase()
        let t0 = Date()
        _ = phase.feed(delta: 3.0, at: t0)
        #expect(phase.spanTicks == 3.0)

        // Pause 0.15s (> 0.12s runGap)
        let t1 = t0.addingTimeInterval(0.15)
        _ = phase.feed(delta: 1.5, at: t1)
        #expect(phase.spanTicks == 1.5)
    }

    @Test("Glow level decays linearly towards zero and never becomes negative")
    func linearDecay() {
        var phase = TapeScrubGlowPhase()
        let t0 = Date()
        _ = phase.feed(delta: 2.0, at: t0)
        let initialLevel = phase.level(at: t0)
        #expect(initialLevel > 0)

        // Midway through decay (decay = 0.45s)
        let midTime = t0.addingTimeInterval(0.225)
        let midLevel = phase.level(at: midTime)
        #expect(midLevel < initialLevel && midLevel > 0)

        // Fully decayed
        let endTime = t0.addingTimeInterval(0.50)
        let endLevel = phase.level(at: endTime)
        #expect(endLevel == 0)
    }

    @Test("Inactive phase returns 0 level regardless of timestamp")
    func inactivePhaseLevelIsZero() {
        var phase = TapeScrubGlowPhase()
        _ = phase.feed(delta: 2.0, at: Date())
        phase.isActive = false
        #expect(phase.level(at: Date()) == 0)
    }

    @Test("Non-finite deltas are safely rejected")
    func nonFiniteDeltas() {
        var phase = TapeScrubGlowPhase()
        let now = Date()
        let fedNan = phase.feed(delta: .nan, at: now)
        let fedInf = phase.feed(delta: .infinity, at: now)
        let fedNegInf = phase.feed(delta: -.infinity, at: now)
        #expect(!fedNan)
        #expect(!fedInf)
        #expect(!fedNegInf)
        #expect(!phase.isActive)
    }
}
