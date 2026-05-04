//
//  NotificationsSettingsView.swift
//  ConstructMessenger
//
//  Created by Maxim Eliseyev on 02.01.2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

struct NotificationsSettingsView: View {
    // MARK: - Notification Settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designStyle) private var designStyle
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("showMessageNotifications") private var showMessageNotifications: Bool = true
    @AppStorage("notificationPreviewType") private var notificationPreviewType: NotificationPreviewType = .nameAndMessage
    @AppStorage("notificationSound") private var notificationSound: Bool = true
    @AppStorage("notificationVibration") private var notificationVibration: Bool = true
    @AppStorage("pushNotificationsEnabled") private var pushNotificationsEnabled: Bool = true

    // MARK: - State
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingSystemSettings = false

    var body: some View {
        Group {
            if designStyle == .apple { appleBody } else { ctBody }
        }
        .onAppear {
            checkNotificationAuthorization()
        }
    }

    // MARK: - CT Body

    private var ctBody: some View {
        VStack(spacing: 0) {
            CTNavBar(
                title: NSLocalizedString("notifications", comment: ""),
                showBack: true,
                backAction: { dismiss() }
            )
            ScrollView {
            VStack(spacing: 0) {

                // MARK: - General Notifications
                CTSettingsSectionHeader(title: NSLocalizedString("notifications", comment: "").uppercased())
                HStack {
                    Text(LocalizedStringKey("enable_notifications"))
                        .font(CTFont.regular(13))
                        .foregroundColor(Color.CT.textDim)
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .tint(Color.CT.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                Text(LocalizedStringKey("notifications_footer"))
                    .font(CTFont.regular(11))
                    .foregroundStyle(Color.CT.textDim)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                CTSep()

                // MARK: - System Permission Status
                CTSettingsSectionHeader(title: NSLocalizedString("system_notification_settings", comment: "").uppercased())
                HStack {
                    Text(LocalizedStringKey("status"))
                        .font(CTFont.regular(13))
                        .foregroundColor(Color.CT.textDim)
                    Spacer()
                    Text(statusText)
                        .font(CTFont.regular(13))
                        .foregroundColor(statusColor)
                    Text(statusIcon)
                        .font(CTFont.regular(13))
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                if authorizationStatus == .denied {
                    CTSep(style: .thin)
                    Button(action: openSystemSettings) {
                        HStack {
                            Text(LocalizedStringKey("open_system_settings"))
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.textDim)
                            Spacer()
                            Text("[→]")
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if authorizationStatus == .notDetermined {
                    CTSep(style: .thin)
                    Button(action: requestNotificationPermission) {
                        HStack {
                            Text(LocalizedStringKey("grant_permission"))
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.accent)
                            Spacer()
                            Text("[→]")
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if authorizationStatus == .denied {
                    Text(LocalizedStringKey("notification_permissions_required"))
                        .font(CTFont.regular(11))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    Text(LocalizedStringKey("system_settings_footer"))
                        .font(CTFont.regular(11))
                        .foregroundStyle(Color.CT.textDim)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                CTSep()

                // MARK: - Message Notifications
                if notificationsEnabled {
                    CTSettingsSectionHeader(title: NSLocalizedString("MESSAGE_NOTIFICATIONS", comment: "").uppercased())
                    HStack {
                        Text(LocalizedStringKey("show_message_notifications"))
                            .font(CTFont.regular(13))
                            .foregroundColor(Color.CT.textDim)
                        Spacer()
                        Toggle("", isOn: $showMessageNotifications)
                            .labelsHidden()
                            .tint(Color.CT.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    CTSep(style: .thin)

                    HStack {
                        Text(LocalizedStringKey("notification_sound"))
                            .font(CTFont.regular(13))
                            .foregroundColor(Color.CT.textDim)
                        Spacer()
                        Toggle("", isOn: $notificationSound)
                            .labelsHidden()
                            .tint(Color.CT.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    CTSep(style: .thin)

                    HStack {
                        Text(LocalizedStringKey("vibration"))
                            .font(CTFont.regular(13))
                            .foregroundColor(Color.CT.textDim)
                        Spacer()
                        Toggle("", isOn: $notificationVibration)
                            .labelsHidden()
                            .tint(Color.CT.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    CTSep()

                    // MARK: - Push Notifications
                    CTSettingsSectionHeader(title: NSLocalizedString("PUSH_NOTIFICATIONS", comment: "").uppercased())
                    #if targetEnvironment(macCatalyst)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("push_not_available_mac", comment: ""))
                            .font(CTFont.regular(13))
                            .foregroundColor(Color.CT.textDim)
                        Text(NSLocalizedString("push_not_available_mac_hint", comment: ""))
                            .font(CTFont.regular(11))
                            .foregroundColor(Color.CT.textDim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    #else
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey("enable_push_notifications"))
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.textDim)
                            Text(LocalizedStringKey("push_notifications_footer"))
                                .font(CTFont.regular(11))
                                .foregroundColor(Color.CT.textDim)
                        }
                        Spacer()
                        Toggle("", isOn: $pushNotificationsEnabled)
                            .labelsHidden()
                            .tint(Color.CT.accent)
                            .disabled(authorizationStatus != .authorized)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    CTSep(style: .thin)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey("push_privacy_notice"))
                            .font(CTFont.regular(13))
                            .foregroundColor(Color.CT.textDim)
                        Text(LocalizedStringKey("push_privacy_notice_text"))
                            .font(CTFont.regular(11))
                            .foregroundColor(Color.CT.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    #endif
                    CTSep()
                }
            }
            .padding(.vertical, 20)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        }
        .background(Color.CT.bg.ignoresSafeArea())
    }

    // MARK: - Apple Body

    private var appleBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - General Notifications
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("notifications", comment: "")) {
                        HStack {
                            Label(LocalizedStringKey("enable_notifications"), systemImage: "bell.fill")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                    }
                    Text(LocalizedStringKey("notifications_footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                // MARK: - System Permission Status
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("system_notification_settings", comment: "")) {
                        HStack {
                            Label {
                                Text(LocalizedStringKey("status"))
                            } icon: {
                                Image(systemName: appleStatusSFSymbol)
                                    .foregroundStyle(appleStatusColor)
                            }
                            .font(.body)
                            Spacer()
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(appleStatusColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))

                        if authorizationStatus == .denied {
                            ConstructRowDivider(indent: 52)
                            Button(action: openSystemSettings) {
                                HStack {
                                    Label(LocalizedStringKey("open_system_settings"), systemImage: "gear")
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .imageScale(.small)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Color(.secondarySystemGroupedBackground))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else if authorizationStatus == .notDetermined {
                            ConstructRowDivider(indent: 52)
                            Button(action: requestNotificationPermission) {
                                HStack {
                                    Label(LocalizedStringKey("grant_permission"), systemImage: "bell.badge.fill")
                                        .font(.body)
                                        .foregroundStyle(.tint)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Color(.secondarySystemGroupedBackground))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(authorizationStatus == .denied
                         ? LocalizedStringKey("notification_permissions_required")
                         : LocalizedStringKey("system_settings_footer"))
                        .font(.caption)
                        .foregroundStyle(authorizationStatus == .denied ? Color.orange : Color.secondary)
                        .padding(.horizontal, 20)
                }

                // MARK: - Message Notifications
                if notificationsEnabled {
                    ConstructSection(header: NSLocalizedString("MESSAGE_NOTIFICATIONS", comment: "")) {
                        HStack {
                            Label(LocalizedStringKey("show_message_notifications"), systemImage: "message.fill")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $showMessageNotifications)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))

                        ConstructRowDivider(indent: 52)

                        HStack {
                            Label(LocalizedStringKey("notification_sound"), systemImage: "speaker.wave.2.fill")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $notificationSound)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))

                        ConstructRowDivider(indent: 52)

                        HStack {
                            Label(LocalizedStringKey("vibration"), systemImage: "hand.tap.fill")
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: $notificationVibration)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                    }

                    // MARK: - Push Notifications
                    #if targetEnvironment(macCatalyst)
                    ConstructSection(header: NSLocalizedString("PUSH_NOTIFICATIONS", comment: "")) {
                        HStack {
                            Label(LocalizedStringKey("push_not_available_mac"), systemImage: "app.badge.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                    }
                    #else
                    VStack(alignment: .leading, spacing: 6) {
                        ConstructSection(header: NSLocalizedString("PUSH_NOTIFICATIONS", comment: "")) {
                            HStack {
                                Label(LocalizedStringKey("enable_push_notifications"), systemImage: "app.badge.fill")
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $pushNotificationsEnabled)
                                    .labelsHidden()
                                    .disabled(authorizationStatus != .authorized)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemGroupedBackground))

                            ConstructRowDivider(indent: 52)

                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("push_privacy_notice"))
                                        .font(.body)
                                    Text(LocalizedStringKey("push_privacy_notice_text"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemGroupedBackground))
                        }
                        Text(LocalizedStringKey("push_notifications_footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    #endif
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(NSLocalizedString("notifications", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Computed Properties
    private var appleStatusSFSymbol: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    private var appleStatusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return Color(.secondaryLabel)
        }
    }

    private var statusIcon: String {
        switch authorizationStatus {
        case .authorized:
            return "[ok]"
        case .denied:
            return "[err]"
        case .notDetermined:
            return "[?]"
        case .provisional:
            return "[ok]"
        case .ephemeral:
            return "[ok]"
        @unknown default:
            return "[?]"
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .authorized:
            return Color.CT.accent
        case .denied:
            return Color.CT.danger
        case .notDetermined:
            return .orange
        case .provisional:
            return Color.CT.accent
        case .ephemeral:
            return Color.CT.accent
        @unknown default:
            return Color.CT.textDim
        }
    }

    private var statusText: LocalizedStringKey {
        switch authorizationStatus {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .notDetermined:
            return "not_determined"
        case .provisional:
            return "authorized"
        case .ephemeral:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }

    // MARK: - Methods
    private func checkNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                checkNotificationAuthorization()
                if granted {
                    notificationsEnabled = true
                }
            }
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Notifications.prefPane"))
        #endif
    }
}

// MARK: - Notification Preview Type
enum NotificationPreviewType: String, CaseIterable {
    case nameAndMessage
    case nameOnly
    case none

    var displayName: LocalizedStringKey {
        switch self {
        case .nameAndMessage: return "preview_name_and_message"
        case .nameOnly: return "preview_name_only"
        case .none: return "preview_none"
        }
    }

    var description: String {
        switch self {
        case .nameAndMessage: return "Show sender name and message content"
        case .nameOnly: return "Show only sender name"
        case .none: return "Show only 'New Message'"
        }
    }

    var iconName: String {
        switch self {
        case .nameAndMessage: return "text.bubble.fill"
        case .nameOnly: return "person.fill"
        case .none: return "eye.slash.fill"
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }
        .preferredColorScheme(.dark)
}
