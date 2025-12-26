//
//  SettingsViewModel.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 14.12.2025.
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var username: String = ""
    @Published var userId: String = ""

    func loadUserInfo(from authViewModel: AuthViewModel) {
        userId = authViewModel.currentUserId ?? SessionManager.shared.currentUserId ?? ""
        displayName = authViewModel.currentDisplayName ?? ""
        username = authViewModel.currentUsername ?? ""
    }
}
