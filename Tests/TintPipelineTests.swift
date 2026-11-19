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
    /// The playback app whose icon is the Artwork Fallback in these tests.
    static let app = "com.apple.Music"

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
        testFailedDecodeSettlesTheTrackColorless()
        testStaleFailedDecodeDoesNothing()
        testUndecodableArtworkArrivingAgainIsNotACover()
        testDecodableArtworkClearsTheUndecodableMark()
        testInheritedCoverDoesNotSwallowTheTracksOwnFailure()
        testRefinementDuringDecodeDoesNotSwallowTheFailure()
        testOwnDecodedCoverSurvivesALaterFailure()
        testColorlessIsDeclaredOncePerTrack()
        testDecodeSupersededByATrackChangeIsRedone()
        testLateBundleRefreshesTheColorlessFallback()
        testLateBundleRefreshesAnUndecodableTracksFallback()
        testInheritedUndecodableBytesWaitForTheTracksOwnCover()
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
        checkEqual(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: app), nil,
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
        checkEqual(pipeline.declareColorlessIfSettled(for: second, bundleIdentifier: app), nil,
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
        let colorless = pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: app)
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
        _ = pipeline.declareColorlessIfSettled(for: coverless, bundleIdentifier: app)
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
        checkTrue(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: app) != nil, "the window expires")
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
        _ = pipeline.declareColorlessIfSettled(for: coverless, bundleIdentifier: app)
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

    /// Issue #24: artwork that cannot be decoded is absent artwork. The newest request failing
    /// settles the track Colorless at once — the Tint Settle Window was cancelled when the bytes
    /// arrived — and invalidates the previous track's tint derivation.
    static func testFailedDecodeSettlesTheTrackColorless() {
        var pipeline = TintPipeline()
        let previous = TrackIdentity(title: "Track 1", artist: "Someone")
        let track = TrackIdentity(title: "Broken Cover", artist: "Someone Else")
        pipeline.noteCurrentTrack(previous)
        let previousTint = pipeline.artworkApplied(for: previous)
        pipeline.noteCurrentTrack(track)
        let order = pipeline.artworkRequested()
        let colorless = pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: app)
        checkTrue(colorless != nil, "a failed decode of the newest request settles the track Colorless")
        checkTrue(!pipeline.accepts(generation: previousTint),
                  "the previous track's tint must not publish over the Colorless track")
        checkEqual(pipeline.heldArtwork, .undecodable(track: track),
                   "the held bytes are remembered as undecodable for this track")
    }

    /// A failure belonging to a superseded request must not arm anything: the newer request
    /// (or the track the notch has moved to) owns the outcome.
    static func testStaleFailedDecodeDoesNothing() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Track 1", artist: "Someone")
        let next = TrackIdentity(title: "Track 2", artist: "Someone")
        pipeline.noteCurrentTrack(track)
        let staleOrder = pipeline.artworkRequested()
        let newestOrder = pipeline.artworkRequested()
        let generation = pipeline.generation
        checkEqual(pipeline.artworkDecodeFailed(order: staleOrder, for: track, bundleIdentifier: app), nil,
                   "a stale failure declares nothing")
        checkEqual(pipeline.generation, generation, "a stale failure does not advance the generation")
        checkEqual(pipeline.heldArtwork, .decoding(order: newestOrder),
                   "a stale failure does not mark the held bytes")
        checkTrue(pipeline.acceptsArtwork(order: newestOrder), "the newer decode can still be applied")

        // The same holds for a decode superseded by a change of track.
        let previousTrackOrder = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(next)
        checkEqual(pipeline.artworkDecodeFailed(order: previousTrackOrder, for: track, bundleIdentifier: app), nil,
                   "a failure for a track the notch has left declares nothing")
        checkEqual(pipeline.generation, generation, "nor advances the generation")
    }

    /// The bad bytes stay "seen", so they arrive again through the unchanged-artwork path. They
    /// must not be recorded as the next track's cover, or that track would keep the previous
    /// rendering and never settle Colorless. Bytes that failed for the previous track are no
    /// artwork for this one, so it waits out a Tint Settle Window and then settles Colorless.
    static func testUndecodableArtworkArrivingAgainIsNotACover() {
        var pipeline = TintPipeline()
        let first = TrackIdentity(title: "Track 1", artist: "Album Artist")
        let second = TrackIdentity(title: "Track 2", artist: "Album Artist")
        pipeline.noteCurrentTrack(first)
        let order = pipeline.artworkRequested()
        _ = pipeline.artworkDecodeFailed(order: order, for: first, bundleIdentifier: app)
        pipeline.noteCurrentTrack(second)
        checkEqual(pipeline.heldArtworkArrived(for: second, bundleIdentifier: app), .armSettleWindow,
                   "the previous track's undecodable bytes give the next track a settle window")
        checkTrue(pipeline.artworkTrack != second, "the track is not recorded as owning a cover")
        checkTrue(pipeline.shouldArmSettleWindow(for: second), "the window arms")
        checkTrue(pipeline.declareColorlessIfSettled(for: second, bundleIdentifier: app) != nil,
                  "and the track settles Colorless when it expires without artwork")
        checkEqual(pipeline.heldArtworkArrived(for: second, bundleIdentifier: app), .noAction,
                   "once Colorless, the same bytes arriving again redo nothing")
    }

    /// New bytes start a fresh decode, and bytes that decode are a cover again, so the
    /// undecodable mark never outlives the bytes it describes.
    static func testDecodableArtworkClearsTheUndecodableMark() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Track 1", artist: "Album Artist")
        let next = TrackIdentity(title: "Track 2", artist: "Album Artist")
        pipeline.noteCurrentTrack(track)
        let order = pipeline.artworkRequested()
        _ = pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: app)
        let newBytes = pipeline.artworkRequested()
        checkEqual(pipeline.heldArtwork, .decoding(order: newBytes),
                   "new bytes are not known to be undecodable")
        _ = pipeline.artworkApplied(for: track)
        pipeline.noteCurrentTrack(next)
        checkEqual(pipeline.heldArtworkArrived(for: next, bundleIdentifier: app), .noAction,
                   "a decoded cover shared by the next track is that track's cover")
        checkEqual(pipeline.declareColorlessIfSettled(for: next, bundleIdentifier: app), nil,
                   "so it never settles Colorless")
    }

    /// NowPlaying's diff events carry the previous artwork forward, so a new track first
    /// inherits the previous track's bytes (recorded as its cover) and only then receives its
    /// own. If its own bytes fail to decode, the inherited cover must not keep it covered:
    /// that is the previous track's cover and tint staying on screen.
    static func testInheritedCoverDoesNotSwallowTheTracksOwnFailure() {
        var pipeline = TintPipeline()
        let first = TrackIdentity(title: "T1", artist: "Someone")
        let second = TrackIdentity(title: "T2", artist: "Someone")
        pipeline.noteCurrentTrack(first)
        _ = pipeline.artworkRequested()
        let firstTint = pipeline.artworkApplied(for: first)

        // `title=T2, artwork=A`: the bytes did not change.
        pipeline.noteCurrentTrack(second)
        checkEqual(pipeline.heldArtworkArrived(for: second, bundleIdentifier: app), .noAction,
                   "the inherited cover is recorded")
        checkEqual(pipeline.artworkTrack, second, "T2 looks covered by the inherited bytes")

        // `artwork=B`: T2's own bytes, which do not decode.
        let order = pipeline.artworkRequested()
        checkTrue(pipeline.artworkDecodeFailed(order: order, for: second, bundleIdentifier: app) != nil,
                  "T2's own failure settles it Colorless despite the inherited cover")
        checkTrue(pipeline.artworkTrack != second, "the inherited cover no longer counts as T2's")
        checkTrue(!pipeline.accepts(generation: firstTint), "T1's tint must not publish over T2")
    }

    /// A refinement of the same track (album or bundle arriving late) while its decode is in
    /// flight reaches the unchanged-bytes path. It must not record the undecided bytes as a
    /// cover, or the failure that follows would find the track covered.
    static func testRefinementDuringDecodeDoesNotSwallowTheFailure() {
        var pipeline = TintPipeline()
        let previous = TrackIdentity(title: "T1", artist: "Someone")
        let track = TrackIdentity(title: "T2", artist: "Someone")
        pipeline.noteCurrentTrack(previous)
        _ = pipeline.artworkApplied(for: previous)

        pipeline.noteCurrentTrack(track)
        let order = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(track)
        checkEqual(pipeline.heldArtworkArrived(for: track, bundleIdentifier: app), .noAction,
                   "a decode in flight decides nothing yet")
        checkTrue(pipeline.artworkTrack != track, "the undecided bytes are not recorded as a cover")
        checkTrue(pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: app) != nil,
                  "the failure still settles the track Colorless")
    }

    /// The cost of distrusting inherited covers stops at the track's own: a track whose own
    /// bytes decoded keeps that cover when a later piece of its artwork fails.
    static func testOwnDecodedCoverSurvivesALaterFailure() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "T1", artist: "Someone")
        pipeline.noteCurrentTrack(track)
        _ = pipeline.artworkRequested()
        let tint = pipeline.artworkApplied(for: track)
        let order = pipeline.artworkRequested()
        checkEqual(pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: app), nil,
                   "the track keeps the cover decoded from its own bytes")
        checkTrue(pipeline.accepts(generation: tint), "and that cover's tint")
    }

    /// Events keep arriving for a track (the flip animation replays on each, see `lastArtwork*`),
    /// so a track already Colorless must not have its Artwork Fallback redone by every one.
    static func testColorlessIsDeclaredOncePerTrack() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Broken Cover", artist: "Someone")
        pipeline.noteCurrentTrack(track)
        let order = pipeline.artworkRequested()
        checkTrue(pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: app) != nil, "the first failure settles")
        let generation = pipeline.generation
        checkEqual(pipeline.heldArtworkArrived(for: track, bundleIdentifier: app), .noAction,
                   "the same bytes again do nothing")
        checkEqual(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: app), nil, "nor does a settle window")
        checkEqual(pipeline.generation, generation, "the generation does not move")

        _ = pipeline.artworkRequested()
        _ = pipeline.artworkApplied(for: track)
        let next = TrackIdentity(title: "Podcast", artist: "Someone Else")
        checkTrue(pipeline.declareColorlessIfSettled(for: next, bundleIdentifier: app) != nil,
                  "another track can still be declared Colorless")
    }

    /// A change of track supersedes the decode of the held bytes, and the new track inherits
    /// those same bytes, so no decode is left to settle it. The pipeline asks for the bytes to be
    /// decoded again for the new track; once that decode is in flight, nothing more is asked.
    static func testDecodeSupersededByATrackChangeIsRedone() {
        var pipeline = TintPipeline()
        let first = TrackIdentity(title: "T1", artist: "X")
        let second = TrackIdentity(title: "T2", artist: "Y")
        let third = TrackIdentity(title: "T3", artist: "Y")
        pipeline.noteCurrentTrack(first)
        _ = pipeline.artworkRequested()
        let firstTint = pipeline.artworkApplied(for: first)

        pipeline.noteCurrentTrack(second)
        let secondsDecode = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(third)
        checkTrue(!pipeline.acceptsArtwork(order: secondsDecode), "T2's decode is superseded")
        checkEqual(pipeline.heldArtworkArrived(for: third, bundleIdentifier: app), .redecode,
                   "T3 inherits bytes nobody will settle, so they are decoded again for it")
        checkTrue(pipeline.artworkTrack != third, "T3 is not recorded as covered meanwhile")

        let thirdsDecode = pipeline.artworkRequested()
        pipeline.noteCurrentTrack(third)
        checkEqual(pipeline.heldArtworkArrived(for: third, bundleIdentifier: app), .noAction,
                   "with T3's own decode in flight there is nothing more to do")
        checkTrue(pipeline.artworkDecodeFailed(order: thirdsDecode, for: third, bundleIdentifier: app) != nil,
                  "and that decode failing settles T3 Colorless")
        checkTrue(!pipeline.accepts(generation: firstTint), "T1's tint does not stay on T3")
    }

    /// A coverless track settles before its bundle is known, so its fallback is the placeholder.
    /// When the bundle arrives the track is declared again, so the fallback becomes the app icon.
    static func testLateBundleRefreshesTheColorlessFallback() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "Podcast", artist: "Someone")
        pipeline.noteCurrentTrack(track)
        checkTrue(pipeline.shouldArmSettleWindow(for: track), "the window arms")
        checkTrue(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: "") != nil,
                  "it settles with no bundle known")
        checkTrue(pipeline.shouldArmSettleWindow(for: track), "the bundle's event arms a new window")
        checkTrue(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: "com.spotify.client") != nil,
                  "a new bundle is declared again, so the fallback shows that app's icon")
        checkEqual(pipeline.colorlessFallback,
                   ColorlessFallback(track: track, bundleIdentifier: "com.spotify.client"),
                   "the fallback on screen is the new app's")
        checkEqual(pipeline.declareColorlessIfSettled(for: track, bundleIdentifier: "com.spotify.client"), nil,
                   "the same bundle again redoes nothing")
    }

    /// The same, for a track that is Colorless because its own bytes did not decode: the bundle
    /// arrives with the unchanged bytes.
    static func testLateBundleRefreshesAnUndecodableTracksFallback() {
        var pipeline = TintPipeline()
        let track = TrackIdentity(title: "T2", artist: "Y")
        pipeline.noteCurrentTrack(track)
        let order = pipeline.artworkRequested()
        checkTrue(pipeline.artworkDecodeFailed(order: order, for: track, bundleIdentifier: "") != nil,
                  "it settles with no bundle known")
        guard case .colorless = pipeline.heldArtworkArrived(for: track, bundleIdentifier: "com.spotify.client") else {
            checkTrue(false, "a late bundle refreshes the fallback")
            return
        }
        checkEqual(pipeline.heldArtworkArrived(for: track, bundleIdentifier: "com.spotify.client"), .noAction,
                   "the same bundle again redoes nothing")
    }

    /// A track whose own cover decoded keeps it when a later piece of its artwork fails, which
    /// leaves the held bytes undecodable. The next track inheriting them first is a track whose
    /// artwork has not arrived yet: it waits out a settle window, and its own cover landing
    /// inside it means it never flashes the fallback.
    static func testInheritedUndecodableBytesWaitForTheTracksOwnCover() {
        var pipeline = TintPipeline()
        let first = TrackIdentity(title: "T1", artist: "X")
        let second = TrackIdentity(title: "T2", artist: "X")
        pipeline.noteCurrentTrack(first)
        _ = pipeline.artworkRequested()
        _ = pipeline.artworkApplied(for: first)
        let laterBytes = pipeline.artworkRequested()
        checkEqual(pipeline.artworkDecodeFailed(order: laterBytes, for: first, bundleIdentifier: app), nil,
                   "T1 keeps its own cover")

        pipeline.noteCurrentTrack(second)
        checkEqual(pipeline.heldArtworkArrived(for: second, bundleIdentifier: app), .armSettleWindow,
                   "T2 inherits T1's undecodable bytes and waits instead of settling at once")
        checkTrue(pipeline.shouldArmSettleWindow(for: second), "the window arms")
        checkEqual(pipeline.heldArtworkArrived(for: second, bundleIdentifier: app), .armSettleWindow,
                   "a refinement asks again, and the window does not re-arm")
        checkTrue(!pipeline.shouldArmSettleWindow(for: second), "one window per track")

        let ownCover = pipeline.artworkRequested()
        checkTrue(pipeline.acceptsArtwork(order: ownCover), "T2's own cover decodes")
        _ = pipeline.artworkApplied(for: second)
        checkEqual(pipeline.declareColorlessIfSettled(for: second, bundleIdentifier: app), nil,
                   "a window that expires afterwards does not take the cover away")
    }
}
