//
//  LauncherView.swift
//  NotBoringNotch
//

import SwiftUI

/// The launcher tab's surface. Only its size is real so far: it reserves the taller notch the
/// launcher needs, which is what makes the height transition observable. The search field,
/// results list, and keyboard handling land here next.
struct LauncherView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
            Text("Launcher")
                .font(.headline)
            Text("Placeholder surface — height only")
                .font(.caption)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    .white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        }
    }
}

#Preview {
    LauncherView()
        .frame(width: 578, height: 396)
        .padding()
        .background(.black)
}
