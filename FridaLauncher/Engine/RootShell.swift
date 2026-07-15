import Foundation
import Darwin

/// Runs shell commands as **root** on a jailbroken device from a TrollStore-installed app.
///
/// A TrollStore app launches as `mobile` (uid 501), so `setuid(0)` doesn't work. Instead —
/// exactly as TrollStore's own `spawnRoot` helper does — we `posix_spawn` `/bin/sh` with
/// *persona* attributes that make the child process run as root (uid/gid 0). This requires
/// the app to be unsandboxed (`com.apple.private.security.no-container`) and to hold the
/// `com.apple.private.persona-mgmt` entitlement; both are in entitlements.plist and are
/// preserved by TrollStore on install.
///
/// Note: iOS 17.6 / 18.0 added a mitigation blocking non-root processes from spawning root
/// via persona. This works on iOS < 17.6 (e.g. the iPhone 6s on 15.8.3).
enum RootShell {

    // The persona spawnattr setters are private (not in the iOS SDK), so resolve them at
    // runtime with dlsym rather than link against them.
    private typealias SetPersonaNp = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, uid_t, UInt32) -> Int32
    private typealias SetPersonaId = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, uid_t) -> Int32

    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    private static let setPersona: SetPersonaNp? = symbol("posix_spawnattr_set_persona_np")
    private static let setPersonaUid: SetPersonaId? = symbol("posix_spawnattr_set_persona_uid_np")
    private static let setPersonaGid: SetPersonaId? = symbol("posix_spawnattr_set_persona_gid_np")

    private static func symbol<T>(_ name: String) -> T? {
        guard let ptr = dlsym(rtldDefault, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    /// Retained for call sites; root is now acquired per-command via persona spawn, so this
    /// is a no-op.
    static func ensureRoot() {}

    /// True when we can actually execute privileged commands (spawned child reports uid=0).
    static func isRootAvailable() -> Bool {
        run("id").contains("uid=0")
    }

    /// Executes `command` through `/bin/sh -c` **as root** and returns combined stdout+stderr.
    /// A GUI app inherits a sparse PATH that omits the jailbreak's binary dirs, so bare
    /// commands (`id`, `pgrep`, `kill`, `launchctl`, …) resolve to "not found". Prepend a
    /// PATH covering both rootless (/var/jb) and rootful locations. /var/jb comes first so
    /// the jailbreak's launchctl shim wins on rootless.
    private static let searchPath =
        "/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

    @discardableResult
    static func run(_ command: String) -> String {
        let shell = shellPath()
        let argv = [shell, "-c", "export PATH=\(searchPath); \(command)"]

        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgv.append(nil)
        defer { for ptr in cArgv where ptr != nil { free(ptr) } }

        var outPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { return "" }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, outPipe[1])
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Persona attributes → run the child as root (uid/gid 0).
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        let personaOverride: UInt32 = 1  // POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
        _ = setPersona?(&attr, 99, personaOverride)
        _ = setPersonaUid?(&attr, 0)
        _ = setPersonaGid?(&attr, 0)

        var pid: pid_t = 0
        let status = posix_spawn(&pid, shell, &fileActions, &attr, cArgv, environ)

        close(outPipe[1])
        guard status == 0 else {
            close(outPipe[0])
            return ""
        }

        var output = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let n = read(outPipe[0], &buffer, bufferSize)
            if n <= 0 { break }
            output.append(buffer, count: n)
        }
        close(outPipe[0])

        var waitStatus: Int32 = 0
        waitpid(pid, &waitStatus, 0)

        return String(data: output, encoding: .utf8) ?? ""
    }

    /// Prefers the jailbreak-provided shell; falls back to the classic rootful location.
    private static func shellPath() -> String {
        let candidates = ["\(FridaPaths.jbRoot)/bin/sh", "/bin/sh", "/var/jb/bin/sh"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/bin/sh"
    }
}
