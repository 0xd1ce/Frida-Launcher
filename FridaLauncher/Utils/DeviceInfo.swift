import Foundation

/// Device architecture / model detection.
///
/// The Android app read `Build.SUPPORTED_ABIS[0]`. On iOS every jailbreakable device
/// in circulation is 64-bit ARM, but Frida still publishes an `ios-arm` (32-bit) build,
/// so we detect the CPU type at runtime and map to the token used in the asset name.
enum DeviceInfo {

    /// Returns the architecture token that appears in Frida's iOS asset names:
    /// `frida-server-<version>-ios-<arch>.xz` where arch is `arm64` or `arm`.
    static func architecture() -> String {
        var cpuType = cpu_type_t(0)
        var size = MemoryLayout<cpu_type_t>.size
        sysctlbyname("hw.cputype", &cpuType, &size, nil, 0)

        // The 64-bit ABI capability flag (CPU_ARCH_ABI64 = 0x01000000). The imported
        // constant's type varies, so use the literal typed as cpu_type_t (Int32).
        let abi64: cpu_type_t = 0x0100_0000
        return (cpuType & abi64) != 0 ? "arm64" : "arm"
    }

    /// Hardware model identifier, e.g. "iPhone14,2". Analogous to Android's `Build.MODEL`.
    static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "iOS Device" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
