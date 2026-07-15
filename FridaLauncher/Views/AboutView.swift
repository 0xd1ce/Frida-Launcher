import SwiftUI

/// About / links sheet (mirrors `showExpandedAboutDialog`).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    link("Report an issue", "globe", "https://github.com/0xd1ce/Frida-Launcher/issues")
                }
                Section {
                    Text("Frida Launcher for jailbroken iOS — manage frida-server with a single tap.\n\nProject forked from [TheCyberSandeep](https://github.com/thecybersandeep/Frida-Launcher) ❤️")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .tint(Theme.cyan)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func link(_ title: String, _ icon: String, _ urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { UIApplication.shared.open(url) }
        } label: {
            Label(title, systemImage: icon).tint(Theme.cyan)
        }
    }
}
