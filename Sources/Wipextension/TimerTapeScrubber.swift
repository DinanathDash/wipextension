//
//  TimerTapeScrubber.swift
//  Wipextension
//
//  Adapted from Droppy's High Alert / Pomodoro design reuse kit with
//  permission from Jordy Spruit (author of Droppy).
//
//  Tape-measure duration scrubber for the timer shelf widgets: a fixed
//  upward pointer with a minute ruler sliding beneath it. Minute ticks,
//  labels every five minutes, soft edge fades, a white-hot highlight on
//  the selected tick, and per-minute haptic detents while scrubbing.
//
//  The tape itself is a single static Canvas (ticks + labels drawn once);
//  all motion is a GPU-composited `.offset`, so drags and settle springs
//  never re-rasterize the ruler.
//
//  Right-to-left layouts mirror the tape the way a slider mirrors: minutes
//  ascend toward the left and the lit run grows in from the right. SwiftUI
//  already mirrors the `.offset` and the leading-aligned frame the tape rides
//  on, but never a `Canvas`, so the ruler mirrors its own ticks, and the
//  AppKit input layer hands over leading-relative pointer motion so the tape
//  keeps following the finger. Without both, an Arabic timer showed the far
//  end of the tape under the pointer and slid against the drag.
//

import AppKit
import SwiftUI
import DroppyKit

struct TimerTapeScrubber: View {
    @Binding var selectedMinutes: Int
    let range: ClosedRange<Int>
    var accent: Color
    var compact: Bool = false
    /// Optional replacement for the "0" tick label. An empty replacement
    /// hides that label while preserving High Alert's indefinite accessibility value.
    var zeroLabelOverride: String? = nil
    /// When true, the indefinite (∞) stop sits at the FAR END of the tape ,
    /// after the largest numeric minute , instead of at zero at the start.
    /// The published value keeps its meaning: 0 = indefinite. The numeric run
    /// then starts at max(lowerBound, 1) and scrubbing past the maximum
    /// lands on ∞.
    var infinityAtEnd: Bool = false

    /// Route detents through the host feedback service; true means an endpoint.
    var onDetent: (_ isEndpoint: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// Mirrored tape: ticks ascend toward the left and pointer input is
    /// flipped into leading-relative tape space (see the file header).
    private var isMirrored: Bool { layoutDirection == .rightToLeft }

    /// Continuous tape position in minutes. The rounded value is published
    /// through `selectedMinutes`; this keeps sub-tick drag positions smooth.
    @State private var tapeValue: CGFloat
    @State private var dragAnchor: CGFloat?
    @State private var scrollSnapTask: Task<Void, Never>?
    // Scrub light: the same faint comet tail as `DetentTapeScrubber`, trailing
    // the pointer while the tape moves and fading on its own once it stops.
    @State private var glow = TapeScrubGlowPhase()
    @State private var glowIdleTask: Task<Void, Never>?
    // Scrub energy: velocity-driven intensity (pure model in
    // `TapeScrubHeatModel`, the SAME source file the iOS companion tape
    // compiles) that makes the tape's own lit region , the warm near-white
    // bloom the ruler draws at the pointer , swell subtly while scrubbing and
    // ease back exponentially once motion stops.
    @State private var heat = TapeScrubHeatModel()

    /// Warm near-white the tail glows in , the same tone the selected tick
    /// burns to in the ruler canvas, so the streak reads as that bloom smearing.
    private var glowTone: Color { Color(red: 1.0, green: 0.95, blue: 0.82) }

    init(
        selectedMinutes: Binding<Int>,
        range: ClosedRange<Int>,
        accent: Color,
        compact: Bool = false,
        zeroLabelOverride: String? = nil,
        infinityAtEnd: Bool = false,
        onDetent: @escaping (_ isEndpoint: Bool) -> Void
    ) {
        _selectedMinutes = selectedMinutes
        self.range = range
        self.accent = accent
        self.compact = compact
        self.zeroLabelOverride = zeroLabelOverride
        self.infinityAtEnd = infinityAtEnd
        self.onDetent = onDetent
        let initial: Int
        if infinityAtEnd, selectedMinutes.wrappedValue == 0 {
            initial = range.upperBound + Self.infinityGapTicks
        } else {
            let lower = infinityAtEnd ? max(range.lowerBound, 1) : range.lowerBound
            initial = min(max(selectedMinutes.wrappedValue, lower), range.upperBound)
        }
        _tapeValue = State(initialValue: CGFloat(initial))
    }

    // MARK: - Tape coordinates
    //
    // The tape works in "tape positions". Without `infinityAtEnd` a position
    // IS the minute value. With it, the numeric run spans
    // max(lowerBound, 1)...upperBound and the ∞ stop sits `infinityGapTicks`
    // past the maximum, so its label keeps the same rhythm as the
    // every-five-minutes numeric labels. Positions inside that gap are not
    // valid stops: they publish and settle to whichever neighbour is nearer.

    /// Ticks between the last numeric minute and the ∞ stop , matches the
    /// five-minute label cadence so the ∞ label spacing looks native.
    private static let infinityGapTicks = 5

    private var numericLowerBound: Int {
        infinityAtEnd ? max(range.lowerBound, 1) : range.lowerBound
    }
    private var infinityTapePosition: Int { range.upperBound + Self.infinityGapTicks }
    private var tapeLowerBound: Int { numericLowerBound }
    private var tapeUpperBound: Int { infinityAtEnd ? infinityTapePosition : range.upperBound }

    /// Minutes → tape position (∞/0 maps to the trailing stop).
    private func tapePosition(forMinutes minutes: Int) -> Int {
        if infinityAtEnd, minutes == 0 { return infinityTapePosition }
        return min(max(minutes, numericLowerBound), range.upperBound)
    }

    /// Tape position → minutes (positions in the trailing gap snap to the
    /// nearer of the maximum numeric stop and ∞).
    private func minutes(forTapePosition position: Int) -> Int {
        guard infinityAtEnd else {
            return min(max(position, range.lowerBound), range.upperBound)
        }
        if position > range.upperBound {
            return position - range.upperBound > Self.infinityGapTicks / 2 ? 0 : range.upperBound
        }
        return max(position, numericLowerBound)
    }

    // MARK: - Metrics

    private var tickSpacing: CGFloat { compact ? 7 : 9 }
    private var tickWidth: CGFloat { compact ? 2 : 2.5 }
    private var tickHeight: CGFloat { compact ? 15 : 20 }
    private var labelFontSize: CGFloat { compact ? 10.5 : 13 }
    private var labelRowHeight: CGFloat { ceil(labelFontSize * 1.2) }
    private var labelGap: CGFloat { compact ? 3 : 4 }
    private var pointerGap: CGFloat { compact ? 3 : 4 }
    private var pointerWidth: CGFloat { compact ? 12 : 15 }
    private var pointerHeight: CGFloat { compact ? 8 : 10 }

    private var tapeHeight: CGFloat { labelRowHeight + labelGap + tickHeight }
    /// Extra canvas width on each side so the first and last labels can
    /// overhang their ticks instead of clipping at the canvas bounds.
    private var canvasOverhang: CGFloat { 24 }
    private var tapeWidth: CGFloat {
        CGFloat(tapeUpperBound - tapeLowerBound) * tickSpacing + tickWidth + canvasOverhang * 2
    }

    static func height(compact: Bool) -> CGFloat {
        let labelRow = ceil((compact ? 10.5 : 13) * 1.2)
        let tick: CGFloat = compact ? 15 : 20
        let gaps: CGFloat = compact ? 6 : 8
        let pointer: CGFloat = compact ? 8 : 10
        return labelRow + tick + gaps + pointer
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let tapeOffsetX = centerX
                - (tapeValue - CGFloat(tapeLowerBound)) * tickSpacing
                - tickWidth / 2
                - canvasOverhang

            ZStack(alignment: .topLeading) {
                // One value-aware ruler: every tick and label is coloured by
                // its own minute , lit (accent, blooming white-hot at and just
                // left of the pointer) when it is at or below the selection,
                // muted (a darker accent) when it is above. Colouring per
                // element, rather than masking a uniform tape at the pointer in
                // view space, keeps each number fully lit or fully muted instead
                // of splitting it down the middle. Motion stays a GPU-composited
                // `.offset`; the canvas only re-rasterises when the selected
                // minute changes (it is Equatable on that), so settle springs
                // never redraw the ruler.
                TapeRulerCanvas(
                    range: tapeLowerBound...tapeUpperBound,
                    numericUpperBound: range.upperBound,
                    infinityPosition: infinityAtEnd ? infinityTapePosition : nil,
                    threshold: tapePosition(forMinutes: selectedMinutes),
                    accent: accent,
                    zeroLabelOverride: zeroLabelOverride,
                    tickSpacing: tickSpacing,
                    tickWidth: tickWidth,
                    tickHeight: tickHeight,
                    labelFontSize: labelFontSize,
                    labelRowHeight: labelRowHeight,
                    labelGap: labelGap,
                    canvasOverhang: canvasOverhang,
                    tapeWidth: tapeWidth,
                    tapeHeight: tapeHeight,
                    mirrored: isMirrored
                )
                .equatable()
                .offset(x: tapeOffsetX)
                .frame(width: geo.size.width, height: tapeHeight, alignment: .topLeading)
                .mask(edgeFade)

                // The scrub tail rides above the ticks, in screen space, so it
                // stays anchored at the pointer while the tape slides beneath.
                // The TimelineView pauses itself the moment the light is idle.
                if !reduceMotion {
                    TimelineView(.animation(paused: !glow.isActive)) { timeline in
                        ZStack {
                            // The lit region coming alive under the tail: the
                            // ruler's own warm near-white bloom swelling
                            // subtly with scrub speed, hugging the active
                            // reading with the model's spatial falloff.
                            TapeScrubLitGlow(
                                intensity: heat.intensity(at: timeline.date),
                                tickSpacing: tickSpacing,
                                tickHeight: tickHeight
                            )
                            TapeScrubGlow(
                                level: glow.level(at: timeline.date),
                                direction: glow.direction,
                                spanTicks: glow.spanTicks,
                                tone: glowTone,
                                tickSpacing: tickSpacing,
                                tickHeight: tickHeight
                            )
                        }
                        .position(
                            x: centerX,
                            y: labelRowHeight + labelGap + tickHeight / 2
                        )
                    }
                    .frame(width: geo.size.width, height: tapeHeight, alignment: .topLeading)
                    .mask(edgeFade)
                    .allowsHitTesting(false)
                }

                ScrubberPointer()
                    .fill(accent)
                    .frame(width: pointerWidth, height: pointerHeight)
                    .position(x: centerX, y: tapeHeight + pointerGap + pointerHeight / 2)
            }
            .contentShape(Rectangle())
            .overlay(TapeScrubberInputCapture(
                mirrorsHorizontalInput: isMirrored,
                onScroll: { delta in handleScroll(delta: delta) },
                onTap: { localX, width in handleTap(localX: localX, viewWidth: width) },
                onDragChanged: { translationX in handleDragChanged(translationX: translationX) },
                onDragEnded: { handleDragEnded() }
            ))
        }
        .frame(height: tapeHeight + pointerGap + pointerHeight)
        .onChange(of: selectedMinutes) { _, newValue in
            syncTapeToExternalChange(newValue)
        }
        .onDisappear {
            scrollSnapTask?.cancel()
            scrollSnapTask = nil
            glowIdleTask?.cancel()
            glowIdleTask = nil
            heat.extinguish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Timer duration")))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            let target: Int
            if infinityAtEnd {
                // Ordered stops: numericLower ... numericUpper, then ∞ (0).
                if selectedMinutes == 0 {
                    target = step > 0 ? 0 : range.upperBound
                } else if selectedMinutes >= range.upperBound && step > 0 {
                    target = 0
                } else {
                    target = min(max(selectedMinutes + step, numericLowerBound), range.upperBound)
                }
            } else {
                target = min(max(selectedMinutes + step, range.lowerBound), range.upperBound)
            }
            selectedMinutes = target
            tapeValue = CGFloat(tapePosition(forMinutes: target))
        }
    }

    // MARK: - Masks

    private var edgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Drag scrubbing

    // All pointer input is handled by the AppKit `TapeScrubberInputCapture`
    // overlay so it works identically with a trackpad or an external mouse. A
    // SwiftUI `DragGesture` under that overlay never received mouse-down, which
    // is why mouse drag and tap-to-set used to do nothing. In a right-to-left
    // layout that overlay also mirrors horizontal input, so everything below
    // works in leading-relative tape space and needs no direction of its own.

    private func handleDragChanged(translationX: CGFloat) {
        if dragAnchor == nil {
            dragAnchor = tapeValue
            scrollSnapTask?.cancel()
        }
        let anchor = dragAnchor ?? tapeValue
        let raw = anchor - translationX / tickSpacing
        let stretched = elasticClamp(raw)
        let previous = tapeValue
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tapeValue = stretched
        }
        seedGlow(delta: stretched - previous)
        publishRoundedValue(from: stretched)
    }

    private func handleDragEnded() {
        guard dragAnchor != nil else { return }
        dragAnchor = nil
        settle(to: tapeValue)
    }

    /// Tap-to-set: a click that doesn't drag jumps the selection to the minute
    /// under the cursor and springs that tick to the pointer.
    private func handleTap(localX: CGFloat, viewWidth: CGFloat) {
        guard dragAnchor == nil else { return }
        scrollSnapTask?.cancel()
        let centerX = viewWidth / 2
        let target = clampToTape(tapeValue + (localX - centerX) / tickSpacing)
        settle(to: target)
    }

    /// Rubber-band past the tape ends: overscroll is asymptotically damped
    /// toward a small cap, then `settle` springs back to the boundary tick.
    private func elasticClamp(_ raw: CGFloat) -> CGFloat {
        let lower = CGFloat(tapeLowerBound)
        let upper = CGFloat(tapeUpperBound)
        let cap: CGFloat = 6
        if raw < lower {
            let pull = lower - raw
            return lower - cap * (1 - 1 / (1 + pull * 0.25 / cap))
        }
        if raw > upper {
            let pull = raw - upper
            return upper + cap * (1 - 1 / (1 + pull * 0.25 / cap))
        }
        return raw
    }

    // MARK: - Scroll wheel scrubbing

    private func handleScroll(delta: CGFloat) {
        guard dragAnchor == nil else { return }
        scrollSnapTask?.cancel()

        // Same surface metaphor as the drag, matching the Theming color tapes
        // (`DetentTapeScrubber`): a horizontal swipe moves the tape under the
        // fixed pointer in the natural-scroll direction. This mirrors that
        // component's `+delta` so Pomodoro / High Alert scrub the same intuitive
        // way instead of inverted.
        let previous = tapeValue
        let raw = tapeValue + delta / (tickSpacing * 1.2)
        let clamped = clampToTape(raw)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tapeValue = clamped
        }
        seedGlow(delta: clamped - previous)
        publishRoundedValue(from: clamped)

        scrollSnapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            settle(to: tapeValue)
        }
    }

    // MARK: - Scrub light

    /// Feed one scrub delta (in minute space) into the tail and the scrub
    /// energy model, then park the timeline once motion stops AND the lit
    /// glow has eased back to rest , it decays on its own exponential curve
    /// and never snaps off.
    private func seedGlow(delta: CGFloat) {
        guard !reduceMotion else { return }
        let now = Date()
        heat.feed(deltaTicks: Double(delta), at: now)
        guard glow.feed(delta: delta, at: now) else { return }
        glowIdleTask?.cancel()
        glowIdleTask = Task { @MainActor in
            // The tail fades within 560 ms; the lit glow needs its full
            // ease-back (`timeUntilRest`, exponential with
            // `coolDownTimeConstant`).
            let restDelay = max(0.56, heat.timeUntilRest(at: Date()) + 0.05)
            try? await Task.sleep(nanoseconds: UInt64(restDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            glow.isActive = false
        }
    }

    // MARK: - Value plumbing

    private func clampToTape(_ value: CGFloat) -> CGFloat {
        min(max(value, CGFloat(tapeLowerBound)), CGFloat(tapeUpperBound))
    }

    private func publishRoundedValue(from value: CGFloat) {
        let roundedTape = min(max(Int(value.rounded()), tapeLowerBound), tapeUpperBound)
        let newMinutes = minutes(forTapePosition: roundedTape)
        guard newMinutes != selectedMinutes else { return }
        let hitEndpoint = roundedTape == tapeLowerBound
            || (infinityAtEnd ? newMinutes == 0 : roundedTape == tapeUpperBound)
        if hitEndpoint {
            onDetent(true)
        } else {
            onDetent(false)
        }
        withAnimation(reduceMotion ? nil : TapeSelectionMotion.easeOut) {
            selectedMinutes = newMinutes
        }
    }

    private func settle(to projected: CGFloat) {
        let roundedTape = Int(clampToTape(projected).rounded())
        let newMinutes = minutes(forTapePosition: roundedTape)
        // Re-derive the tape target from the mapped minutes so the tape never
        // rests inside the trailing ∞ gap , it lands on the max tick or on ∞.
        let target = CGFloat(tapePosition(forMinutes: newMinutes))
        if newMinutes != selectedMinutes {
            onDetent(false)
        }
        // Settle rides the hover preset's clock (same response/damping as
        // its pre-macOS-14 fallback) so the scrubber lands like every other
        // micro interaction instead of on a hand-copied literal.
        withAnimation(reduceMotion ? nil : DroppyAnimation.hover) {
            tapeValue = target
        }
        // The lit-tick recolor publishes on the same quick curve as
        // mid-scrub updates so the selection change reads on one clock.
        if newMinutes != selectedMinutes {
            withAnimation(reduceMotion ? nil : TapeSelectionMotion.easeOut) {
                selectedMinutes = newMinutes
            }
        }
    }

    /// Follows external selection changes (presets, settings) when the user
    /// is not actively scrubbing.
    private func syncTapeToExternalChange(_ newValue: Int) {
        guard dragAnchor == nil else { return }
        let target = CGFloat(tapePosition(forMinutes: newValue))
        guard abs(target - tapeValue) > 0.6 else { return }
        withAnimation(reduceMotion ? nil : DroppyAnimation.hover) {
            tapeValue = target
        }
    }

    private var accessibilityValueText: String {
        if selectedMinutes == 0, zeroLabelOverride != nil || infinityAtEnd {
            return String(localized: "Indefinite")
        }
        return Duration.seconds(selectedMinutes * 60).formatted(
            .units(allowed: [.minutes], width: .wide).locale(.autoupdatingCurrent)
        )
    }
}

// MARK: - Ruler Canvas

/// The minute ruler: a tick every minute, a label every five, drawn once per
/// selection. Each element is coloured by its own minute , lit (accent, with a
/// white-hot bloom at and just left of the pointer) when it is at or below the
/// selection, muted (a darker accent) when it is above , so the fill always
/// lands on whole numbers and never splits a label down the middle. Conforming
/// to `Equatable` on the selected minute lets SwiftUI skip re-rasterising while
/// the parent's `.offset` springs the tape; only a new selection redraws it.
private struct TapeRulerCanvas: View, Equatable {
    /// Full tape range in tape positions (includes the trailing ∞ gap when
    /// `infinityPosition` is set).
    let range: ClosedRange<Int>
    /// Largest tape position that represents a numeric minute; positions
    /// beyond it are the unlabeled run-up to the ∞ stop.
    let numericUpperBound: Int
    /// Tape position of the trailing ∞ stop, or nil when the tape has no
    /// trailing infinity.
    let infinityPosition: Int?
    /// Selection threshold in tape positions.
    let threshold: Int
    let accent: Color
    let zeroLabelOverride: String?
    let tickSpacing: CGFloat
    let tickWidth: CGFloat
    let tickHeight: CGFloat
    let labelFontSize: CGFloat
    let labelRowHeight: CGFloat
    let labelGap: CGFloat
    let canvasOverhang: CGFloat
    let tapeWidth: CGFloat
    let tapeHeight: CGFloat
    /// Right-to-left: every x is measured from the tape's trailing edge, so
    /// the minutes ascend toward the left. `Canvas` never mirrors on its own.
    let mirrored: Bool

    /// Warm near-white the selected tick burns to, cooling to pure accent over
    /// the few ticks on the lit side of the pointer.
    private var hotTone: Color { Color(red: 1.0, green: 0.95, blue: 0.82) }

    /// Base opacity for ticks past the pointer: a dim continuation of the
    /// accent rather than a neutral gray, so the unselected tail still reads as
    /// part of the ruler.
    private var mutedOpacity: Double { 0.4 }

    /// Distance dimming: elements fade a tad the farther they sit from the
    /// selection, so the ruler falls away from the pointer instead of holding
    /// one flat brightness edge to edge. Applied on top of the lit/muted split.
    private func distanceDim(_ distance: Int) -> Double {
        1.0 - 0.3 * min(1.0, Double(distance) / 16.0)
    }

    nonisolated static func == (lhs: TapeRulerCanvas, rhs: TapeRulerCanvas) -> Bool {
        lhs.threshold == rhs.threshold
            && lhs.range == rhs.range
            && lhs.infinityPosition == rhs.infinityPosition
            && lhs.accent == rhs.accent
            && lhs.zeroLabelOverride == rhs.zeroLabelOverride
            && lhs.tickSpacing == rhs.tickSpacing
            && lhs.mirrored == rhs.mirrored
    }

    var body: some View {
        Canvas { context, _ in
            let lower = range.lowerBound

            for value in range {
                let leadingX = canvasOverhang + CGFloat(value - lower) * tickSpacing + tickWidth / 2
                let x = mirrored ? tapeWidth - leadingX : leadingX
                let isMajor = (value % 5 == 0) || (value == infinityPosition)
                let currentTickHeight = isMajor ? tickHeight : (tickHeight * 0.60)
                let currentTickWidth = isMajor ? tickWidth : max(1.5, tickWidth * 0.75)
                let yOffset = tickHeight - currentTickHeight
                let tickRect = CGRect(
                    x: x - currentTickWidth / 2,
                    y: labelRowHeight + labelGap + yOffset,
                    width: currentTickWidth,
                    height: currentTickHeight
                )
                let tickPath = Path(roundedRect: tickRect, cornerRadius: currentTickWidth / 2)
                let lit = value <= threshold
                let dim = distanceDim(abs(value - threshold))
                let baseTone = accent.opacity((lit ? 1.0 : mutedOpacity) * dim)
                context.fill(tickPath, with: .color(baseTone))

                let heat = lit ? heatLevel(below: threshold - value) : 0
                if heat > 0 {
                    context.fill(tickPath, with: .color(hotTone.opacity(heat)))
                }

                let isInfinityStop = value == infinityPosition
                if !isInfinityStop {
                    // Positions past the numeric run (the ∞ gap) carry ticks
                    // but never numeric labels.
                    guard value <= numericUpperBound, value % 5 == 0 else { continue }
                }
                let zeroOverride = value == 0 ? zeroLabelOverride : nil
                let label = isInfinityStop ? "∞" : (zeroOverride ?? "\(value)")
                guard !label.isEmpty else { continue }
                // The ∞ glyph only spans x-height, so it needs a few extra
                // points to read at the same optical size as the digits.
                let usesInfinityGlyph = isInfinityStop || zeroOverride != nil
                let fontSize = usesInfinityGlyph ? labelFontSize + 3.5 : labelFontSize
                let font = Font.system(size: fontSize, weight: .semibold, design: .rounded)
                let labelPoint = CGPoint(x: x, y: labelRowHeight / 2)
                context.draw(
                    context.resolve(Text(label).font(font).foregroundColor(baseTone)),
                    at: labelPoint,
                    anchor: .center
                )
                if heat > 0 {
                    context.draw(
                        context.resolve(Text(label).font(font).foregroundColor(hotTone.opacity(heat))),
                        at: labelPoint,
                        anchor: .center
                    )
                }
            }
        }
        .frame(width: tapeWidth, height: tapeHeight)
    }

    /// White-hot bloom that peaks on the selected tick and cools to plain accent
    /// a few ticks to its left. `below` is how many minutes under the selection
    /// this tick sits (0 is the selected tick); negative means it is above the
    /// selection and gets no bloom.
    private func heatLevel(below: Int) -> Double {
        guard below >= 0 else { return 0 }
        let span = 4.0
        return max(0, 1 - Double(below) / span)
    }
}

// MARK: - Lit-region scrub glow

/// The tape's lit region coming alive while scrubbing: a subtle swell of the
/// ruler's OWN warm near-white bloom (the tone the selected tick already burns
/// to), drawn in screen space over the tick band and biased toward the lit
/// side of the pointer. Strength comes straight from `TapeScrubHeatModel`'s
/// velocity intensity, the model's spatial falloff shapes the gradient so the
/// light hugs the active reading, and every render constant is a shared model
/// constant so macOS and iOS brighten the same light by the same amount. No
/// new hue, no borders, no particles, no motion of its own; it only breathes
/// brighter and eases back. Fully transparent at `intensity == 0`, so an idle
/// tape draws nothing.
private struct TapeScrubLitGlow: View {
    /// Current scrub intensity 0...1 (already decayed by the model for this frame).
    let intensity: Double
    let tickSpacing: CGFloat
    let tickHeight: CGFloat

    /// The exact warm near-white the ruler's selected tick burns to , the
    /// swell must read as that existing light breathing, never a new colour.
    private var tone: Color { Color(red: 1.0, green: 0.95, blue: 0.82) }

    var body: some View {
        let clamped = max(0, min(1, intensity))
        // Half-width spans two falloff constants; the stops below sample the
        // model's exponential falloff at 0τ / 1τ / 2τ so the drawn light decays
        // on the same spatial curve the model defines.
        let halfWidth = CGFloat(TapeScrubHeatModel.falloffTicks) * tickSpacing * 2
        let oneTau = TapeScrubHeatModel.spatialFalloff(
            atTickDistance: TapeScrubHeatModel.falloffTicks
        )
        Ellipse()
            .fill(
                EllipticalGradient(
                    stops: [
                        .init(color: tone, location: 0.0),
                        .init(color: tone.opacity(oneTau), location: 0.5),
                        .init(color: tone.opacity(0), location: 1.0)
                    ]
                )
            )
            .frame(
                width: halfWidth * 2,
                height: tickHeight * CGFloat(TapeScrubHeatModel.litGlowHeightFactor)
            )
            .opacity(clamped * TapeScrubHeatModel.litGlowMaxOpacity)
            .blendMode(.plusLighter)
            .offset(x: -tickSpacing * CGFloat(TapeScrubHeatModel.litGlowCenterBiasTicks))
            .allowsHitTesting(false)
    }
}

// MARK: - Pointer

/// Small upward-pointing triangle fixed under the tape center.
/// Shared by `TimerTapeScrubber` and `DetentTapeScrubber`.
struct ScrubberPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pointer Capture (macOS)
//
// One AppKit layer for ALL pointer input so the scrubber behaves the same with
// a trackpad or an external mouse: scroll-wheel scrubbing, click-and-drag
// scrubbing, and tap-to-set. Mouse events are handled here rather than by a
// SwiftUI DragGesture underneath because this view is hit-test opaque , it
// swallows mouse-down, so a gesture below it would never fire.

struct TapeScrubberInputCapture: NSViewRepresentable {
    /// Right-to-left: flip horizontal scroll and drag deltas and measure a
    /// tap from the trailing edge, so every callback receives leading-relative
    /// motion and the scrubber's tape maths stay direction-free.
    var mirrorsHorizontalInput: Bool = false
    var onScroll: (CGFloat) -> Void
    var onTap: (CGFloat, CGFloat) -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> _View {
        let view = _View()
        view.apply(
            mirrorsHorizontalInput: mirrorsHorizontalInput,
            onScroll: onScroll, onTap: onTap, onDragChanged: onDragChanged, onDragEnded: onDragEnded
        )
        return view
    }

    // Size comes straight from the SwiftUI proposal: never let AppKit's
    // constraint engine measure this view mid animated pass
    // (systemLayoutSizeFittingSize aborts in _nsis_frameInEngine , the media region-view SIGABRT class).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: _View, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 0,
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        )
    }

    func updateNSView(_ nsView: _View, context: Context) {
        nsView.apply(
            mirrorsHorizontalInput: mirrorsHorizontalInput,
            onScroll: onScroll, onTap: onTap, onDragChanged: onDragChanged, onDragEnded: onDragEnded
        )
    }

    final class _View: NSView {
        private var mirrorsHorizontalInput = false
        private var onScroll: ((CGFloat) -> Void)?
        private var onTap: ((CGFloat, CGFloat) -> Void)?
        private var onDragChanged: ((CGFloat) -> Void)?
        private var onDragEnded: (() -> Void)?

        private var mouseDownX: CGFloat?
        private var didDrag = false

        /// +1 in a left-to-right layout, -1 when horizontal input is mirrored.
        private var horizontalSign: CGFloat { mirrorsHorizontalInput ? -1 : 1 }

        func apply(
            mirrorsHorizontalInput: Bool,
            onScroll: @escaping (CGFloat) -> Void,
            onTap: @escaping (CGFloat, CGFloat) -> Void,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping () -> Void
        ) {
            self.mirrorsHorizontalInput = mirrorsHorizontalInput
            self.onScroll = onScroll
            self.onTap = onTap
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        // The scrubber lives in a non-activating shelf panel, so accept the
        // first click without requiring the window to activate first.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func scrollWheel(with event: NSEvent) {
            // Normalize for natural scroll so the physical swipe direction
            // maps to tape movement consistently.
            let invert: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            // Only the horizontal axis has a direction to mirror; a vertical
            // swipe means the same value change in either layout.
            let dx = event.scrollingDeltaX * invert * horizontalSign
            let dy = event.scrollingDeltaY * invert
            let delta = abs(dx) >= abs(dy) ? dx : -dy
            if abs(delta) > 0.3 {
                onScroll?(delta)
            }
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownX = convert(event.locationInWindow, from: nil).x
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startX = mouseDownX else { return }
            let translation = (convert(event.locationInWindow, from: nil).x - startX) * horizontalSign
            // Ignore sub-pixel jitter so a click that barely moves still counts
            // as a tap rather than a drag.
            if !didDrag, abs(translation) < 3 { return }
            didDrag = true
            onDragChanged?(translation)
        }

        override func mouseUp(with event: NSEvent) {
            if didDrag {
                onDragEnded?()
            } else {
                let x = convert(event.locationInWindow, from: nil).x
                onTap?(mirrorsHorizontalInput ? bounds.width - x : x, bounds.width)
            }
            mouseDownX = nil
            didDrag = false
        }
    }
}
