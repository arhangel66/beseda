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
                    .font(.body.weight(.semibold))
                if isActive {
                    Text("Активная")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.14), in: .capsule)
                }
                Spacer(minLength: 0)
                trailingControl
            }

            Text(model.subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
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
                    .foregroundStyle(Color.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
            .font(.caption)
            .foregroundStyle(Color.secondary)
        case .failed(let message):
            HStack(spacing: 10) {
                Text(message)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Color.red)
                    .help(message)
                Button("Повторить") {
                    controller.selectSpeechModel(model)
                }
                .controlSize(.small)
            }
        default:
            if isActive {
                EmptyView()
            } else {
                Button(isDownloaded ? "Выбрать" : "Скачать") {
                    controller.selectSpeechModel(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}
