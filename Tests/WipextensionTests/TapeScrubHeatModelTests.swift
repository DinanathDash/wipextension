//
//  TapeScrubHeatModelTests.swift
//  WipextensionTests
//

import Foundation
import Testing
@testable import Wipextension

@Suite("Tape Scrub Heat Model Tests")
struct TapeScrubHeatModelTests {
    @Test("Fresh heat model starts in resting, unlit state")
    func initialState() {
        let model = TapeScrubHeatModel()
        let now = Date()
        #expect(model.anchorIntensity == 0)
        #expect(model.intensity(at: now) == 0)
        #expect(!model.isGlowing(at: now))
        #expect(model.timeUntilRest(at: now) == 0)
    }

    @Test("Sub-threshold delta ticks are rejected without lighting")
    func subThresholdDelta() {
        var model = TapeScrubHeatModel()
        let now = Date()
        let fed = model.feed(deltaTicks: 0.0005, at: now)
        #expect(!fed)
        #expect(model.intensity(at: now) == 0)
        #expect(!model.isGlowing(at: now))
    }

    @Test("Non-finite deltas (NaN, infinity) are safely rejected")
    func nonFiniteDeltas() {
        var model = TapeScrubHeatModel()
        let now = Date()
        let fedNan = model.feed(deltaTicks: .nan, at: now)
        let fedInf = model.feed(deltaTicks: .infinity, at: now)
        let fedNegInf = model.feed(deltaTicks: -.infinity, at: now)
        #expect(!fedNan)
        #expect(!fedInf)
        #expect(!fedNegInf)
        #expect(model.intensity(at: now) == 0)
    }

    @Test("Single flick ramps intensity according to warmUpBlend")
    func singleFlickWarmUp() {
        var model = TapeScrubHeatModel()
        let t0 = Date()
        // Feed 1: starting from 0, delta = 6.0 ticks over max interval 0.1s gives velocity = 60 (target 1.0)
        // With warmUpBlend = 0.45, anchorIntensity reaches exactly 0.45 (1.0 * 0.45)
        model.feed(deltaTicks: 6.0, at: t0)

        let current = model.intensity(at: t0)
        #expect(abs(current - TapeScrubHeatModel.warmUpBlend) < 0.0001)
        #expect(model.isGlowing(at: t0))
    }

    @Test("Sustained rapid scrubbing reaches high equilibrium near peak without overshoot")
    func sustainedRapidScrubbing() {
        var model = TapeScrubHeatModel()
        var time = Date()
        for _ in 0..<30 {
            time = time.addingTimeInterval(0.005)
            model.feed(deltaTicks: 5.0, at: time)
        }
        let maxed = model.intensity(at: time)
        #expect(maxed >= 0.98 && maxed <= 1.0)
    }

    @Test("Extreme giant delta ticks do not breach intensity ceiling of 1.0")
    func extremeGiantDeltas() {
        var model = TapeScrubHeatModel()
        let t0 = Date()
        model.feed(deltaTicks: 1.0, at: t0)
        let t1 = t0.addingTimeInterval(0.01)
        model.feed(deltaTicks: 100_000.0, at: t1)

        #expect(model.intensity(at: t1) <= 1.0)
        #expect(model.intensity(at: t1) >= 0.45)
    }

    @Test("Negative deltas (reverse scrubbing) produce equal positive heat")
    func negativeDeltasProduceHeat() {
        var forwardModel = TapeScrubHeatModel()
        var reverseModel = TapeScrubHeatModel()
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.02)

        forwardModel.feed(deltaTicks: 3.0, at: t0)
        forwardModel.feed(deltaTicks: 3.0, at: t1)

        reverseModel.feed(deltaTicks: -3.0, at: t0)
        reverseModel.feed(deltaTicks: -3.0, at: t1)

        #expect(abs(forwardModel.intensity(at: t1) - reverseModel.intensity(at: t1)) < 0.0001)
    }

    @Test("Exponential cooldown follows exact theoretical half-life")
    func exponentialCoolDown() {
        var model = TapeScrubHeatModel()
        var time = Date()
        for _ in 0..<15 {
            time = time.addingTimeInterval(0.01)
            model.feed(deltaTicks: 10.0, at: time)
        }
        let peak = model.intensity(at: time)
        #expect(peak > 0.9)

        // Half-life is tau * ln(2) = 0.7 * 0.693147 = ~0.4852 seconds
        let halfLife = TapeScrubHeatModel.coolDownTimeConstant * log(2.0)
        let halfLifeTime = time.addingTimeInterval(halfLife)
        let halfIntensity = model.intensity(at: halfLifeTime)

        let expectedHalf = peak * 0.5
        #expect(abs(halfIntensity - expectedHalf) < 0.01)
    }

    @Test("timeUntilRest accurately predicts when isGlowing becomes false")
    func timeUntilRestPrediction() {
        var model = TapeScrubHeatModel()
        var time = Date()
        for _ in 0..<10 {
            time = time.addingTimeInterval(0.01)
            model.feed(deltaTicks: 5.0, at: time)
        }
        #expect(model.isGlowing(at: time))

        let duration = model.timeUntilRest(at: time)
        #expect(duration > 0)

        // Just before rest: still glowing
        let justBefore = time.addingTimeInterval(duration - 0.05)
        #expect(model.isGlowing(at: justBefore))

        // Just after rest: no longer glowing
        let justAfter = time.addingTimeInterval(duration + 0.05)
        #expect(!model.isGlowing(at: justAfter))
        #expect(model.intensity(at: justAfter) <= TapeScrubHeatModel.restingIntensity)
    }

    @Test("extinguish drops intensity immediately to zero")
    func extinguishTeardown() {
        var model = TapeScrubHeatModel()
        let now = Date()
        model.feed(deltaTicks: 10.0, at: now)
        model.feed(deltaTicks: 10.0, at: now.addingTimeInterval(0.01))
        #expect(model.intensity(at: now.addingTimeInterval(0.01)) > 0)

        model.extinguish()
        #expect(model.intensity(at: now) == 0)
        #expect(!model.isGlowing(at: now))
        #expect(model.timeUntilRest(at: now) == 0)
    }

    @Test("Spatial falloff is 1 at pointer and fades exponentially along distance")
    func spatialFalloffCurve() {
        #expect(TapeScrubHeatModel.spatialFalloff(atTickDistance: 0) == 1.0)

        // At 1 tau distance (6 ticks): exp(-1) = 0.367879...
        let atOneTau = TapeScrubHeatModel.spatialFalloff(atTickDistance: TapeScrubHeatModel.falloffTicks)
        #expect(abs(atOneTau - exp(-1.0)) < 0.0001)

        // Negative distance is symmetric
        let atNegOneTau = TapeScrubHeatModel.spatialFalloff(atTickDistance: -TapeScrubHeatModel.falloffTicks)
        #expect(abs(atNegOneTau - atOneTau) < 0.000001)

        // Huge distance decays towards zero
        #expect(TapeScrubHeatModel.spatialFalloff(atTickDistance: 1000) < 0.000001)

        // Non-finite distance handled safely
        #expect(TapeScrubHeatModel.spatialFalloff(atTickDistance: .infinity) == 0)
        #expect(TapeScrubHeatModel.spatialFalloff(atTickDistance: .nan) == 0)
    }
}
