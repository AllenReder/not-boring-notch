// The camera: the whole stage scene (wallpaper, notch) is scaled about the top centre of the
// stage, where the notch sits, by the timeline's camera cues. SwiftUI's scaleEffect keeps text
// crisp and leaves the window server's glass working.

import SwiftUI

struct CameraLayer<Content: View>: View {
    let timeline: Timeline
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation) { _ in
            let c = timeline.camera(at: max(StudioClock.shared.now, 0))
            content
                .scaleEffect(c.zoom, anchor: .top)
                .offset(c.pan)
        }
    }
}
