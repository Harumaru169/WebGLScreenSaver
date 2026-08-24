import Foundation

enum SharedSettings {
    static let appGroupIdentifier = "group.kosei.haruyama.WebGLScreenSaver"
    static let timeScaleKey = "timeScale"
    static let shaderDraftSourceKey = "shaderDraftSource"
    static let shaderActiveSourceKey = "shaderActiveSource"

    private static let defaultTimeScale: Float = 0.3
    private static let timeScaleRange: ClosedRange<Float> = 0.1...3.0

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

    static var shaderDraftSource: String {
        get {
            defaults.object(forKey: shaderDraftSourceKey) as? String
                ?? ShaderResources.defaultShaderSource
        }
        set {
            defaults.set(newValue, forKey: shaderDraftSourceKey)
        }
    }

    static var shaderActiveSource: String {
        get {
            guard
                let source = defaults.object(forKey: shaderActiveSourceKey) as? String,
                !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return ShaderResources.defaultShaderSource
            }
            return source
        }
        set {
            defaults.set(newValue, forKey: shaderActiveSourceKey)
        }
    }
}

enum ShaderResources {
    private static let fallbackShader = """
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
        }
        """

    static let defaultShaderSource: String = {
        guard
            let url = Bundle.main.url(
                forResource: "DefaultShader",
                withExtension: "glsl"
            ),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallbackShader
        }
        return source
    }()

    static func runtimeHTML() throws -> String {
        guard let url = Bundle.main.url(
            forResource: "ShaderRuntime",
            withExtension: "html"
        ) else {
            throw ShaderResourceError.runtimeNotFound
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum ShaderResourceError: LocalizedError {
    case runtimeNotFound

    var errorDescription: String? {
        switch self {
        case .runtimeNotFound:
            return "ShaderRuntime.html is missing from the application bundle."
        }
    }
}
