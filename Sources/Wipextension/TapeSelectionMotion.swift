//
//  TapeSelectionMotion.swift
//  Wipextension
//
//  Adapted from Droppy's High Alert / Pomodoro design reuse kit with
//  permission from Jordy Spruit (author of Droppy).
//

import AppKit
import QuartzCore
import SwiftUI

/// The original ruler's 80 ms selection-tint ease, with Droppy's display tuning.
/// Other springs and button presses use the public DroppyKit motion presets.
@MainActor
enum TapeSelectionMotion {
    private static var cachedRate = 60
    private static var cachedAt: CFTimeInterval = -.infinity

    static var easeOut: Animation {
        let now = CACurrentMediaTime()
        if now - cachedAt >= 2 {
            let builtIn = NSScreen.screens.first { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return false
                }
                return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
            }
            let mouse = NSEvent.mouseLocation
            let screen = builtIn
                ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
            cachedRate = max(screen?.maximumFramesPerSecond ?? 60, 60)
            cachedAt = now
        }
        let scale = cachedRate >= 100 ? 1.0 : (cachedRate >= 75 ? 1.1 : 1.18)
        return .easeOut(duration: 0.08 * scale)
    }
}
