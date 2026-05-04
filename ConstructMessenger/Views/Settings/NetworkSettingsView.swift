//
//  NetworkSettingsView.swift
//  Construct Messenger
//

import SwiftUI

struct NetworkSettingsView: View {
    var showNavBar: Bool = true

    init(showNavBar: Bool = true) {
        self.showNavBar = showNavBar
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designStyle) private var designStyle
    private var connectionManager = ConnectionStatusManager.shared
    private var streamManager = MessageStreamManager.shared

    // Custom server (Debug only)
    @State private var customHost = GRPCChannelManager.shared.currentHost
    @State private var customPort = "\(GRPCChannelManager.shared.currentPort)"
    @State private var showingAppliedAlert = false

    @StateObject private var iceManager = IceProxyManager.shared

    var body: some View {
        Group {
            if designStyle == .apple { appleBody } else { ctBody }
        }
        .alert("server_applied_title", isPresented: $showingAppliedAlert) {
            Button("ok") { }
        } message: {
            Text("server_applied_message")
        }
    }

    // MARK: - CT Body

    private var ctBody: some View {
        VStack(spacing: 0) {
            if showNavBar {
                CTNavBar(
                    title: NSLocalizedString("network", comment: ""),
                    showBack: true,
                    backAction: { dismiss() }
                )
            }
            ScrollView {
            VStack(spacing: 0) {

                // MARK: - Connection Status
                CTSettingsSectionHeader(title: NSLocalizedString("status", comment: "").uppercased())
                let path = iceManager.currentTrafficPath
                HStack(spacing: 12) {
                    Text(connectionStatusASCII)
                        .font(CTFont.regular(13))
                        .foregroundColor(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionManager.connectionStatus.displayText)
                            .font(CTFont.regular(13))
                            .foregroundStyle(Color.CT.text)
                        Text(path.displayDetail)
                            .font(CTFont.regular(11))
                            .foregroundStyle(Color.CT.textDim)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                if let heartbeat = streamManager.lastHeartbeatDate {
                    CTSep(style: .thin)
                    HStack {
                        Text(LocalizedStringKey("last_heartbeat"))
                            .font(CTFont.regular(13))
                            .foregroundStyle(Color.CT.textDim)
                        Spacer()
                        Text(heartbeat, style: .relative)
                            .font(CTFont.regular(13))
                            .foregroundStyle(Color.CT.textDim)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                if let error = connectionManager.lastError {
                    CTSep(style: .thin)
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.CT.danger)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                CTSep()

                // MARK: - Traffic Protection (ICE)
                CTSettingsSectionHeader(title: NSLocalizedString("traffic_protection", comment: "").uppercased())

                // Tri-state mode selector
                HStack {
                    Text(LocalizedStringKey("ice_title"))
                        .font(CTFont.regular(13))
                        .foregroundColor(iceManager.hasCert ? Color.CT.textDim : Color.CT.textDim.opacity(0.5))
                    Spacer()
                    CTModeSelector(
                        selection: Binding(
                            get: { iceManager.mode },
                            set: { newMode in
                                let oldMode = iceManager.mode
                                iceManager.mode = newMode
                                switch newMode {
                                case .off:
                                    iceManager.stop()
                                case .auto:
                                    // Switching to auto: stop proxy, let DPI detection handle it.
                                    if oldMode == .on { iceManager.stop() }
                                case .on:
                                    Task { await iceManager.startIfEnabled() }
                                }
                            }
                        ),
                        options: IceMode.allCases,
                        labels: [
                            .off:  NSLocalizedString("ice_mode_off", comment: ""),
                            .auto: NSLocalizedString("ice_mode_auto", comment: ""),
                            .on:   NSLocalizedString("ice_mode_on", comment: "")
                        ]
                    )
                    .disabled(!iceManager.hasCert)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                if (iceManager.mode != .off || iceManager.isRunning) && iceManager.hasCert {
                    if iceManager.isOnCooldown {
                        CTSep(style: .thin)
                        HStack {
                            Text(LocalizedStringKey("ice_retry"))
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.textDim)
                            Spacer()
                            Text(CTSymbol.refresh)
                                .font(CTFont.regular(13))
                                .foregroundColor(Color.CT.textDim)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    } else if iceManager.isRunning, let relay = iceManager.activeRelay {
                        CTSep(style: .thin)
                        HStack {
                            Text(pathASCII(iceManager.currentTrafficPath))
                                .font(CTFont.regular(13))
                                .foregroundColor(pathColor(iceManager.currentTrafficPath))
                            Text(relay.address)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color.CT.textDim)
                                .textSelection(.enabled)
                            Spacer()
                            if relay.tlsServerName != nil {
                                Text("TLS")
                                    .font(CTFont.regular(10))
                                    .foregroundColor(Color.CT.accentDim)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(Color.CT.accent.opacity(0.4), lineWidth: 0.5))
                                Text("obfs4")
                                    .font(CTFont.regular(10))
                                    .foregroundColor(Color.CT.accentDim)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(Color.CT.accent.opacity(0.4), lineWidth: 0.5))
                            } else {
                                Text("obfs4")
                                    .font(CTFont.regular(10))
                                    .foregroundColor(Color.CT.accentDim)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(Color.CT.accent.opacity(0.4), lineWidth: 0.5))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    } else if iceManager.mode != .off && !iceManager.isRunning {
                        CTSep(style: .thin)
                        Text(iceManager.lastError ?? NSLocalizedString("ice_unavailable", comment: ""))
                            .font(CTFont.regular(11))
                            .foregroundStyle(Color.CT.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }

                // Footer — mode-specific
                if !iceManager.hasCert {
                    Text(LocalizedStringKey("ice_unavailable"))
                        .font(CTFont.regular(11))
                        .foregroundStyle(Color.CT.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    Text(LocalizedStringKey(iceFooterKey))
                        .font(CTFont.regular(11))
                        .foregroundStyle(Color.CT.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                CTSep()
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
                if showNavBar {
                    CTNavBar(
                        title: NSLocalizedString("network", comment: ""),
                        showBack: true,
                        backAction: { dismiss() }
                    )
                }

                // MARK: - Connection Status
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("status", comment: "")) {
                        HStack(spacing: 12) {
                            Image(systemName: appleConnectionStatusIcon)
                                .font(.system(size: 17))
                                .foregroundStyle(appleConnectionStatusColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connectionManager.connectionStatus.displayText)
                                    .font(.body)
                                Text(iceManager.currentTrafficPath.displayDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))

                        if let heartbeat = streamManager.lastHeartbeatDate {
                            ConstructRowDivider(indent: 52)
                            HStack {
                                Label(LocalizedStringKey("last_heartbeat"), systemImage: "heart.fill")
                                    .font(.body)
                                Spacer()
                                Text(heartbeat, style: .relative)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemGroupedBackground))
                        }

                        if let error = connectionManager.lastError {
                            ConstructRowDivider(indent: 16)
                            Text(error)
                                .font(.caption.monospaced())
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }

                // MARK: - Traffic Protection (ICE)
                VStack(alignment: .leading, spacing: 6) {
                    ConstructSection(header: NSLocalizedString("traffic_protection", comment: "")) {
                        HStack {
                            Label(LocalizedStringKey("ice_title"), systemImage: "shield.fill")
                                .font(.body)
                                .foregroundStyle(iceManager.hasCert ? Color.primary : Color.secondary)
                            Spacer()
                            CTModeSelector(
                                selection: Binding(
                                    get: { iceManager.mode },
                                    set: { newMode in
                                        let oldMode = iceManager.mode
                                        iceManager.mode = newMode
                                        switch newMode {
                                        case .off:
                                            iceManager.stop()
                                        case .auto:
                                            if oldMode == .on { iceManager.stop() }
                                        case .on:
                                            Task { await iceManager.startIfEnabled() }
                                        }
                                    }
                                ),
                                options: IceMode.allCases,
                                labels: [
                                    .off:  NSLocalizedString("ice_mode_off", comment: ""),
                                    .auto: NSLocalizedString("ice_mode_auto", comment: ""),
                                    .on:   NSLocalizedString("ice_mode_on", comment: "")
                                ]
                            )
                            .disabled(!iceManager.hasCert)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))

                        if (iceManager.mode != .off || iceManager.isRunning) && iceManager.hasCert {
                            if iceManager.isOnCooldown {
                                ConstructRowDivider(indent: 52)
                                HStack {
                                    Label(LocalizedStringKey("ice_retry"), systemImage: "arrow.clockwise")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Color(.secondarySystemGroupedBackground))
                            } else if iceManager.isRunning, let relay = iceManager.activeRelay {
                                ConstructRowDivider(indent: 52)
                                HStack {
                                    Image(systemName: "network")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.tint)
                                        .frame(width: 22)
                                    Text(relay.address)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Spacer()
                                    if relay.tlsServerName != nil {
                                        Text("TLS")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color(.tertiarySystemFill))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text("obfs4")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemGroupedBackground))
                            } else if iceManager.mode != .off && !iceManager.isRunning {
                                ConstructRowDivider(indent: 52)
                                Text(iceManager.lastError ?? NSLocalizedString("ice_unavailable", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemGroupedBackground))
                            }
                        }
                    }
                    Text(LocalizedStringKey(!iceManager.hasCert ? "ice_unavailable" : iceFooterKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Actions

    private func applyCustomServer() {
        let host = customHost.trimmingCharacters(in: .whitespaces)
        let port = Int(customPort.trimmingCharacters(in: .whitespaces)) ?? 443
        GRPCChannelManager.shared.setCustomServer(host: host, port: port)
        showingAppliedAlert = true
    }

    // MARK: - Helpers

    private var appleConnectionStatusIcon: String {
        switch connectionManager.connectionStatus {
        case .connected:    return "wifi"
        case .disconnected: return "wifi.slash"
        case .connecting:   return "arrow.clockwise"
        case .unknown:      return "questionmark.circle"
        }
    }

    private var appleConnectionStatusColor: Color {
        switch connectionManager.connectionStatus {
        case .connected:    return .green
        case .disconnected: return .red
        case .connecting:   return .orange
        case .unknown:      return Color(.secondaryLabel)
        }
    }

    private var iceFooterKey: String {
        switch iceManager.mode {
        case .off:  return "ice_footer_off"
        case .auto: return "ice_footer_auto"
        case .on:   return "ice_footer_on"
        }
    }

    private var statusColor: Color {
        switch connectionManager.connectionStatus {
        case .connected:    return Color.CT.accent
        case .disconnected: return Color.CT.danger
        case .connecting:   return .orange
        case .unknown:      return Color.CT.textDim
        }
    }

    private var connectionStatusASCII: String {
        switch connectionManager.connectionStatus {
        case .connected:    return "[ok]"
        case .disconnected: return "[err]"
        case .connecting:   return "[~]"
        case .unknown:      return "[?]"
        }
    }

    private func pathASCII(_ path: TrafficPath) -> String {
        switch path {
        case .direct:          return "[→]"
        case .icePrimary:      return "[t]"
        case .iceRelay:        return "[t]"
        case .iceWebTunnel:    return "[ws]"
        case .iceCooldown:     return "[!]"
        case .iceConnecting:   return "[~]"
        }
    }

    private func pathColor(_ path: TrafficPath) -> Color {
        switch path {
        case .direct:          return Color.CT.accentDim
        case .icePrimary:      return Color.CT.accent
        case .iceRelay:        return Color.CT.accentDim
        case .iceWebTunnel:    return Color.CT.accent
        case .iceCooldown:     return .orange
        case .iceConnecting:   return .orange
        }
    }
}

#Preview {
    NavigationStack {
        NetworkSettingsView()
    }
        .preferredColorScheme(.dark)
}
