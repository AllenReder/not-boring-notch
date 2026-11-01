//
//  LauncherView.swift
//  NotBoringNotch
//

import AppKit
import SwiftUI

/// The launcher tab: search the installed apps, open one with Return.
///
/// This is the one surface in the notch that asks for the keyboard, so opening it takes focus and
/// closing it hands focus back. The tab is never the one the notch reopens on — reopening onto it
/// would take the keyboard from whatever the user was doing.
struct LauncherView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var recents = LauncherRecents.shared
    @StateObject private var model = LauncherModel()

    @State private var query = ""
    @State private var selection = 0
    @State private var window: NSWindow?
    /// Set when Return opened an app: that app takes focus, so nothing here gives it back.
    @State private var isLaunching = false
    @FocusState private var isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            searchField
            list
        }
        .padding(.horizontal, 6)
        .onAppear { model.refresh() }
        .onDisappear {
            if !isLaunching { NSApp.deactivate() }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: model.apps) { _, _ in selection = 0 }
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
        .background(WindowReader { readerWindow in
            window = readerWindow
            // A key window in an inactive app receives nothing, so typing needs both.
            NSApp.activate()
            readerWindow?.makeKey()
            isSearching = true
        })
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($isSearching)
                .onSubmit { open(selected(in: rows)) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.downArrow) { move(by: 1) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08))
        )
    }

    // MARK: - Rows

    /// The apps the user switched to most recently, resolved to rows.
    private var recentApps: [LauncherApp] {
        recents.bundleIDs.compactMap(model.app(withBundleID:))
    }

    /// What the field is asking for: its matches, or — while it is empty — every app the recents
    /// above it have not already shown.
    private var matches: [LauncherApp] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            let shown = Set(recentApps.map(\.identity))
            return model.apps.filter { !shown.contains($0.identity) }
        }
        return LauncherSearch.ranked(model.apps, query: typed)
    }

    /// Everything the list draws, in order, so the selection is one index over both sections.
    private var rows: [LauncherApp] { recentApps + matches }

    /// Clamped on read: the query and the scan can both shrink the list under a selection the
    /// user already set.
    private func selected(in rows: [LauncherApp]) -> LauncherApp? {
        rows.isEmpty ? nil : rows[min(max(selection, 0), rows.count - 1)]
    }

    private var list: some View {
        let rows = self.rows
        let selectedID = selected(in: rows)?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !recentApps.isEmpty {
                        header("Recent")
                        ForEach(recentApps) { appRow($0, selected: $0.id == selectedID) }
                    }
                    ForEach(matches) { appRow($0, selected: $0.id == selectedID) }
                    if rows.isEmpty {
                        Text(query.isEmpty ? "No apps found" : "No app matches “\(query)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.gray)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func appRow(_ app: LauncherApp, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: model.icon(for: app))
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? .white.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { open(app) }
    }

    // MARK: - Actions

    private func move(by delta: Int) -> KeyPress.Result {
        let count = rows.count
        guard count > 0 else { return .handled }
        let current = min(max(selection, 0), count - 1)
        selection = min(max(current + delta, 0), count - 1)
        return .handled
    }

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
