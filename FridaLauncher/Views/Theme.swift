import SwiftUI

/// The vibrant cyan/purple palette introduced in Frida Launcher v2.0.
enum Theme {
    static let cyan = Color(red: 0.0, green: 0.85, blue: 0.9)
    static let purple = Color(red: 0.55, green: 0.35, blue: 0.95)
    static let green = Color(red: 0.2, green: 0.75, blue: 0.4)
    static let red = Color(red: 0.9, green: 0.25, blue: 0.3)
    static let blue = Color(red: 0.2, green: 0.5, blue: 0.95)
    static let orange = Color(red: 0.95, green: 0.55, blue: 0.15)

    static let background = Color(red: 0.06, green: 0.07, blue: 0.10)
    static let card = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let terminal = Color(red: 0.03, green: 0.04, blue: 0.06)

    static let accentGradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .leading,
        endPoint: .trailing
    )
}
