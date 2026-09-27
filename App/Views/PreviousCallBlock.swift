import SwiftUI

/// What the «В прошлый раз» block shows; nil when there is nothing stored to show.
struct PreviousCallContent: Equatable {
    let callID: String
    let dateLine: String
    let digest: String
    let isWholeSummary: Bool

    init?(_ call: PreviousRelatedCall?, now: Date = Date()) {
        guard let call, !call.digest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        callID = call.callID
        dateLine = CallFormatting.when(call.startedAt, now: now)
        digest = call.digest
        isWholeSummary = call.isWholeSummary
    }
}

/// The previous related call's date and stored digest, with a link that selects it.
struct PreviousCallBlock: View {
    let content: PreviousCallContent
    /// the sidebar has little room, so it shows a few lines only
    var digestLineLimit: Int?
    let open: (String) -> Void
    @State private var showsWholeSummary = false

    /// a whole custom-prompt result could fill the pane, so it starts at a few lines
    private var lineLimit: Int? {
        content.isWholeSummary && !showsWholeSummary ? min(digestLineLimit ?? 4, 4) : digestLineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("В прошлый раз · \(content.dateLine)", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // right beside the label: on a wide pane a trailing button drifts far from what it opens
                Button("Открыть") { open(content.callID) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Text(CallSummaryView.rendered(content.digest))
                .font(.callout)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
            if content.isWholeSummary && !showsWholeSummary {
                Button("Показать полностью") { showsWholeSummary = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
