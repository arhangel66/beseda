import Foundation

/// Turns a stored speaker key into what the user reads. Three key classes exist forever:
/// `me`, the bare `them` of every call recorded before diarization, and `them-N`.
enum SpeakerNaming {
    static func remoteIndex(of speaker: String) -> Int? {
        if speaker == TranscriptChannel.systemAudio.speakerID {
            return 1
        }
        let prefix = "\(TranscriptChannel.systemAudio.speakerID)-"
        guard speaker.hasPrefix(prefix) else {
            return nil
        }
        return Int(speaker.dropFirst(prefix.count))
    }

    static func defaultName(for speaker: String) -> String {
        if speaker == TranscriptChannel.microphone.speakerID {
            return "Вы"
        }
        guard let index = remoteIndex(of: speaker) else {
            return speaker
        }
        // an undiarized call keeps the plain name it always had
        return speaker == TranscriptChannel.systemAudio.speakerID ? "Собеседник" : "Собеседник \(index)"
    }

    static func name(for speaker: String, overrides: [String: String]) -> String {
        overrides[speaker] ?? defaultName(for: speaker)
    }

    /// avatar text: a renamed speaker shows their letter, a numbered one shows the number,
    /// because every default remote name starts with the same «С»
    static func initial(for speaker: String, overrides: [String: String]) -> String {
        if let name = overrides[speaker], !name.isEmpty {
            return String(name.prefix(1))
        }
        if speaker != TranscriptChannel.systemAudio.speakerID, let index = remoteIndex(of: speaker) {
            return "\(index)"
        }
        return String(defaultName(for: speaker).prefix(1))
    }
}
