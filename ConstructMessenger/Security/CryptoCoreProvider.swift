//
//  CryptoCoreProvider.swift
//  Construct Messenger
//
//  Extracted from CryptoManager (refactor)
//

import Foundation

final class CryptoCoreProvider {
    private let keychain: KeychainManager

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    func loadOrCreateCore() -> ClassicCryptoCore? {
        do {
            if let savedKeysJson = keychain.loadPrivateKeysJson() {
                Log.info("🔑 Found existing keys in Keychain, restoring CryptoCore...", category: "CryptoManager")
                let core = try createCryptoCoreFromKeysJson(keysJson: savedKeysJson)
                Log.info("✅ CryptoCore restored from saved keys!", category: "CryptoManager")
                return core
            }

            Log.info("🆕 No saved keys found, generating new CryptoCore...", category: "CryptoManager")
            let core = try createCryptoCore()

            let keysJson = try core.exportPrivateKeysJson()
            let saved = keychain.savePrivateKeysJson(keysJson)
            if saved {
                Log.info("✅ New CryptoCore created and keys saved to Keychain", category: "CryptoManager")
            } else {
                Log.error("⚠️ CryptoCore created but failed to save keys to Keychain", category: "CryptoManager")
            }
            return core
        } catch let error as CryptoError {
            Log.fault("❌ Failed to create/restore UniFFI CryptoCore: \(error)", category: "CryptoManager")
            return nil
        } catch {
            Log.fault("❌ Unexpected error creating/restoring CryptoCore: \(error)", category: "CryptoManager")
            return nil
        }
    }
}
