import SwiftUI

/// The filled blue button the prototype uses for the one action that matters on a screen.
struct AccentButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 26
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: height * 0.42, weight: .semibold))
                }
                Text(title)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isEnabled ? Color.white : Palette.textQuaternary)
            .padding(.horizontal, height * 0.42)
            .frame(height: height)
            .background(
                isEnabled ? (isHovering ? Palette.accentPressed : Palette.accent) : Palette.fillSubtle,
                in: .rect(cornerRadius: height * 0.27)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
    }
}

/// The hairline-bordered secondary button.
struct OutlineButton<Label: View>: View {
    var height: CGFloat = 26
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, height * 0.4)
                .frame(height: height)
                .background(isHovering ? Palette.fillHover : Palette.fillRaised, in: .rect(cornerRadius: Metrics.controlCorner))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlCorner)
                        .strokeBorder(Palette.controlBorder, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The pill switch from the prototype, green when on.
struct PillToggle: View {
    @Binding var isOn: Bool
    var width: CGFloat = 32

    private var height: CGFloat {
        width * 0.625
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.ok : Palette.toggleOff)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: width, height: height)
            .animation(.snappy(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// The tab strip: a rounded track with the selected item raised out of it.
struct SegmentedTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    var minimumWidth: CGFloat = 108
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let isSelected = tab == selection
                Text(title(tab))
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .frame(minWidth: minimumWidth)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 14)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Palette.selectedTabBackground)
                                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { selection = tab }
            }
        }
        .padding(2)
        .background(Palette.fillSubtle, in: .rect(cornerRadius: Metrics.rowCorner))
    }
}

struct Avatar: View {
    let initials: String?
    var fallbackSymbol = "waveform"
    var size: CGFloat = 22
    var isSelected = false

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
        .foregroundStyle(isSelected ? Color.white : Palette.avatarText)
        .frame(width: size, height: size)
        .background(isSelected ? Color.white.opacity(0.24) : Palette.avatarBackground, in: .circle)
    }
}

/// Renders a search hit inside a line without splitting it into separate Text views.
struct HighlightedText: View {
    let text: String
    let query: String
    var isSelected = false

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
        result[range].backgroundColor = isSelected ? Color.white.opacity(0.3) : Palette.searchHit
        return result
    }
}

/// A row of bars driven by the real capture level; the hump makes the middle read loudest.
struct LevelMeter: View {
    let level: Double
    var color: Color = Palette.ok
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

/// The bar under a running job. The width is a measured share, never a guess, so the
/// bar is allowed to stand still when the step it draws is standing still.
struct ProgressTrack: View {
    let value: Double
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// A SettingsLink that also tells the Settings window which section to open on.
struct SettingsSectionLink<Label: View>: View {
    let section: String
    let controller: AppController
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink(label: label)
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                controller.requestedSettingsSection = section
            })
    }
}

struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textQuaternary)
    }
}

struct ToastOverlay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.82), in: .rect(cornerRadius: Metrics.cardCorner))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
