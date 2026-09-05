import SwiftUI

/// The model picker: one card per model, the way Handy shows them. Tapping a card that is
/// already on disk switches to it; tapping one that is not starts its download.
struct SpeechModelList: View {
    let controller: AppController

    var body: some View {
        VStack(spacing: 10) {
            ForEach(SpeechModel.catalogue) { model in
                SpeechModelCard(controller: controller, model: model)
            }
        }
    }
}

private struct SpeechModelCard: View {
    let controller: AppController
    let model: SpeechModel

    private var isActive: Bool {
        controller.runtime.model == model
    }

    private var isDownloaded: Bool {
        controller.runtime.isDownloaded(model)
    }

    /// only the active model has stages running, so only its card shows progress
    private var installState: RuntimeStageState? {
        isActive ? controller.runtime.state(of: .speechModel) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 13.5, weight: .semibold))
                if isActive {
                    Text("Активная")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.okText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Palette.okText.opacity(0.14), in: .capsule)
                }
                Spacer(minLength: 0)
                trailingControl
            }

            Text(model.subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Palette.separator)
                .frame(height: 0.5)

            HStack(spacing: 8) {
                Label(model.languages, systemImage: "globe")
                Spacer(minLength: 0)
                Label(model.sizeDescription, systemImage: "internaldrive")
                if isDownloaded && !isActive {
                    Button("Удалить") {
                        controller.removeSpeechModel(model)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.recording)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .background(Palette.windowBackground.opacity(0.5), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(isActive ? Palette.accent.opacity(0.5) : Palette.separator, lineWidth: isActive ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch installState {
        case .running(let fraction):
            HStack(spacing: 8) {
                if let fraction {
                    ProgressView(value: fraction).frame(width: 90)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textSecondary)
        case .failed(let message):
            HStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(Palette.recording)
                    .help(message)
                AccentButton(title: "Повторить", height: 24) {
                    controller.selectSpeechModel(model)
                }
            }
        default:
            if isActive {
                EmptyView()
            } else {
                AccentButton(title: isDownloaded ? "Выбрать" : "Скачать", height: 24) {
                    controller.selectSpeechModel(model)
                }
            }
        }
    }
}
