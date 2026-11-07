//
//  TestHelpers.swift
//  WipextensionTests
//

import AppKit
import CoreGraphics
import DroppyKit
import DroppyKitHarness
import Foundation
@testable import Wipextension

/// Creates a test `DropletHost` with custom granted capabilities and an optional custom preferences store.
@MainActor
func makeHarnessHost(
    capabilities: Set<DropletPermission> = [.accessibility, .globalShortcuts],
    initialPreferences: [String: Any] = [:]
) -> DropletHost {
    let recorder = HarnessRecorder()
    let id = WipextensionDroplet.id

    let prefs = HarnessPreferencesService(dropletID: id, recorder: recorder)
    for (key, value) in initialPreferences {
        if let intVal = value as? Int {
            prefs.setValue(intVal, forKey: key)
        } else if let boolVal = value as? Bool {
            prefs.setValue(boolVal, forKey: key)
        } else if let stringVal = value as? String {
            prefs.setValue(stringVal, forKey: key)
        }
    }

    return DropletHost(
        grantedCapabilities: capabilities,
        preferences: prefs,
        environment: HarnessEnvironmentService(appVersion: "16.0.1", dropletID: id),
        log: HarnessLogService(recorder: recorder),
        installState: HarnessInstallStateService(),
        hud: HarnessHUDService(recorder: recorder),
        shelf: HarnessShelfService(recorder: recorder),
        liveActivity: HarnessLiveActivityService(recorder: recorder),
        notchSurface: HarnessNotchSurfaceService(recorder: recorder, dropletID: id),
        shortcuts: HarnessShortcutsService(recorder: recorder),
        workspace: HarnessWorkspaceService(recorder: recorder),
        feedback: HarnessFeedbackService(recorder: recorder),
        permissions: HarnessPermissionsService(recorder: recorder)
    )
}

/// Helper to create synthetic `CGEvent`s for testing `DeviceHardwareFilter`.
func makeSyntheticScrollEvent(deltaY: Int32, precise: Bool, senderID: UInt64 = 0) -> CGEvent {
    let source = CGEventSource(stateID: .hidSystemState)
    let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: precise ? .pixel : .line,
        wheelCount: 1,
        wheel1: deltaY,
        wheel2: 0,
        wheel3: 0
    )!
    if let field = CGEventField(rawValue: 87), senderID != 0 {
        event.setIntegerValueField(field, value: Int64(senderID))
    }
    return event
}

/// Helper to create synthetic mouse click events.
func makeSyntheticMouseEvent(type: CGEventType, location: CGPoint, senderID: UInt64 = 0) -> CGEvent {
    let source = CGEventSource(stateID: .hidSystemState)
    let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: location,
        mouseButton: .left
    )!
    if let field = CGEventField(rawValue: 87), senderID != 0 {
        event.setIntegerValueField(field, value: Int64(senderID))
    }
    return event
}
