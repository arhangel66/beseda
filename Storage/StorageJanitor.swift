import Foundation

/// The three kinds of file a call folder holds; the settings screen keeps them apart.
enum CallFileKind: Sendable {
    case rawAudio
    case normalizedAudio
    case text
}

struct RetentionRules: Sendable, Equatable {
    var rawAudio: RetentionRule
    var normalizedAudio: RetentionRule

    func rule(for kind: CallFileKind) -> RetentionRule {
        switch kind {
        case .rawAudio:
            rawAudio
        case .normalizedAudio:
            normalizedAudio
        case .text:
            .forever
        }
    }
}

struct StorageUsage: Sendable, Equatable {
    var rawAudioBytes: Int64 = 0
    var normalizedAudioBytes: Int64 = 0
    var textBytes: Int64 = 0

    var audioBytes: Int64 {
        rawAudioBytes + normalizedAudioBytes
    }
}

/// Measures the calls folder and deletes audio the retention rules no longer cover.
struct StorageJanitor: Sendable {
    let callsDirectory: URL

    /// tells apart `me.raw.wav`, `me.asr.wav` and the text a call leaves behind
    static func kind(ofFileNamed name: String) -> CallFileKind? {
        if name.hasSuffix(".raw.wav") {
            return .rawAudio
        }
        if name.hasSuffix(".asr.wav") || name.hasSuffix(".16k-mono.wav") {
            return .normalizedAudio
        }
        if name.hasSuffix(".md") || name.hasSuffix(".json") {
            return .text
        }
        return nil
    }

    static func isExpired(kind: CallFileKind, age: TimeInterval, rules: RetentionRules) -> Bool {
        guard let maximumAge = rules.rule(for: kind).maximumAge else {
            return false
        }
        return age >= maximumAge
    }

    func measure() -> StorageUsage {
        var usage = StorageUsage()
        for file in files() {
            guard let kind = Self.kind(ofFileNamed: file.url.lastPathComponent) else {
                continue
            }
            switch kind {
            case .rawAudio:
                usage.rawAudioBytes += file.size
            case .normalizedAudio:
                usage.normalizedAudioBytes += file.size
            case .text:
                usage.textBytes += file.size
            }
        }
        return usage
    }

    /// how much the current rules would free if the sweep ran right now
    func expiredBytes(rules: RetentionRules, protecting protectedDirectories: Set<String> = [], now: Date = Date()) -> Int64 {
        expiredFiles(rules: rules, protecting: protectedDirectories, now: now).reduce(0) { $0 + $1.size }
    }

    @discardableResult
    func sweep(rules: RetentionRules, protecting protectedDirectories: Set<String> = [], now: Date = Date()) -> Int64 {
        expiredFiles(rules: rules, protecting: protectedDirectories, now: now).reduce(0) { freed, file in
            (try? FileManager.default.removeItem(at: file.url)) == nil ? freed : freed + file.size
        }
    }

    /// a call keeps every file of its own folder; nothing else lives one level under the calls directory
    private func expiredFiles(rules: RetentionRules, protecting protectedDirectories: Set<String>, now: Date) -> [Entry] {
        let protected = Set(protectedDirectories.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path })
        return files().filter { file in
            guard let kind = Self.kind(ofFileNamed: file.url.lastPathComponent) else {
                return false
            }
            return Self.isExpired(kind: kind, age: now.timeIntervalSince(file.modifiedAt), rules: rules)
                && !protected.contains(file.url.deletingLastPathComponent().standardizedFileURL.path)
        }
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private func files() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: callsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [Entry] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate else {
                continue
            }
            entries.append(Entry(url: url, size: Int64(size), modifiedAt: modifiedAt))
        }
        return entries
    }
}

extension Int64 {
    /// "3,4 ГБ" — the prototype writes sizes with a comma, as Russian formatting does
    var byteSizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        guard self > 0 else {
            return "0 Б"
        }
        // ByteCountFormatter has no locale, and it writes "3.4 GB"; Russian wants "3,4 ГБ"
        return formatter.string(fromByteCount: self)
            .replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: "GB", with: "ГБ")
            .replacingOccurrences(of: "MB", with: "МБ")
            .replacingOccurrences(of: "KB", with: "КБ")
            .replacingOccurrences(of: "bytes", with: "Б")
            .replacingOccurrences(of: "byte", with: "Б")
    }
}
