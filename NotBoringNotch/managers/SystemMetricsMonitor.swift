//
//  SystemMetricsMonitor.swift
//  NotBoringNotch
//

import Combine
import Darwin
import Foundation
import IOKit

// MARK: - Sampler

/// Reads one snapshot of system metrics.
///
/// The sampler keeps the previous counters it needs for rate calculation. It is
/// confined to the monitor's serial sampling queue and must not be used from two
/// threads at once.
final class SystemMetricsSampler: @unchecked Sendable {
    private struct NetworkCounters {
        let received: UInt64
        let sent: UInt64
    }

    private struct DiskCounters {
        let read: UInt64
        let write: UInt64
    }

    private static let excludedInterfacePrefixes = [
        "lo", "utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg",
        "awdl", "llw", "bridge", "ap", "anpi", "XHC"
    ]

    private let pageSize: UInt64
    private let totalMemory: UInt64
    private let gpuService: io_service_t
    private let thermalSensors = IOHIDThermalSensors()

    private var previousCPU: host_cpu_load_info?
    private var previousNetwork: (timestamp: TimeInterval, counters: [String: NetworkCounters])?
    private var previousDisk: (timestamp: TimeInterval, counters: [UInt64: DiskCounters])?

    init() {
        pageSize = UInt64(vm_page_size)
        totalMemory = Self.readTotalMemory()
        gpuService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
    }

    deinit {
        if gpuService != 0 {
            IOObjectRelease(gpuService)
        }
    }

    func sample() -> SystemMetricsSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        return SystemMetricsSnapshot(
            timestamp: Date(),
            cpu: readCPU(),
            memory: readMemory(),
            gpu: readGPU(),
            network: readNetwork(now: now),
            disk: readDisk(now: now),
            thermal: thermalSensors.read()
        )
    }

    // MARK: CPU

    private func readCPU() -> CPUMetrics {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .zero }

        let previous = previousCPU
        previousCPU = info
        guard let previous else { return .zero }

        let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return .zero }

        return CPUMetrics(
            usage: (user + system + nice) / total,
            userUsage: user / total,
            systemUsage: system / total,
            idle: idle / total
        )
    }

    // MARK: Memory

    private func readMemory() -> MemoryMetrics {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryMetrics(used: 0, total: totalMemory, pressure: .normal)
        }

        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize

        let resident = active + inactive + speculative + wired + compressed
        let reclaimable = purgeable + external
        let used = min(totalMemory, resident > reclaimable ? resident - reclaimable : 0)

        var pressureLevel: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureSize, nil, 0)
        let pressure: MemoryPressure
        switch pressureLevel {
        case 2: pressure = .warning
        case 4: pressure = .critical
        default: pressure = .normal
        }

        return MemoryMetrics(used: used, total: totalMemory, pressure: pressure)
    }

    // MARK: GPU

    private func readGPU() -> GPUMetrics? {
        guard gpuService != 0 else { return nil }
        guard let statistics = IORegistryEntryCreateCFProperty(
            gpuService,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else { return nil }

        let utilization = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue
            ?? (statistics["GPU Activity(%)"] as? NSNumber)?.doubleValue
        guard let utilization else { return nil }

        return GPUMetrics(
            utilization: min(max(utilization / 100, 0), 1),
            inUseMemory: (statistics["In use system memory"] as? NSNumber)?.uint64Value,
            allocatedMemory: (statistics["Alloc system memory"] as? NSNumber)?.uint64Value
        )
    }

    // MARK: Network

    private func readNetwork(now: TimeInterval) -> NetworkMetrics {
        let counters = readNetworkCounters()
        let previous = previousNetwork
        previousNetwork = (now, counters)

        guard !counters.isEmpty else { return .zero }

        if let previous {
            let elapsed = now - previous.timestamp
            if elapsed > 0.001, elapsed < 5 {
                var best: (name: String, download: Double, upload: Double, received: UInt64, sent: UInt64)?
                for (name, current) in counters {
                    guard let old = previous.counters[name] else { continue }
                    let receivedDelta = current.received >= old.received
                        ? Double(current.received - old.received)
                        : 0
                    let sentDelta = current.sent >= old.sent
                        ? Double(current.sent - old.sent)
                        : 0
                    let rate = receivedDelta + sentDelta
                    if best == nil || rate > (best!.download + best!.upload) {
                        best = (
                            name,
                            receivedDelta / elapsed,
                            sentDelta / elapsed,
                            current.received,
                            current.sent
                        )
                    }
                }
                if let best {
                    return NetworkMetrics(
                        downloadBytesPerSecond: best.download,
                        uploadBytesPerSecond: best.upload,
                        interfaceName: best.name,
                        totalDownloaded: best.received,
                        totalUploaded: best.sent
                    )
                }
            }
        }

        guard let fallback = counters.max(by: {
            ($0.value.received + $0.value.sent) < ($1.value.received + $1.value.sent)
        }) else { return .zero }

        return NetworkMetrics(
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 0,
            interfaceName: fallback.key,
            totalDownloaded: fallback.value.received,
            totalUploaded: fallback.value.sent
        )
    }

    private func readNetworkCounters() -> [String: NetworkCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(&mib, 6, buffer, &length, nil, 0) == 0 else { return [:] }

        var counters: [String: NetworkCounters] = [:]
        var offset = 0

        while offset < length {
            let cursor = buffer.advanced(by: offset)
            let header = cursor.assumingMemoryBound(to: if_msghdr.self).pointee
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= length else { break }

            if header.ifm_type == RTM_IFINFO2 {
                let info = cursor.assumingMemoryBound(to: if_msghdr2.self).pointee
                let linkAddress = UnsafeRawPointer(
                    cursor.advanced(by: MemoryLayout<if_msghdr2>.stride)
                ).assumingMemoryBound(to: sockaddr_dl.self).pointee
                let nameLength = min(
                    Int(linkAddress.sdl_nlen),
                    MemoryLayout.size(ofValue: linkAddress.sdl_data)
                )
                let name = withUnsafeBytes(of: linkAddress.sdl_data) {
                    String(decoding: $0.prefix(nameLength), as: UTF8.self)
                }
                if !name.isEmpty, Self.isPhysicalInterface(name) {
                    counters[name] = NetworkCounters(
                        received: info.ifm_data.ifi_ibytes,
                        sent: info.ifm_data.ifi_obytes
                    )
                }
            }

            offset += messageLength
        }

        return counters
    }

    private static func isPhysicalInterface(_ name: String) -> Bool {
        !excludedInterfacePrefixes.contains { name.hasPrefix($0) }
    }

    // MARK: Disk

    private func readDisk(now: TimeInterval) -> DiskMetrics {
        let counters = readDiskCounters()
        let previous = previousDisk
        previousDisk = (now, counters)

        var readRate = 0.0
        var writeRate = 0.0

        if let previous {
            let elapsed = now - previous.timestamp
            if elapsed > 0.001, elapsed < 5 {
                for (identifier, current) in counters {
                    guard let old = previous.counters[identifier] else { continue }
                    let readDelta = current.read >= old.read ? Double(current.read - old.read) : 0
                    let writeDelta = current.write >= old.write ? Double(current.write - old.write) : 0
                    readRate += readDelta / elapsed
                    writeRate += writeDelta / elapsed
                }
            }
        }

        let capacity = Self.readDiskCapacity()
        return DiskMetrics(
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate,
            freeBytes: capacity.free,
            totalBytes: capacity.total
        )
    }

    private func readDiskCounters() -> [UInt64: DiskCounters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var counters: [UInt64: DiskCounters] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            var identifier: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS else { continue }
            guard let statistics = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            counters[identifier] = DiskCounters(
                read: (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                write: (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            )
        }
        return counters
    }

    private static func readDiskCapacity() -> (free: UInt64, total: UInt64) {
        var statistics = statfs()
        guard statfs("/", &statistics) == 0 else { return (0, 0) }
        let blockSize = UInt64(statistics.f_bsize)
        return (
            UInt64(statistics.f_bavail) * blockSize,
            UInt64(statistics.f_blocks) * blockSize
        )
    }

    // MARK: System

    private static func readTotalMemory() -> UInt64 {
        var memory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memory, &size, nil, 0) == 0 {
            return memory
        }

        var info = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.max_mem) : 0
    }
}

// MARK: - Monitor

/// Owns the sampling timer and publishes the latest snapshot plus a short history.
/// Sampling only runs while at least one `PerformanceView` is visible.
@MainActor
final class SystemMetricsMonitor: ObservableObject {
    static let shared = SystemMetricsMonitor()

    @Published private(set) var snapshot: SystemMetricsSnapshot?
    @Published private(set) var history = SystemMetricsHistory()

    private let sampler = SystemMetricsSampler()
    private let queue = DispatchQueue(
        label: "com.allenreder.notboringnotch.system-metrics",
        qos: .utility
    )
    private var timer: DispatchSourceTimer?
    private var subscribers: Set<UUID> = []
    private var interval: TimeInterval = 1

    private init() {}

    func start(subscriber: UUID, interval: TimeInterval) {
        let clamped = max(0.5, interval)
        let wasEmpty = subscribers.isEmpty
        subscribers.insert(subscriber)

        if wasEmpty {
            snapshot = nil
            history.removeAll()
        }

        if timer != nil, abs(self.interval - clamped) < 0.001 {
            return
        }

        self.interval = clamped
        restartTimer()
    }

    func stop(subscriber: UUID) {
        subscribers.remove(subscriber)
        guard subscribers.isEmpty else { return }
        timer?.cancel()
        timer = nil
    }

    private func restartTimer() {
        timer?.cancel()

        let interval = self.interval
        let sampler = self.sampler
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self, sampler] in
            let snapshot = sampler.sample()
            Task { @MainActor in
                self?.apply(snapshot)
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func apply(_ snapshot: SystemMetricsSnapshot) {
        guard !subscribers.isEmpty else { return }
        self.snapshot = snapshot
        history.append(snapshot)
    }
}
