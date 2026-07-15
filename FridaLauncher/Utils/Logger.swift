import Foundation
import os

/// Thin logging wrapper, mirroring the Android `Logger` object which wrapped `android.util.Log`.
enum Logger {
    private static let log = OSLog(subsystem: "com.0xd1ce.fridalauncher", category: "FridaLauncher")

    static func d(_ message: String) { os_log("%{public}@", log: log, type: .debug, message) }
    static func i(_ message: String) { os_log("%{public}@", log: log, type: .info, message) }
    static func w(_ message: String) { os_log("%{public}@", log: log, type: .default, message) }
    static func e(_ message: String) { os_log("%{public}@", log: log, type: .error, message) }
    static func e(_ message: String, _ error: Error) {
        os_log("%{public}@: %{public}@", log: log, type: .error, message, error.localizedDescription)
    }
}
