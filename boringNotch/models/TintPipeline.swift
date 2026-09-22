//
//  TintPipeline.swift
//  boringNotch
//
//  Ordering and identity policy for the artwork → Tint Source pipeline.
//  See docs/adr/0003-tint-source-and-colorless-fallback.md.
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

/// Pure, synchronous state for the two timing defects this pipeline guards against:
/// a stale color derivation publishing after a newer one, and a track that already
/// has artwork being declared Colorless.
struct TintPipeline {
    private(set) var generation: Int = 0

    /// The track whose artwork has been applied. Never the Artwork Fallback.
    private(set) var artworkTrack: TrackIdentity?

    private var armedTrack: TrackIdentity?

    /// A derivation may publish only if no newer artwork has been applied since it started.
    func accepts(generation: Int) -> Bool {
        generation == self.generation
    }

    /// A track's artwork was applied, so it owns the Tint Source from now on.
    /// Returns the generation its derivation must carry.
    mutating func artworkApplied(for track: TrackIdentity) -> Int {
        generation &+= 1
        artworkTrack = track
        armedTrack = nil
        return generation
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
    /// metadata-only event must not take the tint away from a covered track.
    mutating func declareColorlessIfSettled(for track: TrackIdentity) -> Int? {
        guard artworkTrack != track else { return nil }
        generation &+= 1
        armedTrack = nil
        return generation
    }
}
