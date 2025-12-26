//
//  Logger.swift
//  Construct Messenger
//
//  Created by Maxim Eliseyev on 13.12.2025.
//

import Foundation
import os.log

struct Log {
    private static func log(level: OSLogType, category: String, message: String) {
        let logger = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: category)
        os_log("%@", log: logger, type: level, message)
    }

    static func debug(_ message: String, category: String = "Default") {
        log(level: .debug, category: category, message: message)
    }

    static func info(_ message: String, category: String = "Default") {
        log(level: .info, category: category, message: message)
    }

    static func error(_ message: String, category: String = "Default") {
        log(level: .error, category: category, message: message)
    }
    
    static func fault(_ message: String, category: String = "Default") {
        log(level: .fault, category: category, message: message)
    }
}
