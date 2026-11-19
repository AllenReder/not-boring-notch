//
//  TintPipeline.swift
//  NotBoringNotch
//
//  Ordering and identity policy for the artwork → Tint Source pipeline.
//

import Foundation

/// Identity of a track for the purpose of remembering which artwork belongs to it.
///
/// Deliberately excludes the album and the bundle identifier: both can arrive
/// after the track itself does, so including them would make one track look like
/// two and would let the Tint Settle Window expire on a track that has artwork.
struct TrackIdentity: Equatable {
    var title: String
    var artist: String
}

/// Where a piece of artwork came from. Only `trackArtwork` may become a Tint Source.
enum ArtworkProvenance {
    case trackArtwork
    case appIconFallback
}

/// What is known about the artwork bytes the notch holds.
enum HeldArtwork: Equatable {
    /// A decode of the bytes was requested with this order and has not resolved, so they are
    /// neither a cover nor known to be absent.
    case decoding(order: Int)
    /// The bytes decoded into a cover.
    case decoded
    /// The bytes could not be decoded for this track: they are absent artwork.
    case undecodable(track: TrackIdentity)
}

/// What the notch must do when the artwork bytes it already holds arrive again for a track.
enum HeldArtworkOutcome: Equatable {
    /// Nothing: the bytes are this track's cover now, or their decode is still on its way.
    case noAction
    /// The track is Colorless: show the Artwork Fallback and drop the tint.
    case colorless(generation: Int)
    /// The decode of these bytes was superseded by the change of track, so nothing will settle
    /// this track: decode the same bytes again for it.
    case redecode
    /// The bytes failed to decode for the previous track. Treat this track as one that arrived
    /// without artwork: its own may still come, so wait out the Tint Settle Window.
    case armSettleWindow
}

/// The Artwork Fallback on screen for a Colorless track. The bundle is part of it because the
/// fallback is the playback app's icon, which must follow a bundle that arrives late.
struct ColorlessFallback: Equatable {
    var track: TrackIdentity
    var bundleIdentifier: String
}

/// Pure, synchronous state for the two timing defects this pipeline guards against:
/// a stale color derivation publishing after a newer one, and a track that already
/// has artwork being declared Colorless.
struct TintPipeline {
    private(set) var generation: Int = 0

    /// The track whose artwork has been applied. Never the Artwork Fallback. Also set for a
    /// track that inherited the bytes already on screen (`noteCoverApplied`).
    private(set) var artworkTrack: TrackIdentity?

    /// The track whose own artwork bytes were decoded and applied. Unlike `artworkTrack`, never
    /// set by inheriting bytes, so it tells a track's own cover from the previous track's.
    private(set) var decodedTrack: TrackIdentity?

    /// The most recent Colorless declaration, cleared once any artwork is applied. While it is
    /// set the notch shows this Artwork Fallback with no tint, so declaring the same track
    /// Colorless again for the same bundle has nothing to do.
    private(set) var colorlessFallback: ColorlessFallback?

    /// Ordering for the decoded image itself: claimed when the notch learns of a piece of
    /// artwork, before its decode is dispatched, and validated when the decode returns. It is
    /// deliberately not `generation` — a Colorless declaration must not supersede a decode that
    /// is still in flight.
    private(set) var artworkOrder: Int = 0

    /// The track the notch has most recently been told about. Only a change of track supersedes
    /// pending decodes, so a refinement of the same track leaves them alone.
    private var currentTrack: TrackIdentity?

    private var armedTrack: TrackIdentity?

    /// What is known about the artwork bytes the notch holds. Undecodable bytes stay "seen", so
    /// the same bytes arriving again do not start another decode, but they never count as a
    /// cover: a track that receives them is Colorless, not covered. No bytes are held before the
    /// first request, so the initial value is never consulted; it is the one whose worst case is
    /// another decode.
    private(set) var heldArtwork: HeldArtwork = .decoding(order: 0)

    /// A derivation may publish only if no newer artwork has been applied since it started.
    func accepts(generation: Int) -> Bool {
        generation == self.generation
    }

    /// A track's artwork was applied, so it owns the Tint Source from now on.
    /// Returns the generation its derivation must carry.
    mutating func artworkApplied(for track: TrackIdentity) -> Int {
        generation &+= 1
        artworkTrack = track
        decodedTrack = track
        colorlessFallback = nil
        armedTrack = nil
        heldArtwork = .decoded
        return generation
    }

    /// Claims the order for an artwork decode that is about to be dispatched. A decode may be
    /// applied only while its order is the newest one, and only while the notch is still on the
    /// track it was requested for.
    mutating func artworkRequested() -> Int {
        artworkOrder &+= 1
        heldArtwork = .decoding(order: artworkOrder)
        return artworkOrder
    }

    /// The decode claimed with `order` produced no image. Artwork that cannot be decoded is
    /// absent artwork, so the track settles Colorless now — the Tint Settle Window was
    /// cancelled when the bytes arrived and will not do it later.
    ///
    /// A cover the track merely inherited (`noteCoverApplied`) does not protect it: those bytes
    /// were the previous track's, and keeping them on screen is the failure this guards against.
    /// Only a cover decoded from the track's own bytes is kept.
    ///
    /// Returns the new generation when the track is Colorless, or `nil` when there is nothing
    /// to do: the decode is stale (a newer request or a change of track superseded it, and a
    /// stale failure must not touch state that belongs to the newer one), the track already
    /// shows a cover decoded from its own bytes, or it is already Colorless.
    mutating func artworkDecodeFailed(order: Int, for track: TrackIdentity,
                                      bundleIdentifier: String) -> Int? {
        guard acceptsArtwork(order: order) else { return nil }
        heldArtwork = .undecodable(track: track)
        guard decodedTrack != track else { return nil }
        if artworkTrack == track {
            artworkTrack = nil
        }
        return declareColorlessIfSettled(for: track, bundleIdentifier: bundleIdentifier)
    }

    /// The artwork bytes the notch already holds arrived for this track, so no decode starts.
    ///
    /// - Bytes that decoded become this track's cover (`noteCoverApplied`).
    /// - Bytes still decoding are left to their decode, which settles the track either way —
    ///   recording them as a cover now would make a failed decode look like a covered track.
    ///   If a change of track superseded that decode, it will be dropped and settle nothing, so
    ///   the bytes must be decoded again for this track.
    /// - Bytes that failed to decode for this track leave it Colorless, exactly as when they
    ///   first failed (a bundle that arrived since refreshes the fallback). Bytes that failed for
    ///   the previous track only mean this track has no artwork yet, so it gets a Tint Settle
    ///   Window like any track whose metadata arrives first.
    mutating func heldArtworkArrived(for track: TrackIdentity,
                                     bundleIdentifier: String) -> HeldArtworkOutcome {
        switch heldArtwork {
        case .decoded:
            noteCoverApplied(for: track)
            return .noAction
        case .decoding(let order):
            return acceptsArtwork(order: order) ? .noAction : .redecode
        case .undecodable(let failedTrack):
            guard failedTrack == track || colorlessFallback?.track == track else {
                return .armSettleWindow
            }
            guard let generation = declareColorlessIfSettled(for: track,
                                                             bundleIdentifier: bundleIdentifier)
            else { return .noAction }
            return .colorless(generation: generation)
        }
    }

    /// Records the track the notch is on now. Moving to a different track supersedes every decode
    /// still in flight: they belong to a track the notch has left, and applying one would show the
    /// previous track's cover and publish its tint over the current track — including over a
    /// track that settled Colorless.
    mutating func noteCurrentTrack(_ track: TrackIdentity) {
        guard currentTrack != track else { return }
        currentTrack = track
        artworkOrder &+= 1
    }

    /// Whether a decoded image still belongs to the newest artwork request.
    func acceptsArtwork(order: Int) -> Bool {
        order == artworkOrder
    }

    /// Whether the Tint Settle Window should be armed for this track. One window per
    /// track: metadata that keeps refining must not slide it.
    mutating func shouldArmSettleWindow(for track: TrackIdentity) -> Bool {
        guard armedTrack != track else { return false }
        armedTrack = track
        return true
    }

    /// Records that the artwork already on screen belongs to this track, without
    /// advancing the generation: the bytes did not change, so the derivation they
    /// belong to is still the current one and must be allowed to publish. Needed for
    /// the rest of an album, whose tracks share one cover and therefore never reach
    /// `artworkApplied`.
    mutating func noteCoverApplied(for track: TrackIdentity) {
        artworkTrack = track
        armedTrack = nil
    }

    /// The Tint Settle Window expired. Returns the new generation when the track is
    /// Colorless, or `nil` when artwork is already known for it — the case where a
    /// metadata-only event must not take the tint away from a covered track — or when the
    /// track already shows the Artwork Fallback for this bundle, so repeated events do not redo
    /// it. A bundle that arrives after the track settled is declared again, so the fallback
    /// can show that app's icon.
    mutating func declareColorlessIfSettled(for track: TrackIdentity,
                                            bundleIdentifier: String) -> Int? {
        let fallback = ColorlessFallback(track: track, bundleIdentifier: bundleIdentifier)
        guard artworkTrack != track, colorlessFallback != fallback else { return nil }
        generation &+= 1
        armedTrack = nil
        colorlessFallback = fallback
        return generation
    }
}
