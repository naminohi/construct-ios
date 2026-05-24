//
//  DesignStyle.swift
//  Construct Messenger
//
//  Controls whether the app renders the Construct Terminal (CT) design system
//  or the standard Apple HIG (rounded corners, SF Symbols, system colors).
//
//  This is orthogonal to AppTheme (dark/light/auto), which only controls ColorScheme.
//
//  Usage:
//    // Inject at root (ContentView):
//    .environment(\.designStyle, designStyle)
//
//    // Read in any view or component:
//    @Environment(\.designStyle) private var designStyle
//

import SwiftUI

// MARK: - DesignStyle

enum DesignStyle: String, CaseIterable {
    /// Construct Terminal aesthetic: JetBrains Mono, ASCII symbols, no rounded corners.
    case terminal = "terminal"
    /// Standard Apple HIG: system fonts, SF Symbols, rounded shapes, system colors.
    case apple    = "apple"

    var displayName: LocalizedStringKey {
        switch self {
        case .terminal: return "design_terminal"
        case .apple:    return "design_apple"
        }
    }

    var localizationKey: String {
        switch self {
        case .terminal: return "design_terminal"
        case .apple:    return "design_apple"
        }
    }

    var sfIconName: String {
        switch self {
        case .terminal: return "terminal"
        case .apple:    return "apple.logo"
        }
    }

    var asciiIcon: String {
        switch self {
        case .terminal: return "[>_]"
        case .apple:    return "[◉]"
        }
    }
}

// MARK: - Environment Key

private struct DesignStyleKey: EnvironmentKey {
    static let defaultValue: DesignStyle = .apple
}

extension EnvironmentValues {
    var designStyle: DesignStyle {
        get { self[DesignStyleKey.self] }
        set { self[DesignStyleKey.self] = newValue }
    }
}
