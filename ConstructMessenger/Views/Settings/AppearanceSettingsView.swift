//
//  AppearanceSettingsView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 31.12.2025.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .dark
    @AppStorage("designStyle") private var storedDesignStyle: DesignStyle = .apple
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designStyle) private var designStyle

    var body: some View {
        Group {
            if designStyle == .apple { appleBody } else { ctBody }
        }
        .onAppear {
            // If user previously selected an unavailable theme, reset to dark
            if !appTheme.isAvailable { appTheme = .dark }
        }
    }

    // MARK: - CT Body

    private var ctBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                CTNavBar(
                    title: NSLocalizedString("appearance", comment: ""),
                    showBack: true,
                    backAction: { dismiss() }
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("theme", comment: "")) {
                        ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                            if index > 0 { ConstructRowDivider(indent: 52) }
                            Button {
                                guard theme.isAvailable else { return }
                                appTheme = theme
                            } label: {
                                HStack(spacing: 14) {
                                    CTRowIcon(theme.asciiIcon,
                                              color: theme.isAvailable ? theme.color : Color.CT.textDim)
                                    Text(theme.displayName)
                                        .font(CTFont.bold(16))
                                        .foregroundStyle(theme.isAvailable ? Color.CT.text : Color.CT.textDim)
                                    Spacer()
                                    if !theme.isAvailable {
                                        Text("soon")
                                            .font(CTFont.regular(10))
                                            .foregroundStyle(Color.CT.textDim)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(
                                                Rectangle()
                                                    .strokeBorder(Color.CT.noise, lineWidth: 1)
                                            )
                                    } else if appTheme == theme {
                                        Text("[✓]")
                                            .font(CTFont.bold(14))
                                            .foregroundStyle(Color.CT.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!theme.isAvailable)
                        }
                    }
                    Text(LocalizedStringKey("theme_footer"))
                        .font(CTFont.regular(11))
                        .foregroundStyle(Color.CT.textDim)
                        .padding(.horizontal, 20)
                }

                // MARK: Design Style section
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("design_style", comment: "")) {
                        ForEach(Array(DesignStyle.allCases.enumerated()), id: \.element) { index, style in
                            if index > 0 { ConstructRowDivider(indent: 52) }
                            Button {
                                storedDesignStyle = style
                            } label: {
                                HStack(spacing: 14) {
                                    CTRowIcon(style.asciiIcon, color: Color.CT.accent)
                                    Text(LocalizedStringKey(style.localizationKey))
                                        .font(CTFont.bold(16))
                                        .foregroundStyle(Color.CT.text)
                                    Spacer()
                                    if storedDesignStyle == style {
                                        Text("[✓]")
                                            .font(CTFont.bold(14))
                                            .foregroundStyle(Color.CT.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(LocalizedStringKey("design_style_footer"))
                        .font(CTFont.regular(11))
                        .foregroundStyle(Color.CT.textDim)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
        .ctBackground()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: - Apple Body

    private var appleBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Theme section
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("theme", comment: "")) {
                        ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                            if index > 0 { ConstructRowDivider(indent: 52) }
                            Button {
                                guard theme.isAvailable else { return }
                                appTheme = theme
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: theme.iconName)
                                        .font(.system(size: 17))
                                        .foregroundStyle(theme.isAvailable ? theme.color : Color(.secondaryLabel))
                                        .frame(width: 22)
                                    Text(theme.displayName)
                                        .font(.body)
                                        .foregroundStyle(theme.isAvailable ? Color.primary : Color(.secondaryLabel))
                                    Spacer()
                                    if !theme.isAvailable {
                                        Text(LocalizedStringKey("soon"))
                                            .font(.caption)
                                            .foregroundStyle(Color(.secondaryLabel))
                                    } else if appTheme == theme {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Color(.secondarySystemGroupedBackground))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!theme.isAvailable)
                        }
                    }
                    Text(LocalizedStringKey("theme_footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                // MARK: Design Style section
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("design_style", comment: "")) {
                        ForEach(Array(DesignStyle.allCases.enumerated()), id: \.element) { index, style in
                            if index > 0 { ConstructRowDivider(indent: 52) }
                            Button {
                                storedDesignStyle = style
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: appleStyleIcon(style))
                                        .font(.system(size: 17))
                                        .foregroundStyle(.tint)
                                        .frame(width: 22)
                                    Text(LocalizedStringKey(style.localizationKey))
                                        .font(.body)
                                    Spacer()
                                    if storedDesignStyle == style {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Color(.secondarySystemGroupedBackground))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(LocalizedStringKey("design_style_footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
//        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(NSLocalizedString("appearance", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }

    private func appleStyleIcon(_ style: DesignStyle) -> String {
        switch style {
        case .terminal: return "terminal"
        case .apple:    return "iphone"
        }
    }
}

// MARK: - App Theme Enum
enum AppTheme: String, CaseIterable {
    case automatic = "automatic"
    case light = "light"
    case dark = "dark"

    /// Only dark theme is currently implemented.
    var isAvailable: Bool { true }

    var displayName: LocalizedStringKey {
        switch self {
        case .automatic: return "automatic"
        case .light: return "light"
        case .dark: return "dark"
        }
    }

    var asciiIcon: String {
        switch self {
        case .automatic: return "[◐]"
        case .light:     return "[□]"
        case .dark:      return "[■]"
        }
    }

    var iconName: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .automatic: return Color.CT.textDim
        case .light: return .orange
        case .dark: return Color.CT.accent
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
        .preferredColorScheme(.dark)
}
