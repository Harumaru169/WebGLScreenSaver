import Foundation
import os.log

/// Logging configuration shared between the host app and the screensaver extension.
///
/// Open Console.app and filter by:
///   subsystem == "kosei.haruyama.WebGLScreenSaver"
/// to see logs from the host app and the appex extension at the same time. Every
/// log entry's category and PID make it clear which process the line came from.
enum AppexLog {
    static let subsystem = "kosei.haruyama.WebGLScreenSaver"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static let shaderRuntimeLogger = Self.logger("ShaderRuntime")

    static let hostAppLogger = Self.logger("HostApp")

    static let pluginManagerLogger = Self.logger("PluginManager")

    static let extensionLogger = Self.logger("Extension")

    static let viewControllerLogger = Self.logger("ViewController")

    static let viewLogger = Self.logger("View")

    static let configurationLogger = Self.logger("Configuration")
}
