import Foundation

/// Where summaries are written. All three speak the same chat completions API; they differ in
/// what they cost, what they need installed and how good the result is
/// (docs/summary-model-choice-plan.md).
enum SummaryProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter = "openrouter"
    case builtIn = "builtin"
    case lmStudio = "lmstudio"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .builtIn:
            "Встроенная модель"
        case .openRouter:
            "OpenRouter"
        case .lmStudio:
            "LM Studio"
        }
    }
}

enum OpenRouter {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    static let defaultModel = "google/gemini-3.8-flash"
}

/// The two pinned files the built-in provider needs. Both are downloaded at runtime rather
/// than bundled: nothing third-party to re-sign, and the llama.cpp build moves on its own.
/// A value rather than a bag of constants so tests can install a synthetic pair.
struct BundledSummary: Sendable {
    let title: String
    let subtitle: String
    let llamaBuild: String
    let llamaArchiveURL: URL
    let llamaArchiveSHA256: String
    let modelFilename: String
    let modelURL: URL
    let modelSHA256: String
    let modelBytes: Int64
    /// what the app asks llama-server to serve; the server ignores it, the request needs a name
    let modelID: String

    static let current = BundledSummary(
        title: "Gemma 4 E4B",
        subtitle: "Работает без интернета. Теряет часть договорённостей и редко называет исполнителей.",
        llamaBuild: "b10819",
        llamaArchiveURL: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b10819/llama-b10819-bin-macos-arm64.tar.gz")!,
        llamaArchiveSHA256: "8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66",
        modelFilename: "gemma-4-E4B-it-Q4_0.gguf",
        modelURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/b8093469224f83f5c38f691eb906c380e9e63114/gemma-4-E4B-it-Q4_0.gguf")!,
        modelSHA256: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2",
        modelBytes: 4_590_807_392,
        modelID: "gemma-4-e4b"
    )

    /// the directory the release tarball unpacks into
    var archiveRootName: String {
        "llama-\(llamaBuild)"
    }

    /// one build per directory, so a newer pin installs beside the old one instead of over it
    func buildDirectory(_ paths: AppPaths) -> URL {
        paths.runtimeDirectory
            .appendingPathComponent("llama", isDirectory: true)
            .appendingPathComponent(llamaBuild, isDirectory: true)
    }

    func serverExecutable(_ paths: AppPaths) -> URL {
        buildDirectory(paths).appendingPathComponent("llama-server")
    }

    func modelFile(_ paths: AppPaths) -> URL {
        paths.modelsDirectory.appendingPathComponent(modelFilename)
    }

    /// written after the first successful start, when Metal has compiled and cached its shaders
    func warmUpMarker(_ paths: AppPaths) -> URL {
        buildDirectory(paths).appendingPathComponent("warm-up.ok")
    }

    func serverLog(_ paths: AppPaths) -> URL {
        paths.runtimeDirectory
            .appendingPathComponent("llama", isDirectory: true)
            .appendingPathComponent("server.log")
    }

    func isRuntimeInstalled(_ paths: AppPaths) -> Bool {
        FileManager.default.isExecutableFile(atPath: serverExecutable(paths).path)
    }

    func isModelDownloaded(_ paths: AppPaths) -> Bool {
        let size = try? FileManager.default
            .attributesOfItem(atPath: modelFile(paths).path)[.size] as? Int64
        return size == modelBytes
    }

    func isInstalled(_ paths: AppPaths) -> Bool {
        isRuntimeInstalled(paths) && isModelDownloaded(paths)
    }
}
