import AppKit
import SwiftUI

private let logger = AppexLog.hostAppLogger

@MainActor
struct WindowMainView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var pluginManager = PluginManager()
    @State private var sourceStore = ShaderSourceStore()
    @State private var shaderRuntime = ShaderRuntimeController()

    @State private var statusMessage = "Ready"
    @State private var shaderMessage = "Showing the applied shader."
    @State private var shaderLog = ""
    @State private var timeScale = SharedSettings.timeScale
    @State private var isApplying = false
    @State private var draftSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 14) {
            extensionControls

            HSplitView {
                shaderEditor
                    .frame(minWidth: 440, idealWidth: 560)
                    .padding(.trailing, 5)
                previewPanel
                    .frame(minWidth: 480, idealWidth: 680)
                    .padding(.leading, 5)
            }
        }
        .padding(16)
        .frame(minWidth: 1_000, minHeight: 680)
        .onChange(of: sourceStore.draftSource) { _, _ in
            scheduleDraftSave()
        }
        .onDisappear {
            draftSaveTask?.cancel()
            sourceStore.persistDraft()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("WebGL ScreenSaver")
                    .font(.title.bold())
                Text("Compatible with [Shadertoy](https://www.shadertoy.com/)")
                    .font(.caption)
            }
            Spacer()
        }
    }

    private var extensionControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if pluginManager.isInstalled {
                        Button("Uninstall") {
                            uninstallExtension()
                        }
                    } else {
                        Button("Install") {
                            installExtension()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Enable as Screen Saver") {
                        Task {
                            await pluginManager.enableAsScreensaver()
                        }
                    }
                    .disabled(
                        !pluginManager.isInstalled
                            || pluginManager.isActiveScreensaver
                            || pluginManager.isCheckingScreensaver
                    )

                    statusBadge(
                        title: pluginManager.isInstalled ? "Installed" : "Not Installed",
                        color: pluginManager.isInstalled ? .green : .gray
                    )
                    statusBadge(
                        title: pluginManager.isActiveScreensaver ? "Active" : "Not Active",
                        color: pluginManager.isActiveScreensaver ? .green : .gray
                    )

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    if pluginManager.isLoading
                        || pluginManager.isCheckingScreensaver {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        pluginManager.checkInstallationStatus()
                        pluginManager.checkScreensaverStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh extension status")
                }

                if let path = pluginManager.installedPath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if let error = pluginManager.lastError
                    ?? pluginManager.screensaverError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(4)
        } label: {
            Text("Screen Saver Extension").font(.headline)
        }
    }

    private var shaderEditor: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(sourceStore.hasUnappliedChanges ? .orange : .green)
                        .frame(width: 9, height: 9)
                    Text(
                        sourceStore.hasUnappliedChanges
                            ? "Draft has unapplied changes"
                            : "Draft matches the applied shader"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                }

                TextEditor(text: $sourceStore.draftSource)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }

                HStack(spacing: 8) {
                    Button("Apply") {
                        applyShader()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying || !sourceStore.hasUnappliedChanges)

                    Button("Revert") {
                        sourceStore.revertDraft()
                        shaderMessage = "Draft reverted to the applied shader."
                        shaderLog = ""
                    }
                    .disabled(isApplying || !sourceStore.hasUnappliedChanges)

                    Button("Reset to default") {
                        sourceStore.resetDraftToDefault()
                        shaderMessage = "Default shader loaded into the draft. Apply to activate it."
                        shaderLog = ""
                    }
                    .disabled(isApplying)

                    Spacer()

                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(shaderMessage)
                        .font(.caption)
                        .foregroundStyle(shaderLog.isEmpty ? .secondary : .primary)

                    if !shaderLog.isEmpty {
                        ScrollView {
                            Text(shaderLog)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(4)
        } label: {
            HStack {
                Text("GLSL Source").font(.headline)
                Text("Compatible with [Shadertoy](https://www.shadertoy.com/)")
                    .font(.caption)
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Applied Shader Preview").font(.headline)

                Spacer()
                runtimeStateLabel
            }
                CoreView(
                    runtime: shaderRuntime,
                    shaderSource: sourceStore.activeSource,
                    showsDiagnostics: true
                )
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        openWindow(id: "preview")
                    } label: {
                        Label("Open in Preview Window", systemImage: "macwindow.on.rectangle")
                    }
                    .buttonStyle(.glass)
                    .padding(5)
                }

                HStack(spacing: 10) {
                    Text("Time Scale")
                    Slider(value: $timeScale, in: 0.1...3.0, step: 0.1)
                    Text("\(timeScale, specifier: "%.1f")×")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                .onChange(of: timeScale) { _, newValue in
                    SharedSettings.timeScale = newValue
                    Task {
                        await shaderRuntime.setTimeScale(Double(newValue))
                    }
                }
        }.padding(4)
    }

    private var runtimeStateLabel: some View {
        Group {
            switch shaderRuntime.state {
            case .idle:
                Text("Idle")
            case .loading:
                Text("Loading…")
            case .ready:
                Text("Ready")
            case .rendering:
                Text("Rendering")
            case .compileError:
                Text("Compile Error")
                    .foregroundStyle(.red)
            case .runtimeError:
                Text("Runtime Error")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statusBadge(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else {
                return
            }
            sourceStore.persistDraft()
        }
    }

    private func applyShader() {
        isApplying = true
        shaderMessage = "Compiling shader…"
        shaderLog = ""

        Task {
            let result = await sourceStore.applyDraft { source in
                await shaderRuntime.compile(source: source)
            }
            shaderLog = result.log
            shaderMessage = result.success
                ? "Shader compiled and applied successfully."
                : "The draft was not applied. The previous shader is still active."
            isApplying = false
        }
    }

    private func installExtension() {
        statusMessage = "Installing extension…"
        do {
            try pluginManager.install()
            statusMessage = "Extension installed successfully."
        } catch {
            statusMessage = "Install failed: \(error.localizedDescription)"
            logger.error(
                "Install failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func uninstallExtension() {
        statusMessage = "Uninstalling extension…"
        do {
            try pluginManager.uninstall()
            statusMessage = "Extension uninstalled successfully."
        } catch {
            statusMessage = "Uninstall failed: \(error.localizedDescription)"
            logger.error(
                "Uninstall failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func openScreenSaverSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    WindowMainView()
}
