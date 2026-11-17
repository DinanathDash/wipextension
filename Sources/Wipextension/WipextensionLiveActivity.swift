//
//  WipextensionLiveActivity.swift
//  Wipextension
//

import DroppyKit
import SwiftUI

/// Compact leading accessory: Mode icon color-coded as per the active mode during lock and unlock.
public struct WipextensionCompactLeading: View {
    @ObservedObject var droplet: WipextensionDroplet
    var context: CompactLiveActivityContext?

    public init(droplet: WipextensionDroplet, context: CompactLiveActivityContext? = nil) {
        self.droplet = droplet
        self.context = context
    }

    public var body: some View {
        let shift = context?.roundEndShift(diameter: DroppyLiveActivityMetrics.iconSize) ?? 0
        Image(systemName: droplet.isShowingUnlockConfirmation ? "checkmark.circle.fill" : droplet.mode.icon)
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
            .foregroundStyle(droplet.mode.accentColor)
            .offset(x: -shift)
            .id(droplet.isShowingUnlockConfirmation ? "unlocked" : droplet.mode.rawValue)
            .transition(DroppyTransition.compactContent)
    }
}

/// Compact trailing accessory: Lock icon followed by reverse countdown timer, color-coded as per the active mode.
public struct WipextensionCompactTrailing: View {
    @ObservedObject var droplet: WipextensionDroplet
    var context: CompactLiveActivityContext?

    public init(droplet: WipextensionDroplet, context: CompactLiveActivityContext? = nil) {
        self.droplet = droplet
        self.context = context
    }

    public var body: some View {
        let shift = context?.roundEndShift(diameter: 14) ?? 0
        HStack(spacing: 4) {
            Image(systemName: droplet.isShowingUnlockConfirmation ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(droplet.mode.accentColor)
                .id(droplet.isShowingUnlockConfirmation)
                .transition(DroppyTransition.compactContent)

            if droplet.isCleaning {
                DroppyCompactClock { _ in
                    Text(droplet.formattedRemainingTime)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(droplet.mode.accentColor)
                        .lineLimit(1)
                }
                .transition(DroppyTransition.compactContent)
            }
        }
        .offset(x: shift)
    }
}

/// Companion pill compact mark: Full size mode icon when riding the secondary seat beside another active Live Activity.
public struct WipextensionCompanionCompact: View {
    @ObservedObject var droplet: WipextensionDroplet
    var context: CompactLiveActivityContext?

    public init(droplet: WipextensionDroplet, context: CompactLiveActivityContext? = nil) {
        self.droplet = droplet
        self.context = context
    }

    public var body: some View {
        let size: CGFloat = {
            if let slot = context?.slotSize, slot.width > 0 && slot.height > 0 {
                return min(slot.width, slot.height)
            }
            return 24
        }()
        Image(systemName: droplet.isShowingUnlockConfirmation ? "checkmark.circle.fill" : droplet.mode.icon)
            .font(.system(size: max(14, size * 0.65), weight: .medium))
            .foregroundStyle(droplet.mode.accentColor)
            .id(droplet.isShowingUnlockConfirmation ? "unlocked" : droplet.mode.rawValue)
            .transition(DroppyTransition.compactContent)
    }
}

/// Companion pill detail: Accordion expanded detail on hover while in the secondary seat.
public struct WipextensionCompanionDetail: View {
    @ObservedObject var droplet: WipextensionDroplet
    let context: LiveActivityContext?

    public init(droplet: WipextensionDroplet, context: LiveActivityContext? = nil) {
        self.droplet = droplet
        self.context = context
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(droplet.formattedRemainingTime)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .foregroundStyle(droplet.mode.accentColor)
    }
}
