//
//  DisplayBrightnessController.swift
//  Wipextension
//

import AppKit
import CoreGraphics
import Foundation

/// Manages hardware display brightness for the built-in display.
///
/// Uses macOS's private `DisplayServices` framework to query and adjust the
/// physical backlight brightness on Apple displays. Only targets built-in
/// displays (MacBook screens), leaving external monitors fully operational.
@MainActor
final class DisplayBrightnessController {
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightness: GetBrightnessFunc?
    private var setBrightness: SetBrightnessFunc?
    nonisolated(unsafe) private var frameworkHandle: UnsafeMutableRawPointer?

    /// Cached original brightness levels keyed by display ID.
    private var cachedBrightness: [CGDirectDisplayID: Float] = [:]

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY) {
            self.frameworkHandle = handle
            if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
                self.getBrightness = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            }
            if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
                self.setBrightness = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            }
        }
    }

    deinit {
        if let handle = frameworkHandle {
            dlclose(handle)
        }
    }

    /// Dims only the built-in display to 0.0 brightness, caching its prior level.
    func dimBuiltInToZero() {
        guard let getBrightness = getBrightness, let setBrightness = setBrightness else { return }

        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            // Only dim built-in screens
            guard CGDisplayIsBuiltin(displayID) != 0 else { continue }

            var current: Float = 0.5
            if getBrightness(displayID, &current) == 0 {
                // If not already cached, store the user's brightness
                if cachedBrightness[displayID] == nil {
                    cachedBrightness[displayID] = current
                }
                _ = setBrightness(displayID, 0.0)
            }
        }
    }

    /// Restores the built-in display's brightness to its cached level.
    func restoreBrightness() {
        guard let setBrightness = setBrightness else {
            cachedBrightness.removeAll()
            return
        }

        for (displayID, original) in cachedBrightness {
            _ = setBrightness(displayID, max(0.05, original))
        }
        cachedBrightness.removeAll()
    }
}
