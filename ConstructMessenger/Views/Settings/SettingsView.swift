//
//  SettingsView.swift
//  Construct Messenger
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(AccountRecoveryViewModel.self) private var recoveryVM
    @Environment(SocialRecoveryService.self) private var socialRecoveryService
    @Environment(ChatsViewModel.self) private var chatsViewModel
    @State private var viewModel = SettingsViewModel()
    private var connectionStatus = ConnectionStatusManager.shared
    @State private var showingQRCode = false
    @State private var linkCopied = false
    @State private var showingRecoverySetup = false
    @State private var recoveryBannerDismissed = UserDefaults.standard.bool(forKey: "recovery_banner_dismissed")
    @State private var navigationPath = NavigationPath()
    @Environment(\.designStyle) private var designStyle

    private let inviteGenerator = InviteGenerator()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if designStyle == .apple {
                    appleBody
                } else {
                    VStack(spacing: 0) {
                        CTNavBar(title: NSLocalizedString("settings", comment: ""))
                        ScrollView { ctContent }
                    }
                }
            }
            .ctBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear {
                viewModel.setContext(viewContext)
                viewModel.loadUserInfo(from: authViewModel)
            }
            .task { await recoveryVM.loadStatus() }
            .sheet(isPresented: $showingRecoverySetup) {
                RecoverySetupView()
                    .environment(recoveryVM)
                    .environment(authViewModel)
                    .onDisappear { Task { await recoveryVM.refreshStatus() } }
            }
            .sheet(isPresented: $showingQRCode) {
                ContactQRCodeView(userId: viewModel.userId, username: viewModel.username)
            }
            .onChange(of: navigationPath) { _, path in
                chatsViewModel.isInSettings = !path.isEmpty
            }
        }
    }

    // MARK: - CT Content (terminal design)

    private var ctContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if recoveryVM.statusLoaded && !recoveryVM.isSetup && !recoveryBannerDismissed {
                recoveryBanner
            }

            CTSettingsSectionHeader(title: NSLocalizedString("account", comment: ""))
            NavigationLink(destination: AccountSettingsView()
                .environment(authViewModel)
                .environment(recoveryVM)
                .environment(socialRecoveryService)
                .environment(viewModel)) {
                profileRow
            }
            .buttonStyle(.plain)
            CTSep()

            CTSettingsSectionHeader(title: NSLocalizedString("share", comment: ""))
            Button { showingQRCode = true } label: {
                CTSettingsRow(label: NSLocalizedString("show_qr_code", comment: "").uppercased(), value: CTSymbol.forward, isAction: true)
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            Button { copyContactLink() } label: {
                CTSettingsRow(
                    label: linkCopied ? NSLocalizedString("link_copied", comment: "").uppercased() : NSLocalizedString("copy_contact_link", comment: "").uppercased(),
                    value: linkCopied ? CTSymbol.ok : CTSymbol.forward,
                    valueColor: linkCopied ? Color.CT.accentDim : Color.CT.text,
                    isAction: !linkCopied
                )
            }
            .buttonStyle(.plain)
            .disabled(linkCopied)
            CTSep()

            CTSettingsSectionHeader(title: NSLocalizedString("settings", comment: ""))
            NavigationLink(destination: DevicesView()) {
                CTSettingsRow(label: NSLocalizedString("linked_devices", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: AppearanceSettingsView()) {
                CTSettingsRow(label: NSLocalizedString("appearance", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep()
            NavigationLink(destination: SecurityView()
                .environment(viewModel)) {
                CTSettingsRow(label: NSLocalizedString("security", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: DataStorageSettingsView()) {
                CTSettingsRow(label: NSLocalizedString("data_and_storage", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: NotificationsSettingsView()) {
                CTSettingsRow(label: NSLocalizedString("notifications", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: BackgroundFetchSettingsView()) {
                CTSettingsRow(
                    label: NSLocalizedString("background_fetch", comment: "").uppercased(),
                    value: BackgroundFetchConfig.shouldBeEnabled ? "[on]" : "[off]",
                    valueColor: BackgroundFetchConfig.shouldBeEnabled ? Color.CT.accentDim : Color.CT.textDim
                )
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: NetworkSettingsView()) {
                CTSettingsRow(
                    label: NSLocalizedString("network", comment: "").uppercased(),
                    value: connectionStatus.isConnected ? "[ok]" : "[err]",
                    valueColor: connectionStatus.isConnected ? Color.CT.accentDim : Color.CT.danger
                )
            }
            .buttonStyle(.plain)
            CTSep(style: .thin)
            NavigationLink(destination: DraftsView()) {
                CTSettingsRow(label: NSLocalizedString("drafts", comment: "").uppercased(), value: CTSymbol.forward)
            }
            .buttonStyle(.plain)
            CTSep()

            CTSettingsSectionHeader(title: NSLocalizedString("about", comment: ""))
            CTSettingsRow(label: NSLocalizedString("version", comment: "").uppercased(), value: "v\(AppConstants.appVersion)")
            CTSep()

            CTSettingsSectionHeader(title: NSLocalizedString("developer", comment: ""), color: .orange)
            NavigationLink(destination: DiagnosticsView()) {
                CTSettingsRow(label: NSLocalizedString("diagnostics_logs", comment: "").uppercased(), value: CTSymbol.forward, labelColor: .orange, valueColor: .orange)
            }
            .buttonStyle(.plain)
            CTSep()
        }
        .padding(.bottom, 32)
    }

    // MARK: - Apple Body

    private var appleBody: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text(NSLocalizedString("settings", comment: ""))
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                if recoveryVM.statusLoaded && !recoveryVM.isSetup && !recoveryBannerDismissed {
                    appleRecoveryBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }

                ConstructSection {
                    NavigationLink(destination: AccountSettingsView()
                        .environment(authViewModel)
                        .environment(recoveryVM)
                        .environment(socialRecoveryService)
                        .environment(viewModel)) {
                        appleProfileRow
                    }
                    .buttonStyle(.plain)
                }

                ConstructSection {
                    Button { showingQRCode = true } label: {
                        CTSettingsRow(
                            label: NSLocalizedString("show_qr_code", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: CTSymbol.scan
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    Button { copyContactLink() } label: {
                        CTSettingsRow(
                            label: linkCopied ? NSLocalizedString("link_copied", comment: "").uppercased() : NSLocalizedString("copy_contact_link", comment: "").uppercased(),
                            value: linkCopied ? CTSymbol.ok : CTSymbol.forward,
                            isAction: !linkCopied,
                            icon: "link"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(linkCopied)
                }

                ConstructSection {
                    NavigationLink(destination: SecurityView().environment(viewModel)) {
                        CTSettingsRow(
                            label: NSLocalizedString("security", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: CTSymbol.lock
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: DevicesView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("linked_devices", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: "laptopcomputer"
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: DataStorageSettingsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("data_and_storage", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: CTSymbol.disk
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: AppearanceSettingsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("appearance", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: "paintbrush"
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: NotificationsSettingsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("notifications", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: "bell"
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: BackgroundFetchSettingsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("background_fetch", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: "arrow.clockwise.circle",
                            subtitle: "● \(BackgroundFetchConfig.shouldBeEnabled ? NSLocalizedString("status_enabled", comment: "") : NSLocalizedString("status_disabled", comment: ""))",
                            subtitleColor: BackgroundFetchConfig.shouldBeEnabled ? .green : Color(.secondaryLabel)
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: NetworkSettingsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("network", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: "globe",
                            subtitle: "● \(connectionStatus.isConnected ? NSLocalizedString("connected", comment: "") : NSLocalizedString("disconnected", comment: ""))",
                            subtitleColor: connectionStatus.isConnected ? .green : .red
                        )
                    }
                    .buttonStyle(.plain)
                    CTSep(style: .thin)
                    NavigationLink(destination: DraftsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("drafts", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            isAction: true,
                            icon: CTSymbol.drafts
                        )
                    }
                    .buttonStyle(.plain)
                }

                ConstructSection {
                    CTSettingsRow(
                        label: NSLocalizedString("version", comment: "").uppercased(),
                        value: "Construct v\(AppConstants.appVersion)",
                        icon: "info.circle"
                    )
                }

                ConstructSection {
                    NavigationLink(destination: DiagnosticsView()) {
                        CTSettingsRow(
                            label: NSLocalizedString("diagnostics_logs", comment: "").uppercased(),
                            value: CTSymbol.forward,
                            labelColor: .orange,
                            isAction: true,
                            icon: "stethoscope"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Apple Profile Row

    private var appleProfileRow: some View {
        HStack(spacing: 14) {
            let img: Image? = {
                guard let ui = viewModel.profileImage else { return nil }
                return Image(uiImage: ui)
            }()
            CTHexAvatar(initials: profileInitials, image: img, size: .large)

            VStack(alignment: .leading, spacing: 3) {
                Text(profileDisplayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if !viewModel.username.isEmpty {
                    Text("@\(viewModel.username)")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Apple Recovery Banner

    private var appleRecoveryBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("recovery_not_configured_title", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(NSLocalizedString("recovery_banner_subtitle", comment: ""))
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                Button { showingRecoverySetup = true } label: {
                    Text(NSLocalizedString("recovery_setup_action", comment: ""))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                recoveryBannerDismissed = true
                UserDefaults.standard.set(true, forKey: "recovery_banner_dismissed")
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Profile Row

    private var profileRow: some View {
        HStack(spacing: 12) {
            let img: Image? = {
                guard let ui = viewModel.profileImage else { return nil }
                return Image(uiImage: ui)
            }()
            CTHexAvatar(initials: profileInitials, image: img, size: .large)

            VStack(alignment: .leading, spacing: 3) {
                Text(profileDisplayName.uppercased())
                    .font(CTFont.bold(13))
                    .foregroundColor(Color.CT.text)
                Text(viewModel.username.isEmpty ? NSLocalizedString("username_not_set", comment: "") : "@\(viewModel.username)")
                    .font(CTFont.regular(11))
                    .foregroundColor(Color.CT.textDim)
                Text(viewModel.isDiscoverable
                    ? NSLocalizedString("searchable_indicator", comment: "")
                    : NSLocalizedString("searchable_indicator_off", comment: ""))
                    .font(CTFont.regular(11))
                    .foregroundColor(viewModel.isDiscoverable ? Color.CT.accent : Color.CT.noise)
            }
            Spacer()
            Text(CTSymbol.forward)
                .font(CTFont.bold(14))
                .foregroundColor(Color.CT.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: - Recovery Banner

    private var recoveryBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(CTSymbol.error)
                .font(CTFont.bold(12))
                .foregroundColor(Color.CT.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("recovery_not_configured_title", comment: "").uppercased())
                    .font(CTFont.bold(11))
                    .foregroundColor(Color.CT.danger)
                Text(NSLocalizedString("recovery_banner_subtitle", comment: ""))
                    .font(CTFont.regular(11))
                    .foregroundColor(Color.CT.textDim)
                Button {
                    showingRecoverySetup = true
                } label: {
                    Text(CTSymbol.setup)
                        .font(CTFont.bold(11))
                        .foregroundColor(Color.CT.accent)
                }
            }
            Spacer()
            Button {
                recoveryBannerDismissed = true
                UserDefaults.standard.set(true, forKey: "recovery_banner_dismissed")
            } label: {
                Text(CTSymbol.close)
                    .font(CTFont.regular(12))
                    .foregroundColor(Color.CT.textDim)
            }
        }
        .padding(12)
        .overlay(Rectangle().stroke(Color.CT.danger.opacity(0.4), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var profileDisplayName: String {
        if !viewModel.displayName.isEmpty { return viewModel.displayName }
        if !viewModel.userId.isEmpty { return DisplayNameGenerator.generate(from: viewModel.userId) }
        return NSLocalizedString("account", comment: "")
    }

    private var profileInitials: String {
        let name = profileDisplayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    private func copyContactLink() {
        Task { await copyContactLinkAsync() }
    }

    @MainActor
    private func copyContactLinkAsync() async {
        guard authViewModel.currentUserId != nil else { return }
        guard let deviceId = KeychainManager.shared.loadDeviceID() else { return }
        let serverHostname = ServerConfig.inviteHost
        guard let link = try? inviteGenerator.generateDeepLink(
            userId: viewModel.userId,
            deviceId: deviceId,
            username: viewModel.resolvedDisplayName,
            server: serverHostname,
            useHTTPS: true
        ) else { return }
        PlatformClipboard.copy(link)
        withAnimation { linkCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { linkCopied = false }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewHelpers.createPreviewContainer()
    let context = container.viewContext
    let authViewModel = AuthViewModel(context: context)
    authViewModel.configureMockAuth()
    let recoveryVM = AccountRecoveryViewModel()
    let chatsVM = ChatsViewModel()
    chatsVM.setContext(context)
    return SettingsView()
        .environment(\.managedObjectContext, context)
        .environment(authViewModel)
        .environment(recoveryVM)
        .environment(SocialRecoveryService())
        .environment(chatsVM)
        .environment(SecurityViewModel())
}
#endif
