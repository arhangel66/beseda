import Foundation
import Testing

@testable import Podushka

@Test func parseLoadedKeepsOnlyLlmEntriesAndReturnsTheirIdentifiers() throws {
    let json = Data("""
        [
            {"type": "llm", "identifier": "qwen/qwen3.8-27b", "sizeBytes": 17742040464, "status": "idle"},
            {"type": "embedding", "identifier": "x"}
        ]
        """.utf8)

    #expect(try LocalModelSupport.parseLoaded(json) == ["qwen/qwen3.8-27b"])
}
