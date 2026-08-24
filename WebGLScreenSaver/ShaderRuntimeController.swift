import Combine
import Foundation
import os
import WebKit

struct ShaderCompileResult: Equatable {
    let success: Bool
    let log: String
    let kind: String

    static func runtimeFailure(_ message: String) -> ShaderCompileResult {
        ShaderCompileResult(success: false, log: message, kind: "runtime")
    }
}

enum ShaderFrameDriver: String, Codable {
    case requestAnimationFrame = "raf"
    case manual
}

struct ShaderRuntimeDiagnostics: Decodable, Equatable {
    let canvasWidth: Int
    let canvasHeight: Int
    let devicePixelRatio: Double
    let frame: Int
    let running: Bool
    let hasWebGL2: Bool
    let hasProgram: Bool
    let documentVisibility: String
    let frameDriver: ShaderFrameDriver
}

enum ShaderRuntimeState: Equatable {
    case idle
    case loading
    case ready
    case rendering
    case compileError(String)
    case runtimeError(String)

    var diagnosticMessage: String? {
        switch self {
        case .compileError(let message), .runtimeError(let message):
            return message
        case .idle, .loading, .ready, .rendering:
            return nil
        }
    }
}

private struct ShaderRuntimeResponse: Decodable {
    let success: Bool
    let log: String
    let kind: String
}

@MainActor
final class ShaderRuntimeController: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var state: ShaderRuntimeState = .idle
    @Published private(set) var lastCompileResult: ShaderCompileResult?

    private let logger = AppexLog.shaderRuntimeLogger
    private let diagnosticLabel: String
    private var preparationTask: Task<Void, Error>?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var isPrepared = false
    private var isRecovering = false
    private var hasAttemptedRuntimeRecovery = false
    private var lastRenderableSource: String?
    private var desiredRunning = true
    private var desiredTimeScale = Double(SharedSettings.timeScale)
    private var desiredFrameDriver = ShaderFrameDriver.requestAnimationFrame

    override convenience init() {
        self.init(diagnosticLabel: "host")
    }

    init(diagnosticLabel: String) {
        self.diagnosticLabel = diagnosticLabel
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.inactiveSchedulingPolicy = .none

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .black
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.black.cgColor
        logger.info("[\(diagnosticLabel, privacy: .public)] WKWebView initialized with non-persistent storage")
    }

    func prepare() async throws {
        if isPrepared {
            return
        }
        if let preparationTask {
            try await preparationTask.value
            return
        }

        logger.info("[\(self.diagnosticLabel, privacy: .public)] preparing HTML runtime")
        let task = Task { @MainActor [self] in
            try await loadRuntimeWithOneRetry()
        }
        preparationTask = task

        do {
            try await task.value
            preparationTask = nil
            let diagnostics = try await callDiagnostics()
            logger.info(
                "[\(self.diagnosticLabel, privacy: .public)] WebGL runtime ready webgl2=\(diagnostics.hasWebGL2, privacy: .public) canvas=\(diagnostics.canvasWidth, privacy: .public)x\(diagnostics.canvasHeight, privacy: .public) dpr=\(diagnostics.devicePixelRatio, privacy: .public)"
            )
        } catch {
            preparationTask = nil
            let message = error.localizedDescription
            state = .runtimeError(message)
            logger.error("[\(self.diagnosticLabel, privacy: .public)] Runtime preparation failed: \(message, privacy: .public)")
            throw error
        }
    }

    func prepareAndCompile(source: String) async -> ShaderCompileResult {
        let result = await compile(source: source)
        guard result.success else {
            return result
        }
        await setTimeScale(desiredTimeScale)
        await setFrameDriver(desiredFrameDriver)
        await setRunning(desiredRunning)
        return result
    }

    func compile(source: String) async -> ShaderCompileResult {
        logger.info("[\(self.diagnosticLabel, privacy: .public)] compiling shader source")
        do {
            try await prepare()
            var response = try await callCompile(source: source)
            if !response.success,
               response.kind == "runtime",
               !hasAttemptedRuntimeRecovery {
                response = try await recoverRuntimeAndCompile(source: source)
            }

            let result = ShaderCompileResult(
                success: response.success,
                log: response.log,
                kind: response.kind
            )
            lastCompileResult = result
            if result.success {
                lastRenderableSource = source
                state = desiredRunning ? .rendering : .ready
                logger.info("[\(self.diagnosticLabel, privacy: .public)] shader compile succeeded")
            } else {
                state = result.kind == "runtime"
                    ? .runtimeError(result.log)
                    : .compileError(result.log)
                logger.error(
                    "[\(self.diagnosticLabel, privacy: .public)] Shader compilation failed (\(result.kind, privacy: .public)): \(result.log, privacy: .public)"
                )
            }
            return result
        } catch {
            let result = ShaderCompileResult.runtimeFailure(error.localizedDescription)
            lastCompileResult = result
            state = .runtimeError(result.log)
            logger.error("[\(self.diagnosticLabel, privacy: .public)] Runtime call failed: \(result.log, privacy: .public)")
            return result
        }
    }

    func diagnostics() async throws -> ShaderRuntimeDiagnostics {
        try await prepare()
        return try await callDiagnostics()
    }

    @discardableResult
    func setFrameDriver(_ driver: ShaderFrameDriver) async -> Bool {
        desiredFrameDriver = driver
        guard isPrepared else {
            return true
        }

        do {
            let rawResult = try await webView.callAsyncJavaScript(
                "return window.shaderRuntime.setFrameDriver(driver);",
                arguments: ["driver": driver.rawValue],
                in: nil,
                contentWorld: .page
            )
            let accepted = rawResult as? Bool ?? false
            if accepted {
                logger.info(
                    "[\(self.diagnosticLabel, privacy: .public)] frameDriver=\(driver.rawValue, privacy: .public)"
                )
            }
            return accepted
        } catch {
            logger.error(
                "[\(self.diagnosticLabel, privacy: .public)] Unable to update frame driver: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Draws one frame while the JavaScript runtime is in manual mode. The
    /// caller serializes these IPC calls so a slow shader cannot build a queue.
    func renderOneFrame() async -> Bool {
        guard isPrepared, desiredRunning, desiredFrameDriver == .manual else {
            return false
        }

        do {
            let rawResult = try await webView.callAsyncJavaScript(
                "return window.shaderRuntime.renderOneFrame();",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return rawResult as? Bool ?? false
        } catch {
            return false
        }
    }

    func setRunning(_ value: Bool) async {
        desiredRunning = value
        guard isPrepared else {
            return
        }

        do {
            _ = try await webView.callAsyncJavaScript(
                "return window.shaderRuntime.setRunning(running);",
                arguments: ["running": value],
                in: nil,
                contentWorld: .page
            )
            if lastCompileResult?.success == true {
                state = value ? .rendering : .ready
            }
            logger.info(
                "[\(self.diagnosticLabel, privacy: .public)] running=\(value, privacy: .public)"
            )
        } catch {
            state = .runtimeError(error.localizedDescription)
            logger.error(
                "[\(self.diagnosticLabel, privacy: .public)] Unable to update running state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func setTimeScale(_ value: Double) async {
        guard isPrepared else {
            return
        }

        do {
            _ = try await webView.callAsyncJavaScript(
                "return window.shaderRuntime.setTimeScale(scale);",
                arguments: ["scale": value],
                in: nil,
                contentWorld: .page
            )
        } catch {
            state = .runtimeError(error.localizedDescription)
            logger.error(
                "[\(self.diagnosticLabel, privacy: .public)] Unable to update time scale: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func invalidate() {
        logger.info("[\(self.diagnosticLabel, privacy: .public)] invalidating runtime")
        desiredRunning = false
        preparationTask?.cancel()
        preparationTask = nil
        finishLoading(with: ShaderRuntimeError.runtimeInvalidated)
        webView.stopLoading()
        webView.navigationDelegate = nil
        isPrepared = false
    }

    private func loadRuntimeWithOneRetry() async throws {
        state = .loading
        let html = try ShaderResources.runtimeHTML()
        var lastError: Error?

        for attempt in 1...2 {
            do {
                logger.info(
                    "[\(self.diagnosticLabel, privacy: .public)] loading HTML runtime attempt=\(attempt, privacy: .public)"
                )
                try await load(html: html)
                isPrepared = true
                state = .ready
                return
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ShaderRuntimeError.failedToLoadRuntime
    }

    private func load(html: String) async throws {
        if loadContinuation != nil {
            throw ShaderRuntimeError.loadAlreadyInProgress
        }

        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        }
    }

    private func callCompile(source: String) async throws -> ShaderRuntimeResponse {
        let rawResult = try await webView.callAsyncJavaScript(
            "return window.shaderRuntime.compile(source);",
            arguments: ["source": source],
            in: nil,
            contentWorld: .page
        )
        guard let json = rawResult as? String else {
            throw ShaderRuntimeError.invalidJavaScriptResponse
        }
        return try JSONDecoder().decode(
            ShaderRuntimeResponse.self,
            from: Data(json.utf8)
        )
    }

    private func callDiagnostics() async throws -> ShaderRuntimeDiagnostics {
        let rawResult = try await webView.callAsyncJavaScript(
            "return window.shaderRuntime.diagnostics();",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let json = rawResult as? String else {
            throw ShaderRuntimeError.invalidJavaScriptResponse
        }
        return try JSONDecoder().decode(
            ShaderRuntimeDiagnostics.self,
            from: Data(json.utf8)
        )
    }

    private func recoverRuntimeAndCompile(
        source: String
    ) async throws -> ShaderRuntimeResponse {
        hasAttemptedRuntimeRecovery = true
        isRecovering = true
        defer { isRecovering = false }

        isPrepared = false
        try await loadRuntimeWithOneRetry()
        return try await callCompile(source: source)
    }

    private func recoverAfterContentProcessTermination() async {
        guard !isRecovering else {
            return
        }
        guard !hasAttemptedRuntimeRecovery else {
            let message = "The WebGL content process terminated after its recovery attempt."
            state = .runtimeError(message)
            logger.error("[\(self.diagnosticLabel, privacy: .public)] \(message, privacy: .public)")
            return
        }

        guard let source = lastRenderableSource else {
            let message = "The WebGL content process terminated before a shader was rendered."
            state = .runtimeError(message)
            logger.error("[\(self.diagnosticLabel, privacy: .public)] \(message, privacy: .public)")
            return
        }

        logger.warning(
            "[\(self.diagnosticLabel, privacy: .public)] The WebGL content process terminated; attempting one recovery."
        )
        do {
            let response = try await recoverRuntimeAndCompile(source: source)
            let result = ShaderCompileResult(
                success: response.success,
                log: response.log,
                kind: response.kind
            )
            lastCompileResult = result
            guard result.success else {
                state = .runtimeError(result.log)
                logger.error(
                    "[\(self.diagnosticLabel, privacy: .public)] Runtime recovery failed: \(result.log, privacy: .public)"
                )
                return
            }

            lastRenderableSource = source
            await setTimeScale(desiredTimeScale)
            await setFrameDriver(desiredFrameDriver)
            await setRunning(desiredRunning)
        } catch {
            state = .runtimeError(error.localizedDescription)
            logger.error(
                "[\(self.diagnosticLabel, privacy: .public)] Runtime recovery failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func finishLoading(with error: Error? = nil) {
        guard let continuation = loadContinuation else {
            return
        }
        loadContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

extension ShaderRuntimeController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("[\(self.diagnosticLabel, privacy: .public)] HTML runtime navigation finished")
        finishLoading()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error(
            "[\(self.diagnosticLabel, privacy: .public)] HTML runtime navigation failed: \(error.localizedDescription, privacy: .public)"
        )
        finishLoading(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error(
            "[\(self.diagnosticLabel, privacy: .public)] HTML runtime provisional navigation failed: \(error.localizedDescription, privacy: .public)"
        )
        finishLoading(with: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("[\(self.diagnosticLabel, privacy: .public)] WebKit content process terminated")
        isPrepared = false
        finishLoading(with: ShaderRuntimeError.webContentProcessTerminated)
        Task { @MainActor [weak self] in
            await self?.recoverAfterContentProcessTermination()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(["about", "data", "blob"].contains(scheme) ? .allow : .cancel)
    }
}

enum ShaderRuntimeError: LocalizedError {
    case failedToLoadRuntime
    case invalidJavaScriptResponse
    case loadAlreadyInProgress
    case runtimeInvalidated
    case webContentProcessTerminated

    var errorDescription: String? {
        switch self {
        case .failedToLoadRuntime:
            return "The WebGL runtime could not be loaded."
        case .invalidJavaScriptResponse:
            return "The WebGL runtime returned an invalid response."
        case .loadAlreadyInProgress:
            return "A WebGL runtime load is already in progress."
        case .runtimeInvalidated:
            return "The WebGL runtime was stopped."
        case .webContentProcessTerminated:
            return "The WebGL content process terminated."
        }
    }
}
