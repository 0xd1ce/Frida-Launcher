import SwiftUI

/// Sheet for entering an arbitrary Frida version (mirrors `showCustomVersionDialog`).
struct CustomVersionView: View {
    @Environment(\.dismiss) private var dismiss
    let onSet: (String) -> Void

    @State private var version = ""
    @State private var error: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter version (e.g., 16.7.19, 16.5.9)")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                TextField("16.5.9", text: $version)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let error {
                    Text(error).font(.footnote).foregroundColor(Theme.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Custom Frida Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        let trimmed = version.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { error = "Please enter a version number"; return }
                        guard FridaEngine.isValidVersionFormat(trimmed) else {
                            error = "Invalid version format. Use format like: 16.5.9"; return
                        }
                        onSet(trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}
