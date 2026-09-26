import Foundation

/// TypeSafe Jev through OpenRouter's Decisions API: one `choice` question over the call types,
/// answered with the picked name and its probability instead of generated text.
struct JevClassifier: Sendable {
    typealias Transport = ChatCompletionsProvider.Transport

    static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    static let model = "typesafe/jev-1.13"

    let apiKey: String
    var transport: Transport = { try await URLSession.shared.data(for: $0) }

    struct Answer: Equatable {
        let choice: String
        /// the probability of `choice` among the options
        let probability: Double
        /// USD, as OpenRouter bills it
        let cost: Double?
        /// «one other person besides Mikhail» at or above `jevMinimumProbability`; nil when Jev did not answer it
        var oneOtherPerson: Bool? = nil
    }

    func classify(_ context: ClassifierContext, types: [CallType]) async throws -> Answer {
        let (data, response) = try await transport(Self.request(context, types: types, apiKey: apiKey))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            throw SummarizationError.unavailable("Jev ответил кодом \(status)")
        }
        return try Self.parse(data)
    }

    static func request(_ context: ClassifierContext, types: [CallType], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let body = RequestBody(
            model: model,
            state: .init(started: context.started, duration: context.duration, transcriptOpening: context.opening),
            questions: [
                "call_type": .init(
                    type: "choice",
                    instructions: "Which type is this call? Judge by when it happened, how long it lasted and how the transcript opens.",
                    // duplicate names collapse into one option; the first description wins
                    criteria: Dictionary(types.map { ($0.name, $0.description) }, uniquingKeysWith: { first, _ in first })
                ),
                "other_people": .init(
                    type: "choice",
                    instructions: "How many people besides Mikhail («Вы») speak on the call? Every remote line is labelled «Удалённо» whoever says it, so judge by what is said: names, greetings, who answers whom.",
                    criteria: [
                        "one": "exactly one other person talks with Mikhail",
                        "several": "two or more other people talk"
                    ]
                )
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func parse(_ data: Data) throws -> Answer {
        guard let response = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let answer = response.answers["call_type"], let choice = answer.choice
        else {
            throw SummarizationError.unavailable("Jev вернул ответ без выбора типа")
        }
        let oneOtherPerson = response.answers["other_people"].map {
            ($0.probabilities?["one"] ?? 0) >= SummarizationService.jevMinimumProbability
        }
        return Answer(
            choice: choice, probability: answer.probabilities?[choice] ?? 0, cost: response.usage?.cost,
            oneOtherPerson: oneOtherPerson
        )
    }

    private struct RequestBody: Encodable {
        struct State: Encodable {
            let started: String
            let duration: String
            let transcriptOpening: String

            enum CodingKeys: String, CodingKey {
                case started, duration
                case transcriptOpening = "transcript_opening"
            }
        }
        struct Question: Encodable {
            let type: String
            let instructions: String
            let criteria: [String: String]
        }
        let model: String
        let state: State
        let questions: [String: Question]
    }

    private struct ResponseBody: Decodable {
        struct ChoiceAnswer: Decodable {
            let choice: String?
            let probabilities: [String: Double]?
        }
        struct Usage: Decodable {
            let cost: Double?
        }
        let answers: [String: ChoiceAnswer]
        let usage: Usage?
    }
}

/// What either classifier is told about a call: when, how long, and how it opens.
struct ClassifierContext: Equatable, Sendable {
    /// weekday and local time, e.g. «пятница, 10:15»
    let started: String
    /// e.g. «45 мин»
    let duration: String
    let opening: String

    static let remoteLabel = "Удалённо"

    init(_ detail: StoredCallDetail, timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, HH:mm"
        started = detail.summary.startedDate.map(formatter.string(from:)) ?? "неизвестно"
        duration = "\(max(1, Int((detail.summary.duration / 60).rounded()))) мин"
        // every remote speaker under one label: the diarizer's extra `them-N` must not answer «how many people»
        let transcript = detail.segments.isEmpty ? detail.markdownText ?? "" : detail.segments
                .map { segment in
                    let speaker = SpeakerNaming.remoteIndex(of: segment.speaker) == nil
                        ? SpeakerNaming.name(for: segment.speaker, overrides: detail.speakerNames)
                        : Self.remoteLabel
                    return "\(speaker): \(segment.text)"
                }
                .joined(separator: "\n")
        opening = String(transcript.prefix(SummarizationService.classifierCharacterLimit))
    }

    /// the same facts as a text block for the chat-model classifier
    var asText: String {
        "Начало: \(started). Длительность: \(duration).\n\nНачало расшифровки:\n\(opening)"
    }
}
