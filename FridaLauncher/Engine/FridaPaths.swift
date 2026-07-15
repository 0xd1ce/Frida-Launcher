import Foundation

/// Filesystem locations for the frida-server binary on a jailbroken device.
///
/// The Android app hardcoded `/data/local/tmp/frida-server`. iOS has no such path.
/// Instead we install to the same place Frida's own `re.frida.server` package uses,
/// so this app is a drop-in manager. Modern "rootless" jailbreaks (Dopamine, palera1n
/// rootless) relocate the entire system prefix under `/var/jb`; classic "rootful"
/// jailbreaks (checkra1n, unc0ver) use `/`. We detect which at runtime.
enum FridaPaths {

    /// Jailbreak root prefix: "/var/jb" on rootless, "" on rootful.
    static let jbRoot: String = {
        if FileManager.default.fileExists(atPath: "/var/jb") { return "/var/jb" }
        return ""
    }()

    /// Directory the binary lives in (created on install if missing).
    static var binDir: String { "\(jbRoot)/usr/sbin" }

    /// Full path to the frida-server binary.
    static var binaryPath: String { "\(binDir)/frida-server" }

    /// Marker file recording the installed version, analogous to the Android
    /// `/data/local/tmp/frida-version.txt`.
    static var versionFile: String { "\(jbRoot)/var/root/.frida-launcher-version" }
}
