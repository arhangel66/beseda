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
}

extension SummarizationService {
    /// ≈2k tokens: enough of the opening to tell a daily from a therapy session
    static let classifierCharacterLimit = 8000

    /// Picks the call's type (skipped when `chosen` is given or only one type exists), then runs
    /// that type's prompt. `provider` builds the model client for a given system prompt.
    static func process(
        _ detail: StoredCallDetail,
        types: [CallType],
        chosen: CallType? = nil,
        characterBudget: Int,
        provider: (String) -> SummarizationProvider,
        log: (String) -> Void = { _ in },
        // runs on the caller's actor, so the closures need not be Sendable
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> (type: CallType, text: String) {
        let type: CallType
        if let chosen {
            type = chosen
        } else if types.count == 1 {
            type = types[0]
        } else {
            let opening = String(TranscriptCopy.render(detail, format: .clean).prefix(classifierCharacterLimit))
            let answer = try await provider(classifierPrompt(types)).summarize(text: opening)
            if let named = pickType(answer, from: types) {
                type = named
            } else {
                log("Classifier answered «\(answer)», not a known type; using «\(types[0].name)»")
                type = types[0]
            }
        }
        let text = try await SummarizationService(provider: provider(type.prompt), characterBudget: characterBudget)
            .summarize(detail)
        return (type, text)
    }

    static func classifierPrompt(_ types: [CallType]) -> String {
        let list = types.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        return """
            Определи тип созвона по началу расшифровки. Ответь только названием одного типа из списка, \
            без пояснений.

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
