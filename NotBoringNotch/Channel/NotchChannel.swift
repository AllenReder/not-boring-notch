//
//  NotchChannel.swift
//  NotBoringNotch
//
//  The notch's end of the Notch Channel: the banner on screen, the ones waiting, the Inbox, and
//  the listener an external process delivers to.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// The Notch Channel: a loopback HTTP port an external process posts notifications to.
///
/// The ordering policy lives in `BannerQueue`, what is kept in `NotificationInbox`, and the wire
/// contract in `ChannelNotification`; this type owns the parts that are none of those — the
/// listener's lifecycle, the Channel Token, the discovery file, the Inbox on disk, and the clock
/// that ends a banner's turn.
@MainActor
final class NotchChannel: ObservableObject {
    static let shared = NotchChannel()

    enum Status: Equatable {
        case off
        case listening(port: UInt16)
        /// Why the channel is not listening, ready to show in Settings.
        case failed(String)
    }

    /// What the sender is told it can reach, and with what.
    struct Discovery: Codable {
        let port: Int
        let token: String
        /// The v1 endpoint, which every client written before v2 reads.
        let endpoint: String
        /// Where every v2 route hangs from.
        let baseURL: String

        enum CodingKeys: String, CodingKey {
            case port, token, endpoint
            case baseURL = "base_url"
        }
    }

    @Published private var banners = BannerQueue()
    @Published private(set) var inbox = NotificationInbox()
    @Published private(set) var activities = ActivityStore()
    @Published private(set) var status: Status = .off
    /// Where the port and token are published for clients to read, once the channel is up.
    @Published private(set) var discoveryPath: String?
    /// The notification the Inbox should bring into view when it next appears: the banner the
    /// user opened the notch over.
    @Published var focusedID: String?

    /// The banner the closed notch is showing, if any.
    var visibleBanner: ChannelNotification? { banners.visible }

    /// Whether the Inbox tab is on screen right now. Anything delivered while it is goes straight
    /// into the list the user is looking at, rather than into a banner they would see on close.
    var isInboxOnScreen = false {
        didSet {
            if isInboxOnScreen { markInboxRead() }
        }
    }

    private let server = ChannelServer()
    private var dismissTask: Task<Void, Never>?
    /// Wakes when the next activity is due to leave.
    private var sweepTask: Task<Void, Never>?
    /// The banner whose clock is running, so that drawing the same one again does not refund its
    /// duration.
    private var clocked: ChannelNotification?
    /// The banner that was on screen when the user opened the notch. Opening it is looking at it.
    private var seenBannerID: String?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Applies the current settings, then keeps applying them as they change.
    func start() {
        guard !started else { return }
        started = true

        // A request accepted just before the channel was turned off arrives here just after. The
        // check is made on arrival, so turning the channel off cannot be undone by a late delivery.
        server.onNotification = { [weak self] notification in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.deliver(notification)
            }
        }
        server.onWithdraw = { [weak self] id in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.withdraw(id: id)
            }
        }
        server.onActivity = { [weak self] request in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.handle(request)
            }
        }
        server.onStateChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }

        // `options` defaults to `[.initial]`, which fires the moment we subscribe — applying the same
        // settings a second and then a third time, back to back. `[]` means "only when the value
        // actually changes", so the explicit call at the end of this method is the only initial
        // application. Starting a listener twice in a row is what cost the channel its port (see
        // ChannelServerTests).
        Defaults.publisher(.notchChannelEnabled, options: []).sink { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }.store(in: &cancellables)

        // Every keystroke in the port field is a change, and each one would stop and restart the
        // listener. Only the value the user settles on should cause a rebind.
        Defaults.publisher(.notchChannelPort, options: [])
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.applySettings() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.notchChannelKeepsHistory, options: []).sink { [weak self] change in
            Task { @MainActor in
                guard let self else { return }
                if change.newValue {
                    self.saveInbox()
                } else {
                    self.removeInboxFile()
                }
            }
        }.store(in: &cancellables)

        loadInbox()
        applySettings()
    }

    // MARK: - Settings

    var port: Int { Defaults[.notchChannelPort] }
    var token: String { Defaults[.notchChannelToken] }
    var isEnabled: Bool { Defaults[.notchChannelEnabled] }

    var endpoint: String { Self.baseURL(port: port) + "/v2/notifications" }

    private static func baseURL(port: Int) -> String {
        "http://127.0.0.1:\(port)"
    }

    func regenerateToken() {
        Defaults[.notchChannelToken] = Self.newToken()
        applySettings()

        // The socket does not change for a new token, so nothing will report `.ready` again. The
        // discovery file has to be rewritten here, or a client would keep reading a retired token.
        if case let .listening(port) = status {
            writeDiscoveryFiles(port: port)
        }
    }

    private func applySettings() {
        guard started else { return }

        guard Defaults[.notchChannelEnabled] else {
            server.stop()
            dismissTask?.cancel()
            clocked = nil
            seenBannerID = nil
            sweepTask?.cancel()
            withAnimation(.smooth(duration: 0.35)) {
                banners.removeAll()
                activities.removeAll()
            }
            status = .off
            removeDiscoveryFiles()
            return
        }

        server.start(port: UInt16(clamping: Defaults[.notchChannelPort]), token: currentToken())
    }

    private func apply(_ state: ChannelServer.State) {
        switch state {
        case let .ready(port):
            status = .listening(port: port)
            writeDiscoveryFiles(port: port)
        case let .failed(reason):
            status = .failed(reason)
            removeDiscoveryFiles()
        }
    }

    /// The token is created on first use and kept, so a client that has read the discovery file
    /// keeps working across launches.
    private func currentToken() -> String {
        let existing = Defaults[.notchChannelToken]
        guard existing.isEmpty else { return existing }
        let token = Self.newToken()
        Defaults[.notchChannelToken] = token
        return token
    }

    private static func newToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - Files

    /// `Application Support/NotBoringNotch/` is the directory the app keeps its own state in; the
    /// shelf lives beside it.
    private static let directoryName = "NotBoringNotch"

    /// The discovery file's current name, and the name v1 clients were told to read. Both are
    /// written with the same content, so neither kind of client has to change.
    private static let discoveryFileNames = ["notch-channel.json", "reminder-channel.json"]
    private static let inboxFileName = "notch-channel-inbox.json"

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private func writeDiscoveryFiles(port: UInt16) {
        guard let directory = Self.directory else { return }
        let discovery = Discovery(port: Int(port), token: token,
                                  endpoint: Self.baseURL(port: Int(port)) + "/reminder",
                                  baseURL: Self.baseURL(port: Int(port)))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(discovery)
            for name in Self.discoveryFileNames {
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
            discoveryPath = directory.appendingPathComponent(Self.discoveryFileNames[0]).path
        } catch {
            discoveryPath = nil
        }
    }

    private func removeDiscoveryFiles() {
        guard let directory = Self.directory else { return }
        for name in Self.discoveryFileNames {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        discoveryPath = nil
    }

    /// Writes happen off the main thread, in order, so a burst of deliveries cannot reorder them.
    private let inboxWriter = DispatchQueue(label: "com.allenreder.notboringnotch.notch-channel.inbox")

    private func loadInbox() {
        guard Defaults[.notchChannelKeepsHistory],
              let url = Self.directory?.appendingPathComponent(Self.inboxFileName),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(NotificationInbox.self, from: data) else {
            return
        }
        inbox = stored
    }

    private func saveInbox() {
        guard Defaults[.notchChannelKeepsHistory],
              let directory = Self.directory,
              let data = try? JSONEncoder().encode(inbox) else { return }
        let url = directory.appendingPathComponent(Self.inboxFileName)
        inboxWriter.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func removeInboxFile() {
        guard let url = Self.directory?.appendingPathComponent(Self.inboxFileName) else { return }
        inboxWriter.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Delivery

    func deliver(_ notification: ChannelNotification) {
        let leavesTheBanner = notification.level == .passive || isInboxOnScreen
        if leavesTheBanner, banners.visible?.id == notification.id { resetClock() }

        withAnimation(.smooth(duration: 0.35)) {
            inbox.deliver(notification, read: isInboxOnScreen)

            if leavesTheBanner {
                // Either it never asked for a banner, or the user is already reading the list it
                // just landed in. A banner it may have had under this id goes too.
                banners.remove(id: notification.id)
            } else {
                banners.enqueue(notification)
            }
        }

        if isInboxOnScreen, notification.level != .passive, notification.sound == .standard {
            playAlert()
        }
        saveInbox()
    }

    /// The sender took it back: it leaves the banner and the Inbox alike.
    func withdraw(id: String) {
        if banners.visible?.id == id { resetClock() }
        withAnimation(.smooth(duration: 0.35)) {
            banners.remove(id: id)
            inbox.remove(id: id)
        }
        saveInbox()
    }

    // MARK: - Activities

    /// An activity request from a sender. Updates change the activity in place and silently; only an
    /// `alert` reaches the user as a notification, and only an end leaves one in the Inbox.
    func handle(_ request: ChannelServer.ActivityRequest) {
        let now = Date()
        switch request {
        case let .update(id, update):
            let activity = withAnimation(.smooth(duration: 0.35)) {
                activities.update(id: id, with: update, now: now)
            }
            if let alert = update.alert {
                deliver(activity.notification(for: alert, now: now))
            }

        case let .end(id, update, ending):
            let ended = withAnimation(.smooth(duration: 0.35)) {
                activities.end(id: id, with: update, ending: ending, now: now)
            }
            guard let ended else { break }
            // An alert on the end is the sender asking for the ending to be announced; otherwise it
            // is filed quietly, replacing whatever alert the activity left in the Inbox before.
            if let alert = update.alert {
                deliver(ended.notification(for: alert, now: now))
            } else if ending.leavesNotification {
                deliver(ended.outcome(now: now))
            }

        case let .remove(id):
            withAnimation(.smooth(duration: 0.35)) {
                _ = activities.remove(id: id)
            }
            withdraw(id: ChannelActivity.notificationID(for: id))
        }
        scheduleSweep()
    }

    /// The activity's default action, as a click on it performs. One that has ended is done with.
    func open(_ activity: ChannelActivity) {
        if let target = activity.clickTarget {
            perform(target)
        }
        if activity.isEnded {
            dismissActivity(id: activity.id)
        }
    }

    /// The user put it away. A sender that updates it again brings it back.
    func dismissActivity(id: String) {
        withAnimation(.smooth(duration: 0.35)) {
            _ = activities.remove(id: id)
        }
        scheduleSweep()
    }

    func dismissAllActivities() {
        withAnimation(.smooth(duration: 0.35)) {
            activities.removeAll()
        }
        scheduleSweep()
    }

    private func scheduleSweep() {
        sweepTask?.cancel()
        guard let deadline = activities.nextDeadline else {
            sweepTask = nil
            return
        }
        sweepTask = Task { [weak self] in
            let wait = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.35)) {
                _ = self.activities.sweep(now: Date())
            }
            self.scheduleSweep()
        }
    }

    // MARK: - The banner

    /// Called by the view drawing the banner, which is the one place its clock can start. A banner
    /// that arrives while the notch is hidden keeps its whole duration for when it appears. Drawing
    /// it again does not restart the clock; a sender replacing its content under the same id does.
    func startShowing(_ notification: ChannelNotification) {
        guard banners.visible?.id == notification.id, clocked != notification else { return }
        clocked = notification

        if notification.sound == .standard {
            playAlert()
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(notification.duration))
            // Only the clock of the banner still on screen ends a turn. One whose banner was
            // replaced or withdrawn meanwhile must not end its successor's.
            guard !Task.isCancelled, let self, self.clocked == notification,
                  self.banners.visible == notification else { return }
            self.endTurn()
        }
    }

    /// The notch is hiding ordinary banners (fullscreen). A time-sensitive one waiting behind an
    /// ordinary one that cannot be shown is let through instead of waiting for fullscreen to end.
    /// Only a banner whose clock has not started steps back: one already on screen has been seen.
    func letTimeSensitiveThrough() {
        guard let visible = banners.visible, clocked?.id != visible.id else { return }
        withAnimation(.smooth(duration: 0.35)) {
            _ = banners.yieldToTimeSensitive()
        }
    }

    /// Whether a time-sensitive banner is waiting behind the one on screen.
    var hasTimeSensitiveWaiting: Bool {
        banners.waiting.contains { $0.level == .timeSensitive }
    }

    private func endTurn() {
        dismissTask = nil
        withAnimation(.smooth(duration: 0.35)) {
            banners.turnEnded()
        }
        if banners.visible?.id != clocked?.id {
            clocked = nil
        }
    }

    func dismissVisibleBanner() {
        resetClock()
        withAnimation(.smooth(duration: 0.35)) {
            banners.dismissVisible()
        }
    }

    private func resetClock() {
        dismissTask?.cancel()
        dismissTask = nil
        clocked = nil
    }

    /// The notch opened over a banner: the user is looking at it, and the Inbox should show it.
    /// Returns whether there was one, so the caller can switch to the Inbox.
    @discardableResult
    func notchOpened(showingBanner banner: ChannelNotification?) -> Bool {
        guard let banner, banner.id == banners.visible?.id else { return false }
        seenBannerID = banner.id
        focusedID = banner.id
        return true
    }

    /// The notch closed. A banner the user opened it over has been seen, and gives way.
    func notchClosed() {
        defer { seenBannerID = nil }
        guard let seen = seenBannerID, seen == banners.visible?.id else { return }
        dismissVisibleBanner()
    }

    // MARK: - The Inbox

    func markInboxRead() {
        guard inbox.unreadCount > 0 else { return }
        inbox.markAllRead()
        saveInbox()
    }

    /// The notification's default action, as a click on it performs. A notification acted on is
    /// done, as on iOS: it leaves the Inbox. One with nowhere to go stays.
    func open(_ notification: ChannelNotification) {
        guard let target = notification.clickTarget else { return }
        perform(target)
        remove(id: notification.id)
    }

    func perform(_ action: ChannelAction, of notification: ChannelNotification) {
        switch action.kind {
        case let .url(url):
            NSWorkspace.shared.open(url)
        case let .copy(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        remove(id: notification.id)
    }

    /// The user cleared it.
    func remove(id: String) {
        if banners.visible?.id == id { resetClock() }
        withAnimation(.smooth(duration: 0.35)) {
            banners.remove(id: id)
            inbox.remove(id: id)
        }
        saveInbox()
    }

    func clearInbox() {
        resetClock()
        withAnimation(.smooth(duration: 0.35)) {
            banners.removeAll()
            inbox.removeAll()
        }
        saveInbox()
    }

    private func perform(_ target: ChannelOpenTarget) {
        switch target {
        case let .url(url):
            NSWorkspace.shared.open(url)
        case let .app(identifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func playAlert() {
        guard Bundle.main.url(forResource: "notch", withExtension: "m4a") != nil else { return }
        AudioPlayer().play(fileName: "notch", fileExtension: "m4a")
    }
}
