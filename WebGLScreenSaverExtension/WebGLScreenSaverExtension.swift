
//  Principal class for the screensaver extension. Specified as
//  NSExtensionPrincipalClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).WebGLScreenSaverExtension`.
//
//  Following Apple's own screensavers (e.g. Arabesque.appex) we keep this
//  minimal — only implement init() and let the framework drive lifecycle.
//

import Foundation
import ScreenSaver

private let logger = AppexLog.logger("Extension")

@objc(WebGLScreenSaverExtension)
class WebGLScreenSaverExtension: ScreenSaverExtension {

    @objc override init() {
        logger.info("WebGLScreenSaverExtension.init() PID=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        super.init()
    }

    deinit {
        logger.info("WebGLScreenSaverExtension.deinit")
    }
}
