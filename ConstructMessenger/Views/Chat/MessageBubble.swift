//
//  MessageBubble.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let onRetry: ((Message) -> Void)?

    init(message: Message, onRetry: ((Message) -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        HStack {
            if message.isSentByMe {
                Spacer()
            }

            VStack(alignment: message.isSentByMe ? .trailing : .leading, spacing: 4) {
                Text(message.decryptedContent ?? "Encrypted")
                    .padding(.vertical, 6)

                HStack(spacing: 4) {
                    if message.isSentByMe {
                        deliveryStatusView
                    }

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !message.isSentByMe {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        let status = message.deliveryStatus

        switch status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)

        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)

        case .queued:
            Image(systemName: "tray")
                .font(.system(size: 10))
                .foregroundColor(.orange)

        case .failed:
            Button {
                if let onRetry = onRetry {
                    onRetry(message)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text("Retry")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
