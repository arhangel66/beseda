import Testing

@testable import Beseda

@Test func diarizationUsesCommunityThresholdWithoutSpeakerConstraints() {
    let clustering = Diarizer.config.clustering

    #expect(clustering.threshold == 0.70)
    #expect(clustering.minSpeakers == nil)
    #expect(clustering.maxSpeakers == nil)
    #expect(clustering.numSpeakers == nil)
}
