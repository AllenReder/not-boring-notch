//
//  ReminderChannel.swift
//  NotBoringNotch
//
//  The notch's end of the Reminder Channel: what is on screen, what is waiting, and the
//  listener an external process delivers to. See docs/adr/0007.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// The Reminder Channel: a loopback HTTP port an external process posts Reminders to.
///
/// The ordering policy lives in `ReminderQueue`, and the wire contract in `Reminder`; this type
/// owns the parts that are neither — the listener's lifecycle, the Channel Token, the discovery
/// file, and the clock that ends a Reminder's turn.
@MainActor
final class ReminderChannel: ObservableObject {
    static let shared = ReminderChannel()

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
        let endpoint: String
    }

    @Published private var queue = ReminderQueue()
    @Published private(set) var status: Status = .off
    /// Where the port and token are published for clients to read, once the channel is up.
    @Published private(set) var discoveryPath: String?

    /// The Reminder the notch is showing, if any.
    var visible: Reminder? { queue.visible }

    private let server = ReminderChannelServer()
    private var dismissTask: Task<Void, Never>?
    /// The Reminder whose clock is running, so that drawing the same one again does not
    /// refund its duration.
    private var clocked: Reminder?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Applies the current settings, then keeps applying them as they change.
    func start() {
        guard !started else { return }
        started = true

        server.onReminder = { [weak self] reminder in
            Task { @MainActor in self?.enqueue(reminder) }
        }
        server.onStateChange = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }

        // `options` defaults to `[.initial]`, which fires the moment we subscribe — applying the same
        // settings a second and then a third time, back to back. `[]` means "only when the value
        // actually changes", so the explicit call at the end of this method is the only initial
        // application. Starting a listener twice in a row is what cost the channel its port (see
        // ReminderChannelServerTests).
        Defaults.publisher(.reminderChannelEnabled, options: []).sink { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }.store(in: &cancellables)

        // Every keystroke in the port field is a change, and each one would stop and restart the
        // listener. Only the value the user settles on should cause a rebind.
        Defaults.publisher(.reminderChannelPort, options: [])
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.applySettings() }
            }
            .store(in: &cancellables)

        applySettings()
    }

    // MARK: - Settings

    var port: Int { Defaults[.reminderChannelPort] }
    var token: String { Defaults[.reminderChannelToken] }

    var endpoint: String { Self.endpoint(port: port) }

    private static func endpoint(port: Int) -> String {
        "http://127.0.0.1:\(port)/reminder"
    }

    func regenerateToken() {
        Defaults[.reminderChannelToken] = Self.newToken()
        applySettings()

        // The socket does not change for a new token, so nothing will report `.ready` again. The
        // discovery file has to be rewritten here, or a client would keep reading a retired token.
        if case let .listening(port) = status {
            writeDiscoveryFile(port: port)
        }
    }

    private func applySettings() {
        guard started else { return }

        guard Defaults[.reminderChannelEnabled] else {
            server.stop()
            dismissTask?.cancel()
            clocked = nil
            withAnimation(.smooth(duration: 0.35)) {
                queue = ReminderQueue()
            }
            status = .off
            removeDiscoveryFile()
            return
        }

        server.start(port: UInt16(clamping: Defaults[.reminderChannelPort]), token: currentToken())
    }

    private func apply(_ state: ReminderChannelServer.State) {
        switch state {
        case let .ready(port):
            status = .listening(port: port)
            writeDiscoveryFile(port: port)
        case let .failed(reason):
            status = .failed(reason)
            removeDiscoveryFile()
        }
    }

    /// The token is created on first use and kept, so a client that has read the discovery file
    /// keeps working across launches.
    private func currentToken() -> String {
        let existing = Defaults[.reminderChannelToken]
        guard existing.isEmpty else { return existing }
        let token = Self.newToken()
        Defaults[.reminderChannelToken] = token
        return token
    }

    private static func newToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - The discovery file

    /// Where the channel publishes itself. `Application Support/NotBoringNotch/` is the directory
    /// the app keeps its own state in; the shelf lives beside it.
    private static let directoryName = "NotBoringNotch"

    private var discoveryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent("reminder-channel.json")
    }

    private func writeDiscoveryFile(port: UInt16) {
        guard let url = discoveryURL else { return }
        let discovery = Discovery(port: Int(port), token: token,
                                  endpoint: Self.endpoint(port: Int(port)))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(discovery).write(to: url, options: .atomic)
            discoveryPath = url.path
        } catch {
            discoveryPath = nil
        }
    }

    private func removeDiscoveryFile() {
        guard let url = discoveryURL else { return }
        try? FileManager.default.removeItem(at: url)
        discoveryPath = nil
    }

    // MARK: - What is on screen

    func enqueue(_ reminder: Reminder) {
        withAnimation(.smooth(duration: 0.35)) {
            queue.enqueue(reminder)
        }
    }

    /// Called by whatever view is drawing the Reminder, which is the one place its clock can
    /// start. A Reminder that arrives while the notch is hidden keeps its whole duration for
    /// when it appears. Drawing it again — opening the notch and closing it — does not restart
    /// the clock; a sender replacing its content under the same id does.
    func startShowing(_ reminder: Reminder) {
        guard queue.visible?.id == reminder.id, clocked != reminder else { return }
        clocked = reminder

        if reminder.sound == .standard {
            playAlert()
        }

        dismissTask?.cancel()
        guard !reminder.isSticky else { return }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(reminder.duration))
            guard !Task.isCancelled else { return }
            self?.dismissVisible()
        }
    }

    func dismissVisible() {
        dismissTask?.cancel()
        dismissTask = nil
        clocked = nil
        withAnimation(.smooth(duration: 0.35)) {
            queue.dismissVisible()
        }
    }

    func performAction(_ action: ReminderAction) {
        NSWorkspace.shared.open(action.url)
        dismissVisible()
    }

    private func playAlert() {
        guard Bundle.main.url(forResource: "notch", withExtension: "m4a") != nil else { return }
        AudioPlayer().play(fileName: "notch", fileExtension: "m4a")
    }
}
