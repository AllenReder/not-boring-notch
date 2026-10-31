//
//  SystemMetricsTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/models/SystemMetrics.swift
//

import Foundation

func checkMetricEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                                    file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkMetricClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.0005,
                      _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if abs(actual - expected) > tolerance {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct SystemMetricsTestsRunner {
    static func main() {
        testPercentFormatting()
        testRateFormatting()
        testTemperatureFormatting()
        testMemoryAndDiskUsage()
        testHistoryKeepsTheNewestSamples()
        testHistoryClampsNonFiniteValues()
        testHistorySkipsMissingTemperatures()
        print("✅ SystemMetricsTests: all passed")
    }

    // MARK: - Formatting

    static func testPercentFormatting() {
        checkMetricEqual(MetricFormatter.percent(0.234), "23%")
        checkMetricEqual(MetricFormatter.percent(1), "100%")
        checkMetricEqual(MetricFormatter.percent(0), "0%")
        checkMetricEqual(MetricFormatter.percent(-0.2), "0%", "negative values clamp")
        checkMetricEqual(MetricFormatter.percent(1.4), "100%", "overflow clamps")
        checkMetricEqual(MetricFormatter.percent(.nan), "—", "non-finite values are unavailable")
    }

    static func testRateFormatting() {
        checkMetricEqual(MetricFormatter.rate(0), "0B/s")
        checkMetricEqual(MetricFormatter.rate(-1), "0B/s")
        checkMetricEqual(MetricFormatter.rate(999), "999B/s")
        checkMetricEqual(MetricFormatter.rate(1_500), "1.5KB/s")
        checkMetricEqual(MetricFormatter.rate(1_500_000), "1.5MB/s")
        checkMetricEqual(MetricFormatter.rate(250_000_000), "250MB/s")
        checkMetricEqual(MetricFormatter.rate(.infinity), "0B/s")
    }

    static func testTemperatureFormatting() {
        checkMetricEqual(MetricFormatter.temperature(nil), "—")
        checkMetricEqual(MetricFormatter.temperature(82.4), "82°C")
        checkMetricEqual(MetricFormatter.temperature(82.6), "83°C")
        checkMetricEqual(MetricFormatter.temperature(.nan), "—")
    }

    // MARK: - Ratios

    static func testMemoryAndDiskUsage() {
        checkMetricClose(
            MemoryMetrics(used: 30, total: 20, pressure: .normal).usage,
            1,
            "memory usage clamps at 100%"
        )
        checkMetricClose(
            MemoryMetrics(used: 0, total: 0, pressure: .normal).usage,
            0,
            "zero total memory does not divide by zero"
        )
        checkMetricClose(
            MemoryMetrics(used: 5, total: 20, pressure: .warning).usage,
            0.25
        )
        checkMetricClose(
            DiskMetrics(readBytesPerSecond: 0, writeBytesPerSecond: 0, freeBytes: 40, totalBytes: 100).usage,
            0.6
        )
        checkMetricClose(
            DiskMetrics(readBytesPerSecond: 0, writeBytesPerSecond: 0, freeBytes: 0, totalBytes: 0).usage,
            0
        )
    }

    // MARK: - History

    static func testHistoryKeepsTheNewestSamples() {
        var history = SystemMetricsHistory()
        for index in 0..<100 {
            history.append(makeSnapshot(cpu: Double(index) / 100))
        }
        checkMetricEqual(history.cpu.count, SystemMetricsHistory.capacity)
        checkMetricClose(history.cpu.first ?? -1, 0.40)
        checkMetricClose(history.cpu.last ?? -1, 0.99)
    }

    static func testHistoryClampsNonFiniteValues() {
        var history = SystemMetricsHistory()
        history.append(makeSnapshot(cpu: .nan, download: .infinity))
        checkMetricClose(history.cpu.last ?? -1, 0)
        checkMetricClose(history.download.last ?? -1, 0)
    }

    static func testHistorySkipsMissingTemperatures() {
        var history = SystemMetricsHistory()
        history.append(makeSnapshot(temperature: nil))
        checkMetricEqual(history.temperature.count, 0)
        history.append(makeSnapshot(temperature: 72.5))
        checkMetricEqual(history.temperature.count, 1)
        checkMetricClose(history.temperature.last ?? -1, 72.5)
    }

    // MARK: - Fixtures

    static func makeSnapshot(
        cpu: Double = 0.1,
        gpu: Double? = 0.2,
        memoryUsed: UInt64 = 50,
        memoryTotal: UInt64 = 100,
        download: Double = 0,
        upload: Double = 0,
        read: Double = 0,
        write: Double = 0,
        temperature: Double? = nil
    ) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000_000),
            cpu: CPUMetrics(usage: cpu, userUsage: cpu, systemUsage: 0, idle: 1 - cpu),
            memory: MemoryMetrics(
                used: memoryUsed,
                total: memoryTotal,
                pressure: .normal
            ),
            gpu: gpu.map {
                GPUMetrics(utilization: $0, inUseMemory: nil, allocatedMemory: nil)
            },
            network: NetworkMetrics(
                downloadBytesPerSecond: download,
                uploadBytesPerSecond: upload,
                interfaceName: "en0",
                totalDownloaded: 0,
                totalUploaded: 0
            ),
            disk: DiskMetrics(
                readBytesPerSecond: read,
                writeBytesPerSecond: write,
                freeBytes: 0,
                totalBytes: 0
            ),
            thermal: ThermalMetrics(
                cpuTemperature: temperature,
                gpuTemperature: nil,
                batteryTemperature: nil,
                storageTemperature: nil
            )
        )
    }
}
