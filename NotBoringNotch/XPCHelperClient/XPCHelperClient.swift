import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "com.allenreder.notboringnotch.NotBoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<NotBoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<NotBoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<NotBoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: NotBoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness

    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness

    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

// MARK: - Agent hooks

extension XPCHelperClient {
    /// Start time of each process among `pids` that is still running. A pid that is not running,
    /// or that the helper could not be asked about, is left out.
    /// nil when the helper could not be reached: that says nothing about the processes, and must
    /// not read as "all of them exited".
    nonisolated func agentProcessStartTimes(_ pids: [Int32]) async -> [Int32: Date]? {
        guard !pids.isEmpty else { return [:] }
        return await answer(within: Self.periodicCallLimit) { [self] in
            // A helper that was just restarted fails the first call; asking again reaches the new one.
            for _ in 0..<2 {
                do {
                    let service = await MainActor.run { ensureRemoteService() }
                    let times: [NSNumber: NSNumber] = try await service.withContinuation { service, continuation in
                        service.agentProcessStartTimes(pids.map { NSNumber(value: $0) }) { times in
                            continuation.resume(returning: times)
                        }
                    }
                    return Dictionary(uniqueKeysWithValues: times.map {
                        (Int32(truncating: $0.key), Date(timeIntervalSince1970: $0.value.doubleValue))
                    })
                } catch {
                    continue
                }
            }
            return nil
        }
    }

    /// Each thread's title, for the threads T3 Code could name. Empty when nothing could be asked.
    nonisolated func t3ThreadTitles(_ threadIDs: [String]) async -> [String: String] {
        guard !threadIDs.isEmpty else { return [:] }
        return await answer(within: Self.periodicCallLimit) { [self] in
            let service = await MainActor.run { ensureRemoteService() }
            return try? await service.withContinuation { service, continuation in
                service.t3ThreadTitles(threadIDs) { titles in continuation.resume(returning: titles) }
            }
        } ?? [:]
    }

    /// nil when the helper could not be reached.
    nonisolated func agentHooksStatus(hookScript: String) async -> AgentHooksReport? {
        await decodedReply { service, reply in service.agentHooksStatus(hookScript: hookScript, with: reply) }
    }

    nonisolated func installAgentHooks(_ agents: [AgentHookTarget], hookScript: String) async -> AgentHooksReport? {
        await decodedReply { service, reply in
            service.installAgentHooks(agents.map(\.rawValue), hookScript: hookScript, with: reply)
        }
    }

    nonisolated func uninstallAgentHooks(_ agents: [AgentHookTarget], hookScript: String) async -> AgentHooksReport? {
        await decodedReply { service, reply in
            service.uninstallAgentHooks(agents.map(\.rawValue), hookScript: hookScript, with: reply)
        }
    }

    nonisolated func trustCodexHooks() async -> CodexTrustReport? {
        await decodedReply { service, reply in service.trustCodexHooks(with: reply) }
    }

    private nonisolated func decodedReply<T: Decodable>(
        _ call: @escaping (NotBoringNotchXPCHelperProtocol, @escaping (Data) -> Void) -> Void
    ) async -> T? {
        let data: Data? = await answer(within: Self.settingsCallLimit) { [self] in
            let service = await MainActor.run { ensureRemoteService() }
            return try? await service.withContinuation { service, continuation in
                call(service) { continuation.resume(returning: $0) }
            }
        }
        return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// The sweep and the title lookup run every few seconds; the helper bounds each of its own
    /// commands well inside this.
    private static let periodicCallLimit: TimeInterval = 15
    /// Trusting Codex's hooks gives `codex app-server` up to 20 seconds.
    private static let settingsCallLimit: TimeInterval = 60

    /// What `call` answers, or nil once `seconds` have passed. The helper answers one call at a
    /// time, so a call that never returns would otherwise hold up every caller after it, forever;
    /// the connection is dropped so that the next call starts a fresh one. An answer that comes
    /// later goes nowhere.
    private nonisolated func answer<T>(within seconds: TimeInterval,
                                       _ call: @escaping () async -> T?) async -> T? {
        let answer: T?? = await withCheckedContinuation { continuation in
            let first = FirstAnswer(continuation)
            Task { first.give(await call()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                first.give(nil)
            }
        }
        guard let answer else {
            await MainActor.run { connection?.invalidate() }
            return nil
        }
        return answer
    }
}

/// Resumes a continuation with whichever value comes first, and ignores the rest.
private final class FirstAnswer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T??, Never>?

    init(_ continuation: CheckedContinuation<T??, Never>) { self.continuation = continuation }

    /// `.some(value)` for the call's answer, nil for the clock running out.
    func give(_ value: T??) {
        let waiting = lock.withLock { () -> CheckedContinuation<T??, Never>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: value)
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


