//
//  TabSelectionView.swift
//  NotBoringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id: NotchViews
    let label: String
    let icon: String
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.notchShelf) private var notchShelf
    @Default(.performanceTabEnabled) private var performanceTabEnabled
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        var result = [
            TabModel(id: .home, label: "Home", icon: "house.fill")
        ]

        if notchShelf && (!tvm.isEmpty || coordinator.alwaysShowTabs) {
            result.append(TabModel(id: .shelf, label: "Shelf", icon: "tray.fill"))
        }

        result.append(
            TabModel(id: .launcher, label: "Launch", icon: "magnifyingglass")
        )

        if performanceTabEnabled {
            result.append(
                TabModel(
                    id: .performance,
                    label: "Stats",
                    icon: "speedometer"
                )
            )
        }

        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                TabButton(
                    label: tab.label,
                    icon: tab.icon,
                    selected: coordinator.currentView == tab.id
                ) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.id
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.id == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.id == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    TabSelectionView()
        .environmentObject(NotchViewModel())
}
