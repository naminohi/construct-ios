//
//  ConstructRowComponents.swift
//  Construct Messenger
//
//  Reusable row components using the Construct design system.
//  Used in UserProfileView, SettingsView, AccountSettingsView, and all other settings screens.
//

import SwiftUI

// MARK: - Role

/// Visual role that controls the fill, border, and foreground color of a row.
enum ConstructRowRole {
    /// Primary action — electric-blue tint, strong accent border.
    case primary
    /// Accent action — lighter electric-blue tint.
    case accent
    /// Standard secondary action — neutral dark background.
    case secondary
    /// Destructive action — red tint.
    case destructive
    /// Coming-soon / unavailable — dimmed, shows "soon" badge.
    case disabled
}

// MARK: - Action Row (button-style, full-width rounded card)

/// A full-width tappable row styled according to `ConstructRowRole`.
/// A full-width tappable row styled according to `ConstructRowRole`.
/// .terminal: CT bordered card with ASCII icon.
/// .apple: standard list button with SF Symbol icon.
struct ConstructActionRow: View {

    let icon: String
    let title: LocalizedStringKey
    let role: ConstructRowRole
    var badge: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.designStyle) private var designStyle

    var body: some View {
        Button {
            guard role != .disabled, !isLoading else { return }
            action()
        } label: {
            switch designStyle {
            case .terminal:
                HStack(spacing: 12) {
                    ctIconView(icon, color: terminalForeground)
                        .frame(minWidth: 20, alignment: .center)
                    Text(title)
                        .font(CTFont.bold(16))
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else if role == .disabled {
                        badgeView(badge ?? "soon")
                    } else if let badge {
                        badgeView(badge)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(terminalFill)
                .overlay(Rectangle().strokeBorder(terminalBorder, lineWidth: 1))
                .foregroundStyle(terminalForeground)
            case .apple:
                HStack(spacing: 14) {
                    appleIconView(icon, color: appleForeground)
                        .frame(minWidth: 22, alignment: .center)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(appleForeground)
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else if role == .disabled {
                        Text(badge ?? "soon")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    } else if let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    } else if role != .secondary {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color(.secondarySystemGroupedBackground))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(role == .disabled || isLoading)
    }

    // MARK: Private helpers

    @ViewBuilder
    private func ctIconView(_ icon: String, color: Color) -> some View {
        if icon.hasPrefix("[") || icon.hasPrefix("●") {
            Text(icon)
                .font(CTFont.regular(13))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        } else {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func appleIconView(_ icon: String, color: Color) -> some View {
        let sf = hasSFSymbol(icon) ? sfSymbol(for: icon) : icon
        if icon.hasPrefix("[") || icon.hasPrefix("●") {
            if hasSFSymbol(icon) {
                Image(systemName: sf)
                    .font(.system(size: 17))
                    .foregroundStyle(color)
            } else {
                Text(icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
            }
        } else {
            Image(systemName: sf)
                .font(.system(size: 17))
                .foregroundStyle(color)
        }
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(CTFont.regular(10))
            .foregroundStyle(Color.CT.textDim)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Rectangle().fill(Color.CT.bgMsg))
    }

    private var terminalFill: Color {
        switch role {
        case .primary:     return Color.CT.accent.opacity(0.12)
        case .accent:      return Color.CT.accent.opacity(0.08)
        case .destructive: return Color.red.opacity(0.10)
        default:           return Color.CT.bgMsg
        }
    }

    private var terminalBorder: Color {
        switch role {
        case .primary:     return Color.CT.accent.opacity(0.35)
        case .accent:      return Color.CT.accent.opacity(0.25)
        case .destructive: return Color.red.opacity(0.30)
        default:           return Color.CT.noise
        }
    }

    private var terminalForeground: Color {
        switch role {
        case .primary, .accent: return Color.CT.accent
        case .destructive:      return Color.red
        case .disabled:         return Color.CT.textDim
        case .secondary:        return Color.CT.text
        }
    }

    private var appleForeground: Color {
        switch role {
        case .destructive: return .red
        case .disabled:    return Color(.secondaryLabel)
        default:           return .primary
        }
    }
}

// MARK: - Settings Nav Row (NavigationLink with chevron)

/// A settings-list row that pushes to a destination view.
struct ConstructNavRow<Destination: View>: View {

    let icon: String
    let title: LocalizedStringKey
    var iconColor: Color = Color.CT.accent
    let destination: Destination

    @Environment(\.designStyle) private var designStyle

    var body: some View {
        NavigationLink(destination: destination) {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            iconView(icon, color: iconColor)
                .frame(minWidth: 22, alignment: .center)

            Text(title)
                .font(designStyle == .apple ? .body : CTFont.bold(16))
                .foregroundStyle(designStyle == .apple ? Color.primary : Color.CT.text)

            Spacer()

            switch designStyle {
            case .terminal:
                Text("[→]")
                    .font(CTFont.regular(12))
                    .foregroundStyle(Color.CT.textDim)
            case .apple:
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, designStyle == .apple ? 13 : 14)
        .background(designStyle == .apple ? Color(.secondarySystemGroupedBackground) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconView(_ icon: String, color: Color) -> some View {
        if designStyle == .apple {
            if hasSFSymbol(icon) {
                Image(systemName: sfSymbol(for: icon))
                    .font(.system(size: 17))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            } else if icon.hasPrefix("[") || icon.hasPrefix("●") {
                Text(icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            }
        } else {
            if icon.hasPrefix("[") || icon.hasPrefix("●") {
                Text(icon)
                    .font(CTFont.regular(13))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Settings Button Row (tap action, no chevron by default)

/// A settings-list row that triggers an action.
struct ConstructButtonRow: View {

    let icon: String
    let title: LocalizedStringKey
    var iconColor: Color = Color.CT.accent
    var showChevron: Bool = false
    let action: () -> Void

    @Environment(\.designStyle) private var designStyle

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconView(icon, color: iconColor)
                    .frame(minWidth: 22, alignment: .center)

                Text(title)
                    .font(designStyle == .apple ? .body : CTFont.bold(16))
                    .foregroundStyle(designStyle == .apple ? Color.primary : Color.CT.text)

                Spacer()

                if showChevron {
                    switch designStyle {
                    case .terminal:
                        Text("[→]")
                            .font(CTFont.regular(12))
                            .foregroundStyle(Color.CT.textDim)
                            .lineLimit(1)
                            .fixedSize()
                    case .apple:
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, designStyle == .apple ? 13 : 14)
            .background(designStyle == .apple ? Color(.secondarySystemGroupedBackground) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconView(_ icon: String, color: Color) -> some View {
        if designStyle == .apple {
            if hasSFSymbol(icon) {
                Image(systemName: sfSymbol(for: icon))
                    .font(.system(size: 17))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            } else if icon.hasPrefix("[") || icon.hasPrefix("●") {
                Text(icon).font(.system(size: 14))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            } else {
                Image(systemName: icon).font(.system(size: 17))
                    .foregroundStyle(color == Color.CT.accent ? .accentColor : color)
            }
        } else {
            if icon.hasPrefix("[") || icon.hasPrefix("●") {
                Text(icon)
                    .font(CTFont.regular(13))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Settings Row Divider

/// Styled divider between rows.
struct ConstructRowDivider: View {
    var indent: CGFloat = 54

    @Environment(\.designStyle) private var designStyle

    var body: some View {
        Divider()
            .overlay(designStyle == .apple ? Color(.separator) : Color.CT.noise)
            .padding(.leading, indent)
    }
}

// MARK: - Settings Section Container

/// Section container.
/// .terminal: dark card with CT border.
/// .apple: grouped background card (no custom border).
struct ConstructSection<Content: View>: View {

    var header: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.designStyle) private var designStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header.uppercased())
                    .font(designStyle == .apple ? .footnote : CTFont.bold(10))
                    .foregroundStyle(Color(.secondaryLabel))
                    .tracking(designStyle == .apple ? 0.5 : 1.5)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                Group {
                    switch designStyle {
                    case .terminal:
                        Rectangle()
                            .fill(Color.CT.bgMsg)
                            .overlay(Rectangle().strokeBorder(Color.CT.noise, lineWidth: 1))
                    case .apple:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: designStyle == .apple ? 12 : 0))
        }
        .padding(.horizontal, 16)
    }
}
