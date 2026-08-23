//  Host application for the screensaver extension. The host app exists so the
//  .appex can be bundled and registered with pluginkit; macOS does not load
//  appex bundles that aren't embedded inside an application.
//

import SwiftUI

@main
struct WebGLScreenSaverApp: App {
    var body: some Scene {
        WindowGroup {
            WindowMainView()
        }

        Window("Preview", id: "preview") {
            CoreView()
                .ignoresSafeArea()
        }
        .defaultSize(width: 640, height: 480)
    }
}
