//  ScreenSaverView that displays the rainbow color animation. The actual
//  animation logic lives in RainbowAnimator (shared with the host app's
//  PreviewView).
//
//  Two equally valid rendering options exist for an Appex screensaver:
//    1. Direct CALayer animation driven by your own Timer or CABasicAnimation
//       (this sample's approach — see RainbowAnimator).
//    2. The traditional ScreenSaverView overrides (startAnimation,
//       stopAnimation, animateOneFrame). Both work; pick whichever fits
//       your animation model.
//
//  SwiftUI can also be used for screensaver content via NSHostingView: create
//  the SwiftUI root view, wrap it in NSHostingView, and add it as a subview
//  of this ScreenSaverView. The Aerial screensaver uses this pattern for
//  weather/clock overlays on top of video playback.
//

import Cocoa
import ScreenSaver
import SwiftUI

private let logger = AppexLog.logger("View")

final class WebGLScreenSaverView: ScreenSaverView {
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        logger.info(
            "init(frame: \(frame.size.width, privacy: .public)x\(frame.size.height, privacy: .public), isPreview: \(isPreview))"
        )

        // Enable layer-backed view for better rendering compatibility with SwiftUI
        wantsLayer = true

        let timeView = CoreView()
        let hostingController = NSHostingController(rootView: timeView)

        // Set frame directly to bounds and enable autoresizing
        hostingController.view.frame = bounds
        hostingController.view.autoresizingMask = [.width, .height]
        addSubview(hostingController.view)
    }

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        fatalError("Not implemented.")
    }

    deinit {
        logger.info("deinit")
    }
}
