//  Main view controller for the screensaver. Specified as
//  ScreenSaverViewControllerClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).WebGLScreenSaverViewController`.

import AppKit
import ScreenSaver

@objc(WebGLScreenSaverViewController)
class WebGLScreenSaverViewController: ScreenSaverViewController {
    private let logger = AppexLog.viewControllerLogger
    
    private let instanceID = String(UUID().uuidString.prefix(8))

    /// Strong reference so the framework cannot drop the screen saver view.
    private var saverView: WebGLScreenSaverView?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        logger.info("[VC:\(self.instanceID, privacy: .public)] init(nibName:bundle:)")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        logger.info("[VC:\(self.instanceID, privacy: .public)] init(coder:)")
    }

    deinit {
        logger.info("[VC:\(self.instanceID, privacy: .public)] deinit")
    }

    /// Compatibility entry point for hosts that provide a display-specific
    /// frame. WallpaperAgent currently uses the standard `loadView()` path.
    override func loadView(forFrame frame: NSRect, isPreview: Bool) {
        logger.info(
            "[VC:\(self.instanceID, privacy: .public)] loadView(forFrame: \(frame.width, privacy: .public)x\(frame.height, privacy: .public), isPreview: \(isPreview, privacy: .public))"
        )
        installSaverView(frame: frame, isPreview: isPreview, trigger: "loadView(forFrame:isPreview:)")
    }

    /// WallpaperAgent does not resize a 1x1 service view after attachment, so a
    /// useful initial frame is required even though the remote host may scale it.
    override func loadView() {
        let fallbackFrame = NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let isPreview = fallbackFrame.width < 400
        logger.warning(
            "[VC:\(self.instanceID, privacy: .public)] loadView() fallback frame=\(fallbackFrame.width, privacy: .public)x\(fallbackFrame.height, privacy: .public) preview=\(isPreview, privacy: .public)"
        )
        installSaverView(
            frame: fallbackFrame,
            isPreview: isPreview,
            trigger: "loadView() fallback"
        )
    }

    private func installSaverView(
        frame: NSRect,
        isPreview: Bool,
        trigger: String
    ) {
        if let saverView {
            logger.warning(
                "[VC:\(self.instanceID, privacy: .public)] ignored duplicate \(trigger, privacy: .public); view=\(saverView.instanceID, privacy: .public)"
            )
            return
        }

        guard let saverView = WebGLScreenSaverView(
            frame: frame,
            isPreview: isPreview,
            controllerInstanceID: instanceID
        ) else {
            logger.error(
                "[VC:\(self.instanceID, privacy: .public)] failed to create ScreenSaverView from \(trigger, privacy: .public)"
            )
            self.view = NSView(frame: frame)
            return
        }

        self.saverView = saverView
        self.view = saverView
        logger.info(
            "[VC:\(self.instanceID, privacy: .public)] installed view=\(saverView.instanceID, privacy: .public) via \(trigger, privacy: .public)"
        )
    }
}
