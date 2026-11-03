import Foundation

/// «Люди в звонках»: one line per person, `Name: spelling1, spelling2`; the spellings are how speech
/// recognition garbles the name.
struct CallPeople {
    /// lowercased spelling or name → the name as the user wrote it
    let canonicalBySpelling: [String: String]
    /// every spelling as a whole word, longest first so «Сергей Петров» wins over «Сергей»
    let pattern: NSRegularExpression?

    init(_ text: String) {
        var canonicalBySpelling: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                continue
            }
            let spellings = parts.count > 1 ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : []
            for spelling in [name] + spellings where !spelling.isEmpty {
                canonicalBySpelling[spelling.lowercased()] = name
            }
        }
        self.canonicalBySpelling = canonicalBySpelling
        let alternatives = canonicalBySpelling.keys
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
            .map(NSRegularExpression.escapedPattern(for:))
        pattern = alternatives.isEmpty ? nil
            : try? NSRegularExpression(pattern: "\\b(\(alternatives.joined(separator: "|")))\\b", options: .caseInsensitive)
    }

    /// the spellings found in `text`, as written there, in order
    func mentions(in text: String) -> [String] {
        guard let pattern else {
            return []
        }
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// a name compared the way the eval did: trimmed, a trailing dot dropped, spellings folded into the person
    func canonical(_ name: String) -> String {
        let folded = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        if ["", "unknown", "none", "null", "?"].contains(folded) {
            return StoredSpeakerGuess.unknown
        }
        return canonicalBySpelling[folded].map { $0.lowercased() } ?? folded
    }
}

/// Port of rules version 3 (untracked/epics/speaker-names/rules.py, windows.py `clues`): votes from
/// lines that say exactly one known name — thanks goes to the remote voice before the line, an address
/// to the remote voice after it — minus one wherever a remote voice says the name itself.
enum SpeakerNameRules {
    private static let thanks = try! NSRegularExpression(pattern: "\\b(thank|thanks|спасибо)\\b", options: .caseInsensitive)
    private static let filler = "(?:\\b(?:uh|um|so|okay|ok|anyway|and|yeah|yes|hi|hello|hey|but|now|привет|ну|так|окей)\\b[\\s,.]*)*"
    private static let you = try! NSRegularExpression(pattern: "\\b(you|your|yours|ты|тебе|тебя|твой|твоя|вы|вам|вас)\\b|\\?", options: .caseInsensitive)
    /// how far the voice before or after a line is looked for
    private static let reach = 7

    static func guesses(for segments: [StoredTranscriptSegment], people: CallPeople) -> [String: StoredSpeakerGuess] {
        // segments in order → one guess per remote speaker key, "unknown" where no vote wins
        var votes: [String: [String: Int]] = [:]
        var evidence: [String: [String: [String]]] = [:]
        var saidTheirOwnName: Set<[String]> = []
        for (i, segment) in segments.enumerated() {
            let mentions = people.mentions(in: segment.text)
            let names = Set(mentions.compactMap { people.canonicalBySpelling[$0.lowercased()] })
            guard names.count == 1, let name = names.first,
                  let alias = mentions.first(where: { people.canonicalBySpelling[$0.lowercased()] == name }) else {
                continue
            }
            let isOther = { (other: StoredTranscriptSegment) in other.speaker != "me" && other.speaker != segment.speaker }
            let before = segments[max(0, i - reach)..<i].last(where: isOther)?.speaker
            let after = segments[(i + 1)..<min(segments.count, i + 1 + reach)].first(where: isOther)?.speaker
            if segment.speaker != "me" {
                saidTheirOwnName.insert([segment.speaker, name])
            }
            let line = "line \(segment.orderIndex), \(segment.speaker): '\(segment.text.prefix(160))'"
            if matches(thanks, segment.text), let before {
                votes[before, default: [:]][name, default: 0] += 1
                evidence[before, default: [:]][name, default: []].append("\(line) -> thanks, previous remote voice \(before)")
            } else if isAddress(segment.text, alias: alias), let after {
                votes[after, default: [:]][name, default: 0] += 1
                evidence[after, default: [:]][name, default: []].append("\(line) -> addressed, next remote voice \(after)")
            }
        }
        // a voice saying a name counts against it being that person, but diarization glues lines: a penalty, not a veto
        for pair in saidTheirOwnName {
            votes[pair[0], default: [:]][pair[1], default: 0] -= 1
        }
        let pairs = votes.flatMap { label, byName in byName.map { (score: $0.value, label: label, name: $0.key) } }
            .filter { $0.score > 0 }
            .sorted { ($0.score, $0.label, $0.name) > ($1.score, $1.label, $1.name) }
        var answer: [String: StoredSpeakerGuess] = [:]
        var taken: Set<String> = []
        for pair in pairs where answer[pair.label] == nil && !taken.contains(pair.name) {
            let lines = evidence[pair.label]?[pair.name] ?? []
            let more = lines.count > 1 ? " (+\(lines.count - 1) more)" : ""
            answer[pair.label] = StoredSpeakerGuess(name: pair.name, source: .rules, evidence: (lines.first ?? "") + more)
            taken.insert(pair.name)
        }
        for label in remoteLabels(of: segments) where answer[label] == nil {
            answer[label] = StoredSpeakerGuess(name: StoredSpeakerGuess.unknown, source: .rules, evidence: "no name clue the rules trust")
        }
        return answer
    }

    static func remoteLabels(of segments: [StoredTranscriptSegment]) -> [String] {
        Set(segments.map(\.speaker)).subtracting(["me"]).sorted()
    }

    /// the name in a vocative position: opening the line, set off by commas, or closing it
    static func isAddress(_ text: String, alias: String) -> Bool {
        let name = NSRegularExpression.escapedPattern(for: alias)
        if matches("^\\W*\(filler)\(name)\\b[\\s,.!?]", text) {
            return true
        }
        if matches(",\\s*\(filler)\(name)\\b\\s*[,.!?]?\\s*$", text) {
            return true
        }
        if matches("[,.]\\s*\(filler)\(name)\\b\\s*,", text) && matches(you, text) {
            return true
        }
        return matches("\\b\(name)\\b\\s*,", text) && matches(you, text)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        matches(try! NSRegularExpression(pattern: pattern, options: .caseInsensitive), text)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// Names a finished call's remote speakers: the rules first, then one Gemma 4 12B request for the
/// labels they leave unknown. Eval and the choice of this pipeline: untracked/epics/speaker-names/README.md.
@MainActor
final class SpeakerNamer {
    /// untracked/epics/speaker-names/prompts/p1.txt verbatim: the prompt the eval measured (full call, no context)
    static let prompt = """
        You read a transcript of a call recorded by Mikhail. "me" is Mikhail. The other speakers are labelled them-1, them-2, ... by a speaker diarizer; each label is one distinct voice. Lines start with their index number and a time stamp.
        Work out the real name of each them-N label from the transcript. Names may be garbled by speech recognition.
        On these calls people address each other by name all the time, so there are almost always clues. Look for them first:
        - a greeting ("Hi Rustam") or a question to someone ("Sergei, what about the reliability score?") — the next voice that answers is that person;
        - a hand-over ("Mohammed, you can go", "Pixel, your turn") — the NEXT voice to speak is that person, not the one saying it;
        - thanks after an update ("Thank you, Sergei") — the voice that just finished is that person;
        - a self-introduction ("this is Lucas"), or being talked about and reacting ("Pixel was sick" — "yes, I was down").
        A person's topics or role are only a second hint. Never name a label by elimination ("the remaining one must be Gus"): "unknown" is better than a guess.
        Answer with JSON only: an object with one key per label, value = the person's name or "unknown".
        """
    /// a local model reads a long call for minutes
    private static let timeout: TimeInterval = 900

    var log: (String) -> Void = { _ in }

    private let paths: AppPaths
    private let server: LlamaServer

    init(paths: AppPaths, server: LlamaServer) {
        self.paths = paths
        self.server = server
    }

    func guesses(for segments: [StoredTranscriptSegment], peopleList: String) async -> [String: StoredSpeakerGuess] {
        // the call's segments → one guess per remote speaker; a model failure leaves the rules' answer
        let people = CallPeople(peopleList)
        let rules = SpeakerNameRules.guesses(for: segments, people: people)
        guard rules.values.contains(where: { $0.name == StoredSpeakerGuess.unknown }) else {
            return rules
        }
        guard BundledSummary.gemma12B.isModelDownloaded(paths) else {
            log("Speaker names: rules only, \(BundledSummary.gemma12B.title) is not downloaded")
            return rules
        }
        do {
            // AppController unloads it at once unless the summary that follows runs on the same model
            defer { server.noteIdle() }
            let reply = try await askModel(segments)
            return Self.merging(modelReply: reply, into: rules, people: people)
        } catch {
            log("Speaker names: the model failed, rules only: \(error.localizedDescription)")
            return rules
        }
    }

    /// the rules' names where they have one, the model's for the rest unless the rules already placed that person
    static func merging(modelReply: String, into rules: [String: StoredSpeakerGuess], people: CallPeople) -> [String: StoredSpeakerGuess] {
        // the eval's prompt answers a name per label and no reason: the raw reply is the model's evidence
        let answer = (try? JSONDecoder().decode([String: String].self, from: Data(modelReply.utf8))) ?? [:]
        let placed = Set(rules.values.map { people.canonical($0.name) }).subtracting([StoredSpeakerGuess.unknown])
        var merged: [String: StoredSpeakerGuess] = [:]
        for (label, rule) in rules {
            guard rule.name == StoredSpeakerGuess.unknown else {
                merged[label] = StoredSpeakerGuess(name: rule.name, source: rule.source, evidence: rule.evidence, modelReply: modelReply)
                continue
            }
            guard let said = answer[label] else {
                merged[label] = StoredSpeakerGuess(name: StoredSpeakerGuess.unknown, source: .model, evidence: "the model gave no answer for this label", modelReply: modelReply)
                continue
            }
            let canonical = people.canonical(said)
            let name = canonical == StoredSpeakerGuess.unknown ? StoredSpeakerGuess.unknown
                : placed.contains(canonical) ? StoredSpeakerGuess.unknown
                : people.canonicalBySpelling[canonical] ?? said.trimmingCharacters(in: .whitespaces)
            let evidence = canonical == StoredSpeakerGuess.unknown ? "the model found no name for \(label)"
                : placed.contains(canonical) ? "the model said \(said), whom the rules already placed"
                : "the model read the whole call and named \(label) \(said)"
            merged[label] = StoredSpeakerGuess(name: name, source: .model, evidence: evidence, modelReply: modelReply)
        }
        return merged
    }

    /// the model's raw JSON for every remote label of the call
    private func askModel(_ segments: [StoredTranscriptSegment]) async throws -> String {
        let labels = SpeakerNameRules.remoteLabels(of: segments)
        let entry: [String: Any] = ["type": "string"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": Dictionary(uniqueKeysWithValues: labels.map { ($0, entry) }),
            "required": labels,
            "additionalProperties": false
        ]
        let transcript = segments.map { segment in
            let seconds = Int(segment.startSec)
            let text = segment.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            return String(format: "%d [%02d:%02d] %@: %@", segment.orderIndex, seconds / 60, seconds % 60, segment.speaker, text)
        }.joined(separator: "\n")
        let body: [String: Any] = [
            "model": BundledSummary.gemma12B.modelID,
            "temperature": 0,
            "max_tokens": 400,
            "stream": false,
            "response_format": ["type": "json_schema", "json_schema": ["name": "names", "schema": schema]],
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": [["role": "system", "content": Self.prompt], ["role": "user", "content": transcript]]
        ]
        let started = Date()
        let baseURL = try await server.ensureRunning()
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let reply = try ChatCompletionsProvider.parse(
            data, status: (response as? HTTPURLResponse)?.statusCode ?? 200, serviceName: BundledSummary.gemma12B.title
        )
        log("Speaker names: the model answered in \(Int(Date().timeIntervalSince(started))) s")
        return reply
    }
}
