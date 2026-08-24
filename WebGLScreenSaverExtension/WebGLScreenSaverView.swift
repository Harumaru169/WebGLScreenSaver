//  ScreenSaverView hosting one WKWebView per display. WebGL animation is driven
//  by requestAnimationFrame inside the hosted page.

import Cocoa
import ScreenSaver
import WebKit

@MainActor
final class WebGLScreenSaverView: ScreenSaverView {
    private let logger = AppexLog.viewLogger
    
    let instanceID = String(UUID().uuidString.prefix(8))

    private let controllerInstanceID: String
    private var runtimeController: ShaderRuntimeController?
    private var startupTask: Task<Void, Never>?
    private var runtimeIdentity: UUID?
    private var lastLoggedSize: NSSize?

    init?(
        frame: NSRect,
        isPreview: Bool,
        controllerInstanceID: String
    ) {
        self.controllerInstanceID = controllerInstanceID
        super.init(frame: frame, isPreview: isPreview)

        logger.info(
            "\(self.logPrefix, privacy: .public) init frame=\(frame.width, privacy: .public)x\(frame.height, privacy: .public) preview=\(isPreview, privacy: .public)"
        )

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizesSubviews = true
        animationTimeInterval = 1.0 / 60.0 // screen saverのfpsを決める
    }

    override convenience init?(frame: NSRect, isPreview: Bool) {
        self.init(
            frame: frame,
            isPreview: isPreview,
            controllerInstanceID: "unknown"
        )
    }

    required init?(coder decoder: NSCoder) {
        fatalError("Not implemented.")
    }

    override func startAnimation() {
        super.startAnimation()
        logger.info("\(self.logPrefix, privacy: .public) startAnimation \(self.windowContext, privacy: .public)")
        ensureRuntimeStarted(trigger: "startAnimation")
    }

    override func stopAnimation() {
        logger.info("\(self.logPrefix, privacy: .public) stopAnimation \(self.windowContext, privacy: .public)")
        stopRuntime(trigger: "stopAnimation")
        super.stopAnimation()
    }

    override func animateOneFrame() {
        super.animateOneFrame()

        if runtimeController == nil, window != nil {
            ensureRuntimeStarted(trigger: "animateOneFrame")
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            logger.info(
                "\(self.logPrefix, privacy: .public) attached to window; \(self.windowContext, privacy: .public)"
            )
            if window?.isVisible == true {
                ensureRuntimeStarted(trigger: "viewDidMoveToWindow(visible)")
            } else {
                self.logger.info(
                    "\(self.logPrefix, privacy: .public) waiting for animation callback; remote window is not visible"
                )
            }
        } else {
            logger.info("\(self.logPrefix, privacy: .public) detached from window")
            stopRuntime(trigger: "viewDidMoveToWindow(detached)")
        }
    }

    override func layout() {
        super.layout()
        runtimeController?.webView.frame = bounds

        guard bounds.size != lastLoggedSize else {
            return
        }
        lastLoggedSize = bounds.size
        logger.info(
            "\(self.logPrefix, privacy: .public) layout logical=\(self.bounds.width, privacy: .public)x\(self.bounds.height, privacy: .public) \(self.windowContext, privacy: .public)"
        )
    }

    func ensureRuntimeStarted(trigger: String) {
        guard window != nil else {
            logger.info(
                "\(self.logPrefix, privacy: .public) deferred runtime start from \(trigger, privacy: .public); no window"
            )
            return
        }

        if let runtime = runtimeController {
            logger.info(
                "\(self.logPrefix, privacy: .public) runtime already exists from \(trigger, privacy: .public); requesting resume"
            )
            Task { @MainActor [weak self, runtime] in
                guard self?.runtimeController === runtime else {
                    return
                }
                await runtime.setRunning(true)
            }
            return
        }

        let identity = UUID()
        let runtime = ShaderRuntimeController(diagnosticLabel: "view:\(instanceID)")
        let webView = runtime.webView
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]

        let disabledOcclusionDetection = webView
            .setScreenSaverOcclusionDetectionEnabled(false)
        logger.info(
            "\(self.logPrefix, privacy: .public) creating WKWebView trigger=\(trigger, privacy: .public) occlusionDisabled=\(disabledOcclusionDetection, privacy: .public) \(self.windowContext, privacy: .public)"
        )

        addSubview(webView)
        runtimeController = runtime
        runtimeIdentity = identity

        let source = SharedSettings.shaderActiveSource
        let timeScale = Double(SharedSettings.timeScale)
        startupTask = Task { @MainActor [weak self, runtime] in
            let result = await runtime.prepareAndCompile(source: source)
            guard let self,
                  self.runtimeController === runtime,
                  self.runtimeIdentity == identity,
                  !Task.isCancelled else {
                self?.logger.info(
                    "[View:\(self?.instanceID ?? "released", privacy: .public)] discarded stale compile result"
                )
                return
            }

            self.startupTask = nil
            if result.success {
                await runtime.setTimeScale(timeScale)
                await runtime.setRunning(true)
                self.logger.info(
                    "\(self.logPrefix, privacy: .public) shader compile succeeded; rendering requested"
                )
            } else {
                self.logger.error(
                    "\(self.logPrefix, privacy: .public) shader failed kind=\(result.kind, privacy: .public) log=\(result.log, privacy: .public)"
                )
            }
        }
    }

    func stopRuntime(trigger: String) {
        startupTask?.cancel()
        startupTask = nil
        runtimeIdentity = nil

        guard let runtime = runtimeController else {
            logger.info(
                "\(self.logPrefix, privacy: .public) runtime already stopped from \(trigger, privacy: .public)"
            )
            return
        }

        runtimeController = nil
        runtime.webView.removeFromSuperview()
        runtime.invalidate()
        logger.info(
            "\(self.logPrefix, privacy: .public) stopped runtime from \(trigger, privacy: .public)"
        )
    }

    deinit {
        startupTask?.cancel()
        logger.info(
            "[VC:\(self.controllerInstanceID, privacy: .public) View:\(self.instanceID, privacy: .public)] deinit"
        )
    }

    private var logPrefix: String {
        "[VC:\(controllerInstanceID) View:\(instanceID)]"
    }

    private var windowContext: String {
        guard let window else {
            return "window=none"
        }

        let screen = window.screen
        let screenName = screen?.localizedName ?? "unknown"
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (screen?.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value
        let displayIDText = displayID.map(String.init) ?? "unknown"
        let screenSize = screen?.frame.size ?? .zero
        return "window=\(window.windowNumber) visible=\(window.isVisible) reportedScreen=\(screenName)#\(displayIDText) reportedScreenLogical=\(screenSize.width)x\(screenSize.height) backingScale=\(window.backingScaleFactor) preview=\(isPreview)"
    }
}

private extension WKWebView {
    /// ScreenSaver's remote view hierarchy is reported to WebKit as occluded,
    /// which otherwise suspends JavaScript and requestAnimationFrame.
    @discardableResult
    func setScreenSaverOcclusionDetectionEnabled(_ enabled: Bool) -> Bool {
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard responds(to: selector), let implementation = method(for: selector) else {
            return false
        }

        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setter = unsafeBitCast(implementation, to: Setter.self)
        setter(self, selector, enabled)
        return true
    }
}
