import Combine
import Foundation

@MainActor
final class ShaderSourceStore: ObservableObject {
    @Published var draftSource: String
    @Published private(set) var activeSource: String

    var hasUnappliedChanges: Bool {
        draftSource != activeSource
    }

    init() {
        draftSource = SharedSettings.shaderDraftSource
        activeSource = SharedSettings.shaderActiveSource
    }

    func persistDraft() {
        SharedSettings.shaderDraftSource = draftSource
    }

    @discardableResult
    func applyDraft(
        after compile: (String) async -> ShaderCompileResult
    ) async -> ShaderCompileResult {
        persistDraft()
        let result = await compile(draftSource)
        guard result.success else {
            return result
        }

        SharedSettings.shaderActiveSource = draftSource
        activeSource = draftSource
        return result
    }

    func revertDraft() {
        draftSource = activeSource
        persistDraft()
    }

    func resetDraftToDefault() {
        draftSource = ShaderResources.defaultShaderSource
        persistDraft()
    }
}
