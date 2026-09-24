//
//  ReminderChannelServerTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/managers/ReminderChannelServer.swift NotBoringNotch/models/Reminder.swift
//
//  Helper names are prefixed (`checkServer*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//
//  These bind real loopback ports. Every port comes from the kernel rather than being
//  written down, so a run cannot fail — or silently skip — because something else on the
//  machine happened to hold a fixed number.
//

import Foundation

func checkServer(_ condition: Bool, _ message: String = "",
                 file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

/// Records what the listener reports. It reports on its own queue, so a test waits for it
/// rather than reading it.
final class ServerStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String] = []

    func record(_ state: String) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }

    var readyCount: Int { all.filter { $0.hasPrefix("ready") }.count }
    var failures: [String] { all.filter { $0.contains("failed") } }

    /// Waits until the recorded states satisfy `predicate`, or gives up.
    @discardableResult
    func wait(until predicate: ([String]) -> Bool, timeout: TimeInterval = 5) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshot = all
            if predicate(snapshot) { return snapshot }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return all
    }
}

/// A port the kernel says is free right now, so the test never names one.
func checkServerFreePort() -> UInt16? {
    let handle = socket(AF_INET, SOCK_STREAM, 0)
    guard handle >= 0 else { return nil }
    defer { close(handle) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)

    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(handle, $0, length) }
    }
    guard bound == 0 else { return nil }

    let named = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(handle, $0, &length) }
    }
    guard named == 0 else { return nil }
    return UInt16(bigEndian: address.sin_port)
}

@main
struct ReminderChannelServerTestsRunner {
    static func main() {
        testStartingTwiceOnTheSamePortKeepsListening()
        testANewTokenDoesNotDropTheSocket()
        testAChangedPortIsRebound()
        print("✅ ReminderChannelServerTests: all passed")
    }

    /// Starting the channel twice with the same settings must leave it listening.
    ///
    /// The bug this exists to catch: `Defaults.publisher` publishes its initial value, and treating
    /// that as a change asked the server to start two or three times in a row at launch. Each
    /// restart cancelled the listener and raced its own closing socket for the port, so the notch
    /// listened nowhere and the discovery file was withdrawn — while the app looked fine, and the
    /// only sign was a wall of `Address already in use` in the console.
    static func testStartingTwiceOnTheSamePortKeepsListening() {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return
        }

        let server = ReminderChannelServer()
        let recorder = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }

        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") },
                    "the first start must listen on \(port), got \(recorder.all)")

        server.start(port: port, token: "token")
        recorder.wait(until: { $0.count(where: { $0.hasPrefix("ready") }) > 1 }, timeout: 1.5)

        checkServer(recorder.failures.isEmpty,
                    "starting twice on one port must not fail, got \(recorder.all)")
        checkServer(recorder.readyCount == 1,
                    "starting twice on one port must not drop and re-take it, got \(recorder.all)")
        server.stop()
    }

    /// Regenerating the Channel Token must not touch the socket: the listener is the same, only
    /// who it answers to changes. Restarting here would race the port the same way.
    static func testANewTokenDoesNotDropTheSocket() {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return
        }

        let server = ReminderChannelServer()
        let recorder = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }

        server.start(port: port, token: "first")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") },
                    "the first start must listen on \(port), got \(recorder.all)")

        server.start(port: port, token: "second")
        recorder.wait(until: { $0.count(where: { $0.hasPrefix("ready") }) > 1 }, timeout: 1.5)

        checkServer(recorder.failures.isEmpty, "a new token must not fail, got \(recorder.all)")
        checkServer(recorder.readyCount == 1,
                    "a new token must not drop the socket, got \(recorder.all)")
        server.stop()
    }

    /// A port the user actually changed is a different question, and must rebind.
    static func testAChangedPortIsRebound() {
        guard let port = checkServerFreePort(), let otherPort = checkServerFreePort() else {
            print("⚠️  could not find two free ports, skipping")
            return
        }

        let server = ReminderChannelServer()
        let recorder = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }

        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") },
                    "the first start must listen on \(port), got \(recorder.all)")

        server.start(port: otherPort, token: "token")
        let states = recorder.wait(until: {
            $0.contains { $0.contains("\(otherPort)") && $0.hasPrefix("ready") }
        })

        checkServer(states.contains { $0.contains("\(otherPort)") && $0.hasPrefix("ready") },
                    "a changed port must be bound, got \(states)")
        checkServer(recorder.failures.isEmpty, "a changed port must not fail, got \(states)")
        server.stop()
    }
}
