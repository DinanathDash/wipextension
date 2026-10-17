//
//  TapeScrubHeatModel.swift
//  Wipextension
//
//  Adapted from Droppy's High Alert / Pomodoro design reuse kit with
//  permission from Jordy Spruit (author of Droppy).
//
//  Pure scrub-energy model for the timer tape scrubbers (Pomodoro / High Alert
//  on the Mac, and the companion's mirrored tape on iOS): how fast the user is
//  scrubbing maps to a 0...1 intensity, which cools on an exponential curve
//  once motion stops and falls off spatially around the active reading.
//
//  That intensity drives ONE thing: the tape's own lit region , the warm
//  near-white bloom the ruler already draws at and just left of the pointer ,
//  swelling subtly brighter while the user scrubs and easing back on rest.
//  There is deliberately no colour of its own here: an earlier amber→red
//  "heat" ramp was rejected because the light must stay in the tape's existing
//  colour language, never a new hue layered on top.
//
//  Platform-free by contract: Foundation only, no SwiftUI/AppKit/UIKit, so the
//  identical type can back both the macOS and iOS scrubbers and a unit test can
//  drive it without a view. All tuning lives in the explicit constants below ,
//  when one platform re-tunes the feel, the other inherits it by mirroring
//  these values, not by re-deriving them.
//

import Foundation

/// Velocity-driven scrub energy for a tape scrubber.
///
/// Feed it every scrub delta (in tick/minute space); read `intensity(at:)`
/// from a frame clock while `isGlowing(at:)` is true. Between feeds the
/// intensity decays exponentially (`exp(-dt / coolDownTimeConstant)`), so the
/// light never snaps off , a stop always reads as a smooth ease-back.
struct TapeScrubHeatModel: Equatable {
    // MARK: Tuning constants (shared macOS <-> iOS; keep in sync by value)

    /// Scrub velocity, in ticks per second, that reads as full intensity.
    /// intensity target = clamp(|velocity| / maxVelocityTicksPerSecond, 0, 1).
    static let maxVelocityTicksPerSecond: Double = 60

    /// Exponential ease-back time constant, in seconds. After a stop the
    /// intensity follows i * exp(-dt / tau): ~50% left at 0.49 s, ~5% at 2.1 s.
    static let coolDownTimeConstant: Double = 0.7

    /// Spatial falloff scale, in ticks: the swell concentrates on the active
    /// reading and fades as exp(-distance / falloffTicks) along the tape.
    static let falloffTicks: Double = 6

    /// How strongly a single feed pulls the intensity toward its velocity
    /// target (0...1). Below 1 the swell ramps over a few events instead of
    /// jumping, so slow scrubs stay barely-there and only a sustained fast
    /// flick reaches the (still subtle) peak.
    static let warmUpBlend: Double = 0.45

    /// Intensity below which the light counts as fully rested; drives
    /// `isGlowing(at:)` so a frame clock can park instead of animating an
    /// invisible glow forever.
    static let restingIntensity: Double = 0.01

    /// Event gaps are clamped into this range (seconds) before the velocity
    /// divide, so the first event of a gesture and duplicate timestamps do not
    /// read as infinite speed.
    static let minimumEventInterval: Double = 1.0 / 240.0
    static let maximumEventInterval: Double = 0.1

    // MARK: Lit-region glow (shared render constants, macOS <-> iOS)
    //
    // The drawn swell reuses the ruler's own lit tone (the warm near-white the
    // selected tick burns to); these constants only shape how much of it the
    // scrub adds, so both platforms brighten the same light by the same amount.

    /// Peak extra opacity of the lit-region swell at full scrub intensity.
    /// Subtle by design , the light comes alive, it does not become an effect.
    static let litGlowMaxOpacity: Double = 0.16

    /// Vertical spread of the swell, in tick heights.
    static let litGlowHeightFactor: Double = 1.6

    /// How far the swell's centre sits toward the lit side of the tape (in
    /// ticks, left of the pointer), hugging the bloom the ruler already draws
    /// at and just below the selection.
    static let litGlowCenterBiasTicks: Double = 1.5

    /// Spatial falloff factor for a tick `distance` ticks from the active
    /// reading: 1 at the reading, exp(-distance / falloffTicks) away from it.
    static func spatialFalloff(atTickDistance distance: Double) -> Double {
        exp(-abs(distance) / falloffTicks)
    }

    // MARK: State

    /// Intensity at `anchorTime`; read the current value via `intensity(at:)`.
    private(set) var anchorIntensity: Double = 0
    private(set) var anchorTime: Date = .distantPast

    /// Current intensity 0...1 at `date`, decaying exponentially since the
    /// last feed.
    func intensity(at date: Date) -> Double {
        guard anchorIntensity > 0 else { return 0 }
        let dt = date.timeIntervalSince(anchorTime)
        guard dt > 0 else { return anchorIntensity }
        return anchorIntensity * exp(-dt / Self.coolDownTimeConstant)
    }

    /// True while there is visible light left to draw.
    func isGlowing(at date: Date) -> Bool {
        intensity(at: date) > Self.restingIntensity
    }

    /// Seconds from `date` until the light has fully rested (`isGlowing`
    /// false); 0 when already at rest. Lets a caller schedule one park instead
    /// of polling.
    func timeUntilRest(at date: Date) -> Double {
        let current = intensity(at: date)
        guard current > Self.restingIntensity else { return 0 }
        return Self.coolDownTimeConstant * log(current / Self.restingIntensity)
    }

    /// Feed one scrub delta (in ticks). Velocity is |delta| over the clamped
    /// interval since the previous feed; its clamped ratio to
    /// `maxVelocityTicksPerSecond` becomes the intensity target, approached at
    /// `warmUpBlend` per event and never below the decayed current value , so
    /// the light rises with speed and only ever *eases back* by the
    /// exponential curve, never by a slower event snapping it down.
    /// Returns false when the delta was too small to change anything.
    @discardableResult
    mutating func feed(deltaTicks: Double, at now: Date) -> Bool {
        let magnitude = abs(deltaTicks)
        guard magnitude > 0.001 else { return false }
        let rawInterval = now.timeIntervalSince(anchorTime)
        let interval = min(max(rawInterval, Self.minimumEventInterval), Self.maximumEventInterval)
        let velocity = magnitude / interval
        let target = min(velocity / Self.maxVelocityTicksPerSecond, 1)
        let current = intensity(at: now)
        let risen = current + (target - current) * Self.warmUpBlend
        anchorIntensity = max(current, min(risen, 1))
        anchorTime = now
        return true
    }

    /// Drop straight to rest (view teardown); normal stops just let it decay.
    mutating func extinguish() {
        anchorIntensity = 0
        anchorTime = .distantPast
    }
}
