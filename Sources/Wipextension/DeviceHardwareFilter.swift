//
//  DeviceHardwareFilter.swift
//  Wipextension
//

import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.hid

/// Differentiates between the Mac's built-in trackpad and external pointing devices (USB/Bluetooth mice).
final class DeviceHardwareFilter: @unchecked Sendable {
    private var isTrackpadCache: [UInt64: Bool] = [:]
    private let lock = NSLock()

    /// Determines if a pointing event originated from the built-in trackpad.
    ///
    /// Returns `true` if the event is from the internal trackpad.
    /// Returns `false` if the event is from an external mouse or unknown.
    func isBuiltInTrackpad(event: CGEvent) -> Bool {
        guard let field = CGEventField(rawValue: 87) else {
            return fallbackCheck(event: event)
        }

        let senderID = UInt64(event.getIntegerValueField(field))
        guard senderID != 0 else {
            return fallbackCheck(event: event)
        }

        lock.lock()
        if let cached = isTrackpadCache[senderID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var isTrackpad = false

        if let matching = IORegistryEntryIDMatching(senderID) {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            if service != 0 {
                defer { IOObjectRelease(service) }

                // Check Product string
                if let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                    let lower = product.lowercased()
                    if lower.contains("trackpad") || lower.contains("internal") {
                        isTrackpad = true
                    }
                }

                // Check Built-In flag
                if !isTrackpad {
                    if let builtIn = IORegistryEntryCreateCFProperty(service, "Built-In" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool, builtIn {
                        isTrackpad = true
                    }
                }
            }
        }

        lock.lock()
        isTrackpadCache[senderID] = isTrackpad
        lock.unlock()

        return isTrackpad
    }

    private func fallbackCheck(event: CGEvent) -> Bool {
        // If senderID could not be determined, check NSEvent properties
        if let nsEvent = NSEvent(cgEvent: event) {
            if nsEvent.type == .scrollWheel && nsEvent.hasPreciseScrollingDeltas {
                return true
            }
            if nsEvent.subtype == .touch {
                return true
            }
        }
        return false
    }
}
