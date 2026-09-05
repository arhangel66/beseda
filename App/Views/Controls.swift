import SwiftUI

struct Avatar: View {
    let initials: String?
    var fallbackSymbol = "waveform"
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.48, weight: .semibold))
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.46))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
        .background(.quaternary, in: .circle)
    }
}

/// Renders a search hit inside a line without splitting it into separate Text views.
struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let range = result.range(of: query, options: .caseInsensitive) else {
            return result
        }
        result[range].backgroundColor = Color.yellow.opacity(0.45)
        return result
    }
}

/// A row of bars driven by the real capture level; the hump makes the middle read loudest.
struct LevelMeter: View {
    let level: Double
    var color: Color = Color.green
    var barCount = 26
    var height: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(height: barHeight(at: index))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.09), value: level)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let position = Double(index) / Double(max(1, barCount - 1))
        let envelope = sin(.pi * position) * 0.55 + 0.45
        return max(3, min(1, level * envelope) * height)
    }
}

struct SettingsSectionLink<Label: View>: View {
    let section: String
    let controller: AppController
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink(label: label)
            .simultaneousGesture(TapGesture().onEnded {
                controller.requestedSettingsSection = section
            })
    }
}

struct ToastOverlay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: Metrics.cardCorner))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
