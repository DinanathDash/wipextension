//
//  WipextensionSettingsView.swift
//  Wipextension
//

import AppKit
import DroppyKit
import SwiftUI

/// Settings pane for Wipextension conforming to DroppyKit guidelines.
struct WipextensionSettingsView: View {
    @ObservedObject var droplet: WipextensionDroplet
    @State private var currentShortcut: DropletKeyboardShortcut?

    private var modeBinding: Binding<CleaningMode> {
        Binding(
            get: { droplet.mode },
            set: { droplet.mode = $0 }
        )
    }

    private var includeTrackpadBinding: Binding<Bool> {
        Binding(
            get: { droplet.includeTrackpad },
            set: { droplet.includeTrackpad = $0 }
        )
    }

    private var durationOptions: [Int] {
        let presets = [1, 2, 5, 10, 15, 20, 30]
        let current = droplet.selectedDuration
        if !presets.contains(current) {
            return (presets + [current]).sorted()
        }
        return presets
    }

    private var defaultDurationBinding: Binding<Int> {
        Binding(
            get: { droplet.selectedDuration },
            set: { droplet.updateSelectedDuration($0) }
        )
    }

    var body: some View {
        DropletSettingsPane {
            // Main Settings Section: Target, Input, Timer, Shortcuts
            DropletSettingsSection {
                settingsSectionHeader("Settings")
            } content: {
                DropletSettingsCard {
                settingsUnifiedPickerRow(
                    title: "Cleaning target",
                    subtitle: "Choose what to clean when cleaning starts.",
                    options: CleaningMode.allCases,
                    groupPosition: .top,
                    isSelected: { $0 == modeBinding.wrappedValue },
                    action: { modeBinding.wrappedValue = $0 }
                ) { modeOption, _, _ in
                    HStack(spacing: 6) {
                        Image(systemName: modeOption.icon)
                        Text(modeOption.title)
                    }
                }

                DropletToggleRow(
                    title: "Clean trackpad",
                    subtitle: "Lock the built-in trackpad along with the keyboard. External mice remain active.",
                    isOn: includeTrackpadBinding
                )

                settingsUnifiedPickerRow(
                    title: "Default timer duration",
                    subtitle: "Default duration (1–30 minutes) used for sessions and global shortcuts.",
                    options: durationOptions,
                    groupPosition: .middle,
                    isSelected: { $0 == defaultDurationBinding.wrappedValue },
                    action: { defaultDurationBinding.wrappedValue = $0 }
                ) { minutes, _, _ in
                    Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                }

                DropletControlRow(title: "Keyboard Shortcuts", infoTip: "Every shortcut lives on the Shortcuts page.") {
                    Button {
                        droplet.openShortcuts()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentShortcut?.displayString ?? "Set up")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .onAppear {
                        currentShortcut = droplet.currentShortcut()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                        currentShortcut = droplet.currentShortcut()
                    }
                }
            }
        }

            // Credits Section (Separate, styled after DropClip's credits card)
            DropletSettingsSection {
                settingsSectionHeader("Credits")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: String(localized: "Based on High Alert by Jordy Spruit"),
                        infoTip: String(localized: "Wipextension adapts the minute tape design language from Droppy's High Alert with permission from Jordy Spruit.")
                    ) {
                        Button(String(localized: "Acknowledgements")) {
                            droplet.openAcknowledgements()
                        }
                    }
                }
            }
        }
    }
}
