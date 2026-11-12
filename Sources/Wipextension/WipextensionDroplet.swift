//
//  WipextensionDroplet.swift
//  Wipextension
//

import Combine
import CoreGraphics
import ApplicationServices
import AppKit
import Carbon.HIToolbox
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(WipextensionPrincipal)
public final class WipextensionPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { WipextensionDroplet() }
}

/// Wipextension.
@MainActor
public final class WipextensionDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "wipextension"

    internal var host: DropletHost?
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)

    public func autoStopDuration() -> Int {
        host?.preferences.value(forKey: "autoStopDuration", default: 60) ?? 60
    }

    public func setAutoStopDuration(_ value: Int) {
        host?.preferences.setValue(value, forKey: "autoStopDuration")
        objectWillChange.send()
    }

    public func currentShortcut() -> DropletKeyboardShortcut? {
        host?.shortcuts.currentShortcut(id: "toggle")
    }

    public func openShortcuts() {
        host?.workspace.openShortcuts()
    }

    public func openLicense() {
        if let licenseURL = Bundle(for: WipextensionPrincipal.self).url(forResource: "LICENSE", withExtension: nil) {
            NSWorkspace.shared.open(licenseURL)
        } else if let bundleURL = Bundle(for: WipextensionPrincipal.self).bundleURL as URL? {
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
        }
    }

    public static let acknowledgementsGitLabURL = "https://gitlab.com/droppyformac1/droplets/-/blob/main/droplets/wipextension/NOTICE.md"

    public func openAcknowledgements() {
        if let legalURL = Bundle(for: WipextensionPrincipal.self).url(forResource: "Acknowledgements", withExtension: "txt", subdirectory: "Assets/Legal") {
            NSWorkspace.shared.open(legalURL)
        } else if let url = Bundle(for: WipextensionPrincipal.self).url(forResource: "ACKNOWLEDGEMENTS", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let url = Bundle(for: WipextensionPrincipal.self).url(forResource: "NOTICE", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: Self.acknowledgementsGitLabURL) {
            NSWorkspace.shared.open(url)
        }
    }

    public func openDroppyWebsite() {
        if let url = URL(string: "https://getdroppy.app") {
            NSWorkspace.shared.open(url)
        }
    }

    public func playDetentFeedback() {
        host?.feedback.play(.tick)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    @Published public private(set) var isCleaning: Bool = false
    @Published public private(set) var remainingSeconds: Int = 300
    @Published public var selectedDuration: Int = 5 {
        didSet {
            let clamped = min(max(selectedDuration, 1), 30)
            if selectedDuration != clamped { selectedDuration = clamped }
            if !isCleaning { remainingSeconds = selectedDuration * 60 }
            host?.preferences.setValue(selectedDuration, forKey: "selectedDuration")
        }
    }
    @Published public var mode: CleaningMode = .keyboard {
        didSet {
            host?.preferences.setValue(mode.rawValue, forKey: "cleaningMode")
        }
    }
    @Published public var includeTrackpad: Bool = false {
        didSet {
            host?.preferences.setValue(includeTrackpad, forKey: "includeTrackpad")
        }
    }
    @Published public private(set) var isShowingUnlockConfirmation: Bool = false

    public var formattedRemainingTime: String {
        let total = max(0, remainingSeconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private let brightnessController = DisplayBrightnessController()
    fileprivate let hardwareFilter = DeviceHardwareFilter()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var notificationObservers: [NSObjectProtocol] = []
    private var countdownTask: Task<Void, Never>?
    nonisolated(unsafe) private var cachedToggleShortcut: DropletKeyboardShortcut?

    public var defaultToggleShortcut: DropletKeyboardShortcut {
        DropletKeyboardShortcut(
            keyCode: 53,
            modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue
        )
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        host.log.info("Wipextension activated")

        let storedModeRaw = host.preferences.value(forKey: "cleaningMode", default: CleaningMode.keyboard.rawValue)
        self.mode = CleaningMode(rawValue: storedModeRaw) ?? .keyboard
        self.includeTrackpad = host.preferences.value(forKey: "includeTrackpad", default: false)
        let storedDuration = host.preferences.value(forKey: "selectedDuration", default: 5)
        self.selectedDuration = min(max(storedDuration, 1), 30)
        self.remainingSeconds = self.selectedDuration * 60

        if host.isGranted(.globalShortcuts) {
            host.shortcuts.register(id: "toggle", title: "Toggle Wipextension", defaultShortcut: defaultToggleShortcut) { [weak self] in
                self?.toggleCleaning()
            }
        }
    }

    public func deactivate() {
        if isCleaning {
            stopCleaning()
        }
        isShowingUnlockConfirmation = false
        activitySubject.send(nil)
        host = nil
    }

    public func updateSelectedDuration(_ newDuration: Int) {
        selectedDuration = min(max(newDuration, 1), 30)
    }

    public func toggleCleaning() {
        if isCleaning {
            stopCleaning()
        } else {
            startCleaning()
        }
    }

    public func startCleaning() {
        guard !isCleaning else { return }

        isShowingUnlockConfirmation = false

        let status = host?.permissions.status(for: .accessibility) ?? .notDetermined
        if status != .granted {
            Task {
                if status == .notDetermined {
                    let granted = await host?.permissions.request(.accessibility) == .granted
                    if granted {
                        await MainActor.run { self.startCleaning() }
                    }
                } else {
                    await MainActor.run {
                        host?.permissions.openSystemSettings(for: .accessibility)
                    }
                }
            }
            return
        }

        self.cachedToggleShortcut = host?.shortcuts.currentShortcut(id: "toggle")

        // 1. Dim built-in display if display cleaning is active
        if mode == .display || mode == .both {
            brightnessController.dimBuiltInToZero()
        }

        // 2. Setup event tap if keyboard or trackpad cleaning is active
        if mode == .keyboard || mode == .both {
            var mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                    (1 << CGEventType.keyUp.rawValue) |
                                    (1 << CGEventType.flagsChanged.rawValue) |
                                    (1 << 14) // NX_SYSDEFINED

            if includeTrackpad {
                mask |= (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.mouseMoved.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.rightMouseDragged.rawValue) |
                        (1 << CGEventType.scrollWheel.rawValue) |
                        (1 << CGEventType.otherMouseDown.rawValue) |
                        (1 << CGEventType.otherMouseUp.rawValue) |
                        (1 << CGEventType.otherMouseDragged.rawValue) |
                        (1 << 29) // Gesture events
            }

            // droppykit-lint: allow event-tap: suppresses keyboard and trackpad inputs while cleaning session is active
            eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { proxy, type, event, refcon in
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let ref = refcon {
                            let droplet = Unmanaged<WipextensionDroplet>.fromOpaque(ref).takeUnretainedValue()
                            if let tap = droplet.eventTap {
                                CGEvent.tapEnable(tap: tap, enable: true)
                            }
                        }
                        return Unmanaged.passUnretained(event)
                    }

                    guard let ref = refcon else { return Unmanaged.passUnretained(event) }
                    let droplet = Unmanaged<WipextensionDroplet>.fromOpaque(ref).takeUnretainedValue()

                    // Check for global unlock keyboard shortcut
                    if type == .keyDown || type == .keyUp {
                        if let shortcut = droplet.cachedToggleShortcut, let nsEvent = NSEvent(cgEvent: event) {
                            var mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                            let dropFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
                            if dropFlags.contains(.function) { mask.insert(.function) }
                            if nsEvent.keyCode == shortcut.keyCode && nsEvent.modifierFlags.intersection(mask) == dropFlags.intersection(mask) {
                                return Unmanaged.passUnretained(event)
                            }
                        }
                        // Drop all other keystrokes
                        return nil
                    }

                    // For pointer / trackpad events
                    if droplet.includeTrackpad {
                        if droplet.hardwareFilter.isBuiltInTrackpad(event: event) {
                            return nil // Block built-in trackpad
                        } else {
                            return Unmanaged.passUnretained(event) // Allow external mouse
                        }
                    }

                    return Unmanaged.passUnretained(event)
                },
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )

            if let tap = eventTap {
                runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                if let source = runLoopSource {
                    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }

        isCleaning = true
        remainingSeconds = selectedDuration * 60
        host?.log.info("Started Wipextension in \(self.mode.rawValue) mode for \(self.selectedDuration) minutes.")

        // 3. Register auto-stop listeners for system events
        let center = NSWorkspace.shared.notificationCenter
        notificationObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.host?.log.info("System is sleeping, automatically disabling Wipextension.")
                self?.stopCleaning()
            }
        })
        notificationObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.host?.log.info("Screens slept, automatically disabling Wipextension.")
                self?.stopCleaning()
            }
        })
        notificationObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.host?.log.info("Screen locked, automatically disabling Wipextension.")
                self?.stopCleaning()
            }
        })

        // 4. Start session countdown timer
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while self.remainingSeconds > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                withAnimation(DroppyAnimation.state) {
                    self.remainingSeconds -= 1
                }
            }
            if !Task.isCancelled && self.isCleaning {
                self.stopCleaning(completedNaturally: true)
            }
        }

        publishActivity()
    }

    public func stopCleaning(completedNaturally: Bool = false) {
        guard isCleaning else { return }

        // Restore built-in screen brightness
        brightnessController.restoreBrightness()

        // Tear down event tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        // Clear observers
        for observer in notificationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        notificationObservers.removeAll()

        countdownTask?.cancel()
        countdownTask = nil

        isCleaning = false
        remainingSeconds = selectedDuration * 60
        isShowingUnlockConfirmation = true
        host?.log.info("Wipextension stopped.")
        publishActivity()

        // Present HUD completion card if available
        if let host = host, host.isGranted(.hud) {
            host.hud.present(DropletHUDRequest(
                id: "wipextension-complete",
                duration: 3.5,
                priority: .normal,
                accessibilityLabel: "Cleaning completed. Mac unlocked.",
                card: DropletHUDCard(
                    title: "Mac Unlocked",
                    message: completedNaturally ? "Cleaning session finished safely." : "Wipextension stopped.",
                    systemImage: "lock.open.fill",
                    tint: mode.accentColor
                ),
                isExpanded: true
            ) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(self.mode.accentColor)
            } trailing: {
                Text("Unlocked")
            })
        }


        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            if !self.isCleaning && self.isShowingUnlockConfirmation {
                self.isShowingUnlockConfirmation = false
                self.publishActivity()
            }
        }
    }

    private func publishActivity() {
        if isCleaning {
            activitySubject.send(
                LiveActivityState(
                    priority: .countdown,
                    kind: .timer,
                    accessibilityTitle: "Cleaning in progress",
                    accessibilityValue: { [weak self] in
                        guard let self = self else { return "" }
                        return "\(self.formattedRemainingTime) remaining"
                    },
                    isInteractive: false,
                    joinsPersistentActivitySet: true,
                    compactPresentation: CompactLiveActivityPresentationMetadata(
                        id: "wipextension",
                        accessibilityLabel: "Cleaning in progress",
                        accessibilityValue: formattedRemainingTime,
                        preferredWidth: 84
                    ),
                    expandedWidgetID: "wipextension"
                )
            )
        } else if isShowingUnlockConfirmation {
            activitySubject.send(
                LiveActivityState(
                    priority: .status,
                    kind: .custom,
                    accessibilityTitle: "Cleaning unlocked",
                    accessibilityValue: { "Unlocked" },
                    isInteractive: false,
                    joinsPersistentActivitySet: true,
                    compactPresentation: CompactLiveActivityPresentationMetadata(
                        id: "wipextension-unlocked",
                        accessibilityLabel: "Cleaning unlocked",
                        accessibilityValue: "Unlocked",
                        preferredWidth: 74
                    ),
                    expandedWidgetID: "wipextension"
                )
            )
        } else {
            activitySubject.send(nil)
        }
    }
}

// MARK: - Shelf widget

extension WipextensionDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: "wipextension",
                title: "Wipextension",
                systemImage: "sparkles",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 350,
                    preferredPairedWidth: 175,
                    contentHeight: .fixed(DroppyShellMetrics.shelfWidgetStandardContentHeight + 8)
                )
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(WipextensionWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

// MARK: - Live activity

extension WipextensionDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {
        host?.log.debug("live activity seat is now \(seat)")
    }

    public func makeCompactLeading(context: CompactLiveActivityContext) -> AnyView {
        AnyView(WipextensionCompactLeading(droplet: self, context: context))
    }

    public func makeCompactTrailing(context: CompactLiveActivityContext) -> AnyView {
        AnyView(WipextensionCompactTrailing(droplet: self, context: context))
    }

    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        AnyView(WipextensionCompanionCompact(droplet: self, context: context))
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? {
        guard isCleaning else { return nil }
        return AnyView(WipextensionCompanionDetail(droplet: self, context: context))
    }
}

// MARK: - MCP Tools (AI Apps)

extension WipextensionDroplet: MCPToolProviding {
    public var mcpTools: [DropletMCPTool] {
        [
            DropletMCPTool(
                name: "start_cleaning",
                title: "Start cleaning",
                summary: "Locks keyboard input, trackpad gestures, and optionally dims the display to clean the Mac. Takes duration in minutes (1–30), mode ('keyboard', 'display', or 'both'), and include_trackpad (boolean).",
                inputSchemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "duration_minutes": {
                      "type": "integer",
                      "minimum": 1,
                      "maximum": 30,
                      "description": "Cleaning duration in minutes (1 to 30)."
                    },
                    "mode": {
                      "type": "string",
                      "enum": ["keyboard", "display", "both"],
                      "description": "The cleaning mode to use."
                    },
                    "include_trackpad": {
                      "type": "boolean",
                      "description": "Whether to block built-in trackpad input alongside keyboard."
                    }
                  }
                }
                """
            ),
            DropletMCPTool(
                name: "stop_cleaning",
                title: "Stop cleaning",
                summary: "Stops an active cleaning session and restores screen brightness, keyboard input, and trackpad functionality."
            ),
            DropletMCPTool(
                name: "get_status",
                title: "Get cleaning status",
                summary: "Returns the current state of Wipextension including whether cleaning is active, remaining seconds, selected mode, and trackpad lock state."
            )
        ]
    }

    public func performMCPTool(named name: String, argumentsJSON: String) async throws -> String {
        switch name {
        case "start_cleaning":
            struct StartArgs: Decodable {
                let duration_minutes: Int?
                let mode: String?
                let include_trackpad: Bool?
            }

            let args = (try? JSONDecoder().decode(StartArgs.self, from: Data(argumentsJSON.utf8)))

            if let duration = args?.duration_minutes {
                self.selectedDuration = min(max(duration, 1), 30)
            }
            if let modeRaw = args?.mode, let parsedMode = CleaningMode(rawValue: modeRaw) {
                self.mode = parsedMode
            }
            if let trackpad = args?.include_trackpad {
                self.includeTrackpad = trackpad
            }

            self.startCleaning()

            let result: [String: Any] = [
                "status": "cleaning_started",
                "is_cleaning": self.isCleaning,
                "duration_minutes": self.selectedDuration,
                "remaining_seconds": self.remainingSeconds,
                "mode": self.mode.rawValue,
                "include_trackpad": self.includeTrackpad
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
            return String(decoding: data, as: UTF8.self)

        case "stop_cleaning":
            self.stopCleaning()
            let result: [String: Any] = [
                "status": "cleaning_stopped",
                "is_cleaning": self.isCleaning,
                "mode": self.mode.rawValue
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
            return String(decoding: data, as: UTF8.self)

        case "get_status":
            let result: [String: Any] = [
                "is_cleaning": self.isCleaning,
                "is_showing_unlock_confirmation": self.isShowingUnlockConfirmation,
                "remaining_seconds": self.remainingSeconds,
                "formatted_remaining_time": self.formattedRemainingTime,
                "selected_duration_minutes": self.selectedDuration,
                "mode": self.mode.rawValue,
                "include_trackpad": self.includeTrackpad
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
            return String(decoding: data, as: UTF8.self)

        default:
            throw NSError(
                domain: "WipextensionMCP",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Unknown MCP tool named '\(name)'."]
            )
        }
    }
}

// MARK: - Settings

extension WipextensionDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(WipextensionSettingsView(droplet: self))
    }
}

// MARK: - Keyboard Shortcut String Helpers

extension DropletKeyboardShortcut {
    var displayString: String {
        var result = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }

        if let keyString = keyString(for: keyCode) {
            result += keyString
        }
        return result
    }

    private func keyString(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_Command, kVK_RightCommand: return "⌘"
        case kVK_Shift, kVK_RightShift: return "⇧"
        case kVK_CapsLock: return "⇪"
        case kVK_Option, kVK_RightOption: return "⌥"
        case kVK_Control, kVK_RightControl: return "⌃"
        case kVK_Function: return "Fn"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_VolumeUp: return "Volume Up"
        case kVK_VolumeDown: return "Volume Down"
        case kVK_Mute: return "Mute"
        case kVK_Help: return "Help"
        case kVK_Home: return "↖"
        case kVK_PageUp: return "⇞"
        case kVK_ForwardDelete: return "⌦"
        case kVK_End: return "↘"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: break
        }

        guard let unmanagedSource = TISCopyCurrentASCIICapableKeyboardInputSource() else { return nil }
        let source = unmanagedSource.takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var chars = [UniChar](repeating: 0, count: maxLength)

        UCKeyTranslate(keyboardLayout,
                       keyCode,
                       UInt16(kUCKeyActionDown),
                       0,
                       UInt32(LMGetKbdType()),
                       UInt32(kUCKeyTranslateNoDeadKeysBit),
                       &deadKeyState,
                       maxLength,
                       &length,
                       &chars)

        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
