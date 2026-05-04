//
//  AppleDesignSystem.swift
//  Construct Messenger
//
//  Apple HIG renderings for every CT* component.
//  These are private implementation structs used only when
//  @Environment(\.designStyle) == .apple.
//
//  Each struct mirrors the CT equivalent's parameters exactly so the
//  dispatch call sites in ConstructTheme.swift are mechanical 1-to-1 replacements.
//

import SwiftUI

// MARK: - SF Symbol mapping

/// Maps CT ASCII symbols to their SF Symbol equivalents.
func sfSymbol(for ctSymbol: String) -> String {
    switch ctSymbol {
    // Navigation
    case CTSymbol.back:         return "chevron.left"
    case CTSymbol.forward:      return "chevron.right"
    // Actions
    case CTSymbol.add:          return "plus"
    case CTSymbol.close:        return "xmark"
    case CTSymbol.send:         return "arrow.up.circle.fill"
    case CTSymbol.media:        return "photo"
    case CTSymbol.menu:         return "ellipsis"
    case CTSymbol.edit:         return "square.and.pencil"
    case CTSymbol.refresh,
         CTSymbol.retry:        return "arrow.clockwise"
    case CTSymbol.upload:       return "arrow.up"
    case CTSymbol.callOut:      return "phone.arrow.up.right"
    // Status
    case CTSymbol.ok:           return "checkmark"
    case CTSymbol.read:         return "checkmark.message"
    case CTSymbol.delivered:    return "checkmark.circle"
    case CTSymbol.error:        return "exclamationmark.triangle"
    case CTSymbol.loading:      return "ellipsis"
    // Security / Settings
    case CTSymbol.biometric:    return "faceid"
    case CTSymbol.key:          return "key"
    case CTSymbol.lock:         return "lock"
    case CTSymbol.log:          return "doc.text"
    case CTSymbol.disk:         return "internaldrive"
    case CTSymbol.image:        return "photo"
    // State
    case CTSymbol.pin:          return "pin"
    case CTSymbol.scan:         return "qrcode.viewfinder"
    case CTSymbol.search:       return "magnifyingglass"
    case CTSymbol.drafts:       return "doc.plaintext"
    case CTSymbol.ttl:          return "timer"
    case CTSymbol.setup:        return "wrench.and.screwdriver"
    // Calls
    case CTSymbol.callEnd:      return "phone.down"
    case CTSymbol.callAnswer:   return "phone"
    // Devices
    case CTSymbol.deviceGeneric,
         CTSymbol.deviceIOS,
         CTSymbol.deviceAndroid: return "iphone"
    case CTSymbol.deviceMac:    return "desktopcomputer"
    // Tab bar
    case CTSymbol.tabChats:     return "message"
    case CTSymbol.tabSynaps,
         CTSymbol.tabContacts:  return "person.circle.fill"
    case CTSymbol.tabCalls:     return "phone"
    case CTSymbol.tabSettings:  return "gear"
    // Input
    case CTSymbol.mic:          return "mic"
    case CTSymbol.attach:       return "paperclip"
    default:
        // Unknown / multi-char ASCII → fallback to a neutral symbol
        return "circle"
    }
}

/// Returns true if this CT symbol has a meaningful SF Symbol mapping.
func hasSFSymbol(_ ctSymbol: String) -> Bool {
    sfSymbol(for: ctSymbol) != "circle"
}

// MARK: - _APNavBar

struct _APNavBar: View {
    let title: String
    var showBack: Bool = false
    var trailingSymbol: String? = nil
    var trailingColor: Color = .accentColor
    var backAction: (() -> Void)? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Centered title
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 0) {
                if showBack {
                    Button(action: { backAction?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text(NSLocalizedString("back", comment: ""))
                                .font(.body)
                        }
                        .foregroundStyle(.tint)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if let sym = trailingSymbol {
                    Button(action: { trailingAction?() }) {
                        Image(systemName: sfSymbol(for: sym))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(trailingColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - _APTabBar

struct _APTabBar: View {
    @Binding var selected: Int
    var items: [CTTabItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button(action: { selected = i }) {
                    VStack(spacing: 3) {
                        Image(systemName: tabIcon(items[i].symbol, selected: i == selected))
                            .imageScale(.medium)
                            .symbolRenderingMode(.hierarchical)
                        Text(fullLabel(for: items[i].label))
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(i == selected ? Color.accentColor : Color(.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            ZStack(alignment: .top) {
                Color(.systemBackground)
                Divider().frame(maxWidth: .infinity, maxHeight: 0.5)
            }
        )
    }

    private func tabIcon(_ ctSymbol: String, selected: Bool) -> String {
        let base = sfSymbol(for: ctSymbol)
        let filled = "\(base).fill"
        // Some SF Symbols don't have a .fill variant — fall back gracefully.
        return selected ? filled : base
    }

    /// Maps CT abbreviated tab labels to full localized names for Apple HIG display.
    private func fullLabel(for ctLabel: String) -> String {
        switch ctLabel {
        case "MSG": return NSLocalizedString("tab_chats_full",    comment: "")
        case "SYN": return NSLocalizedString("tab_synaps_full",   comment: "")
        case "TEL": return NSLocalizedString("tab_calls_full",    comment: "")
        case "CFG": return NSLocalizedString("tab_settings_full", comment: "")
        default:    return ctLabel
        }
    }
}

// MARK: - _APSettingsSectionHeader

struct _APSettingsSectionHeader: View {
    let title: String
    var color: Color = Color(.secondaryLabel)

    var body: some View {
        Text(title.uppercased())
            .font(.footnote)
            .foregroundStyle(color == Color.CT.accentDim ? Color(.secondaryLabel) : color)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - _APSettingsRow

struct _APSettingsRow: View {
    let label: String
    var value: String = CTSymbol.forward
    var icon: String? = nil
    var subtitle: String? = nil
    var subtitleColor: Color = Color(.secondaryLabel)
    var labelColor: Color = .primary
    var valueColor: Color = Color(.secondaryLabel)
    var isAction: Bool    = false
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: resolvedIcon(icon))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isDestructive ? .red : iconColor(for: labelColor))
                    .frame(width: 24, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(normalizedLabel)
                    .font(.body)
                    .foregroundStyle(isDestructive ? .red : (labelColor == Color.CT.textDim ? Color.primary : labelColor))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }
            }

            Spacer()

            if isAction || value == CTSymbol.forward {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Color(.tertiaryLabel))
            } else {
                Text(value == CTSymbol.forward ? "" : appleValue)
                    .font(.body)
                    .foregroundStyle(isDestructive ? .red : (valueColor == Color.CT.text ? Color(.secondaryLabel) : valueColor))
            }
        }
        .padding(.horizontal, icon != nil ? 16 : 20)
        .padding(.vertical, subtitle != nil ? 10 : 13)
        .background(Color(.secondarySystemGroupedBackground))
    }

    /// Resolves a CT symbol (e.g. "[lock]") or plain SF Symbol name to an SF Symbol name.
    private func resolvedIcon(_ icon: String) -> String {
        icon.hasPrefix("[") ? sfSymbol(for: icon) : icon
    }

    private func iconColor(for labelColor: Color) -> Color {
        if labelColor == Color.CT.textDim || labelColor == .primary || labelColor == Color.CT.text {
            return Color(.secondaryLabel)
        }
        return labelColor
    }

    /// Converts ALL-CAPS strings (from CT views that call .uppercased()) to title case.
    private var normalizedLabel: String {
        let hasLower = label.contains(where: \.isLowercase)
        guard !hasLower else { return label }
        return label.localizedCapitalized
    }

    private var appleValue: String {
        switch value {
        case CTSymbol.ok:        return "✓"
        case CTSymbol.forward:   return ""
        case CTSymbol.error:     return "⚠"
        case CTSymbol.loading:   return "…"
        default:
            let hasLower = value.contains(where: \.isLowercase)
            return hasLower ? value : value.localizedCapitalized
        }
    }
}

// MARK: - _APSep

struct _APSep: View {
    enum Style { case thin, thick }
    var style: Style = .thin

    var body: some View {
        if style == .thick {
            Color.clear.frame(height: 20)   // visual section gap
        } else {
            Divider()
                .padding(.leading, 20)
        }
    }
}

// MARK: - _APHexAvatar (circular in Apple theme)

struct _APHexAvatar: View {
    var initials: String
    var image: Image? = nil
    var size: CTHexAvatar.AvatarSize = .medium
    var colorSeed: String? = nil

    private var accentColor: Color {
        Color.hexagonAccent(for: colorSeed ?? initials)
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.rawValue, height: size.rawValue)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(accentColor.opacity(0.18))
                Circle()
                    .strokeBorder(accentColor, lineWidth: 1.5)
                Text(String(initials.prefix(2)).uppercased())
                    .font(.system(size: size.rawValue * 0.30, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
        }
        .frame(width: size.rawValue, height: size.rawValue)
    }
}

// MARK: - _APRowIcon

struct _APRowIcon: View {
    let symbol: String
    var color: Color  = Color(.secondaryLabel)
    var size: CGFloat = 14

    var body: some View {
        Group {
            if hasSFSymbol(symbol) {
                Image(systemName: sfSymbol(for: symbol))
                    .font(.system(size: size))
                    .foregroundStyle(color == Color.CT.textDim ? Color(.secondaryLabel) : color)
            } else {
                Text(symbol)
                    .font(.system(size: size))
                    .foregroundStyle(color == Color.CT.textDim ? Color(.secondaryLabel) : color)
            }
        }
        .frame(minWidth: 28, alignment: .center)
    }
}

// MARK: - _APBackground

struct _APBackground: View {
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }
}

// MARK: - _APModeSelector

struct _APModeSelector<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let labels: [T: String]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(labels[option] ?? "").tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}

// MARK: - _APSystemMessage

struct _APSystemMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
    }
}

// MARK: - _APTextField

struct _APTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var alignment: TextAlignment = .leading

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.body)
        .multilineTextAlignment(alignment)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - _APButton

struct _APButton: View {
    let label: String
    var isEnabled: Bool     = true
    var isDestructive: Bool = false
    let action: () -> Void

    private var bgColor: Color {
        if !isEnabled { return Color(.systemFill) }
        return isDestructive ? Color(.systemRed) : Color.accentColor
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : Color(.secondaryLabel))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.horizontal, 16)
    }
}

// MARK: - Apple background modifier helper

extension View {
    func apBackground() -> some View {
        self.background(_APBackground())
    }
}
