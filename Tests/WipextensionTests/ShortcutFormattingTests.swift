//
//  ShortcutFormattingTests.swift
//  WipextensionTests
//

import AppKit
import Carbon.HIToolbox
import DroppyKit
import Foundation
import Testing
@testable import Wipextension

@MainActor
@Suite("Keyboard Shortcut Formatting Tests")
struct ShortcutFormattingTests {
    @Test("Default toggle shortcut renders as ⌃⌘⎋")
    func defaultShortcutDisplay() {
        let droplet = WipextensionDroplet()
        let shortcut = droplet.defaultToggleShortcut
        #expect(shortcut.displayString == "⌃⌘⎋")
    }

    @Test("Modifier symbols are appended in standard macOS order (⌃⌥⇧⌘)")
    func modifierOrdering() {
        let allModifiers = NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue
        let shortcut = DropletKeyboardShortcut(keyCode: 53, modifiers: allModifiers)
        #expect(shortcut.displayString == "⌃⌥⇧⌘⎋")
    }

    @Test("Special keys map to their standard typographic glyphs", arguments: [
        (UInt16(kVK_Escape), "⎋"),
        (UInt16(kVK_Space), "Space"),
        (UInt16(kVK_Return), "↩"),
        (UInt16(kVK_Tab), "⇥"),
        (UInt16(kVK_Delete), "⌫"),
        (UInt16(kVK_UpArrow), "↑"),
        (UInt16(kVK_DownArrow), "↓"),
        (UInt16(kVK_LeftArrow), "←"),
        (UInt16(kVK_RightArrow), "→"),
        (UInt16(kVK_F1), "F1"),
        (UInt16(kVK_F12), "F12")
    ])
    func specialKeyGlyphs(keyCode: UInt16, expectedGlyph: String) {
        let shortcut = DropletKeyboardShortcut(keyCode: keyCode, modifiers: 0)
        #expect(shortcut.displayString == expectedGlyph)
    }

    @Test("Shortcuts without modifiers only show key name")
    func noModifiers() {
        let shortcut = DropletKeyboardShortcut(keyCode: UInt16(kVK_Space), modifiers: 0)
        #expect(shortcut.displayString == "Space")
    }
}
