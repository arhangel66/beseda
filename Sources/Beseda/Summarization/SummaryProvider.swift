import Foundation

/// Where summaries are written. All three speak the same chat completions API; they differ in
/// what they cost, what they need installed and how good the result is
/// (docs/archive/summary-model-choice-plan.md).
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

/// Pinned model data and llama.cpp release; store bundles the executable, direct builds download it.
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
        subtitle: "Работает без интернета. Называет исполнителей, но может пропустить одну договорённость или мелкое поручение.",
        llamaBuild: "b10819",
        llamaArchiveURL: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b10819/llama-b10819-bin-macos-arm64.tar.gz")!,
        llamaArchiveSHA256: "8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66",
        modelFilename: "gemma-4-E4B-it-Q4_0.gguf",
        modelURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/b8093469224f83f5c38f691eb906c380e9e63114/gemma-4-E4B-it-Q4_0.gguf")!,
        modelSHA256: "a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2",
        modelBytes: 4_590_807_392,
        modelID: "gemma-4-e4b"
    )

    /// names a call's remote speakers (SpeakerNamer); same engine as the summary model
    // TODO(Mikhail): pin the URL to a commit revision like the E4B one instead of `main`
    static let speakerNames = BundledSummary(
        title: "Gemma 4 12B для имён говорящих",
        subtitle: "Узнаёт имена собеседников, когда правил не хватает. Запускается после звонка и сразу выгружается.",
        llamaBuild: current.llamaBuild,
        llamaArchiveURL: current.llamaArchiveURL,
        llamaArchiveSHA256: current.llamaArchiveSHA256,
        modelFilename: "gemma-4-12B-it-Q4_0.gguf",
        modelURL: URL(string: "https://huggingface.co/ggml-org/gemma-4-12B-it-GGUF/resolve/main/gemma-4-12B-it-Q4_0.gguf")!,
        modelSHA256: "3712b9bd32cae83a22f67ee7a4466d8d7a4f21646ac8a07d19bf9418e8767a70",
        modelBytes: 7_219_673_216,
        modelID: "gemma-4-12b"
    )

    /// Store mode is declared by the signed app plist, never inferred from a writable path.
    static var storeMode: Bool { Bundle.main.object(forInfoDictionaryKey: "BesedaStoreSummary") as? Bool == true }

    static func bundledServer(in bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Helpers/llama-server")
    }

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

    /// one per model: the two servers each truncate their own log on start
    func serverLog(_ paths: AppPaths) -> URL {
        paths.runtimeDirectory
            .appendingPathComponent("llama", isDirectory: true)
            .appendingPathComponent("server-\(modelID).log")
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
