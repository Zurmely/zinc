import Foundation
import os

/// Unified logging for Zinc. Uses `os.Logger` on all paths; optional file sink is async and off by default.
enum ZincLogger {
    private static let logger = Logger(subsystem: "com.zinc.app", category: "general")
    private static let fileQueue = DispatchQueue(label: "com.zinc.filelog", qos: .utility)
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let logFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Zinc", isDirectory: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private static let maxLogFileBytes = 1_048_576

    private enum Keys {
        static let fileLoggingEnabled = "zinc.debug.fileLoggingEnabled"
    }

    static var fileLoggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.fileLoggingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fileLoggingEnabled) }
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        appendToFileIfEnabled(message)
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        appendToFileIfEnabled(message)
    }

    private static func appendToFileIfEnabled(_ message: String) {
        guard fileLoggingEnabled else { return }
        let line = "\(dateFormatter.string(from: Date()))  \(message)\n"
        fileQueue.async {
            writeLineToFile(line)
        }
    }

    private static func writeLineToFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        let fileManager = FileManager.default
        let dir = logFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: logFileURL.path),
           let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
           let size = attributes[.size] as? Int,
           size + data.count > maxLogFileBytes {
            let rotatedURL = dir.appendingPathComponent("debug.log.1")
            try? fileManager.removeItem(at: rotatedURL)
            try? fileManager.moveItem(at: logFileURL, to: rotatedURL)
        }

        if fileManager.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
