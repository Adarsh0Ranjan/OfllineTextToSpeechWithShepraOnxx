//
//  Logger.swift
//  MyTTSApp
//
//  Created by Adarsh Ranjan on 05/10/25.
//

import Foundation


struct Logger {
    static func log(_ message: String, tag: String = "INFO") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(tag)] \(message)")
    }

    static func error(_ message: String) {
        log("❌ \(message)", tag: "ERROR")
    }

    static func success(_ message: String) {
        log("✅ \(message)", tag: "SUCCESS")
    }

    static func debug(_ message: String) {
        log("🧩 \(message)", tag: "DEBUG")
    }
}
