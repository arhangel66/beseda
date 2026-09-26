import Foundation

// the two app symbols the copied files use that live in files not worth copying
enum BesedaError: Error {
    case processFailed(String)
}

extension Int64 {
    var byteSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
