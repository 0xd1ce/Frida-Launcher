import Foundation

/// The frida-server management engine for jailbroken iOS.
///
/// On iOS, frida-server is distributed as the `re.frida.server` Debian package. Frida's
/// GitHub releases host that `.deb` for every version (`frida_<ver>_iphoneos-arm64.deb` and
/// `…-arm.deb`), which is the source used here — it gives the full version history *and*
/// keeps old versions installable (unlike build.frida.re, which only serves the latest).
/// The `.deb` is installed with `dpkg`, which also drops the launchd daemon into place.
/// Root operations go through `RootShell`; networking uses `URLSession`'s async API.
enum FridaEngine {

    static let packageName = "re.frida.server"
    // The lightweight tags endpoint (a few KB) rather than /releases (several MB of assets),
    // which is too heavy to fetch/decode reliably on older devices.
    private static let githubTagsAPI = "https://api.github.com/repos/frida/frida/tags?per_page=100"

    /// The packaging architecture Frida's repo uses: rootless jailbreaks (with /var/jb)
    /// consume `iphoneos-arm64`; classic rootful jailbreaks consume `iphoneos-arm`.
    static var packagingArch: String {
        FridaPaths.jbRoot.isEmpty ? "iphoneos-arm" : "iphoneos-arm64"
    }

    private static var dpkg: String { "\(FridaPaths.jbRoot)/usr/bin/dpkg" }
    private static var dpkgQuery: String { "\(FridaPaths.jbRoot)/usr/bin/dpkg-query" }
    private static var launchDaemonPlist: String { "\(FridaPaths.jbRoot)/Library/LaunchDaemons/re.frida.server.plist" }

    /// The GitHub release-asset download URL for a version + packaging arch.
    private static func downloadURL(version: String, arch: String) -> String {
        "https://github.com/frida/frida/releases/download/\(version)/frida_\(version)_\(arch).deb"
    }

    // MARK: - Release discovery (GitHub tags)

    /// Returns the frida version history from GitHub's tags, newest first, each with the
    /// `.deb` download URL for this device's packaging arch (URL is constructed from the
    /// release-asset naming pattern; the download step validates it).
    static func availableReleases() async -> [FridaRelease] {
        guard let url = URL(string: githubTagsAPI) else { return [] }
        struct GithubTag: Decodable { let name: String }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            let tags = try JSONDecoder().decode([GithubTag].self, from: data)
            let arch = packagingArch

            let releases = tags.map { tag -> FridaRelease in
                FridaRelease(
                    version: tag.name,
                    releaseDate: "",
                    assets: [FridaAsset(name: "frida_\(tag.name)_\(arch).deb",
                                        downloadURL: downloadURL(version: tag.name, arch: arch),
                                        architecture: arch, size: 0)],
                    isAvailable: true
                )
            }
            // Tags aren't returned in a guaranteed order; sort newest-first numerically.
            return releases.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
        } catch {
            Logger.e("Failed to load releases", error)
            return []
        }
    }

    /// The `.deb` URL for a typed/custom version (constructed from the GitHub release-asset
    /// pattern; the download step validates it exists).
    static func fridaServerURL(version: String, architecture: String) async -> String? {
        downloadURL(version: version, arch: packagingArch)
    }

    static func isValidVersionFormat(_ version: String) -> Bool {
        version.range(of: "^\\d+\\.\\d+\\.\\d+(-[a-zA-Z0-9]+)?$", options: .regularExpression) != nil
    }

    // MARK: - Download

    /// Downloads the `.deb` into the app's caches dir and returns the local file URL.
    static func downloadFridaServer(from urlString: String) async -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let destination = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("re.frida.server.deb")
            try data.write(to: destination)
            return destination
        } catch {
            Logger.e("Failed to download frida-server package", error)
            return nil
        }
    }

    // MARK: - Install / uninstall (via dpkg)

    static func installFridaServer(from fileURL: URL, version: String) async -> Bool {
        await io {
            RootShell.run("\(dpkg) -i '\(fileURL.path)'")
            saveInstalledVersionSync(version)
            return isFridaServerInstalledSync()
        }
    }

    static func uninstallFridaServer() async -> Bool {
        await io {
            if isFridaServerRunningSync() { _ = stopFridaServerSync() }
            RootShell.run("\(dpkg) -r \(packageName)")
            RootShell.run("rm -f '\(FridaPaths.versionFile)'")
            return !isFridaServerInstalledSync()
        }
    }

    // MARK: - Version bookkeeping

    @discardableResult
    static func saveInstalledVersion(_ version: String) async -> Bool {
        await io { saveInstalledVersionSync(version) }
    }

    static func installedFridaVersion() async -> String? {
        await io {
            // Prefer dpkg's record; fall back to the marker file we write on install.
            if let v = dpkgVersionSync() { return v }
            let fromFile = RootShell.run("cat '\(FridaPaths.versionFile)' 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return fromFile.isEmpty ? nil : fromFile
        }
    }

    // MARK: - Lifecycle (start / stop / status)

    static func startFridaServer() async -> Bool {
        await startFridaServer(withFlags: "")
    }

    static func startFridaServer(withFlags flags: String) async -> Bool {
        await io {
            if isFridaServerRunningSync() { return true }

            if flags.trimmingCharacters(in: .whitespaces).isEmpty {
                // Prefer the packaged launchd daemon. `bootstrap` is the modern (rootless)
                // verb; `load -w` is the legacy (rootful) one. Fall back to the raw binary.
                RootShell.run("launchctl bootstrap system '\(launchDaemonPlist)' 2>/dev/null")
                RootShell.run("launchctl load -w '\(launchDaemonPlist)' 2>/dev/null")
                Thread.sleep(forTimeInterval: 1.0)
                if isFridaServerRunningSync() { return true }
                // Fallback: run the binary directly, backgrounded and detached from stdio.
                // (No `nohup` — it may be absent on the bootstrap; a bare `&` reparents to
                // launchd and survives our shell exiting.)
                RootShell.run("'\(FridaPaths.binaryPath)' </dev/null >/dev/null 2>&1 &")
            } else {
                // Custom flags can't go through launchd, so take the daemon down and run
                // the binary directly with the flags (again, no `nohup`).
                RootShell.run("launchctl bootout system/\(packageName) 2>/dev/null")
                RootShell.run("launchctl unload '\(launchDaemonPlist)' 2>/dev/null")
                RootShell.run("'\(FridaPaths.binaryPath)' \(flags) </dev/null >/dev/null 2>&1 &")
            }
            Thread.sleep(forTimeInterval: 1.5)
            return isFridaServerRunningSync()
        }
    }

    static func stopFridaServer() async -> Bool {
        await io { stopFridaServerSync() }
    }

    static func isFridaServerInstalled() async -> Bool {
        await io { isFridaServerInstalledSync() }
    }

    static func isFridaServerRunning() async -> Bool {
        await io { isFridaServerRunningSync() }
    }

    static func isRootAvailable() async -> Bool {
        await io { RootShell.isRootAvailable() }
    }

    // MARK: - Synchronous root-shell primitives

    private static func saveInstalledVersionSync(_ version: String) -> Bool {
        RootShell.run("mkdir -p '\(FridaPaths.jbRoot)/var/root'")
        RootShell.run("printf '%s' '\(version)' > '\(FridaPaths.versionFile)'")
        return true
    }

    private static func dpkgVersionSync() -> String? {
        let v = RootShell.run("\(dpkgQuery) -W -f='${Version}' \(packageName) 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func isFridaServerInstalledSync() -> Bool {
        if dpkgVersionSync() != nil { return true }
        // Fallback: the binary is present even if dpkg's db doesn't know about it.
        return RootShell.run("[ -f '\(FridaPaths.binaryPath)' ] && echo FRIDA_INSTALLED")
            .contains("FRIDA_INSTALLED")
    }

    private static func isFridaServerRunningSync() -> Bool {
        // Primary: launchd's own view. `launchctl` is always present; a running daemon has a
        // numeric PID in column 1, a booted-out service is absent entirely. (stderr is
        // suppressed so a "not found" from any tool is never mistaken for output.)
        let listing = RootShell.run("launchctl list 2>/dev/null | grep '\(packageName)'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if listing.range(of: "^[0-9]+", options: .regularExpression) != nil { return true }

        // Secondary (covers manual/custom-flag starts that aren't a launchd service).
        // pgrep may be absent on the bootstrap, so suppress stderr and require a PID.
        let pids = RootShell.run("pgrep -x frida-server 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if pids.range(of: "^[0-9]", options: .regularExpression) != nil { return true }

        // Tertiary: ps + bracketed grep (the bracket keeps our own grep/sh from matching).
        return RootShell.run("ps ax 2>/dev/null | grep '[f]rida-server'").contains("frida-server")
    }

    private static func stopFridaServerSync() -> Bool {
        // Tear the daemon out of launchd first so KeepAlive can't respawn frida-server.
        // `bootout` is the modern (rootless) verb; `unload -w` is the legacy (rootful) one.
        RootShell.run("launchctl bootout system/\(packageName) 2>/dev/null")
        RootShell.run("launchctl bootout system '\(launchDaemonPlist)' 2>/dev/null")
        RootShell.run("launchctl unload -w '\(launchDaemonPlist)' 2>/dev/null")
        RootShell.run("kill -9 $(pgrep -x frida-server) 2>/dev/null")
        Thread.sleep(forTimeInterval: 0.6)
        if !isFridaServerRunningSync() { return true }

        RootShell.run("pkill -9 -x frida-server 2>/dev/null")
        Thread.sleep(forTimeInterval: 0.5)
        return !isFridaServerRunningSync()
    }

    // MARK: - IO helper

    /// Runs blocking work off the main actor, mirroring `withContext(Dispatchers.IO)`.
    private static func io<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .utility, operation: work).value
    }
}
