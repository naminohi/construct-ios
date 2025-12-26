//
//  ConnectionStatusBanner.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 14.12.2025.
//

import SwiftUI

/// User-facing connection status banner (shown only when disconnected/reconnecting)
struct ConnectionStatusBanner: View {
    @ObservedObject var webSocketManager = WebSocketManager.shared

    var body: some View {
        if !webSocketManager.isConnected {
            HStack(spacing: 8) {
                if case .reconnecting = webSocketManager.connectionStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                }

                Text(webSocketManager.connectionStatus.displayText)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(bannerColor)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var bannerColor: Color {
        switch webSocketManager.connectionStatus {
        case .connected:
            return .clear
        case .disconnected:
            return .red
        case .reconnecting:
            return .orange
        }
    }
}
