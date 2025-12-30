//
//  SettingsViewModel.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 14.12.2025.
//

import Foundation
import Combine
import SwiftUI // Required for UIImage

enum SettingsKeys {
    static let displayName = "displayName"
    static let profileImageData = "profileImageData"
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var displayName: String = UserDefaults.standard.string(forKey: SettingsKeys.displayName) ?? "" {
        didSet {
            UserDefaults.standard.set(displayName, forKey: SettingsKeys.displayName)
            // TODO: In a real app, you might want to debounce this or only save on a "finish editing" event
            // or send to server immediately as requested by the user initially.
        }
    }

    @Published var username: String = ""
    @Published var userId: String = ""
    
    @Published var profileImage: UIImage? = {
        if let imageData = UserDefaults.standard.data(forKey: SettingsKeys.profileImageData) {
            return UIImage(data: imageData)
        }
        return nil
    }() {
        didSet {
            if let image = profileImage, let imageData = image.jpegData(compressionQuality: 0.8) {
                UserDefaults.standard.set(imageData, forKey: SettingsKeys.profileImageData)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKeys.profileImageData)
            }
        }
    }

    func loadUserInfo(from authViewModel: AuthViewModel) {
        userId = authViewModel.currentUserId ?? SessionManager.shared.currentUserId ?? ""
        username = authViewModel.currentUsername ?? ""
        
        // If displayName was not loaded from UserDefaults, try to load from authViewModel
        if displayName.isEmpty {
             displayName = authViewModel.currentDisplayName ?? ""
        }
    }
}

