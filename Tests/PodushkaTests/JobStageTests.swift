import Foundation
import Testing

@testable import Podushka

@Test func theBarCountsFinishedStepsAndThePartOfTheRunningOne() {
    let stage = JobStage(title: "Расшифровываю собеседников", index: 3, total: 5, fraction: 0.5)

    #expect(stage.overall == 0.5)
}

@Test func aStepThatCannotReportShowsOnlyTheStepsBeforeIt() {
    let stage = JobStage(title: "Запускаю распознавание", index: 3, total: 5)

    #expect(stage.overall == 0.4)
}

@Test func theEstimateComesFromHowLongTheFinishedPartTook() {
    let now = Date()
    let stage = JobStage(
        title: "Расшифровываю запись",
        index: 1,
        total: 2,
        fraction: 0.25,
        startedAt: now.addingTimeInterval(-10)
    )

    #expect(stage.remainingSec(now: now) == 30)
    #expect(stage.caption(now: now) == "Шаг 1 из 2 · осталось 30 сек")
}

@Test func aBarelyStartedStepGivesNoEstimate() {
    let now = Date()
    let stage = JobStage(
        title: "Расшифровываю запись",
        index: 1,
        total: 2,
        fraction: 0.05,
        startedAt: now.addingTimeInterval(-10)
    )

    #expect(stage.remainingSec(now: now) == nil)
    #expect(stage.caption(now: now) == "Шаг 1 из 2")
}

@Test func aLongWaitIsRoundedUpToMinutes() {
    let now = Date()
    let stage = JobStage(
        title: "Различаю, кто говорит",
        index: 4,
        total: 4,
        fraction: 0.2,
        startedAt: now.addingTimeInterval(-30)
    )

    #expect(stage.caption(now: now) == "Шаг 4 из 4 · осталось 2 мин")
}
