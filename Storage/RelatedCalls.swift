import Foundation

/// What a previous call is looked up for: a stored call, or a calendar event before any call exists.
struct RelatedCallTarget: Hashable {
    var callID: String?
    let startsAt: Date
    let title: String?
    let seriesID: String?
    let callType: String?
    let participants: [String]
}

/// The previous related call and the stored text worth showing before the next one.
struct PreviousRelatedCall: Hashable {
    let callID: String
    let startedAt: Date
    let digest: String
    /// the summary has none of the default sections, so `digest` is all of it
    let isWholeSummary: Bool
}

enum RelatedCalls {
    /// the sections that say what was agreed and what is left, as ChatCompletionsProvider.defaultPrompt
    /// names them now and as previousDefaultPrompt named them before BESEDA-94
    static let digestSections = ["Договорились", "Главное", "Кто что делает", "Что делать", "Открытые вопросы"]

    /// Most recent `ready` call before the target: same series or title first, then same type
    /// plus a shared participant. Rule (a) over the whole history wins before rule (b) is tried.
    static func previousCall(to target: RelatedCallTarget, among calls: [StoredCallSummary]) -> StoredCallSummary? {
        let earlier = calls
            .filter { $0.status == "ready" && $0.id != target.callID }
            .compactMap { call in call.startedDate.map { (call, $0) } }
            .filter { $0.1 < target.startsAt }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let title = normalizedTitle(target.title)
        if let sameSeriesOrTitle = earlier.first(where: { call in
            (target.seriesID != nil && call.eventSeriesID == target.seriesID)
                || (title != nil && normalizedTitle(call.eventTitle) == title)
        }) {
            return sameSeriesOrTitle
        }
        guard let callType = target.callType else {
            return nil
        }
        let participants = Set(target.participants)
        return earlier.first { call in
            call.callType == callType && !participants.isDisjoint(with: call.participants)
        }
    }

    /// Only stored summary text, never the transcript: the decision/next steps/open questions
    /// sections of a summary written by a default prompt; nil when it has none of them.
    static func digest(ofSummary summary: String?) -> String? {
        guard let summary else {
            return nil
        }
        let lines = summary.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return nil
        }
        var bodies: [String: [String]] = [:]
        var currentHeading: String?
        for line in lines {
            if line.count > 4, line.hasPrefix("**"), line.hasSuffix("**") {
                currentHeading = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            } else if let currentHeading {
                bodies[currentHeading, default: []].append(line)
            }
        }
        // a custom prompt may happen to have «Открытые вопросы»; only the agreements and tasks mark a default one
        guard ["Договорились", "Кто что делает", "Что делать"].contains(where: { bodies[$0] != nil }) else {
            return nil
        }
        let sections = digestSections.compactMap { heading in
            bodies[heading].map { "**\(heading)**\n" + $0.joined(separator: "\n") }
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    static func previousRelatedCall(to target: RelatedCallTarget, among calls: [StoredCallSummary]) -> PreviousRelatedCall? {
        guard let call = previousCall(to: target, among: calls),
              let startedAt = call.startedDate,
              let summary = call.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return nil
        }
        // a custom prompt's result has no known sections; the user sees all of it, collapsed
        let digest = digest(ofSummary: summary)
        return PreviousRelatedCall(
            callID: call.id, startedAt: startedAt, digest: digest ?? summary, isWholeSummary: digest == nil
        )
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension CallStore {
    // ponytail: scans the latest 1000 calls in memory; a SQL filter on title/series is the upgrade if history outgrows it
    func previousRelatedCall(toCallID callID: String) throws -> PreviousRelatedCall? {
        guard let call = try fetchCall(id: callID), let startedAt = call.startedDate else {
            return nil
        }
        let target = RelatedCallTarget(
            callID: call.id,
            startsAt: startedAt,
            title: call.eventTitle,
            seriesID: call.eventSeriesID,
            callType: call.callType,
            participants: call.participants
        )
        return RelatedCalls.previousRelatedCall(to: target, among: try fetchCalls(limit: 1000))
    }

    /// an event has no call type yet, so only the series and title rule can find its previous call
    func previousRelatedCall(to event: CalendarEvent) throws -> PreviousRelatedCall? {
        let target = RelatedCallTarget(
            startsAt: event.startsAt,
            title: event.title,
            seriesID: event.seriesID,
            callType: nil,
            participants: event.participants
        )
        return RelatedCalls.previousRelatedCall(to: target, among: try fetchCalls(limit: 1000))
    }
}
