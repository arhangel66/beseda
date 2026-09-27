import Foundation
import Testing

@Test func russianUILiteralsUseTheCyrillicProductName() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = repository.appendingPathComponent("Sources/Beseda")
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }
        .filter { ["swift", "plist"].contains($0.pathExtension) }
    let literals = try NSRegularExpression(
        pattern: #"(?s)(?:\"\"\".*?\"\"\"|\"(?:\\.|[^\"\\])*\"|<string>.*?</string>)"#
    )
    let cyrillic = try NSRegularExpression(pattern: #"[А-Яа-яЁё]"#)

    var offenders: [String] = []
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(source.startIndex..., in: source)
        for match in literals.matches(in: source, range: range) {
            let literal = (source as NSString).substring(with: match.range)
            guard literal.contains("Beseda"),
                  cyrillic.firstMatch(in: literal, range: NSRange(literal.startIndex..., in: literal)) != nil else {
                continue
            }
            let line = source[..<Range(match.range, in: source)!.lowerBound].count(where: { $0 == "\n" }) + 1
            offenders.append("\(file.path.replacingOccurrences(of: repository.path + "/", with: "")):\(line)")
        }
    }

    #expect(offenders.isEmpty, "Russian UI literals containing Latin Beseda: \(offenders.joined(separator: ", "))")
}
