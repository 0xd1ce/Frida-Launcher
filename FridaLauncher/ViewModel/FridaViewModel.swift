import Foundation
import SwiftUI

/// Observable state + orchestration for the UI — the iOS port of `FridaViewModel`.
///
/// Kotlin `LiveData` becomes `@Published` properties; `viewModelScope.launch` becomes
/// `Task { … }` on the `@MainActor`. Every published mutation happens on the main actor,
/// so the UI updates safely while `FridaEngine` does its blocking work in the background.
@MainActor
final class FridaViewModel: ObservableObject {

    enum RootStatus {
        case unknown, available, notAvailable, nonRootMode
    }

    // MARK: - Published state (mirrors the LiveData fields)

    /// Timestamped log lines shown in the log panel. The Android app kept a single
    /// appended string in a TextView; here we keep the lines and render them.
    @Published var logLines: [String] = []
    @Published var isLoading = false
    @Published var isServerInstalled = false
    @Published var isServerRunning = false
    @Published var installedVersion = "Unknown"
    @Published var availableReleases: [FridaRelease] = []
    @Published var selectedVersion: String?
    @Published var isCustomVersion = false
    @Published var selectedArchitecture: String
    @Published var lastCustomFlags = ""
    @Published var rootAccessStatus: RootStatus = .unknown

    init() {
        selectedArchitecture = DeviceInfo.architecture()
        appendLog("Frida Launcher initialized")
    }

    // MARK: - Logging

    /// Appends a timestamped status line (mirrors the `statusMessage` observer that
    /// prefixed each message with `[HH:mm:ss]`).
    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("[\(formatter.string(from: Date()))] \(message)")
    }

    func clearLogs() {
        logLines = []
        appendLog("Logs cleared")
    }

    var logText: String { logLines.joined(separator: "\n") }

    // MARK: - Status

    func checkStatus() {
        Task {
            isLoading = true
            appendLog("Checking Frida server status...")

            let installed = await FridaEngine.isFridaServerInstalled()
            isServerInstalled = installed

            let version = await FridaEngine.installedFridaVersion()
            installedVersion = version ?? "Unknown"

            if installed {
                rootAccessStatus = .available
                let running = await FridaEngine.isFridaServerRunning()
                isServerRunning = running
                appendLog("Frida server \(installedVersion) is installed and \(running ? "running" : "not running")")
            } else {
                isServerRunning = false
                // A fresh device may simply not have the binary yet; only flag missing
                // root when a privileged probe actually fails.
                let hasRoot = await FridaEngine.isRootAvailable()
                rootAccessStatus = hasRoot ? .nonRootMode : .notAvailable
                appendLog(hasRoot ? "Frida server is not installed" : "Root access not available")
            }

            isLoading = false
        }
    }

    func loadAvailableReleases() {
        Task {
            isLoading = true
            appendLog("Loading available Frida releases...")

            let releases = await FridaEngine.availableReleases()
            availableReleases = releases

            if !releases.isEmpty {
                if selectedVersion == nil { selectedVersion = releases.first?.version }
                appendLog("Loaded \(releases.count) Frida releases")
            } else {
                appendLog("No Frida releases found")
            }
            isLoading = false
        }
    }

    // MARK: - Version selection

    func setSelectedVersion(_ version: String) {
        selectedVersion = version
        isCustomVersion = false
    }

    func setCustomVersion(_ version: String) {
        guard FridaEngine.isValidVersionFormat(version) else {
            appendLog("Invalid version format. Use format like: 16.5.9")
            return
        }
        selectedVersion = version
        isCustomVersion = true
        appendLog("Custom version set: \(version)")
    }

    // MARK: - Install

    func downloadAndInstallFridaServer() {
        Task {
            isLoading = true
            guard let version = selectedVersion else {
                appendLog("No version selected")
                isLoading = false
                return
            }
            appendLog("Fetching Frida server \(version)...")

            // Use the URL from the selected list entry, or construct one for a custom-typed
            // version. (Both are GitHub release-asset URLs; the download validates it.)
            let url: String?
            if let listedURL = availableReleases.first(where: { $0.version == version })?.assets.first?.downloadURL {
                url = listedURL
            } else {
                url = await FridaEngine.fridaServerURL(version: version, architecture: selectedArchitecture)
            }

            guard let downloadURL = url else {
                appendLog("Couldn't resolve a download URL for Frida \(version).")
                isLoading = false
                return
            }

            appendLog("Downloading Frida server \(version)...")
            guard let fridaFile = await FridaEngine.downloadFridaServer(from: downloadURL) else {
                appendLog("Failed to download Frida \(version) — this version may not provide an iOS build.")
                isLoading = false
                return
            }

            appendLog("Installing Frida server \(version)...")
            let installed = await FridaEngine.installFridaServer(from: fridaFile, version: version)
            if installed {
                appendLog("Frida server \(version) installed successfully")
                isServerInstalled = true
                installedVersion = version
            } else {
                appendLog("Failed to install Frida server")
            }

            try? FileManager.default.removeItem(at: fridaFile)
            isLoading = false
        }
    }

    // MARK: - Lifecycle

    func startFridaServer() {
        Task {
            isLoading = true
            appendLog("Starting Frida server...")
            let started = await FridaEngine.startFridaServer()
            if started {
                appendLog("Frida server started successfully")
                isServerRunning = true
            } else {
                appendLog("Failed to start Frida server")
            }
            isLoading = false
        }
    }

    func startFridaServerWithCustomFlags(_ flags: String) {
        let sanitized = sanitizeFlags(flags)
        lastCustomFlags = sanitized
        Task {
            isLoading = true
            appendLog("Starting Frida server with custom flags: \(sanitized)")
            let started = await FridaEngine.startFridaServer(withFlags: sanitized)
            if started {
                appendLog("Frida server started successfully with flags: \(sanitized)")
                isServerRunning = true
            } else {
                appendLog("Failed to start Frida server with flags: \(sanitized)")
            }
            isLoading = false
        }
    }

    func stopFridaServer() {
        Task {
            isLoading = true
            appendLog("Stopping Frida server...")
            let stopped = await FridaEngine.stopFridaServer()
            if stopped {
                appendLog("Frida server stopped successfully")
                isServerRunning = false
            } else {
                appendLog("Failed to stop Frida server")
            }
            isLoading = false
        }
    }

    func uninstallFridaServer() {
        Task {
            isLoading = true
            appendLog("Uninstalling Frida server...")
            let uninstalled = await FridaEngine.uninstallFridaServer()
            if uninstalled {
                appendLog("Frida server uninstalled successfully")
                isServerInstalled = false
                isServerRunning = false
            } else {
                appendLog("Failed to uninstall Frida server")
            }
            isLoading = false
        }
    }

    /// Strips shell metacharacters, mirroring the Android `sanitizeFlags`.
    private func sanitizeFlags(_ flags: String) -> String {
        flags.replacingOccurrences(
            of: "[;&|<>$`\\\\]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }
}
