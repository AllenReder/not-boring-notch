//
//  SystemMetrics.swift
//  NotBoringNotch
//

import Foundation

// MARK: - Snapshot

struct SystemMetricsSnapshot: Equatable {
    let timestamp: Date
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let gpu: GPUMetrics?
    let network: NetworkMetrics
    let disk: DiskMetrics
    let thermal: ThermalMetrics
}

struct CPUMetrics: Equatable {
    let usage: Double
    let userUsage: Double
    let systemUsage: Double
    let idle: Double

    static let zero = CPUMetrics(usage: 0, userUsage: 0, systemUsage: 0, idle: 1)
}

struct MemoryMetrics: Equatable {
    let used: UInt64
    let total: UInt64
    let pressure: MemoryPressure

    var usage: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}

enum MemoryPressure: String, Equatable {
    case normal
    case warning
    case critical

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

struct GPUMetrics: Equatable {
    let utilization: Double
    let inUseMemory: UInt64?
    let allocatedMemory: UInt64?
}

struct NetworkMetrics: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let interfaceName: String?
    let totalDownloaded: UInt64
    let totalUploaded: UInt64

    static let zero = NetworkMetrics(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        interfaceName: nil,
        totalDownloaded: 0,
        totalUploaded: 0
    )
}

struct DiskMetrics: Equatable {
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    let freeBytes: UInt64
    let totalBytes: UInt64

    var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(totalBytes - freeBytes) / Double(totalBytes), 0), 1)
    }
}

struct ThermalMetrics: Equatable {
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let batteryTemperature: Double?
    let storageTemperature: Double?

    static let empty = ThermalMetrics(
        cpuTemperature: nil,
        gpuTemperature: nil,
        batteryTemperature: nil,
        storageTemperature: nil
    )
}

// MARK: - History

struct SystemMetricsHistory: Equatable {
    static let capacity = 60

    private(set) var cpu: [Double] = []
    private(set) var gpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var download: [Double] = []
    private(set) var upload: [Double] = []
    private(set) var diskRead: [Double] = []
    private(set) var diskWrite: [Double] = []
    private(set) var temperature: [Double] = []

    mutating func append(_ snapshot: SystemMetricsSnapshot) {
        Self.push(snapshot.cpu.usage, into: &cpu)
        Self.push(snapshot.gpu?.utilization ?? 0, into: &gpu)
        Self.push(snapshot.memory.usage, into: &memory)
        Self.push(snapshot.network.downloadBytesPerSecond, into: &download)
        Self.push(snapshot.network.uploadBytesPerSecond, into: &upload)
        Self.push(snapshot.disk.readBytesPerSecond, into: &diskRead)
        Self.push(snapshot.disk.writeBytesPerSecond, into: &diskWrite)
        if let cpuTemperature = snapshot.thermal.cpuTemperature, cpuTemperature.isFinite {
            Self.push(cpuTemperature, into: &temperature)
        }
    }

    mutating func removeAll() {
        cpu.removeAll()
        gpu.removeAll()
        memory.removeAll()
        download.removeAll()
        upload.removeAll()
        diskRead.removeAll()
        diskWrite.removeAll()
        temperature.removeAll()
    }

    private static func push(_ value: Double, into values: inout [Double]) {
        values.append(value.isFinite ? value : 0)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}

// MARK: - Formatting

enum MetricFormatter {
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))°C"
    }

    static func bytes(_ value: UInt64, style: ByteCountFormatter.CountStyle = .file) -> String {
        guard value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: style)
    }

    /// A compact rate for the narrow detail cards, e.g. `61KB/s` or `1.5MB/s`.
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        let number = unitIndex == 0 || value >= 10
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number)\(units[unitIndex])"
    }

}
