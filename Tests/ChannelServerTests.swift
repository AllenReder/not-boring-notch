//
//  ChannelServerTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/Channel/Server/ChannelServer.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift NotBoringNotch/Channel/Agents/AgentSession.swift NotBoringNotch/Channel/Agents/AgentEvent.swift NotBoringNotch/Channel/Agents/AgentAdapter.swift
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

/// Sends `request` byte for byte — framing URLSession would never produce — and returns the
/// response's status line, or "" if the server closed without answering.
func checkServerRaw(_ request: String, port: UInt16) -> String {
    let handle = socket(AF_INET, SOCK_STREAM, 0)
    guard handle >= 0 else { return "" }
    defer { close(handle) }

    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connected == 0 else { return "" }

    let bytes = Array(request.utf8)
    _ = bytes.withUnsafeBytes { send(handle, $0.baseAddress, bytes.count, 0) }

    var response = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = recv(handle, &chunk, chunk.count, 0)
        if count <= 0 { break }
        response.append(contentsOf: chunk[0 ..< count])
    }
    let text = String(decoding: response, as: UTF8.self)
    return text.components(separatedBy: "\r\n").first ?? ""
}

@main
struct ChannelServerTestsRunner {
    static func main() {
        testStartingTwiceOnTheSamePortKeepsListening()
        testANewTokenDoesNotDropTheSocket()
        testAChangedPortIsRebound()
        testTheRoutes()
        testTheAgentRoute()
        testTheAgentRouteTakesBodiesTheOthersDoNot()
        testBadFramingIsRefusedBeforeTheBody()
        testStoppingEndsAcceptedConnections()
        print("✅ ChannelServerTests: all passed")
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

        let server = ChannelServer()
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

        let server = ChannelServer()
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

        let server = ChannelServer()
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

    // MARK: - Routes

    /// One request, answered: the status and the decoded JSON body.
    static func request(_ method: String, _ path: String, port: UInt16, token: String? = "token",
                        body: String? = nil, headers: [String: String] = [:]) -> (Int, [String: String]) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let done = DispatchSemaphore(value: 0)
        var result: (Int, [String: String]) = (0, [:])
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
            result = (status, json)
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return result
    }

    static func testTheRoutes() {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return
        }

        let server = ChannelServer()
        let recorder = ServerStateRecorder()
        let delivered = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }
        server.onNotification = { delivered.record("deliver \($0.id) \($0.level.rawValue) \($0.banner.rawValue)") }
        server.onWithdraw = { delivered.record("withdraw \($0)") }

        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") }, "listening")

        var (status, json) = request("POST", "/v2/notifications", port: port,
                                     body: #"{"id":"n1","title":"t","level":"passive"}"#)
        checkServer(status == 202 && json["id"] == "n1", "v2 delivers, got \(status) \(json)")

        (status, json) = request("POST", "/reminder", port: port, body: #"{"id":"r1","title":"t","sticky":true}"#)
        checkServer(status == 202 && json["id"] == "r1", "v1 still delivers, got \(status) \(json)")

        (status, json) = request("DELETE", "/v2/notifications/claude%3A42", port: port)
        checkServer(status == 200 && json["id"] == "claude:42", "an id is percent-decoded, got \(status) \(json)")

        (status, json) = request("DELETE", "/v2/notifications/never-sent", port: port)
        checkServer(status == 200, "withdrawing an unknown id is not an error, got \(status)")

        (status, json) = request("POST", "/v2/notifications", port: port, body: #"{"title":"t","level":"loud"}"#)
        checkServer(status == 400 && json["error"] == "unknown_level" && json["level"] == "loud",
                    "a bad level names itself, got \(status) \(json)")

        (status, _) = request("GET", "/v2/notifications", port: port)
        checkServer(status == 405, "a known path with the wrong method, got \(status)")
        (status, _) = request("POST", "/v2/notifications/x", port: port, body: "{}")
        checkServer(status == 405, "a notification's path only takes DELETE, got \(status)")
        (status, _) = request("POST", "/v2/nothing", port: port, body: "{}")
        checkServer(status == 404, "an unknown path, got \(status)")

        (status, _) = request("DELETE", "/v2/notifications/n1", port: port, token: "wrong")
        checkServer(status == 401, "a wrong token cannot withdraw either, got \(status)")
        (status, _) = request("DELETE", "/v2/notifications/n1", port: port,
                              headers: ["Origin": "https://evil.example"])
        checkServer(status == 403, "nor can a browser, got \(status)")

        let events = delivered.wait(until: { $0.count >= 4 })
        checkServer(events == ["deliver n1 passive temporary", "deliver r1 active untilSeen",
                               "withdraw claude:42", "withdraw never-sent"],
                    "exactly the authorised, well-formed requests reach the notch, got \(events)")
        server.stop()
    }

    /// Framing is settled from the headers alone. A negative length used to reach a range
    /// constructor and trap the whole app, before the token was even looked at.
    static func testBadFramingIsRefusedBeforeTheBody() {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return
        }
        let server = ChannelServer()
        let recorder = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }
        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") }, "listening")

        let head = "POST /v2/notifications HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
        let cases: [(String, String, String)] = [
            ("Content-Length: -1\r\n\r\n", "400", "a negative length"),
            ("Content-Length: +5\r\n\r\n", "400", "a signed length"),
            ("Content-Length: 5\r\nContent-Length: 6\r\n\r\n{}", "400", "two lengths that disagree"),
            ("Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n", "400", "a transfer encoding"),
            ("Content-Length: 999999\r\n\r\n", "413", "a body announced too large, refused unread"),
        ]
        for (rest, status, what) in cases {
            let line = checkServerRaw(head + rest, port: port)
            checkServer(line.contains(" \(status) "), "\(what): got \(line)")
        }

        let (status, _) = request("POST", "/v2/notifications", port: port, body: #"{"title":"t"}"#)
        checkServer(status == 202, "and the server is still up, got \(status)")
        server.stop()
    }

    /// A request already accepted when the channel stops is ended, not delivered afterwards.
    static func testStoppingEndsAcceptedConnections() {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return
        }
        let server = ChannelServer()
        let recorder = ServerStateRecorder()
        let delivered = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }
        server.onNotification = { delivered.record($0.id) }
        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") }, "listening")

        // Headers now, the body after the stop.
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let body = #"{"id":"late","title":"t"}"#
        let head = "POST /v2/notifications HTTP/1.1\r\nAuthorization: Bearer token\r\n" +
            "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        _ = Array(head.utf8).withUnsafeBytes { send(handle, $0.baseAddress, $0.count, 0) }
        Thread.sleep(forTimeInterval: 0.3)
        server.stop()
        _ = Array(body.utf8).withUnsafeBytes { send(handle, $0.baseAddress, $0.count, 0) }
        Thread.sleep(forTimeInterval: 0.5)
        close(handle)

        checkServer(delivered.wait(until: { !$0.isEmpty }, timeout: 1).isEmpty,
                    "nothing is delivered after the stop")
    }

    // MARK: - Agent hooks

    static func startedServer(_ onAgent: @escaping (AgentEnvelope) -> Void) -> (ChannelServer, UInt16)? {
        guard let port = checkServerFreePort() else {
            print("⚠️  could not find a free port, skipping")
            return nil
        }
        let server = ChannelServer()
        let recorder = ServerStateRecorder()
        server.onStateChange = { recorder.record(String(describing: $0)) }
        server.onAgentEvent = onAgent
        server.start(port: port, token: "token")
        checkServer(recorder.wait(until: { $0.contains { $0.hasPrefix("ready") } })
                        .contains { $0.hasPrefix("ready") }, "listening")
        return (server, port)
    }

    static func testTheAgentRoute() {
        let received = ServerStateRecorder()
        guard let (server, port) = startedServer({ envelope in
            received.record("\(envelope.agent.rawValue) \(envelope.sessionID) \(envelope.event) \(envelope.host) pid=\(envelope.pid.map(String.init) ?? "-")")
        }) else { return }
        let path = "/v2/agents/claude-code/events"

        var (status, json) = request("POST", path, port: port,
                                     body: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/tmp/p"}"#,
                                     headers: ["X-Agent-Pid": "321", "X-Agent-T3-Thread": "th-1", "X-Agent-T3-Environment": "env-1"])
        checkServer(status == 202 && json["status"] == "accepted", "a hook is accepted, got \(status) \(json)")

        (status, json) = request("POST", "/v2/agents/codex/events", port: port,
                                 body: #"{"hook_event_name":"Stop","session_id":"c1","last_assistant_message":"done"}"#)
        checkServer(status == 202, "so is Codex's, got \(status) \(json)")

        (status, json) = request("POST", path, port: port, body: #"{"hook_event_name":"PreCompact","session_id":"s1"}"#)
        checkServer(status == 202 && json["status"] == "ignored", "a hook the table does not know is not an error, got \(status) \(json)")

        (status, json) = request("POST", path, port: port, body: #"{"hook_event_name":"Stop"}"#)
        checkServer(status == 400 && json["error"] == "missing_session_id", "a hook with no session, got \(status) \(json)")
        (status, json) = request("POST", path, port: port, body: "{ not json")
        checkServer(status == 400 && json["error"] == "malformed", "a body that is not JSON, got \(status) \(json)")

        (status, json) = request("POST", "/v2/agents/gemini/events", port: port, body: "{}")
        checkServer(status == 404 && json["error"] == "not_found", "an agent the notch does not know, got \(status) \(json)")
        (status, _) = request("POST", "/v2/agents/claude-code", port: port, body: "{}")
        checkServer(status == 404, "the agent's own path serves nothing, got \(status)")
        (status, _) = request("POST", "/v2/agents/claude-code/events/extra", port: port, body: "{}")
        checkServer(status == 404, "nor does anything below events, got \(status)")
        (status, _) = request("GET", path, port: port)
        checkServer(status == 405, "events only take POST, got \(status)")

        (status, _) = request("POST", path, port: port, token: nil, body: #"{"hook_event_name":"Stop","session_id":"s1"}"#)
        checkServer(status == 401, "a hook without the token, got \(status)")
        (status, _) = request("POST", path, port: port, token: "wrong", body: #"{"hook_event_name":"Stop","session_id":"s1"}"#)
        checkServer(status == 401, "a hook with the wrong token, got \(status)")
        (status, _) = request("POST", path, port: port, body: #"{"hook_event_name":"Stop","session_id":"s1"}"#,
                              headers: ["Origin": "https://evil.example"])
        checkServer(status == 403, "a hook from a browser, got \(status)")
        let line = checkServerRaw("POST \(path) HTTP/1.1\r\nAuthorization: Bearer token\r\nContent-Type: text/plain\r\n" +
                                  "Content-Length: 2\r\n\r\n{}", port: port)
        checkServer(line.contains(" 415 "), "a hook that is not JSON, got \(line)")
        let noLength = checkServerRaw("POST \(path) HTTP/1.1\r\nAuthorization: Bearer token\r\nContent-Type: application/json\r\n\r\n",
                                      port: port)
        checkServer(noLength.contains(" 411 "), "a hook with no length, got \(noLength)")

        let events = received.wait(until: { $0.count >= 2 })
        checkServer(events == [
            "claude-code s1 promptSubmitted t3Code(threadID: \"th-1\", environmentID: Optional(\"env-1\")) pid=321",
            "codex c1 turnEnded(summary: Optional(\"done\"), failed: false) app(bundleID: nil, termProgram: nil, tmuxPane: nil) pid=-",
        ], "exactly the well-formed, authorised hooks reach the notch, got \(events)")
        server.stop()
    }

    /// A hook can carry the file a tool is writing, so this route's body limit is 4 MiB; the
    /// other routes keep 64 KiB.
    static func testTheAgentRouteTakesBodiesTheOthersDoNot() {
        let received = ServerStateRecorder()
        guard let (server, port) = startedServer({ received.record($0.sessionID) }) else { return }

        // A body of exactly the limit, padded inside a string field.
        let limit = ChannelServer.maximumAgentPayloadBytes
        let frame = #"{"hook_event_name":"PostToolUse","session_id":"big","tool_input":""}"#
        let padding = String(repeating: "x", count: limit - frame.utf8.count)
        let body = #"{"hook_event_name":"PostToolUse","session_id":"big","tool_input":""# + padding + #""}"#
        checkServer(body.utf8.count == limit, "the body is exactly the limit, got \(body.utf8.count)")

        var (status, json) = request("POST", "/v2/agents/claude-code/events", port: port, body: body)
        checkServer(status == 202, "a body of exactly 4 MiB is accepted, got \(status) \(json)")

        let beyondNotifications = #"{"hook_event_name":"PostToolUse","session_id":"big","tool_input":""#
            + String(repeating: "x", count: 70 * 1024) + #""}"#
        (status, json) = request("POST", "/v2/agents/claude-code/events", port: port, body: beyondNotifications)
        checkServer(status == 202, "and one past the notifications' limit is accepted, too, got \(status) \(json)")

        let head = "POST /v2/agents/claude-code/events HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n"
        var line = checkServerRaw(head + "Content-Length: \(limit + 1)\r\n\r\n", port: port)
        checkServer(line.contains(" 413 "), "a body announced one byte over 4 MiB is refused unread, got \(line)")
        line = checkServerRaw("POST /v2/notifications HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n" +
                              "Content-Length: \(ChannelNotification.maximumPayloadBytes + 1)\r\n\r\n", port: port)
        checkServer(line.contains(" 413 "), "while a notification over 64 KiB still is refused, got \(line)")

        (status, _) = request("POST", "/v2/agents/claude-code/events", port: port,
                              body: #"{"hook_event_name":"PostToolUse","session_id":"after"}"#)
        checkServer(status == 202, "and the server is still up, got \(status)")

        let seen = received.wait(until: { $0.count >= 3 })
        checkServer(seen == ["big", "big", "after"], "the big hooks arrived whole, got \(seen)")
        server.stop()
    }
}
