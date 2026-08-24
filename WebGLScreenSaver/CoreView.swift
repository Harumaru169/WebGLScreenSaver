import SwiftUI
import WebKit

struct CoreView: View {
    let runtime: ShaderRuntimeController

    let shaderSource: String
    var showsDiagnostics = true

    var body: some View {
        ShaderWebView(webView: runtime.webView)
            .background(Color.black)
            .overlay {
                if showsDiagnostics,
                   case .runtimeError(let message) = runtime.state {
                    runtimeDiagnostic(message)
                }
            }
            .task(id: shaderSource) {
                _ = await runtime.prepareAndCompile(source: shaderSource)
            }
            .onAppear {
                Task {
                    await runtime.setRunning(true)
                    await runtime.setTimeScale(Double(SharedSettings.timeScale))
                }
            }
            .onDisappear {
                Task {
                    await runtime.setRunning(false)
                }
            }
    }

    @ViewBuilder
    private func runtimeDiagnostic(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text("WebGL runtime error")
                .font(.headline)
            Text(message)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

private struct ShaderWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct StandaloneShaderView: View {
    @State private var runtime = ShaderRuntimeController()

    var body: some View {
        CoreView(
            runtime: runtime,
            shaderSource: SharedSettings.shaderActiveSource,
            showsDiagnostics: true
        )
    }
}

#Preview {
    StandaloneShaderView()
        .frame(width: 640, height: 480)
}
