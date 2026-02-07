//
//  MessageCryptoService.swift
//  Construct Messenger
//
//  Extracted from CryptoManager (refactor)
//

import Foundation

final class MessageCryptoService {
    struct EncryptedMessageComponents {
        let ephemeralPublicKey: Data
        let messageNumber: UInt32
        let content: String
        let suiteId: UInt16
    }

    func encryptMessage(
        _ message: String,
        for userId: String,
        core: ClassicCryptoCore?,
        sessionStore: SessionStore,
        restoreSession: (String) -> Bool,
        saveSession: (String) -> Void,
        archiveSession: (String, ArchiveReason) -> Void
    ) throws -> EncryptedMessageComponents {
        guard let core = core else {
            throw CryptoManagerError.coreNotInitialized
        }

        if !sessionStore.hasSession(for: userId) {
            if !restoreSession(userId) {
                throw CryptoManagerError.sessionNotFound
            }
        }

        guard let sessionId = sessionStore.getSessionId(for: userId),
              let suiteId = sessionStore.getSuiteId(for: userId) else {
            throw CryptoManagerError.sessionNotFound
        }

        do {
            let rustComponents = try core.encryptMessage(sessionId: sessionId, plaintext: message)
            let components = EncryptedMessageComponents(
                ephemeralPublicKey: Data(rustComponents.ephemeralPublicKey),
                messageNumber: rustComponents.messageNumber,
                content: MessagePadding.padCiphertextBase64(rustComponents.content),
                suiteId: suiteId
            )
            saveSession(userId)
            return components
        } catch {
            archiveSession(userId, .decryptionFailed)
            throw CryptoManagerError.encryptionFailed
        }
    }

    func decryptMessage(
        _ message: ChatMessage,
        core: ClassicCryptoCore?,
        sessionStore: SessionStore,
        restoreSession: (String) -> Bool,
        saveSession: (String) -> Void,
        archiveSession: (String, ArchiveReason) -> Void,
        tryDecryptWithArchived: (ChatMessage) throws -> String
    ) throws -> String {
        guard let core = core else {
            throw CryptoManagerError.coreNotInitialized
        }

        if !sessionStore.hasSession(for: message.from) {
            if !restoreSession(message.from) {
                throw CryptoManagerError.sessionNotFound
            }
        }

        guard let sessionId = sessionStore.getSessionId(for: message.from) else {
            throw CryptoManagerError.sessionNotFound
        }

        do {
            let contentForDecrypt = MessagePadding.unpadCiphertextBase64(message.content)
            let plaintext = try core.decryptMessage(
                sessionId: sessionId,
                ephemeralPublicKey: [UInt8](message.ephemeralPublicKey),
                messageNumber: message.messageNumber,
                content: contentForDecrypt
            )
            saveSession(message.from)
            return plaintext
        } catch {
            if let plaintext = try? tryDecryptWithArchived(message) {
                return plaintext
            }
            archiveSession(message.from, .decryptionFailed)
            throw CryptoManagerError.decryptionFailed
        }
    }
}
