//
//  AgentHookScriptTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below.
//
// SOURCES: NotBoringNotch/Agents/Hooks/AgentHookScript.swift
//
//  Runs the real script under /bin/sh with a temporary HOME. A small loopback listener, started
//  here on a port the kernel picks, stands in for the Notch Channel and records what arrives.
//  What the script promises is what an agent depends on, so that is what is checked: the
//  request it sends, that it prints nothing, that it exits 0, and that it never holds the agent
//  up when the notch is gone.
//

import Foundation

func checkHook(_ condition: Bool, _ message: String = "",
               file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

// MARK: - Listener

struct HookRequest {
    var requestLine = ""
    var headers: [String: String] = [:]   // lowercased names
    var body = Data()
}

/// Accepts connections one at a time on its own thread and records each request.
final class HookListener: @unchecked Sendable {
    enum Behavior { case respond, hang }

    let port: UInt16
    private let handle: Int32
    private let behavior: Behavior
    private let lock = NSLock()
    private var recorded: [HookRequest] = []

    init(behavior: Behavior = .respond) {
        self.behavior = behavior
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = UInt16(bigEndian: address.sin_port)
        handle = fd
        listen(fd, 8)
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    var requests: [HookRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func waitForRequests(_ count: Int, timeout: TimeInterval = 3) -> [HookRequest] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, requests.count < count { Thread.sleep(forTimeInterval: 0.02) }
        return requests
    }

    private func acceptLoop() {
        while true {
            let client = accept(handle, nil, nil)
            if client < 0 { return }
            serve(client)
        }
    }

    private func serve(_ client: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        let separator = Data("\r\n\r\n".utf8)
        var request = HookRequest()
        var expected = 0
        var headerEnd: Data.Index?

        while true {
            if headerEnd == nil, let range = buffer.range(of: separator) {
                let head = String(decoding: buffer[buffer.startIndex ..< range.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                request.requestLine = lines.first ?? ""
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let name = line[..<colon].lowercased()
                    request.headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                expected = Int(request.headers["content-length"] ?? "") ?? 0
                headerEnd = range.upperBound
            }
            if let end = headerEnd, buffer.count - (end - buffer.startIndex) >= expected {
                request.body = Data(buffer[end ..< end + expected])
                break
            }
            let count = recv(client, &chunk, chunk.count, 0)
            if count <= 0 { close(client); return }
            buffer.append(contentsOf: chunk[0 ..< count])
        }

        lock.lock()
        recorded.append(request)
        lock.unlock()

        switch behavior {
        case .respond:
            let reply = "HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
            _ = reply.withCString { send(client, $0, strlen($0), 0) }
            close(client)
        case .hang:
            // Hold the connection open, answering nothing, for longer than any test waits.
            Thread.sleep(forTimeInterval: 10)
            close(client)
        }
    }
}

// MARK: - Running the script

struct HookRun {
    var status: Int32
    var stdout: Data
    var stderr: Data
    var elapsed: TimeInterval
}

struct HookSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var tmp: URL { root.appendingPathComponent("tmp") }
    var script: URL { root.appendingPathComponent("notch-agent-hook") }
    var discovery: URL {
        home.appendingPathComponent("Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/notch-channel.json")
    }

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hook-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try AgentHookScript.source.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    func publishDiscovery(port: UInt16, token: String = "tok-123") throws {
        try FileManager.default.createDirectory(
            at: discovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"port":\#(port),"token":"\#(token)"}"#.utf8).write(to: discovery)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// Runs `executable arguments` with exactly `environment`, feeding `input` on stdin.
    func run(_ executable: String, _ arguments: [String], environment extra: [String: String] = [:],
             input: Data = Data()) -> HookRun {
        var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": tmp.path + "/"]
        for (key, value) in extra { environment[key] = value }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let started = Date()
        try! process.run()
        let writer = Thread { try? stdin.fileHandleForWriting.write(contentsOf: input); try? stdin.fileHandleForWriting.close() }
        writer.start()
        var out = Data(), err = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { out = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { err = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        process.waitUntilExit()
        group.wait()
        return HookRun(status: process.terminationStatus, stdout: out, stderr: err,
                       elapsed: Date().timeIntervalSince(started))
    }

    func runScript(_ agent: String, environment: [String: String] = [:], input: Data = Data()) -> HookRun {
        run("/bin/sh", [script.path, agent], environment: environment, input: input)
    }
}

// MARK: - Checks

let payload = Data("{\"hook_event_name\":\"Stop\",\"text\":\"héllo \\\" \\\\ $HOME `x`\"}\n\n".utf8)

func testScriptShape() {
    let lines = AgentHookScript.source.components(separatedBy: "\n")
    checkHook(lines[0] == "#!/bin/sh", "starts with a /bin/sh shebang")
    checkHook(lines[1] == "# notch-agent-hook-version: \(AgentHookScript.version)",
              "the second line is the version marker, got \(lines[1])")
}

func testSendsHeadersAndBodyUnchanged() throws {
    let sandbox = try HookSandbox()
    defer { sandbox.cleanUp() }
    let listener = HookListener()
    try sandbox.publishDiscovery(port: listener.port, token: "secret-token")
    let t3Home = sandbox.root.appendingPathComponent("t3")
    try FileManager.default.createDirectory(
        at: t3Home.appendingPathComponent("userdata"), withIntermediateDirectories: true)
    try "env-42\n".write(to: t3Home.appendingPathComponent("userdata/environment-id"),
                         atomically: true, encoding: .utf8)

    // A process named "claude" between the test and the script, as the agent would be.
    let claude = sandbox.root.appendingPathComponent("claude")
    try FileManager.default.copyItem(atPath: "/bin/sh", toPath: claude.path)
    // A copy of a system binary is killed on launch until it is signed again.
    let signing = sandbox.run("/usr/bin/codesign", ["--force", "-s", "-", claude.path])
    checkHook(signing.status == 0, "the stand-in agent could be signed")
    let environment = [
        "__CFBundleIdentifier": "com.t3tools.t3code",
        "TERM_PROGRAM": "ghostty",
        "TMUX_PANE": "%7",
        "T3CODE_THREAD_ID": "thread-abc",
        "T3CODE_HOME": t3Home.path,
    ]
    // Not the last command, so the shell cannot exec it and take its parent's place.
    let command = "\"$0\" \"$1\" codex; true"
    let process = Process()
    process.executableURL = claude
    process.arguments = ["-c", command, sandbox.script.path, "codex"]
    var env = ["HOME": sandbox.home.path, "PATH": "/usr/bin:/bin", "TMPDIR": sandbox.tmp.path + "/"]
    for (key, value) in environment { env[key] = value }
    process.environment = env
    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    try stdin.fileHandleForWriting.write(contentsOf: payload)
    try stdin.fileHandleForWriting.close()
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    checkHook(process.terminationStatus == 0, "exits 0")
    checkHook(out.isEmpty && err.isEmpty, "prints nothing, got \(String(decoding: out + err, as: UTF8.self))")

    let requests = listener.waitForRequests(1)
    checkHook(requests.count == 1, "exactly one request, got \(requests.count)")
    let request = requests[0]
    checkHook(request.requestLine == "POST /v2/agents/codex/events HTTP/1.1", "route, got \(request.requestLine)")
    checkHook(request.body == payload, "the body arrives byte for byte")
    checkHook(request.headers["authorization"] == "Bearer secret-token", "token")
    checkHook(request.headers["content-type"] == "application/json", "content type")
    checkHook(request.headers["x-agent-pid"] == String(process.processIdentifier),
              "the pid is the nearest ancestor named claude, got \(request.headers["x-agent-pid"] ?? "none")")
    checkHook(request.headers["x-agent-host-bundle"] == "com.t3tools.t3code", "host bundle")
    checkHook(request.headers["x-agent-term-program"] == "ghostty", "term program")
    checkHook(request.headers["x-agent-tmux-pane"] == "%7", "tmux pane")
    checkHook(request.headers["x-agent-t3-thread"] == "thread-abc", "t3 thread")
    checkHook(request.headers["x-agent-t3-environment"] == "env-42", "t3 environment, read from the userdata file")
    checkHook((try FileManager.default.contentsOfDirectory(atPath: sandbox.tmp.path)).isEmpty,
              "the private curl config does not outlive the script")
}

func testOmitsEmptyAndUnsafeHeaders() throws {
    let sandbox = try HookSandbox()
    defer { sandbox.cleanUp() }
    let listener = HookListener()
    try sandbox.publishDiscovery(port: listener.port)

    // Nothing from the agent's environment, an unsafe value, and a T3 thread whose environment
    // file is missing. (Whether a pid is sent depends on who is running the tests, so only its
    // shape is checked here.)
    let run = sandbox.runScript("claude-code", environment: [
        "TERM_PROGRAM": "evil\"; injected",
        "T3CODE_THREAD_ID": "thread-1",
        "T3CODE_HOME": sandbox.root.appendingPathComponent("nowhere").path,
    ], input: payload)
    checkHook(run.status == 0, "exits 0")
    let request = listener.waitForRequests(1).first
    checkHook(request != nil, "the request arrives")
    guard let request else { return }
    checkHook(request.requestLine == "POST /v2/agents/claude-code/events HTTP/1.1", "route")
    checkHook(request.headers["x-agent-pid"].map { Int32($0) != nil } ?? true, "a pid header is a number")
    checkHook(request.headers["x-agent-host-bundle"] == nil, "empty values are not sent")
    checkHook(request.headers["x-agent-tmux-pane"] == nil, "empty values are not sent")
    checkHook(request.headers["x-agent-term-program"] == nil, "a value that could break the config is left out")
    checkHook(request.headers["x-agent-t3-thread"] == "thread-1", "the thread still goes")
    checkHook(request.headers["x-agent-t3-environment"] == nil, "no environment-id file, no header")
    checkHook(request.body == payload, "body")
}

func testNeverBlocksTheAgent() throws {
    let big = Data(repeating: UInt8(ascii: "x"), count: 1_000_000)   // more than a pipe holds

    do {   // nothing listens
        let sandbox = try HookSandbox()
        defer { sandbox.cleanUp() }
        let closed = socket(AF_INET, SOCK_STREAM, 0)   // bound, never listening: refused
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(closed, $0, length) }
        }
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(closed, $0, &length) }
        }
        try sandbox.publishDiscovery(port: UInt16(bigEndian: address.sin_port))
        let run = sandbox.runScript("codex", input: big)
        close(closed)
        checkHook(run.status == 0 && run.stdout.isEmpty && run.stderr.isEmpty, "nothing listening: exit 0, silent")
        checkHook(run.elapsed < 1.5, "nothing listening: returns promptly, took \(run.elapsed)")
    }

    do {   // no discovery file
        let sandbox = try HookSandbox()
        defer { sandbox.cleanUp() }
        let run = sandbox.runScript("codex", input: big)
        checkHook(run.status == 0 && run.stdout.isEmpty && run.stderr.isEmpty, "no discovery file: exit 0, silent")
        checkHook(run.elapsed < 1.5, "no discovery file: returns promptly, took \(run.elapsed)")
    }

    do {   // a discovery file without a token
        let sandbox = try HookSandbox()
        defer { sandbox.cleanUp() }
        try FileManager.default.createDirectory(
            at: sandbox.discovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"port\":1234}".utf8).write(to: sandbox.discovery)
        let run = sandbox.runScript("codex", input: payload)
        checkHook(run.status == 0 && run.stdout.isEmpty && run.stderr.isEmpty, "half a discovery file: exit 0, silent")
    }

    do {   // the notch accepts and never answers
        let sandbox = try HookSandbox()
        defer { sandbox.cleanUp() }
        let listener = HookListener(behavior: .hang)
        try sandbox.publishDiscovery(port: listener.port)
        let run = sandbox.runScript("claude-code", input: payload)
        checkHook(run.status == 0 && run.stdout.isEmpty && run.stderr.isEmpty, "a hung notch: exit 0, silent")
        checkHook(run.elapsed < 1.5, "a hung notch: gives up after about a second, took \(run.elapsed)")
        checkHook(run.elapsed >= 0.9, "a hung notch: the cap is about a second, took \(run.elapsed)")
    }

    do {   // an agent name the script does not know sends nothing
        let sandbox = try HookSandbox()
        defer { sandbox.cleanUp() }
        let listener = HookListener()
        try sandbox.publishDiscovery(port: listener.port)
        let run = sandbox.runScript("../../x", input: payload)
        checkHook(run.status == 0 && run.stdout.isEmpty, "unknown agent: exit 0, silent")
        Thread.sleep(forTimeInterval: 0.2)
        checkHook(listener.requests.isEmpty, "unknown agent: nothing is sent")
    }
}

func testIsFast() throws {
    let sandbox = try HookSandbox()
    defer { sandbox.cleanUp() }
    let listener = HookListener()
    try sandbox.publishDiscovery(port: listener.port)
    _ = sandbox.runScript("codex", input: payload)   // warm the caches
    var times: [TimeInterval] = []
    for _ in 0 ..< 10 { times.append(sandbox.runScript("codex", input: payload).elapsed) }
    times.sort()
    print("   bridge median \(Int(times[times.count / 2] * 1000)) ms, max \(Int(times.last! * 1000)) ms")
    checkHook(times[times.count / 2] < 0.15, "the bridge is a few tens of milliseconds, median \(times[times.count / 2])")
}

@main
enum AgentHookScriptTests {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        do {
            testScriptShape()
            try testSendsHeadersAndBodyUnchanged()
            try testOmitsEmptyAndUnsafeHeaders()
            try testNeverBlocksTheAgent()
            try testIsFast()
            print("✅ AgentHookScriptTests passed")
        } catch {
            print("❌ \(error)")
            exit(1)
        }
    }
}
