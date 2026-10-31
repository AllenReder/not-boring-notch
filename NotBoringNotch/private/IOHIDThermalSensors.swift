//
//  IOHIDThermalSensors.swift
//  NotBoringNotch
//
//  Reads the temperature sensors that macOS exposes through IOHIDEventSystemClient.
//  These symbols are SPI; the app already reaches private frameworks the same way
//  (see CGSSpace.swift). The sandbox permits this without extra entitlements.
//

import CoreFoundation
import Foundation

@_silgen_name("IOHIDEventSystemClientCreate")
private func hidClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
@discardableResult
private func hidClientSetMatching(_ client: UnsafeRawPointer?, _ matching: CFDictionary?) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func hidClientCopyServices(_ client: UnsafeRawPointer?) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func hidServiceCopyProperty(_ service: UnsafeRawPointer?, _ key: CFString?) -> Unmanaged<CFString>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func hidServiceCopyEvent(
    _ service: UnsafeRawPointer?,
    _ type: Int64,
    _ matching: Int32,
    _ options: Int64
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func hidEventGetFloatValue(_ event: UnsafeRawPointer?, _ field: Int32) -> Double

/// Reads CPU/GPU/battery/storage temperatures from the HID event system.
///
/// The client and its service list are created once. Each `read()` only copies
/// temperature events for the sensors that were classified as relevant, which
/// keeps the per-tick cost low.
final class IOHIDThermalSensors {
    private enum Kind {
        case cpu
        case gpu
        case battery
        case storage
    }

    private struct Sensor {
        let service: UnsafeRawPointer
        let kind: Kind
    }

    private var client: CFTypeRef?
    private var services: CFArray?
    private var sensors: [Sensor] = []

    private static let temperatureEventType: Int64 = 15
    private static let temperatureEventField = Int32(15 << 16)

    init() {
        guard let clientReference = hidClientCreate(kCFAllocatorDefault) else { return }
        let client = clientReference.takeRetainedValue()
        self.client = client

        let matching: CFDictionary = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 5
        ] as CFDictionary
        hidClientSetMatching(Unmanaged.passUnretained(client).toOpaque(), matching)

        guard let servicesReference = hidClientCopyServices(Unmanaged.passUnretained(client).toOpaque()) else {
            return
        }
        let services = servicesReference.takeRetainedValue()
        self.services = services

        var classified: [Sensor] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, index) else { continue }
            guard let nameReference = hidServiceCopyProperty(service, "Product" as CFString) else { continue }
            let name = nameReference.takeRetainedValue() as String
            guard let kind = Self.kind(for: name) else { continue }
            classified.append(Sensor(service: service, kind: kind))
        }
        sensors = classified
    }

    func read() -> ThermalMetrics {
        guard !sensors.isEmpty else { return .empty }

        var cpuTemperatures: [Double] = []
        var gpuTemperatures: [Double] = []
        var batteryTemperature: Double?
        var storageTemperatures: [Double] = []

        for sensor in sensors {
            guard let temperature = temperature(for: sensor.service) else { continue }
            switch sensor.kind {
            case .cpu:
                cpuTemperatures.append(temperature)
            case .gpu:
                gpuTemperatures.append(temperature)
            case .battery:
                batteryTemperature = temperature
            case .storage:
                storageTemperatures.append(temperature)
            }
        }

        return ThermalMetrics(
            cpuTemperature: cpuTemperatures.max(),
            gpuTemperature: gpuTemperatures.max(),
            batteryTemperature: batteryTemperature,
            storageTemperature: storageTemperatures.max()
        )
    }

    private func temperature(for service: UnsafeRawPointer) -> Double? {
        guard let eventReference = hidServiceCopyEvent(
            service,
            Self.temperatureEventType,
            0,
            0
        ) else { return nil }
        let event = eventReference.takeRetainedValue()
        let value = hidEventGetFloatValue(
            Unmanaged.passUnretained(event).toOpaque(),
            Self.temperatureEventField
        )
        guard value.isFinite, value > 0, value < 150 else { return nil }
        return value
    }

    private static func kind(for name: String) -> Kind? {
        if name.contains("gas gauge") {
            return .battery
        }
        if name.hasPrefix("NAND") {
            return .storage
        }
        if name.contains("GPU") || (name.hasPrefix("PMU TP") && name.hasSuffix("g")) {
            return .gpu
        }
        if name.hasPrefix("PMU tdie") || name.contains("MTR Temp") {
            return .cpu
        }
        return nil
    }
}
