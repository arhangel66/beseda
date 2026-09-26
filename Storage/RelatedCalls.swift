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
}

enum RelatedCalls {
    /// the summary sections that say what was agreed and what is left, as ChatCompletionsProvider.defaultPrompt names them
    static let digestSections = ["Главное", "Что делать", "Открытые вопросы"]
    static let fallbackLineCount = 5

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
    /// sections when the summary has them, otherwise its first non-empty lines.
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
        let sections = digestSections.compactMap { heading in
            bodies[heading].map { "**\(heading)**\n" + $0.joined(separator: "\n") }
        }
        if !sections.isEmpty {
            return sections.joined(separator: "\n\n")
        }
        return lines.prefix(fallbackLineCount).joined(separator: "\n")
    }

    static func previousRelatedCall(to target: RelatedCallTarget, among calls: [StoredCallSummary]) -> PreviousRelatedCall? {
        guard let call = previousCall(to: target, among: calls),
              let startedAt = call.startedDate,
              let digest = digest(ofSummary: call.summaryText) else {
            return nil
        }
        return PreviousRelatedCall(callID: call.id, startedAt: startedAt, digest: digest)
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
