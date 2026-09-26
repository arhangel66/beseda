import Foundation

/// What `resolve` settled on: a server that answered and a model to send the request to.
struct SummaryConnection: Sendable {
    let baseURL: URL
    let model: String
}

/// LM Studio's CLI and local server; without it there is no model to call.
enum LocalModelSupport {
    static func lmsExecutable() throws -> URL {
        let expandedHomePath = ("~/.cache/lm-studio/bin/lms" as NSString).expandingTildeInPath
        return try ExecutableResolver.resolve(["lms", expandedHomePath])
    }

    static var isInstalled: Bool {
        (try? lmsExecutable()) != nil
    }

    static func discoverServer() async throws -> URL? {
        let lms = try lmsExecutable()
        let output = try await ProcessRunner.output(
            executableURL: lms,
            arguments: ["server", "status", "--json"],
            currentDirectoryURL: nil
        )
        let status = try JSONDecoder().decode(ServerStatus.self, from: Data(output.utf8))
        guard status.running else {
            return nil
        }
        return URL(string: "http://localhost:\(status.port)/v1")
    }

    static func startServer() async throws {
        try await ProcessRunner.run(
            executableURL: try lmsExecutable(),
            arguments: ["server", "start"],
            currentDirectoryURL: nil
        )
    }

    static func chatModels(at baseURL: URL) async throws -> [String] {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("models"))
        return try JSONDecoder().decode(ModelList.self, from: data)
            .data
            .map(\.id)
            .filter { !$0.localizedCaseInsensitiveContains("embed") }
    }

    /// `lms ps --json`; empty when `lms` is missing rather than throwing, since a caller only uses this to prefer an already-loaded model
    static func loadedChatModels() async throws -> [String] {
        guard let lms = try? lmsExecutable() else {
            return []
        }
        let output = try await ProcessRunner.output(
            executableURL: lms,
            arguments: ["ps", "--json"],
            currentDirectoryURL: nil
        )
        return try parseLoaded(Data(output.utf8))
    }

    /// the only part of `loadedChatModels` that touches raw JSON, kept pure so tests can hit it directly
    static func parseLoaded(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([LoadedModel].self, from: data)
            .filter { $0.type == "llm" }
            .map(\.identifier)
    }

    static let manualInstructions = "LM Studio не найден. Откройте его и включите Local Server во вкладке Developer."

    /// settles on a server and a model from the settings values, falling back to discovery when they are unset
    static func resolve(serverURL: String, model: String) async throws -> SummaryConnection {
        let baseURL: URL
        if !serverURL.isEmpty {
            guard let url = URL(string: serverURL) else {
                throw SummarizationError.unavailable("Адрес сервера не похож на URL")
            }
            baseURL = url
        } else if let discovered = try await discoverServer() {
            baseURL = discovered
        } else {
            throw SummarizationError.unavailable("LM Studio не запущен")
        }

        if !model.isEmpty {
            return SummaryConnection(baseURL: baseURL, model: model)
        }

        let available = try await chatModels(at: baseURL)
        let loaded = try await loadedChatModels()
        guard let chosen = available.first(where: loaded.contains) ?? available.first else {
            throw SummarizationError.unavailable("В LM Studio не загружено ни одной чат-модели")
        }
        return SummaryConnection(baseURL: baseURL, model: chosen)
    }

    private struct ServerStatus: Decodable {
        let running: Bool
        let port: Int
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
        }
        let data: [Model]
    }

    private struct LoadedModel: Decodable {
        let type: String
        let identifier: String
    }
}
