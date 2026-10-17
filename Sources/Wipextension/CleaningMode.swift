//
//  CleaningMode.swift
//  Wipextension
//

import Foundation
import SwiftUI

/// Available cleaning modes supported by Wipextension.
public enum CleaningMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case keyboard = "keyboard"
    case display = "display"
    case both = "both"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .display: return "Display"
        case .both: return "Keyboard & Display"
        }
    }

    public var icon: String {
        switch self {
        case .keyboard: return "keyboard"
        case .display: return "display"
        case .both: return "macbook"
        }
    }

    /// Distinct signature accent color for each mode.
    public var accentColor: Color {
        switch self {
        case .keyboard:
            // Warm vibrant amber/orange
            return Color(red: 0.98, green: 0.58, blue: 0.15)
        case .display:
            // Electric vibrant cyan
            return Color(red: 0.15, green: 0.78, blue: 0.98)
        case .both:
            // Radiant violet/purple
            return Color(red: 0.75, green: 0.45, blue: 0.98)
        }
    }

    /// Background wash for pills and circles in this mode.
    public var pillBackground: Color {
        accentColor.opacity(0.18)
    }

    /// The text displayed in the widget block readout when this mode is selected.
    public var blockNoticeText: String {
        switch self {
        case .keyboard:
            return "Keyboard will be locked"
        case .display:
            return "Display will be locked"
        case .both:
            return "Keyboard & Display\n both will be locked"
        }
    }

    /// Next mode when cycling through on the shelf widget icon button.
    public var next: CleaningMode {
        switch self {
        case .keyboard: return .display
        case .display: return .both
        case .both: return .keyboard
        }
    }
}
