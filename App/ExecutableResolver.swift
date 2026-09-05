import Foundation

enum ExecutableResolver {
    static func resolve(_ names: [String]) throws -> URL {
        let fileManager = FileManager.default
        let pathValues = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let searchDirectories = pathValues + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        for name in names {
            if name.contains("/") {
                if fileManager.isExecutableFile(atPath: name) {
                    return URL(fileURLWithPath: name)
                }
                continue
            }

            for directory in searchDirectories {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        throw BesedaError.executableNotFound(names.joined(separator: ", "))
    }
}

enum BesedaError: LocalizedError {
    case executableNotFound(String)
    case processFailed(String)
    case invalidWorkerResponse(String)
    case runtimeMissing

    /// the banner matches on this text to offer the install button
    static let runtimeMissingMessage = "Движок распознавания не установлен"

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "Executable not found: \(name)"
        case .runtimeMissing:
            Self.runtimeMissingMessage
        case .processFailed(let message):
            message
        case .invalidWorkerResponse(let message):
            message
        }
    }
}
