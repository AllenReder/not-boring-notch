//
//  AgentHooksXPCTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotchXPCHelper/NotBoringNotchXPCHelperProtocol.swift NotBoringNotchXPCHelper/NotBoringNotchXPCHelper.swift NotBoringNotchXPCHelper/AgentHooks/AgentHookInstaller.swift NotBoringNotchXPCHelper/AgentHooks/AgentHookEntries.swift NotBoringNotchXPCHelper/AgentHooks/ConfigFile.swift NotBoringNotchXPCHelper/AgentHooks/JSONSurgeon.swift NotBoringNotchXPCHelper/AgentHooks/CodexHooksConfig.swift NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift NotBoringNotchXPCHelper/AgentHooks/AgentProcess.swift NotBoringNotchXPCHelper/AgentHooks/CodexTrust.swift NotBoringNotch/Agents/Hooks/AgentHookScript.swift NotBoringNotchXPCHelper/AgentHooks/PiExtension.swift NotBoringNotchXPCHelper/AgentHooks/AgentPluginFile.swift NotBoringNotchXPCHelper/AgentHooks/T3ThreadTitles.swift NotBoringNotchXPCHelper/AgentHooks/ChildProcess.swift
//
//  The helper's real class behind a real NSXPCConnection (an anonymous listener in this
//  process), called through the protocol the app uses. What this proves is what a unit test of
//  the installer can't: that the types in the protocol survive the trip, and that the JSON
//  replies decode into what the app expects. The helper's home is a temporary directory.
//

import Foundation

func checkXPC(_ condition: Bool, _ message: String = "",
              file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

final class AcceptingDelegate: NSObject, NSXPCListenerDelegate {
    let helper: NotBoringNotchXPCHelper
    init(helper: NotBoringNotchXPCHelper) { self.helper = helper }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any NotBoringNotchXPCHelperProtocol).self)
        connection.exportedObject = helper
        connection.resume()
        return true
    }
}

@main
enum AgentHooksXPCTests {
    static func main() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xpc-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let helper = NotBoringNotchXPCHelper()
        helper.homeDirectory = home
        let delegate = AcceptingDelegate(helper: helper)
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: (any NotBoringNotchXPCHelperProtocol).self)
        connection.resume()
        defer { connection.invalidate() }

        /// One call across the connection, waiting for its reply.
        func call<T>(_ body: (any NotBoringNotchXPCHelperProtocol, @escaping (T) -> Void) -> Void) -> T {
            var result: T?
            let done = DispatchSemaphore(value: 0)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                print("❌ XPC error: \(error)")
                exit(1)
            } as! any NotBoringNotchXPCHelperProtocol
            body(proxy) { value in
                result = value
                done.signal()
            }
            checkXPC(done.wait(timeout: .now() + 60) == .success, "the helper answered in time")
            return result!
        }
        func report(_ data: Data) -> AgentHooksReport {
            guard let report = try? JSONDecoder().decode(AgentHooksReport.self, from: data) else {
                checkXPC(false, "the reply decodes as a report, got \(String(decoding: data, as: UTF8.self))")
                return AgentHooksReport(statuses: [])
            }
            return report
        }

        // Process start times: NSNumber keys and values across the connection.
        let me = ProcessInfo.processInfo.processIdentifier
        let times: [NSNumber: NSNumber] = call { proxy, reply in
            proxy.agentProcessStartTimes([NSNumber(value: me), NSNumber(value: Int32(99_999_999))], with: reply)
        }
        checkXPC(times.count == 1, "the running pid is answered and the impossible one is not, got \(times)")
        checkXPC(times[NSNumber(value: me)]?.doubleValue == AgentProcess.startTime(of: me), "the start time is the process's own")

        // Hooks, end to end.
        let script = AgentHookScript.source
        var current = report(call { proxy, reply in proxy.agentHooksStatus(hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.notInstalled, .notInstalled, .notInstalled], "nothing installed to start with, got \(current)")
        checkXPC(current.statuses.map(\.agent) == [.claudeCode, .codex, .pi], "one status per agent, in order")

        current = report(call { proxy, reply in proxy.installAgentHooks(["claude-code", "codex", "pi", "nonsense"], hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.installed, .installed, .installed], "installs all three and ignores a name it doesn't know, got \(current)")
        checkXPC(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/settings.json").path), "and wrote into the helper's home")
        checkXPC(FileManager.default.fileExists(atPath: home.appendingPathComponent(".pi/agent/extensions/not-boring-notch.ts").path), "pi's extension too")

        current = report(call { proxy, reply in proxy.agentHooksStatus(hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.installed, .installed, .installed], "status sees what was installed")

        let newer = script.replacingOccurrences(of: "version: \(AgentHookScript.version)", with: "version: \(AgentHookScript.version + 1)")
        current = report(call { proxy, reply in proxy.agentHooksStatus(hookScript: newer, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.outdated, .outdated, .installed],
                 "a newer bundled script makes both hook agents outdated, and pi, which does not use it, stays, got \(current)")

        let trust: Data = call { proxy, reply in proxy.trustCodexHooks(with: reply) }
        let trustReport = try JSONDecoder().decode(CodexTrustReport.self, from: trust)
        checkXPC(trustReport.trusted > 0 || trustReport.problem != nil, "trusting either trusts something or says why not, got \(trustReport)")

        current = report(call { proxy, reply in proxy.uninstallAgentHooks(["codex"], hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.notInstalled], "uninstalls one agent, got \(current)")
        current = report(call { proxy, reply in proxy.uninstallAgentHooks(["claude-code"], hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.notInstalled], "and then the other, got \(current)")
        current = report(call { proxy, reply in proxy.uninstallAgentHooks(["pi"], hookScript: script, with: reply) })
        checkXPC(current.statuses.map(\.state) == [.notInstalled], "and pi, got \(current)")
        checkXPC(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".not-boring-notch/bin/notch-agent-hook").path), "and the script goes with it")

        print("✅ AgentHooksXPCTests passed")
    }
}
