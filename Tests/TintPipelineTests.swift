//
//  TintPipelineTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/models/TintPipeline.swift
//
//  Helper names are prefixed (`check*`) so they stay distinguishable from the helpers
//  in the other standalone runners in this folder.
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
        testStaleArtworkDecodeIsDiscarded()
        testArtworkRequestDoesNotInvalidateADerivation()
        testColorlessDoesNotSupersedeAPendingArtworkDecode()
        testMovingToAnotherTrackSupersedesThePreviousTracksDecode()
        testRefiningTheCurrentTrackDoesNotSupersedeItsDecode()
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

    /// Issue #18: two track changes in quick succession start two decodes, and whichever
    /// finishes last used to win. Only the decode belonging to the newest request may be
    /// applied.
    static func testStaleArtworkDecodeIsDiscarded() {
        var pipeline = TintPipeline()
        let slowDecode = pipeline.artworkRequested()
        let newestDecode = pipeline.artworkRequested()
        checkTrue(pipeline.acceptsArtwork(order: newestDecode), "the newest decode is applied")
        checkTrue(!pipeline.acceptsArtwork(order: slowDecode),
                  "a decode that returns after a newer request must be dropped")
    }

    /// The image's order and the tint generation are separate counters: requesting a decode
    /// must not invalidate a derivation that is still in flight for the artwork already on
    /// screen.
    static func testArtworkRequestDoesNotInvalidateADerivation() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Bubble", artist: "Samuel Kim")
        let generation = pipeline.artworkApplied(for: track)
        _ = pipeline.artworkRequested()
        checkTrue(pipeline.accepts(generation: generation),
                  "a pending tint derivation survives a newer artwork request")
    }

    /// The Tint Settle Window may expire while a large cover is still decoding. That track's
    /// own cover is not superseded by the Colorless declaration: dropping it would strand the
    /// track on its Artwork Fallback.
    static func testColorlessDoesNotSupersedeAPendingArtworkDecode() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Podcast", artist: "Someone")
        pipeline.noteCurrentTrack(track)
        let pendingDecode = pipeline.artworkRequested()
        _ = pipeline.shouldArmSettleWindow(for: track)
        checkTrue(pipeline.declareColorlessIfSettled(for: track) != nil, "the window expires")
        checkTrue(pipeline.acceptsArtwork(order: pendingDecode),
                  "the late decode still applies over the Artwork Fallback")
    }

    /// The guard is scoped to the track, not just to the request: a coverless track that settled
    /// Colorless must not be overwritten by the *previous* track's slow decode, which would put
    /// that track's cover and tint on screen for the current one.
    static func testMovingToAnotherTrackSupersedesThePreviousTracksDecode() {
        var pipeline = TintPipeline()
        let previous = TrackIdentity(title: "Track 1", artist: "Someone")
        let coverless = TrackIdentity(title: "Podcast", artist: "Someone Else")
        pipeline.noteCurrentTrack(previous)
        let pendingDecode = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(coverless)
        _ = pipeline.shouldArmSettleWindow(for: coverless)
        _ = pipeline.declareColorlessIfSettled(for: coverless)
        checkTrue(!pipeline.acceptsArtwork(order: pendingDecode),
                  "the previous track's cover must not replace the Artwork Fallback")
    }

    /// A track refining itself — an album or bundle field arriving late — is not a move, so a
    /// decode already in flight for it stays valid.
    static func testRefiningTheCurrentTrackDoesNotSupersedeItsDecode() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Bubble", artist: "Samuel Kim")
        pipeline.noteCurrentTrack(track)
        let pendingDecode = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(track)
        checkTrue(pipeline.acceptsArtwork(order: pendingDecode),
                  "refining the same track is not a move")
    }
}
