import Foundation

/// Where Podushka keeps its files. Everything it creates sits under one Application Support
/// folder, so uninstalling is deleting the app and that folder. The speech engine is compiled
/// into the binary, so the only thing installed at runtime is the model file itself.
struct AppPaths {
    let dataDirectory: URL

    static let current = AppPaths(
        dataDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Podushka", isDirectory: true)
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

    /// the pre-bundle layout: calls and the index under `untracked/` in the checkout
    static var legacyDataDirectory: URL {
        sourceRoot.appendingPathComponent("untracked", isDirectory: true)
    }

    var callsDirectory: URL {
        dataDirectory.appendingPathComponent("calls", isDirectory: true)
    }

    var callIndexURL: URL {
        dataDirectory.appendingPathComponent("calls.sqlite")
    }

    var appLogURL: URL {
        dataDirectory.appendingPathComponent("podushka-app.log")
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

/// Moves the developer-layout files into Application Support the first time the new build runs.
enum LegacyDataMigration {
    private static let items = ["calls", "calls.sqlite", "calls.sqlite-wal", "calls.sqlite-shm", "podushka-app.log"]

    /// the names that moved; nothing moves once the data directory has an index of its own
    @discardableResult
    static func run(from legacy: URL, to paths: AppPaths) throws -> [String] {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: paths.callIndexURL.path),
              fileManager.fileExists(atPath: legacy.appendingPathComponent("calls.sqlite").path) else {
            return []
        }
        try fileManager.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
        var moved: [String] = []
        for item in items {
            let source = legacy.appendingPathComponent(item)
            let target = paths.dataDirectory.appendingPathComponent(item)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }
            if item == "podushka-app.log", fileManager.fileExists(atPath: target.path) {
                // the new build may have logged a line or two before this ran; keep both
                let handle = try FileHandle(forWritingTo: target)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(contentsOf: source))
                try handle.close()
                try fileManager.removeItem(at: source)
            } else {
                try fileManager.moveItem(at: source, to: target)
            }
            moved.append(item)
        }
        return moved
    }
}
