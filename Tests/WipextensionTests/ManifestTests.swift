//
//  ManifestTests.swift
//  WipextensionTests
//

import Foundation
import Testing
import DroppyKit
@testable import Wipextension

@Suite("Manifest and Descriptor Tests")
struct ManifestTests {
    private func manifestJSON() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("droplet.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    private func capabilities() throws -> [String] {
        try manifestJSON()["capabilities"] as? [String] ?? []
    }

    private func surfaces() throws -> [String] {
        try manifestJSON()["surfaces"] as? [String] ?? []
    }

    @Test("droplet.json contains expected identifier and metadata")
    func manifestIdentity() throws {
        let json = try manifestJSON()
        #expect(json["id"] as? String == "wipextension")
        #expect(json["name"] as? String == "Wipextension")
        #expect(json["version"] as? String == "1.1.0")
        #expect(json["category"] as? String == "Productivity")
        #expect(json["icon"] as? String == "Wipextension.icon")
    }

    @Test("droplet.json specifies minAPI 1.22.0 or compatible")
    func manifestKitRequirements() throws {
        let kit = try manifestJSON()["kit"] as? [String: Any]
        #expect(kit?["minAPI"] as? String == "1.22.0")
        #expect(kit?["abi"] as? Int == 1)
    }

    @Test("droplet.json declares required capabilities for shortcuts and accessibility")
    func manifestCapabilities() throws {
        let caps = try capabilities()
        #expect(caps.contains("global-shortcuts"))
        #expect(caps.contains("accessibility"))
        #expect(caps.count == 2)
    }

    @Test("droplet.json declares required surfaces")
    func manifestSurfaces() throws {
        let surfs = try surfaces()
        #expect(surfs.contains("shelf-widget"))
        #expect(surfs.contains("live-activity"))
        #expect(surfs.contains("settings-pane"))
    }

    @Test("droplet.json includes relevant keywords for discoverability")
    func manifestKeywords() throws {
        let json = try manifestJSON()
        let keywords = json["keywords"] as? [String] ?? []
        #expect(keywords.contains("keyboard"))
        #expect(keywords.contains("screen"))
        #expect(keywords.contains("display"))
        #expect(keywords.contains("trackpad"))
        #expect(keywords.contains("clean"))
        #expect(keywords.contains("lock"))
    }

    @MainActor
    @Test("WipextensionDroplet advertises shelf widget with matching descriptor traits")
    func widgetDescriptorTraits() {
        let droplet = WipextensionDroplet()
        let descriptors = droplet.widgetDescriptors
        #expect(descriptors.count == 1)

        let first = descriptors.first
        #expect(first?.id == "wipextension")
        #expect(first?.title == "Wipextension")
        #expect(first?.systemImage == "sparkles")
        #expect(first?.layoutTraits.preferredSoloWidth == 350)
        #expect(first?.layoutTraits.preferredPairedWidth == 175)
        #expect(first?.layoutTraits.contentHeight == .fixed(DroppyShellMetrics.shelfWidgetStandardContentHeight + 8))
    }
}
