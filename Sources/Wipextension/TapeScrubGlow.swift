//
//  TapeScrubGlow.swift
//  Wipextension
//
//  Adapted from Droppy's High Alert / Pomodoro design reuse kit with
//  permission from Jordy Spruit (author of Droppy).
//

import SwiftUI

// MARK: - Scrub light (shared with TimerTapeScrubber)

/// Brightness/direction state for the scrub tail. Pure value math so both tape
/// scrubbers can hold one of these in `@State`: `feed` tops the light up with
/// each scrub delta, `level(at:)` decays it linearly toward dark, and
/// `isActive == false` lets the driving TimelineView pause while idle.
struct TapeScrubGlowPhase {
    private(set) var seed: CGFloat = 0
    private(set) var seedAt: Date = .distantPast
    /// Sign of the last value change (+1 = value increasing, tape sliding left).
    private(set) var direction: CGFloat = 0
    /// Ticks scrubbed through since the current continuous run began (unsigned,
    /// capped). The tail is drawn this long so it only ever covers the span the
    /// gesture actually swept, never the whole tape.
    private(set) var spanTicks: CGFloat = 0
    var isActive = false
    /// Seconds for the tail to fade from full to dark once motion stops.
    var decay: CGFloat = 0.45
    /// A pause longer than this (seconds) between scrub deltas starts a fresh
    /// run, so the span measures the current swipe rather than accumulating
    /// across separate flicks.
    private var runGap: CGFloat { 0.12 }
    /// Hard cap on the swept span so a long fast scrub still leaves a bounded,
    /// understated tail instead of a tape-spanning smear.
    private var maxSpanTicks: CGFloat { 8 }

    func level(at date: Date) -> CGFloat {
        guard isActive else { return 0 }
        let dt = CGFloat(date.timeIntervalSince(seedAt))
        guard dt > 0 else { return seed }
        return max(0, seed - dt / decay)
    }

    /// Returns false when the delta was too small to light the tail.
    mutating func feed(delta: CGFloat, at now: Date) -> Bool {
        let mag = min(1, abs(delta) / 1.6)
        guard mag > 0.001 else { return false }
        // Fresh run if we were idle or paused a beat: reset the swept span so
        // the tail always measures just this continuous scrub.
        let gap = CGFloat(now.timeIntervalSince(seedAt))
        if !isActive || gap > runGap {
            spanTicks = 0
        }
        seed = min(1, level(at: now) + mag * 0.8)
        seedAt = now
        spanTicks = min(maxSpanTicks, spanTicks + abs(delta))
        if delta != 0 { direction = delta > 0 ? 1 : -1 }
        isActive = true
        return true
    }
}

/// The soft motion trail drawn over the tick band while the tape moves: a
/// faint, additively-blended smear that streams out of the fixed pointer along
/// the ticks that just passed beneath it. It is bounded to the span the gesture
/// actually swept (`spanTicks`, not the whole tape), fades out on its own once
/// scrubbing stops (`level` decays to 0), and never renders a hard solid edge ,
/// the head glow tapers straight into transparency so it reads as light, not a
/// block of colour. Fully transparent at `level == 0`.
struct TapeScrubGlow: View {
    let level: CGFloat
    /// Sign of the value change; the tape itself slides the opposite way, and
    /// the tail streams with the tape.
    let direction: CGFloat
    /// Ticks swept in the current run; sets how far the tail reaches.
    let spanTicks: CGFloat
    let tone: Color
    let tickSpacing: CGFloat
    let tickHeight: CGFloat

    var body: some View {
        let clamped = max(0, min(1, level))
        // Length tracks the swept span (bounded by the phase's cap), so a small
        // nudge leaves a short wisp and a long scrub a longer , but still
        // finite , streak. A small floor keeps a single-tick tap legible.
        let length = max(12, spanTicks * tickSpacing)
        // Ticks exit the pointer on the side the tape slides toward
        // (opposite the value direction); the tail streams after them.
        let tailDir: CGFloat = direction > 0 ? -1 : 1
        Capsule()
            .fill(
                LinearGradient(
                    // Faint at the pointer head, fading fully out along the
                    // tail , no solid end, so no cut-off blob.
                    stops: tailDir < 0
                        ? [.init(color: tone.opacity(0), location: 0.0),
                           .init(color: tone, location: 1.0)]
                        : [.init(color: tone, location: 0.0),
                           .init(color: tone.opacity(0), location: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: length, height: tickHeight)
            .blur(radius: 5)
            .opacity(Double(clamped) * 0.16)
            .blendMode(.plusLighter)
            // Anchor the head at the pointer; only the tail extends out.
            .offset(x: tailDir * length / 2)
    }
}

