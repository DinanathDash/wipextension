//
//  WipextensionWidget.swift
//  Wipextension
//

import AppKit
import DroppyKit
import SwiftUI

/// Shelf widget for Wipextension conforming strictly to DroppyKit guidelines.
struct WipextensionWidget: View {
    @ObservedObject var droplet: WipextensionDroplet
    let context: ShelfWidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modeNoticeTimer: Task<Void, Never>?
    @State private var showingModeNotice: Bool = false

    private var isCompact: Bool { context.isCompact }
    private var accent: Color { droplet.mode.accentColor }
    private var pillBg: Color { droplet.mode.pillBackground }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
                    .padding(context.contentInsets)
            } else {
                soloLayout
                    .padding(
                        EdgeInsets(
                            top: 0,
                            leading: context.contentInsets.leading,
                            bottom: context.contentInsets.bottom,
                            trailing: context.contentInsets.trailing
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state, value: droplet.mode)
        .animation(reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state, value: droplet.isCleaning)
    }

    // MARK: - Solo Layout

    private var soloLayout: some View {
        VStack(spacing: 6) {
            // Top Section: High Alert Minute Tape Scrubber (1 - 30 minutes)
            TimerTapeScrubber(
                selectedMinutes: Binding(
                    get: {
                        if droplet.isCleaning {
                            return max(1, Int(ceil(Double(droplet.remainingSeconds) / 60.0)))
                        }
                        return droplet.selectedDuration
                    },
                    set: { droplet.updateSelectedDuration($0) }
                ),
                range: 1...30,
                accent: accent,
                compact: context.isCompact,
                infinityAtEnd: false,
                onDetent: { _ in
                    droplet.playDetentFeedback()
                }
            )
            .allowsHitTesting(!droplet.isCleaning && !context.isPreview && !context.isShelfTransitioning)

            // Bottom Section: Controls & Readout
            HStack(spacing: 10) {
                // 1. Start / Stop Pill Button
                Button {
                    droplet.toggleCleaning()
                } label: {
                    Text(droplet.isCleaning ? "Stop Cleaning" : "Start Cleaning")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(pillBg)
                        )
                }
                .buttonStyle(.plain)

                // 2. Mode Toggle Circular Button (Neutral glass wash, no accent color, no outline)
                Button {
                    cycleMode()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 34, height: 34)

                        Image(systemName: droplet.mode.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    }
                }
                .buttonStyle(.plain)
                .help("Switch cleaning mode: \(droplet.mode.title)")

                Spacer(minLength: 8)

                // 3. Right Readout: single Text view animating via numericText tumbler on mode change
                Text(showingModeNotice ? droplet.mode.blockNoticeText : formattedTime)
                    .font(.system(size: showingModeNotice ? 12 : 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: droplet.isCleaning))
                    .foregroundStyle(accent)
                    .lineLimit(showingModeNotice ? 2 : 1)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.5)
                    .animation(
                        reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state,
                        value: formattedTime
                    )
                    .animation(
                        reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state,
                        value: showingModeNotice
                    )
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Compact Layout

    private var compactLayout: some View {
        VStack(spacing: DroppySpacing.xsm) {
            HStack(spacing: 4) {
                Image(systemName: droplet.mode.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Text(droplet.mode.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    droplet.toggleCleaning()
                } label: {
                    ZStack {
                        Circle()
                            .fill(pillBg)
                            .frame(width: 36, height: 36)

                        Image(systemName: droplet.isCleaning ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .buttonStyle(.plain)

                // Neutral mode button in compact layout
                Button {
                    cycleMode()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 28, height: 28)

                        Image(systemName: droplet.mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text(showingModeNotice ? droplet.mode.title : formattedTime)
                    .font(.system(size: showingModeNotice ? 11 : 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: droplet.isCleaning))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .animation(
                        reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state,
                        value: formattedTime
                    )
                    .animation(
                        reduceMotion || context.isShelfTransitioning ? nil : DroppyAnimation.state,
                        value: showingModeNotice
                    )
            }
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let totalSeconds = droplet.isCleaning ? droplet.remainingSeconds : (droplet.selectedDuration * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func cycleMode() {
        withAnimation(reduceMotion ? nil : DroppyAnimation.state) {
            droplet.mode = droplet.mode.next
            triggerModeNotice()
        }
    }

    private func triggerModeNotice() {
        modeNoticeTimer?.cancel()
        withAnimation(reduceMotion ? nil : DroppyAnimation.state) {
            showingModeNotice = true
        }
        modeNoticeTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : DroppyAnimation.state) {
                showingModeNotice = false
            }
        }
    }
}
