//
//  MessageInputView.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack {
                TextField("Message...", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.leading, 12)
                    .padding(.trailing, canSend ? 0 : 12)
                    .padding(.vertical, 8)

                if canSend {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? .blue : .gray)
                            .padding(.trailing, 8)
                    }
                    .disabled(!canSend || isSending)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background(Color(uiColor: .systemGray6))
            .clipShape(Capsule())

        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
        .animation(.easeInOut(duration: 0.2), value: canSend)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
