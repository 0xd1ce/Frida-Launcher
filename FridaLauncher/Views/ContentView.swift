import SwiftUI

/// Main screen — the iOS port of `MainActivity` + `activity_main.xml`.
struct ContentView: View {
    @StateObject private var viewModel = FridaViewModel()

    @State private var showCustomVersion = false
    @State private var showCustomFlags = false
    @State private var showAbout = false
    @State private var showServerNotRunningAlert = false
    @State private var versionSelection = 0  // index into releases, or count == "Custom…"

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    if viewModel.rootAccessStatus == .notAvailable { rootRequiredBanner }
                    statusCard
                    versionCard
                    if viewModel.isServerInstalled { serverControls }
                    logPanel
                    aboutButton
                }
                .padding()
            }

            if viewModel.isLoading { loadingOverlay }
        }
        .onAppear {
            viewModel.checkStatus()
            viewModel.loadAvailableReleases()
        }
        .sheet(isPresented: $showCustomVersion) {
            CustomVersionView { viewModel.setCustomVersion($0) }
        }
        .sheet(isPresented: $showCustomFlags) {
            CustomFlagsView(initialFlags: viewModel.lastCustomFlags) {
                viewModel.startFridaServerWithCustomFlags($0)
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .alert("Server Not Running", isPresented: $showServerNotRunningAlert) {
            Button("Start Server") { viewModel.startFridaServer() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frida server is not currently running.\n\nPlease start the server first before trying to stop it.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Frida Launcher")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.accentGradient)
            Text("Device: \(DeviceInfo.modelIdentifier()) (\(viewModel.selectedArchitecture))")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var rootRequiredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Root access required. This app must run on a jailbroken device with root.")
                .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.2))
        .foregroundColor(Theme.red)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status card

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                statusRow("Installed:", viewModel.isServerInstalled ? "Yes" : "No",
                          viewModel.isServerInstalled ? Theme.green : Theme.red)
                statusRow("Running:", viewModel.isServerRunning ? "Yes" : "No",
                          viewModel.isServerRunning ? Theme.green : Theme.red)
                statusRow("Version:", viewModel.installedVersion, Theme.blue)
            }
        }
    }

    private func statusRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Text(value).fontWeight(.bold).foregroundColor(color)
            Spacer()
        }
    }

    // MARK: - Version picker + install

    private var versionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Frida Version").font(.headline)

                Menu {
                    ForEach(Array(viewModel.availableReleases.enumerated()), id: \.element.id) { index, release in
                        Button(release.releaseDate.isEmpty
                               ? release.version
                               : "\(release.version)  ·  \(release.releaseDate)") {
                            versionSelection = index
                            viewModel.setSelectedVersion(release.version)
                        }
                    }
                    Divider()
                    Button("⚙️ Custom Version…") { showCustomVersion = true }
                } label: {
                    HStack {
                        Text(selectedVersionLabel)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding()
                    .background(Theme.terminal)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(viewModel.isLoading)

                HStack(spacing: 12) {
                    actionButton("Install", systemImage: "square.and.arrow.down", color: Theme.blue) {
                        viewModel.downloadAndInstallFridaServer()
                    }
                    .disabled(viewModel.isLoading || viewModel.selectedVersion == nil)

                    actionButton("Refresh", systemImage: "arrow.clockwise", color: Theme.purple) {
                        viewModel.checkStatus()
                        viewModel.loadAvailableReleases()
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private var selectedVersionLabel: String {
        if viewModel.isCustomVersion, let v = viewModel.selectedVersion { return "\(v)  (custom)" }
        return viewModel.selectedVersion ?? "Select a version"
    }

    // MARK: - Server controls (visible only when installed)

    private var serverControls: some View {
        card {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton("Start", systemImage: "play.fill", color: Theme.green) {
                        if viewModel.isServerRunning {
                            viewModel.appendLog("Server is already running. Stop it first.")
                        } else {
                            viewModel.startFridaServer()
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isServerRunning)

                    actionButton("Custom", systemImage: "slider.horizontal.3", color: Theme.green) {
                        if viewModel.isServerRunning {
                            viewModel.appendLog("Server is already running. Stop it first.")
                        } else {
                            showCustomFlags = true
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isServerRunning)
                }
                HStack(spacing: 12) {
                    actionButton("Stop", systemImage: "stop.fill", color: Theme.red) {
                        if viewModel.isServerRunning {
                            viewModel.stopFridaServer()
                        } else {
                            showServerNotRunningAlert = true
                        }
                    }
                    .disabled(viewModel.isLoading)

                    actionButton("Uninstall", systemImage: "trash", color: Theme.orange) {
                        viewModel.uninstallFridaServer()
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - Log panel

    private var logPanel: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Logs").font(.headline)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = viewModel.logText
                    } label: { Image(systemName: "doc.on.doc") }
                    Button {
                        viewModel.clearLogs()
                    } label: { Image(systemName: "trash") }
                }
                .tint(Theme.cyan)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Theme.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(8)
                    .background(Theme.terminal)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: viewModel.logLines.count) { _ in
                        withAnimation { proxy.scrollTo(viewModel.logLines.count - 1, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var aboutButton: some View {
        Button { showAbout = true } label: {
            Label("About & Links", systemImage: "info.circle")
        }
        .tint(Theme.cyan)
        .padding(.bottom, 8)
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            ProgressView().scaleEffect(1.5).tint(Theme.cyan)
        }
    }

    // MARK: - Reusable building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
