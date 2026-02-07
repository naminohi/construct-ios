//
//  RegistrationBundleService.swift
//  Construct Messenger
//
//  Extracted from CryptoManager (refactor)
//

import Foundation

final class RegistrationBundleService {
    func generateRegistrationBundle(core: ClassicCryptoCore?) -> RegistrationBundle? {
        guard let core = core else { return nil }

        do {
            let jsonString = try core.exportRegistrationBundleJson()
            guard let jsonData = jsonString.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(RegistrationBundle.self, from: jsonData)
        } catch {
            return nil
        }
    }
}
