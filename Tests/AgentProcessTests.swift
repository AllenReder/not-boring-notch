//
//  AgentProcessTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/AgentProcess.swift
//
//  The notch decides an agent has quit when its process is gone, and a reused pid must count as
//  gone, so the start time is part of what is checked.
//

import Foundation

func checkProcess(_ condition: Bool, _ message: String = "",
                  file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
enum AgentProcessTests {
    static func main() throws {
        let me = ProcessInfo.processInfo.processIdentifier

        let own = AgentProcess.startTimes(of: [me])
        checkProcess(own.count == 1, "this process is running")
        let started = own[me]!
        let now = Date().timeIntervalSince1970
        checkProcess(started <= now && now - started < 3600, "its start time is a recent time since 1970, got \(started) at \(now)")
        checkProcess(AgentProcess.startTimes(of: [me])[me] == started, "asking twice gives the same start time")

        // A child: running, then gone.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let pid = child.processIdentifier
        let running = AgentProcess.startTimes(of: [pid, me])
        checkProcess(running[pid] != nil && running[me] == started, "a child and this process are both running")
        checkProcess(running[pid]! >= started, "the child started after this process")

        child.terminate()
        child.waitUntilExit()
        checkProcess(AgentProcess.startTimes(of: [pid])[pid] == nil, "an exited and reaped child is left out")

        // Nonsense is left out, not an error.
        let none = AgentProcess.startTimes(of: [0, -1, Int32.max, 99_999_999])
        checkProcess(none.isEmpty, "pids that can't exist are left out, got \(none)")
        checkProcess(AgentProcess.startTimes(of: []).isEmpty, "nothing asked, nothing answered")

        print("✅ AgentProcessTests passed")
    }
}
