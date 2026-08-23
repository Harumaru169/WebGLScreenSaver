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
}
