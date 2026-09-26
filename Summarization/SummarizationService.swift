import Foundation

/// Turns a stored call into the text a provider gets, and nothing else: the reader-facing
/// dialogue with renamed speakers already in it.
final class SummarizationService: Sendable {
    private let provider: SummarizationProvider
    /// ≈100k tokens at 3 chars/token, comfortably under a 131k-token context window
    private let characterBudget: Int

    init(provider: SummarizationProvider, characterBudget: Int = 300_000) {
        self.provider = provider
        self.characterBudget = characterBudget
    }

    func summarize(_ detail: StoredCallDetail) async throws -> String {
        // a call with no segments still renders its markdown, so the emptiness check is on the render
        let text = TranscriptCopy.render(detail, format: .clean)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.emptyTranscript
        }

        guard text.count > characterBudget else {
            return try await provider.summarize(text: text)
        }

        let summary = try await provider.summarize(text: Self.truncated(text, to: characterBudget))
        return "Пересказано только начало разговора — целиком в модель не поместилось.\n\n" + summary
    }

    /// cuts at the last newline before the limit so a line doesn't get chopped mid-sentence
    private static func truncated(_ text: String, to budget: Int) -> String {
        let cutoff = text.index(text.startIndex, offsetBy: budget)
        let prefix = text[..<cutoff]
        guard let lastNewline = prefix.lastIndex(of: "\n") else {
            return String(prefix)
        }
        return String(prefix[..<lastNewline])
    }
}

/// The one thing a summarizer has to do; tests put a spy here instead of a real model.
protocol SummarizationProvider: Sendable {
    func summarize(text: String) async throws -> String
}

/// The cases the error card offers a different way out of; everything else is `unavailable`.
enum SummarizationError: LocalizedError {
    case emptyTranscript
    /// the endpoint did not answer at all: LM Studio not started, llama-server not up
    case serverDown(String)
    /// the key was refused or has no credit left
    case unauthorized(String)
    /// the built-in model or its runtime is not downloaded yet
    case modelMissing

    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "В этом разговоре нечего пересказывать: расшифровка пустая."
        case .modelMissing:
            "Встроенная модель ещё не скачана."
        case .serverDown(let message), .unauthorized(let message), .unavailable(let message):
            message
        }
    }
}

/// A kind of call the user defines: the classifier reads `name` and `description`, the summary runs `prompt`.
struct CallType: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var description: String
    var prompt: String
    /// the built-in «Другое»: undeletable, holds the general prompt, takes an unknown or unsure answer
    var isOther = false

    static let otherName = "Другое"

    init(name: String, description: String, prompt: String, isOther: Bool = false) {
        self.name = name
        self.description = description
        self.prompt = prompt
        self.isOther = isOther
    }

    // types stored before the flag have no `isOther` key; AppSettings then flags the first one
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        prompt = try container.decode(String.self, forKey: .prompt)
        isOther = try container.decodeIfPresent(Bool.self, forKey: .isOther) ?? false
    }
}

extension [CallType] {
    /// the settings always hold one «Другое»; a list without it (a test's) falls back to its first type
    var other: CallType {
        first(where: \.isOther) ?? self[0]
    }
}

extension SummarizationService {
    /// ≈2k tokens: enough of the opening to tell a daily from a therapy session
    static let classifierCharacterLimit = 8000

    /// below this Jev's pick is not trusted and the call goes to «Другое»
    // ponytail: a round guess, not tuned on labeled calls; tune it once real calls are classified
    static let jevMinimumProbability = 0.5

    /// Picks the call's type (skipped when `chosen` is given or only «Другое» exists), then runs
    /// that type's prompt. `types.other` is the fallback for an unknown or unsure answer.
    /// `provider` builds the model client for a given system prompt; `jev`, when given, classifies
    /// first and falls back to `provider` on failure. The classifier also answers whether exactly one
    /// person besides Mikhail spoke: `oneOtherPerson`, nil when it did not run or could not tell.
    static func process(
        _ detail: StoredCallDetail,
        types: [CallType],
        chosen: CallType? = nil,
        characterBudget: Int,
        provider: (String) -> SummarizationProvider,
        jev: JevClassifier? = nil,
        log: (String) -> Void = { _ in },
        // runs on the caller's actor, so the closures need not be Sendable
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> (type: CallType, text: String, oneOtherPerson: Bool?) {
        let type: CallType
        var oneOtherPerson: Bool?
        if let chosen {
            type = chosen
        } else if types.count == 1 {
            type = types[0]
        } else {
            (type, oneOtherPerson) = try await classify(detail, types: types, provider: provider, jev: jev, log: log)
        }
        let text = try await SummarizationService(provider: provider(type.prompt), characterBudget: characterBudget)
            .summarize(detail)
        return (type, text, oneOtherPerson)
    }

    static func classify(
        _ detail: StoredCallDetail,
        types: [CallType],
        provider: (String) -> SummarizationProvider,
        jev: JevClassifier?,
        log: (String) -> Void,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> (CallType, oneOtherPerson: Bool?) {
        let context = ClassifierContext(detail)
        if let jev {
            do {
                let answer = try await jev.classify(context, types: types)
                log("Jev picked «\(answer.choice)» at \(answer.probability), one other person: \(answer.oneOtherPerson.map(String.init) ?? "no answer"), cost $\(answer.cost ?? 0)")
                guard answer.probability >= jevMinimumProbability,
                      let named = types.first(where: { $0.name == answer.choice }) ?? pickType(answer.choice, from: types)
                else {
                    return (types.other, answer.oneOtherPerson)
                }
                return (named, answer.oneOtherPerson)
            } catch {
                log("Jev failed (\(error.localizedDescription)); classifying with the summary model")
            }
        }
        let answer = try await provider(classifierPrompt(types)).summarize(text: context.asText)
        let lines = answer.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let oneOtherPerson = lines.dropFirst().last.flatMap(parseOneOtherPerson)
        if let named = lines.first.flatMap({ pickType($0, from: types) }) {
            return (named, oneOtherPerson)
        }
        log("Classifier answered «\(answer)», not a known type; using «\(types.other.name)»")
        return (types.other, oneOtherPerson)
    }

    /// the local classifier's second line: «один» or «несколько», anything else is no answer
    static func parseOneOtherPerson(_ line: String) -> Bool? {
        let line = line.lowercased()
        if line.contains("несколько") {
            return false
        }
        return line.contains("один") ? true : nil
    }

    static func classifierPrompt(_ types: [CallType]) -> String {
        let list = types.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        return """
            Определи тип созвона по времени, длительности и началу расшифровки. Если ни один тип \
            явно не подходит, выбери «\(types.other.name)». Первой строкой ответь только названием одного \
            типа из списка, без пояснений.

            Второй строкой ответь одним словом, сколько людей кроме Михаила («Вы») говорит на созвоне: \
            «один» или «несколько». Все чужие реплики помечены одинаково «\(ClassifierContext.remoteLabel)», \
            поэтому суди по содержанию: имена, обращения, кто кому отвечает.

            \(list)
            """
    }

    /// tolerant of case, spaces, quotes and extra words; the longest name wins so «1:1» never beats «личный 1:1»
    static func pickType(_ answer: String, from types: [CallType]) -> CallType? {
        let answer = answer.lowercased()
        return types
            .filter { !$0.name.isEmpty && answer.contains($0.name.lowercased().trimmingCharacters(in: .whitespaces)) }
            .max { $0.name.count < $1.name.count }
    }
}
