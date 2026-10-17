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

    public static let acknowledgementsGitLabURL = "https://gitlab.com/droppyformac1/droplets/-/blob/main/droplets/wipextension/ACKNOWLEDGEMENTS.md"

    public func openAcknowledgements() {
        if let url = Bundle(for: WipextensionPrincipal.self).url(forResource: "ACKNOWLEDGEMENTS", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let legalURL = Bundle(for: WipextensionPrincipal.self).url(forResource: "Acknowledgements", withExtension: "txt", subdirectory: "Assets/Legal") {
            NSWorkspace.shared.open(legalURL)
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
                self.stopCleaning()
            }
        }

        publishActivity()
    }

    public func stopCleaning() {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            if !self.isCleaning && self.isShowingUnlockConfirmation {
                self.isShowingUnlockConfirmation = false
                self.publishActivity()
            }
        }
    }

    private func publishActivity() {
        if isCleaning || isShowingUnlockConfirmation {
            activitySubject.send(
                LiveActivityState(
                    priority: 200,
                    accessibilityTitle: isCleaning ? "Cleaning active" : "Cleaning unlocked",
                    isInteractive: false,
                    joinsPersistentActivitySet: false,
                    compactPresentation: nil,
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

    public func makeCompactLeading() -> AnyView {
        AnyView(
            Image(systemName: mode.icon)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .id(isShowingUnlockConfirmation)
                .transition(DroppyTransition.compactContent)
        )
    }

    public func makeCompactTrailing() -> AnyView {
        AnyView(
            Image(systemName: isShowingUnlockConfirmation ? "lock.open.fill" : "lock.fill")
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .id(isShowingUnlockConfirmation)
                .transition(DroppyTransition.compactContent)
        )
    }

    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        AnyView(
            Image(systemName: isShowingUnlockConfirmation ? "checkmark.circle.fill" : mode.icon)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        )
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? { nil }
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

        let source = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
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
