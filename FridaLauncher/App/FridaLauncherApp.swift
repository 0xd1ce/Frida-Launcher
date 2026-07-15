import SwiftUI

@main
struct FridaLauncherApp: App {
    init() {
        // Elevate to root as early as possible so every subsequent shell command
        // in FridaEngine runs privileged. No-ops if already root or not permitted.
        RootShell.ensureRoot()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
