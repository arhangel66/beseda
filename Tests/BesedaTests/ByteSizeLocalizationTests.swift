import Foundation
import Testing
@testable import Beseda

@Test func byteSizesFollowSystemLanguageWithoutChangingRussianCopy() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    #expect(Int64(0).byteSizeDescription(locale: english) == "Zero KB" || !Int64(0).byteSizeDescription(locale: english).contains("Б"))
    #expect(Int64(0).byteSizeDescription(locale: russian) == "0 Б")
    #expect(Int64(1_000_000).byteSizeDescription(locale: english).contains("MB"))
    #expect(Int64(1_000_000).byteSizeDescription(locale: russian).contains("МБ"))
}
