//
//  MessagePackHelpers.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 15.12.2025.
//
import Foundation
import MessagePack

struct MessagePackHelper {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = MessagePackEncoder()
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(from data: Data) throws -> T {
        let decoder = MessagePackDecoder()
        return try decoder.decode(T.self, from: data)
    }
}