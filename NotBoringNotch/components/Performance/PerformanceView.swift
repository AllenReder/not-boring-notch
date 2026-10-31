//
//  PerformanceView.swift
//  NotBoringNotch
//

import Defaults
import SwiftUI

/// The performance tab. It samples only while it is on screen; leaving the tab
/// or closing the notch stops the monitor.
@MainActor
struct PerformanceView: View {
    @ObservedObject var monitor = SystemMetricsMonitor.shared
    @Default(.performanceInterval) private var interval
    @Default(.performanceCardOrder) private var cardOrder
    @State private var subscriberID = UUID()

    private var resolvedOrder: [PerformanceMetric] {
        var seen = Set<PerformanceMetric>()
        var order = cardOrder.filter { seen.insert($0).inserted }
        for metric in PerformanceMetric.defaultOrder where !seen.contains(metric) {
            seen.insert(metric)
            order.append(metric)
        }
        return Array(order.prefix(PerformanceMetric.allCases.count))
    }

    /// Row-major: the first three metrics fill the top row, the last three the bottom row.
    private var rows: [[PerformanceMetric]] {
        let order = resolvedOrder
        return [
            Array(order.prefix(3)),
            Array(order.dropFirst(3).prefix(3))
        ]
    }

    var body: some View {
        Group {
            if let snapshot = monitor.snapshot {
                dashboard(snapshot)
            } else {
                loading
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .onAppear {
            monitor.start(subscriber: subscriberID, interval: interval.rawValue)
        }
        .onDisappear {
            monitor.stop(subscriber: subscriberID)
        }
        .onChange(of: interval) { _, newValue in
            monitor.start(subscriber: subscriberID, interval: newValue.rawValue)
        }
    }

    private func dashboard(_ snapshot: SystemMetricsSnapshot) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { metric in
                        metricCard(metric, snapshot: snapshot)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func metricCard(_ metric: PerformanceMetric, snapshot: SystemMetricsSnapshot) -> some View {
        PerformanceMetricCard(
            title: metric.title,
            icon: metric.icon,
            value: value(for: metric, snapshot: snapshot),
            subtitle: subtitle(for: metric, snapshot: snapshot),
            values: history(for: metric),
            maxValue: maxValue(for: metric),
            color: color(for: metric)
        )
    }

    private var loading: some View {
        VStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Sampling…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metric content

    private func value(for metric: PerformanceMetric, snapshot: SystemMetricsSnapshot) -> String {
        switch metric {
        case .cpu:
            return MetricFormatter.percent(snapshot.cpu.usage)
        case .gpu:
            return snapshot.gpu.map { MetricFormatter.percent($0.utilization) } ?? "—"
        case .memory:
            return MetricFormatter.percent(snapshot.memory.usage)
        case .temperature:
            return MetricFormatter.temperature(snapshot.thermal.cpuTemperature)
        case .network:
            return "↓ \(MetricFormatter.rate(snapshot.network.downloadBytesPerSecond))"
        case .disk:
            return snapshot.disk.readBytesPerSecond >= snapshot.disk.writeBytesPerSecond
                ? "R \(MetricFormatter.rate(snapshot.disk.readBytesPerSecond))"
                : "W \(MetricFormatter.rate(snapshot.disk.writeBytesPerSecond))"
        }
    }

    private func subtitle(for metric: PerformanceMetric, snapshot: SystemMetricsSnapshot) -> String {
        switch metric {
        case .cpu:
            return "User \(MetricFormatter.percent(snapshot.cpu.userUsage)) · Sys \(MetricFormatter.percent(snapshot.cpu.systemUsage))"
        case .gpu:
            return gpuSubtitle(snapshot.gpu)
        case .memory:
            return "\(MetricFormatter.bytes(snapshot.memory.used, style: .memory)) / \(MetricFormatter.bytes(snapshot.memory.total, style: .memory)) · \(snapshot.memory.pressure.label)"
        case .temperature:
            return thermalSubtitle(snapshot.thermal)
        case .network:
            return "↑ \(MetricFormatter.rate(snapshot.network.uploadBytesPerSecond)) · \(snapshot.network.interfaceName ?? "No interface")"
        case .disk:
            let other = snapshot.disk.readBytesPerSecond >= snapshot.disk.writeBytesPerSecond
                ? "W \(MetricFormatter.rate(snapshot.disk.writeBytesPerSecond))"
                : "R \(MetricFormatter.rate(snapshot.disk.readBytesPerSecond))"
            return "\(other) · \(MetricFormatter.bytes(snapshot.disk.freeBytes)) free"
        }
    }

    private func history(for metric: PerformanceMetric) -> [Double] {
        switch metric {
        case .cpu: return monitor.history.cpu
        case .gpu: return monitor.history.gpu
        case .memory: return monitor.history.memory
        case .temperature: return monitor.history.temperature
        case .network: return monitor.history.download
        case .disk: return monitor.history.diskRead
        }
    }

    private func maxValue(for metric: PerformanceMetric) -> Double {
        switch metric {
        case .cpu, .gpu, .memory:
            return 1
        case .temperature:
            return 100
        case .network:
            return rateMax(monitor.history.download)
        case .disk:
            return rateMax(monitor.history.diskRead)
        }
    }

    private func color(for metric: PerformanceMetric) -> Color {
        switch metric {
        case .cpu: return .metricCPU
        case .gpu: return .metricGPU
        case .memory: return .metricMemory
        case .temperature: return .metricThermal
        case .network: return .metricNetwork
        case .disk: return .metricDisk
        }
    }

    private func gpuSubtitle(_ gpu: GPUMetrics?) -> String {
        guard let gpu else { return "Unavailable" }
        guard let memory = gpu.inUseMemory else { return "GPU" }
        return "\(MetricFormatter.bytes(memory, style: .memory)) in use"
    }

    private func thermalSubtitle(_ thermal: ThermalMetrics) -> String {
        var parts: [String] = []
        if let gpu = thermal.gpuTemperature {
            parts.append("GPU \(MetricFormatter.temperature(gpu))")
        }
        if let storage = thermal.storageTemperature {
            parts.append("SSD \(MetricFormatter.temperature(storage))")
        }
        if let battery = thermal.batteryTemperature {
            parts.append("Batt \(MetricFormatter.temperature(battery))")
        }
        return parts.isEmpty ? "Unavailable" : parts.prefix(2).joined(separator: " · ")
    }

    private func rateMax(_ values: [Double]) -> Double {
        max(values.max() ?? 0, 1024) * 1.15
    }
}

// MARK: - Card

private struct PerformanceMetricCard: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String
    let values: [Double]
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Sparkline(values: values, color: color, maxValue: maxValue)
                .frame(height: 14)

            Text(subtitle)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value). \(subtitle)")
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let maxValue: Double

    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            if points.count > 1 {
                ZStack {
                    fillPath(points, in: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.30), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    linePath(points)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                        )
                }
            } else {
                Rectangle()
                    .fill(color.opacity(0.15))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let scale = max(maxValue, 0.0001)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let normalized = min(max((value.isFinite ? value : 0) / scale, 0), 1)
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(normalized) * size.height
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(_ points: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

// MARK: - Palette

private extension Color {
    static let metricCPU = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let metricGPU = Color(red: 0.68, green: 0.48, blue: 1.0)
    static let metricMemory = Color(red: 0.35, green: 0.85, blue: 0.62)
    static let metricThermal = Color(red: 1.0, green: 0.62, blue: 0.32)
    static let metricNetwork = Color(red: 0.35, green: 0.82, blue: 0.90)
    static let metricDisk = Color(red: 1.0, green: 0.78, blue: 0.35)
}
