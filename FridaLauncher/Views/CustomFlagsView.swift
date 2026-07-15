import SwiftUI

/// Sheet for starting frida-server with custom flags (mirrors `showCustomFlagsDialog`
/// and `showFlagsHelpDialog`).
struct CustomFlagsView: View {
    @Environment(\.dismiss) private var dismiss
    let initialFlags: String
    let onStart: (String) -> Void

    @State private var flags = ""
    @State private var showHelp = false

    /// The flag reference shown in the help sheet (same list as the Android app).
    private let flagItems: [(String, String)] = [
        ("-l, --listen=ADDRESS", "Listen on ADDRESS (e.g., 0.0.0.0:27042)"),
        ("--certificate=CERT", "Enable TLS using CERTIFICATE"),
        ("--origin=ORIGIN", "Only accept requests with Origin header"),
        ("--token=TOKEN", "Require authentication using TOKEN"),
        ("--asset-root=ROOT", "Serve static files inside ROOT"),
        ("-d, --directory=DIR", "Store binaries in DIRECTORY"),
        ("-D, --daemonize", "Detach and become a daemon"),
        ("--policy-softener=TYPE", "Select policy softener"),
        ("-P, --disable-preload", "Disable preload optimization"),
        ("-C, --ignore-crashes", "Disable native crash reporter")
    ]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Flags passed to frida-server")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                TextField("-l 0.0.0.0:27042", text: $flags)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                Button {
                    showHelp = true
                } label: {
                    Label("Available flags", systemImage: "questionmark.circle")
                }
                .tint(Theme.cyan)

                Spacer()
            }
            .padding()
            .navigationTitle("Run with Custom Flags")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { flags = initialFlags }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(flags.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showHelp) {
                FlagsHelpView(flagItems: flagItems)
            }
        }
    }
}

/// Read-only reference list of frida-server flags.
struct FlagsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    let flagItems: [(String, String)]

    var body: some View {
        NavigationView {
            List(flagItems, id: \.0) { flag, description in
                VStack(alignment: .leading, spacing: 4) {
                    Text(flag)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Available Flags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
