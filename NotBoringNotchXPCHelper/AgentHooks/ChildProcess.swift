//
//  ChildProcess.swift
//  NotBoringNotchXPCHelper
//
//  A command run to completion under a deadline that holds. The helper answers the app's calls
//  one at a time, so a command that outlives its deadline holds up every call behind it.
//

import Foundation

enum ChildProcess {
    /// What the command printed, or nil when it could not start, failed, or took longer than
    /// `timeout`. The output is read while the command runs, so a large one cannot fill the pipe
    /// and stall it; and nothing waits on a pipe that something the command left behind (a
    /// process a login shell's profile backgrounds, say) keeps open.
    static func output(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        var data = Data()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = read.wait(timeout: .now() + 1)
            return nil
        }
        // The pipe ends when the process does; anything that kept it open gets a second.
        guard read.wait(timeout: .now() + 1) == .success else { return nil }
        return process.terminationStatus == 0 ? data : nil
    }
}
