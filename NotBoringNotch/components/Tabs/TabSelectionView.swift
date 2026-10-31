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
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.notchShelf) private var notchShelf
    @Default(.performanceTabEnabled) private var performanceTabEnabled
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        var result = [
            TabModel(id: .home, label: "Home", icon: "house.fill", view: .home)
        ]

        if notchShelf && (!tvm.isEmpty || coordinator.alwaysShowTabs) {
            result.append(TabModel(id: .shelf, label: "Shelf", icon: "tray.fill", view: .shelf))
        }

        if performanceTabEnabled {
            result.append(
                TabModel(
                    id: .performance,
                    label: "Stats",
                    icon: "speedometer",
                    view: .performance
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
                    selected: coordinator.currentView == tab.view
                ) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
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
