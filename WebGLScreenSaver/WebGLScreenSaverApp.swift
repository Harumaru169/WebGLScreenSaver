//  Host application for the screensaver extension. The host app exists so the
//  .appex can be bundled and registered with pluginkit; macOS does not load
//  appex bundles that aren't embedded inside an application.
//

import SwiftUI

@main
struct WebGLScreenSaverApp: App {
    var body: some Scene {
        Window("WebGLScreenSaver", id: "main") {
            WindowMainView()
        }
        .defaultSize(width: 1_280, height: 800)

        Window("Preview", id: "preview") {
            StandaloneShaderView()
                .ignoresSafeArea()
        }
        .defaultSize(width: 640, height: 480)
    }
}
