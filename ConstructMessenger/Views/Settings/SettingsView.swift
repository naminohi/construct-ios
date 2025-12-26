//
//  SettingsView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 14.12.2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingLogoutConfirmation = false

    // 🎯 AppStorage автоматически синхронизируется с UserDefaults!
    @AppStorage(APIConstants.customServerURLKey) private var storedServerURL: String?
    @State private var editingServerURL: String = ""
    @State private var isEditingServer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Display Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.displayName)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Username")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("@\(viewModel.username)")
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("User ID")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.userId)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } header: {
                    Text("Account Information")
                }

                Section {
                    HStack {
                        Text("Connection")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(WebSocketManager.shared.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(WebSocketManager.shared.isConnected ? "Connected" : "Disconnected")
                                .fontWeight(.medium)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .foregroundColor(.secondary)
                        Text(APIConstants.activeServerURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                } header: {
                    Text("Connection")
                }

                Section {
                    if isEditingServer {
                        TextField("wss://your-server.com", text: $editingServerURL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .textContentType(.URL)

                        HStack {
                            Button("Cancel") {
                                isEditingServer = false
                                editingServerURL = ""
                            }

                            Spacer()

                            Button("Apply") {
                                saveCustomServer()
                            }
                            .disabled(editingServerURL.isEmpty)
                        }
                    } else {
                        Button {
                            isEditingServer = true
                            editingServerURL = storedServerURL ?? ""
                        } label: {
                            Text("Change Server")
                        }

                        if storedServerURL != nil {
                            Button(role: .destructive) {
                                resetToDefaultServer()
                            } label: {
                                Text("Reset to Default")
                            }
                        }
                    }
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("Default: \(ServerEnvironment.current.serverURL)")
                        .font(.caption)
                }

                Section {
                    Text("App Version")
                        .foregroundColor(.secondary)
                    Text("\(AppConstants.appVersion) (\(AppConstants.buildNumber))")
                        .font(.caption)
                        .foregroundColor(.gray)
                } header: {
                    Text("About")
                }

                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Logout")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                viewModel.loadUserInfo(from: authViewModel)
            }
            .alert("Logout", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    authViewModel.logout()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
    }

    // MARK: - Server Configuration Methods

    private func saveCustomServer() {
        var url = editingServerURL.trimmingCharacters(in: .whitespaces)

        // Ensure URL has wss:// or ws:// prefix
        if !url.hasPrefix("wss://") && !url.hasPrefix("ws://") {
            url = "wss://" + url
        }

        // 🎯 @AppStorage автоматически сохранит в UserDefaults!
        storedServerURL = url
        isEditingServer = false

        // Notify and reconnect
        NotificationCenter.default.post(name: .serverURLChanged, object: nil)
        reconnectToServer()

        print("⚠️ Using custom server: \(url)")
    }

    private func resetToDefaultServer() {
        // 🎯 @AppStorage автоматически удалит из UserDefaults!
        storedServerURL = nil

        // Notify and reconnect
        NotificationCenter.default.post(name: .serverURLChanged, object: nil)
        reconnectToServer()

        print("✅ Reset to default server: \(ServerEnvironment.current.serverURL)")
    }

    private func reconnectToServer() {
        WebSocketManager.shared.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WebSocketManager.shared.connect()
        }
    }
}

#Preview {
    let authViewModel = AuthViewModel()
    authViewModel.isAuthenticated = true
    authViewModel.currentUserId = "user123"
    authViewModel.currentUsername = "john_doe"
    authViewModel.currentDisplayName = "John Doe"

    return SettingsView()
        .environmentObject(authViewModel)
}
