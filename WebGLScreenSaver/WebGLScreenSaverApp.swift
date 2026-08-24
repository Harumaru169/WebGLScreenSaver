//  Host application for the screensaver extension. The host app exists so the
//  .appex can be bundled and registered with pluginkit; macOS does not load
//  appex bundles that aren't embedded inside an application.
//

import SwiftUI

@main
struct WebGLScreenSaverApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("WebGL Screen Saver", id: "main") {
            WindowMainView()
                .presentedWindowToolbarStyle(.unified)
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button {
                    openWindow(id: "about")
                } label: {
                    Text("About WebGL Screen Saver")
                }
            }
        }

        Window("Preview", id: "preview") {
            StandaloneShaderView()
                .ignoresSafeArea()
                .presentedWindowToolbarStyle(.unified)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 480)

        Window("About WebGL Screen Saver", id: "about") {
            AboutView()
                .toolbar(removing: .title)
                .toolbarBackground(.hidden, for: .windowToolbar)
                .containerBackground(.ultraThickMaterial, for: .window)
                .windowMinimizeBehavior(.disabled)
        }
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}
