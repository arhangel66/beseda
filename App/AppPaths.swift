import Foundation

/// Where Beseda keeps its files. Everything it creates sits under one Application Support
/// folder, so uninstalling is deleting the app and that folder. The speech engine is compiled
/// into the binary, so the only thing installed at runtime is the model file itself.
struct AppPaths {
    let dataDirectory: URL

    static let current = AppPaths(
        dataDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Beseda", isDirectory: true)
    )

    /// the checkout this binary was compiled from; only meaningful on the developer's Mac
    static let sourceRoot: URL = {
        var cursor = URL(fileURLWithPath: #filePath)
        while cursor.path != "/" {
            if FileManager.default.fileExists(atPath: cursor.appendingPathComponent("Package.swift").path) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }()

    /// the folder the app used while it was called Podushka
    static var legacyDataDirectory: URL {
        current.dataDirectory.deletingLastPathComponent().appendingPathComponent("Podushka", isDirectory: true)
    }

    var callsDirectory: URL {
        dataDirectory.appendingPathComponent("calls", isDirectory: true)
    }

    var callIndexURL: URL {
        dataDirectory.appendingPathComponent("calls.sqlite")
    }

    var appLogURL: URL {
        dataDirectory.appendingPathComponent("beseda-app.log")
    }

    var runtimeDirectory: URL {
        dataDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    var modelsDirectory: URL {
        runtimeDirectory.appendingPathComponent("models", isDirectory: true)
    }
}

/// Removes what the Python engine left behind. An install made before the move to transcribe.cpp
/// carries about 3.6 GB of venv, interpreter, uv cache and Hugging Face snapshots that nothing
/// reads any more.
enum PythonRuntimeCleanup {
    private static let items = ["venv", "python", "cache", "models/hub"]

    /// the bytes freed; zero when there was nothing left from the old engine
    @discardableResult
    static func run(_ paths: AppPaths) -> Int64 {
        let fileManager = FileManager.default
        var freed: Int64 = 0
        for item in items {
            let url = paths.runtimeDirectory.appendingPathComponent(item)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            freed += size(of: url)
            try? fileManager.removeItem(at: url)
        }
        return freed
    }

    private static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

/// Moves the Podushka-era folder to the Beseda one the first time the renamed app runs,
/// so calls, the index, settings files and the downloaded model come along.
enum LegacyDataMigration {
    /// true when the folder moved; nothing moves once the new folder exists
    @discardableResult
    static func run(from legacy: URL, to paths: AppPaths) throws -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: paths.dataDirectory.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return false
        }
        try fileManager.moveItem(at: legacy, to: paths.dataDirectory)
        let oldLog = paths.dataDirectory.appendingPathComponent("podushka-app.log")
        if fileManager.fileExists(atPath: oldLog.path) {
            try fileManager.moveItem(at: oldLog, to: paths.appLogURL)
        }
        return true
    }
}
