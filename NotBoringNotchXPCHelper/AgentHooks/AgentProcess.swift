//
//  AgentProcess.swift
//  NotBoringNotchXPCHelper
//
//  Whether an agent's process is still running. The sandboxed app can't ask the kernel about
//  other processes, so it asks here. Ported from CodeStatus,
//  Sources/CodeStatusCore/Runtime/ProcessInspector.swift (MIT): a process is its pid and its
//  start time, because a pid is reused. A pid whose start time changed is a different process,
//  and the caller sees that by comparing the time it saw first.
//

import Foundation

enum AgentProcess {
    /// Start time, in seconds since 1970, of each running process among `pids`. A pid that is
    /// not running, or is a zombie, is left out.
    static func startTimes(of pids: [Int32]) -> [Int32: TimeInterval] {
        var times: [Int32: TimeInterval] = [:]
        for pid in Set(pids) where pid > 0 {
            if let time = startTime(of: pid) { times[pid] = time }
        }
        return times
    }

    static func startTime(of pid: Int32) -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        // A pid that does not exist is not an error: the call succeeds and fills in nothing.
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid, info.kp_proc.p_stat != SZOMB else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        return TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000
    }
}
