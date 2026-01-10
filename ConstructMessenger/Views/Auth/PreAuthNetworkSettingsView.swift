//
//  PreAuthNetworkSettingsView.swift
//  Construct Messenger
//
//  Network settings available before authentication
//

import SwiftUI

/// Simplified network settings view for pre-authentication server configuration
struct PreAuthNetworkSettingsView: View {
    @State private var serverType: ServerType = .default
    @State private var customServerURL = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var saveTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    
    // Computed property to get stored server URL
    private var storedServerURL: String? {
        APIConstants.customServerURL
    }

    enum ServerType: String, CaseIterable {
        case `default` = "default"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .default:
                return NSLocalizedString("default_server", comment: "")
            case .custom:
                return NSLocalizedString("custom_server", comment: "")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Server Type Selection
                Section {
                    Picker("server_type", selection: $serverType) {
                        ForEach(ServerType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: serverType) { newType in
                        handleServerTypeChange(newType)
                    }

                    // MARK: - Server URL Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("server_address")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("custom_server_placeholder", text: $customServerURL)
                            .font(.system(size: 13, design: .monospaced))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .disabled(serverType == .default)
                            .overlay(
                                Group {
                                    if serverType == .default {} else { EmptyView() }
                                }
                            )
                            .onChange(of: customServerURL) { newValue in
                                handleServerURLChange(newValue)
                            }
                            .onSubmit {
                                saveServerURL()
                            }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("server_configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("preauth_server_info")
                            .font(.caption)

                        if serverType == .custom {
                            Text("custom_server_prefix_warning")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("default_server_info")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Active Server Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("current_active_server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(APIConstants.activeServerURL)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("active_configuration")
                }
            }
            .navigationTitle("network_settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") {
                        // Ensure any pending changes are saved
                        saveServerURL()
                        dismiss()
                    }
                }
            }
            .onAppear {
                initializeServerType()
            }
            .alert("server_changed", isPresented: $showingAlert) {
                Button("ok") { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Initialization
    private func initializeServerType() {
        if let existingURL = storedServerURL, !existingURL.isEmpty {
            serverType = .custom
            customServerURL = existingURL
        } else {
            serverType = .default
            customServerURL = ServerConfig.defaultWebsocketURL
        }
    }

    // MARK: - Actions
    private func handleServerTypeChange(_ newType: ServerType) {
        saveTask?.cancel()

        switch newType {
        case .default:
            // Reset to default server
            APIConstants.saveCustomServerURL(nil)
            customServerURL = ServerConfig.defaultWebsocketURL
            Log.info("⚙️ Switched to default server: \(ServerConfig.defaultWebsocketURL)", category: "PreAuthNetworkSettings")

        case .custom:
            // Load existing custom server or prepare for new input
            if let existingURL = storedServerURL, !existingURL.isEmpty {
                customServerURL = existingURL
            } else {
                customServerURL = ""
            }
        }
    }

    private func handleServerURLChange(_ newValue: String) {
        // Cancel previous save task
        saveTask?.cancel()

        // Only auto-save if we're in custom mode
        guard serverType == .custom else { return }

        // Don't save empty strings immediately (let user finish typing)
        guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        // Debounce save operation
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveServerURL()
            }
        }
    }

    private func saveServerURL() {
        saveTask?.cancel()

        switch serverType {
        case .default:
            // Ensure we're using default (clear any custom URL)
            if storedServerURL != nil {
                APIConstants.saveCustomServerURL(nil)
                Log.info("⚙️ Reset to default server: \(ServerConfig.defaultWebsocketURL)", category: "PreAuthNetworkSettings")
            }

        case .custom:
            var url = customServerURL.trimmingCharacters(in: .whitespaces)

            // Validate URL is not empty
            guard !url.isEmpty else {
                // Clear stored URL if field is empty
                if storedServerURL != nil {
                    APIConstants.saveCustomServerURL(nil)
                }
                return
            }

            // Ensure URL has wss:// or ws:// prefix
            if !url.hasPrefix("wss://") && !url.hasPrefix("ws://") {
                url = "wss://" + url
                // Update the field with the corrected URL
                customServerURL = url
            }

            // Only save if URL actually changed
            if storedServerURL != url {
                APIConstants.saveCustomServerURL(url)
                Log.info("⚙️ Custom server saved to Keychain: \(url)", category: "PreAuthNetworkSettings")

                // Show confirmation message only if it's a significant change
                if !url.isEmpty {
                    alertMessage = String(format: NSLocalizedString("server_changed_message", comment: ""), url)
                    showingAlert = true
                }
            }
        }
    }
}

#Preview {
    PreAuthNetworkSettingsView()
}
