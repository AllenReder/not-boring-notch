//
//  LauncherView.swift
//  NotBoringNotch
//

import AppKit
import Defaults
import SwiftUI

/// The launcher tab: search the installed apps, open one with Return.
///
/// This is the one surface in the notch that asks for the keyboard, so opening it takes focus and
/// closing it hands focus back. The tab is never the one the notch reopens on — reopening onto it
/// would take the keyboard from whatever the user was doing.
struct LauncherView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var coordinator = NotchViewCoordinator.shared
    @ObservedObject private var recents = LauncherRecents.shared
    @StateObject private var model = LauncherModel()
    @Default(.launcherRowHeight) private var rowHeight: CGFloat
    @Default(.launcherRecentsLimit) private var recentsLimit: Int

    @State private var query = ""
    @State private var selection = 0
    /// The row the last command asked the list to bring into view, cleared once it has.
    @State private var scrollTarget: String?
    @State private var window: NSWindow?
    /// Set when Return opened an app: that app takes focus, so nothing here gives it back.
    @State private var isLaunching = false
    @FocusState private var isSearching: Bool

    /// The top of the list, so a new query starts above the Recent header rather than below it.
    private static let topAnchor = "launcher.top"

    private var metrics: LauncherMetrics { LauncherMetrics(rowHeight: rowHeight) }

    var body: some View {
        content(
            LauncherList(apps: model.apps, recents: recentApps, query: query, metrics: metrics))
    }

    private func content(_ list: LauncherList) -> some View {
        VStack(spacing: metrics.spacing) {
            searchField(list)
            rows(list)
        }
        .padding(.horizontal, 6)
        .onAppear { model.refresh() }
        .onDisappear {
            if !isLaunching { NSApp.deactivate() }
        }
        // A new query is a new list: it starts at the top, on its first row.
        .onChange(of: query) { _, _ in
            selection = 0
            scrollTarget = Self.topAnchor
        }
        // The surface follows what is on it: a search with two matches has no reason to be the
        // height of a list it is not showing. The window was sized for the maximum already.
        .onChange(of: list.neededHeight, initial: true) { _, height in
            coordinator.contentHeight = height
        }
        .onExitCommand { vm.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            notification in
            // Losing key means the user clicked away. Switching tabs hands key back here too, and
            // the pointer still being over the notch is what tells the two apart.
            guard let resigning = notification.object as? NSWindow, resigning === window,
                !vm.isMouseHovering()
            else { return }
            vm.close()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) {
            _ in
            // The app losing activation is the same fact as the window losing key, and it arrives
            // even when the window never became key. Only the pointer tells it apart from the
            // launcher switching tabs, which deactivates the app with the pointer still there.
            guard !vm.isMouseHovering() else { return }
            vm.close()
        }
        .background(WindowReader { readerWindow in
            window = readerWindow
            // A key window in an inactive app receives nothing, so typing needs both.
            NSApp.activate()
            readerWindow?.makeKey()
            isSearching = true
        })
    }

    // MARK: - Field

    private func searchField(_ list: LauncherList) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($isSearching)
                .onSubmit { open(list.selected(selection)?.app) }
                .onKeyPress(.upArrow) { move(by: -1, in: list) }
                .onKeyPress(.downArrow) { move(by: 1, in: list) }
        }
        .padding(.horizontal, 10)
        .frame(height: metrics.field)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08))
        )
    }

    // MARK: - Rows

    /// The apps the user switched to most recently, resolved to what the list can draw and cut to
    /// the setting. Resolved before the cut: an app that has since been uninstalled should not eat
    /// one of the rows the setting asked for.
    private var recentApps: [LauncherApp] {
        Array(recents.bundleIDs.compactMap(model.app(withBundleID:)).prefix(recentsLimit))
    }

    private func rows(_ list: LauncherList) -> some View {
        let selectedID = list.selected(selection)?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchor)
                    if !list.recentRows.isEmpty {
                        header("Recent")
                        ForEach(list.recentRows) { appRow($0, selected: $0.id == selectedID) }
                        if !list.otherRows.isEmpty { separator }
                    }
                    ForEach(list.otherRows) { appRow($0, selected: $0.id == selectedID) }
                    if list.isEmpty {
                        // Two literals rather than one ternary: `Text` only localizes what it can
                        // see as a literal, and a String built in code is drawn verbatim.
                        Group {
                            if list.typed.isEmpty {
                                Text("No apps found")
                            } else {
                                Text("No app matches “\(list.typed)”")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .frame(height: metrics.row, alignment: .bottomLeading)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, metrics.spacing)
            }
            // Only a command moves the list. The pointer never scrolls it: dragging the row out
            // from under the pointer would drag the selection along with it.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
    }

    /// Takes a key rather than a String so the title is localized; `Text(String)` is drawn
    /// verbatim.
    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.gray)
            .frame(height: metrics.header, alignment: .bottomLeading)
            .padding(.horizontal, 8)
    }

    /// A hairline in the middle of the space the list reserves for it.
    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .frame(height: metrics.separator)
            .padding(.horizontal, 8)
    }

    private func appRow(_ row: LauncherList.Row, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: model.icon(for: row.app))
                .resizable()
                .frame(width: metrics.icon, height: metrics.icon)
            Text(row.app.name)
                .font(.system(size: metrics.name, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: metrics.row)
        .background(
            RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
                .fill(selected ? .white.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { open(row.app) }
        // The pointer is the same cursor as the arrow keys: whatever is under it is what Return
        // opens. Leaving does not move the selection back, so the pointer can leave to type.
        .onHover { inside in
            guard inside else { return }
            selection = row.index
        }
    }

    // MARK: - Actions

    private func move(by delta: Int, in list: LauncherList) -> KeyPress.Result {
        guard let current = list.selected(selection) else { return .handled }
        let next = min(max(current.index + delta, 0), list.rows.count - 1)
        selection = next
        scrollTarget = list.rows[next].id
        return .handled
    }

    /// Launches, and leaves focus to the app that opens: this surface is done.
    private func open(_ app: LauncherApp?) {
        guard let app else { return }
        isLaunching = true
        NSWorkspace.shared.openApplication(
            at: app.url, configuration: NSWorkspace.OpenConfiguration())
        vm.close()
    }
}

// MARK: - Model

/// The installed apps, and the icons the list draws for them.
@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var apps: [LauncherApp] = []

    /// Decoding an icon costs more than the row it lands in, so each one is decoded once.
    private var icons: [String: NSImage] = [:]
    private var isScanning = false

    /// Re-reads the app folders. Cheap enough to run on every open, which is what makes an app
    /// installed a minute ago findable now.
    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let found = LauncherAppScanner.scan()
            await MainActor.run {
                self.apps = found
                self.isScanning = false
            }
        }
    }

    /// A recent app is not necessarily in the scanned folders, so the system is asked as well.
    func app(withBundleID bundleID: String) -> LauncherApp? {
        if let known = apps.first(where: { $0.bundleID == bundleID }) { return known }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return LauncherApp(
            url: url, name: LauncherAppScanner.displayName(of: url), bundleID: bundleID)
    }

    func icon(for app: LauncherApp) -> NSImage {
        if let cached = icons[app.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = icon
        return icon
    }
}

// MARK: - Window

/// Hands over the window the launcher landed in, once it is in the hierarchy.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { Reader(onWindow: onWindow) }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        private let onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow(window)
        }
    }
}

#Preview {
    LauncherView()
        .environmentObject(NotchViewModel())
        .frame(width: 578, height: 396)
        .padding()
        .background(.black)
}
