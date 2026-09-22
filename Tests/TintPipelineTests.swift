//
//  TintPipelineTests.swift
//  Tests
//
//  Standalone runner. The Tests folder is not part of an Xcode target, so run it
//  directly:
//
//    swiftc -o /tmp/tint-pipeline-tests \
//      Tests/TintPipelineTests.swift boringNotch/models/TintPipeline.swift \
//      && /tmp/tint-pipeline-tests
//
//  Helper names are prefixed (`check*`) so they stay distinguishable from the helpers
//  in the other standalone runners in this folder. Each runner has its own `@main`,
//  so they are compiled one file at a time.
//

import Foundation

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkTrue(_ condition: Bool, _ message: String = "",
               file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct TintPipelineTestsRunner {
    static func main() {
        testLatestArtworkOwnsTheTint()
        testStaleDerivationIsDiscarded()
        testMetadataRefinementDoesNotTakeTheTintAway()
        testUnchangedArtworkStillBelongsToTheNewTrack()
        testCoverlessTrackSettlesColorless()
        testSettleWindowArmsOncePerTrack()
        testReplayedCoverlessTrackArmsAgain()
        testTrackIdentityOnlyRefinesOnTitleOrArtist()
        print("✅ TintPipelineTests: all passed")
    }

    /// Artwork application is what advances the pipeline, and only the newest
    /// derivation may publish.
    static func testLatestArtworkOwnsTheTint() {
        var pipeline = TintPipeline()
        let first = pipeline.artworkApplied(for: .init(title: "A", artist: "1"))
        let second = pipeline.artworkApplied(for: .init(title: "B", artist: "2"))
        checkTrue(second > first, "each applied artwork advances the generation")
        checkTrue(pipeline.accepts(generation: second), "the newest derivation publishes")
    }

    /// The reported defect: the Artwork Fallback's color derivation was still in
    /// flight when the real artwork landed, and its stale result won the race.
    static func testStaleDerivationIsDiscarded() {
        var pipeline = TintPipeline()
        let fallbackEra = pipeline.artworkApplied(for: .init(title: "A", artist: "1"))
        let artworkEra = pipeline.artworkApplied(for: .init(title: "B", artist: "2"))
        checkTrue(!pipeline.accepts(generation: fallbackEra), "a superseded derivation must be discarded")
        checkTrue(pipeline.accepts(generation: artworkEra), "the surviving derivation still publishes")
    }

    /// A metadata-only event (album or bundle arriving after the artwork) must not
    /// take the tint away from a track that already has a cover.
    static func testMetadataRefinementDoesNotTakeTheTintAway() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Bubble", artist: "Samuel Kim")
        let generation = pipeline.artworkApplied(for: track)
        checkEqual(pipeline.declareColorlessIfSettled(for: track), nil,
                   "a covered track never settles Colorless")
        checkTrue(pipeline.accepts(generation: generation),
                  "the cover's derivation survives the refinement")
    }

    /// Tracks that share a cover (the rest of an album) never reach `artworkApplied`
    /// because the artwork bytes did not change, so the pipeline is told about the
    /// ownership directly. Without that they would settle Colorless while their own
    /// cover is on screen.
    static func testUnchangedArtworkStillBelongsToTheNewTrack() {
        var pipeline = TintPipeline()
        let first = TrackIdentity(title: "Track 1", artist: "Album Artist")
        let second = TrackIdentity(title: "Track 2", artist: "Album Artist")
        let generation = pipeline.artworkApplied(for: first)
        pipeline.noteCoverApplied(for: second)
        checkEqual(pipeline.declareColorlessIfSettled(for: second), nil,
                   "an unchanged cover still counts as this track's artwork")
        checkTrue(pipeline.accepts(generation: generation),
                  "recording ownership must not invalidate a derivation still in flight")
    }

    /// A track that offers no artwork becomes Colorless, and any derivation still
    /// in flight from before that point is invalidated.
    static func testCoverlessTrackSettlesColorless() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Podcast", artist: "Someone")
        let abandoned = pipeline.artworkApplied(for: TrackIdentity(title: "Previous", artist: "Track"))
        checkTrue(pipeline.shouldArmSettleWindow(for: track), "a track without artwork arms the window")
        let colorless = pipeline.declareColorlessIfSettled(for: track)
        checkTrue(colorless != nil, "the window expiring without artwork settles the track Colorless")
        checkTrue(!pipeline.accepts(generation: abandoned),
                  "a derivation from an older track must not publish over Colorless")
    }

    /// Metadata that keeps refining a coverless track must not slide the window.
    static func testSettleWindowArmsOncePerTrack() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Podcast", artist: "Someone")
        checkTrue(pipeline.shouldArmSettleWindow(for: track), "first event arms the window")
        checkTrue(!pipeline.shouldArmSettleWindow(for: track), "refinements do not re-arm it")
    }

    /// Once another track's artwork has landed, replaying a coverless track gives
    /// it a fresh window instead of inheriting the settled state.
    static func testReplayedCoverlessTrackArmsAgain() {
        var pipeline = TintPipeline()
        let coverless = TrackIdentity(title: "Podcast", artist: "Someone")
        checkTrue(pipeline.shouldArmSettleWindow(for: coverless), "first play arms the window")
        _ = pipeline.declareColorlessIfSettled(for: coverless)
        _ = pipeline.artworkApplied(for: TrackIdentity(title: "Song", artist: "Someone Else"))
        checkTrue(pipeline.shouldArmSettleWindow(for: coverless), "a replay arms the window again")
    }

    /// Deliberate inexactness: identity is (title, artist) only, so an album or
    /// bundle field arriving late cannot make one track look like two.
    static func testTrackIdentityOnlyRefinesOnTitleOrArtist() {
        let before = TrackIdentity(title: "Bubble", artist: "Samuel Kim")
        let after = TrackIdentity(title: "Bubble", artist: "Samuel Kim")
        checkEqual(before, after, "album and bundle are not part of track identity")
        checkTrue(before != TrackIdentity(title: "Bubble", artist: "Someone Else"),
                  "a different artist is a different track")
    }
}
