import Foundation

/// One entry in the model picker. Every field the picker shows is here, plus what the
/// installer needs to fetch and verify the file: a revision-pinned URL and its hash.
struct SpeechModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let languages: String
    let bytes: Int64
    let filename: String
    let downloadURL: URL
    let sha256: String
    /// nil when the runtime windows long audio itself; otherwise the window the model was
    /// trained on, past which it silently drops speech and has to be fed in pieces
    let maxUtteranceSec: Double?

    static let catalogue: [SpeechModel] = [parakeetV3, gigaamV3]

    static let parakeetV3 = SpeechModel(
        id: "parakeet-tdt-0.6b-v3",
        title: "Parakeet v3",
        subtitle: "Быстрая и точная, пишет латиницу как есть",
        languages: "25 языков",
        bytes: 485_425_504,
        filename: "parakeet-tdt-0.6b-v3-Q4_K_M.gguf",
        downloadURL: URL(string: "https://huggingface.co/handy-computer/parakeet-tdt-0.6b-v3-gguf/resolve/85ac09ea12fc4b1112fa76810059364bc6adc9de/parakeet-tdt-0.6b-v3-Q4_K_M.gguf")!,
        sha256: "b68557be1e3c40207fd7c4bd9d63f1d3316b963f15325bfb0cc16a8bb0ffd181",
        maxUtteranceSec: nil
    )

    static let gigaamV3 = SpeechModel(
        id: "gigaam-v3-e2e-rnnt",
        title: "GigaAM v3",
        subtitle: "Сбер, со знаками препинания. Английские слова пишет на слух",
        languages: "только русский",
        bytes: 273_724_832,
        filename: "gigaam-v3-e2e-rnnt-Q8_0.gguf",
        downloadURL: URL(string: "https://huggingface.co/handy-computer/gigaam-v3-e2e-rnnt-gguf/resolve/f719d70812344f4d0fb8c11c0887b190501a7465/gigaam-v3-e2e-rnnt-Q8_0.gguf")!,
        sha256: "78d63b47723b7f8d78c6113a6ef983b5a86e2a86f6c273e1f5cb6967b1c4467a",
        maxUtteranceSec: 25
    )

    static let `default` = parakeetV3

    static func named(_ id: String) -> SpeechModel? {
        catalogue.first { $0.id == id }
    }

    var sizeDescription: String {
        bytes.byteSizeDescription
    }

    func localURL(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    func isDownloaded(in directory: URL) -> Bool {
        let path = localURL(in: directory).path
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        return size == bytes
    }
}
