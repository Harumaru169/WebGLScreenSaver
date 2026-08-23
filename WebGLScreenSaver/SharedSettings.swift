import Foundation

enum SharedSettings {
    static let appGroupIdentifier = "group.kosei.haruyama.WebGLScreenSaver"
    static let timeScaleKey = "timeScale"

    private static let defaultTimeScale: Float = 1.0
    private static let timeScaleRange: ClosedRange<Float> = 1.0...3.0

    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            preconditionFailure(
                "Unable to open the shared UserDefaults suite: \(appGroupIdentifier)"
            )
        }

        defaults.register(defaults: [timeScaleKey: defaultTimeScale])
        return defaults
    }()

    static var timeScale: Float {
        get {
            min(
                max(defaults.float(forKey: timeScaleKey), timeScaleRange.lowerBound),
                timeScaleRange.upperBound
            )
        }
        set {
            defaults.set(
                min(max(newValue, timeScaleRange.lowerBound), timeScaleRange.upperBound),
                forKey: timeScaleKey
            )
        }
    }
}
