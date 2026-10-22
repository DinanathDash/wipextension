//
//  WipextensionLiveActivity.swift
//  Wipextension
//

import DroppyKit
import SwiftUI

/// Compact leading accessory: Mode icon color-coded as per the active mode during lock and unlock.
public struct WipextensionCompactLeading: View {
    @ObservedObject var droplet: WipextensionDroplet

    public init(droplet: WipextensionDroplet) {
        self.droplet = droplet
    }

    public var body: some View {
        Image(systemName: droplet.isShowingUnlockConfirmation ? "checkmark.circle.fill" : droplet.mode.icon)
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
            .foregroundStyle(droplet.mode.accentColor)
            .id(droplet.isShowingUnlockConfirmation ? "unlocked" : droplet.mode.rawValue)
            .transition(DroppyTransition.compactContent)
    }
}

/// Compact trailing accessory: Lock icon followed by reverse countdown timer, color-coded as per the active mode.
public struct WipextensionCompactTrailing: View {
    @ObservedObject var droplet: WipextensionDroplet

    public init(droplet: WipextensionDroplet) {
        self.droplet = droplet
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: droplet.isShowingUnlockConfirmation ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(droplet.mode.accentColor)
                .id(droplet.isShowingUnlockConfirmation)
                .transition(DroppyTransition.compactContent)

            if droplet.isCleaning {
                Text(droplet.formattedRemainingTime)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(droplet.mode.accentColor)
                    .lineLimit(1)
                    .frame(width: 39, alignment: .trailing)
                    .contentTransition(.numericText(value: Double(droplet.remainingSeconds)))
                    .animation(DroppyAnimation.state, value: droplet.remainingSeconds)
                    .transition(DroppyTransition.compactContent)
            }
        }
    }
}

/// Companion pill compact mark: Color-coded icon when riding the secondary seat beside another active Live Activity.
public struct WipextensionCompanionCompact: View {
    @ObservedObject var droplet: WipextensionDroplet

    public init(droplet: WipextensionDroplet) {
        self.droplet = droplet
    }

    public var body: some View {
        Image(systemName: droplet.isShowingUnlockConfirmation ? "checkmark.circle.fill" : droplet.mode.icon)
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
            .foregroundStyle(droplet.mode.accentColor)
            .id(droplet.isShowingUnlockConfirmation ? "unlocked" : droplet.mode.rawValue)
            .transition(DroppyTransition.compactContent)
    }
}

/// Companion pill detail: Accordion expanded detail on hover while in the secondary seat.
public struct WipextensionCompanionDetail: View {
    @ObservedObject var droplet: WipextensionDroplet

    public init(droplet: WipextensionDroplet) {
        self.droplet = droplet
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
