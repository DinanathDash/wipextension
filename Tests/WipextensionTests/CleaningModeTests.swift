//
//  CleaningModeTests.swift
//  WipextensionTests
//

import Foundation
import SwiftUI
import Testing
@testable import Wipextension

@Suite("Cleaning Mode Tests")
struct CleaningModeTests {
    @Test("All cleaning modes are unique and exhaustively represented")
    func allModes() {
        #expect(CleaningMode.allCases.count == 3)
        let set = Set(CleaningMode.allCases)
        #expect(set.count == 3)
        #expect(set.contains(.keyboard))
        #expect(set.contains(.display))
        #expect(set.contains(.both))
    }

    @Test("Identifiable id matches raw value", arguments: CleaningMode.allCases)
    func idMatchesRawValue(mode: CleaningMode) {
        #expect(mode.id == mode.rawValue)
    }

    @Test("Mode titles match expectations", arguments: [
        (CleaningMode.keyboard, "Keyboard"),
        (CleaningMode.display, "Display"),
        (CleaningMode.both, "Keyboard & Display")
    ])
    func modeTitles(mode: CleaningMode, expectedTitle: String) {
        #expect(mode.title == expectedTitle)
    }

    @Test("Mode icons match expectations", arguments: [
        (CleaningMode.keyboard, "keyboard"),
        (CleaningMode.display, "display"),
        (CleaningMode.both, "macbook")
    ])
    func modeIcons(mode: CleaningMode, expectedIcon: String) {
        #expect(mode.icon == expectedIcon)
    }

    @Test("Mode cycle follows strict keyboard -> display -> both -> keyboard order")
    func modeCycling() {
        #expect(CleaningMode.keyboard.next == .display)
        #expect(CleaningMode.display.next == .both)
        #expect(CleaningMode.both.next == .keyboard)

        // Multiple complete cycles
        var current: CleaningMode = .keyboard
        for _ in 0..<9 {
            current = current.next
        }
        #expect(current == .keyboard)
    }

    @Test("Block notice text is informative for each mode")
    func blockNotices() {
        #expect(CleaningMode.keyboard.blockNoticeText == "Keyboard will be locked")
        #expect(CleaningMode.display.blockNoticeText == "Display will be locked")
        #expect(CleaningMode.both.blockNoticeText.contains("both will be locked"))
    }

    @Test("Pill background has opacity applied to accent color")
    func pillBackgroundCheck() {
        for mode in CleaningMode.allCases {
            // pillBackground is derived as accentColor.opacity(0.18)
            #expect(mode.pillBackground == mode.accentColor.opacity(0.18))
        }
    }

    @Test("Codable serialization and deserialization roundtrip", arguments: CleaningMode.allCases)
    func codableRoundtrip(mode: CleaningMode) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        let decoded = try JSONDecoder().decode(CleaningMode.self, from: data)
        #expect(decoded == mode)
    }

    @Test("Decoding invalid mode strings throws an error")
    func invalidDecoding() {
        let invalidJSON = Data("\"invalid_mode\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CleaningMode.self, from: invalidJSON)
        }
    }
}
