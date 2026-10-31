# 0008. The Performance Tab Samples In Process

## Context

The notch has tabs for Home and Shelf. A third, opt-in tab adds CPU, GPU,
memory, network, disk, and temperature readouts. The app is sandboxed
(`com.apple.security.app-sandbox`); its embedded XPC helper is not.

The reference implementations were studied, not adopted: Stats is a Swift
AppKit app that is not sandboxed, and btop is a C++ TUI. A probe on macOS 27
with an app-sandbox entitlement confirmed which APIs survive the sandbox:

- Mach host statistics, `sysctl`, `getifaddrs` / `NET_RT_IFLIST2`,
  `IOAccelerator.PerformanceStatistics`, `IOBlockStorageDriver` statistics,
  `statfs`, and `IOHIDEventSystemClient` temperature sensors work in process.
- `IOServiceOpen(AppleSMC)` returns `kIOReturnNotPermitted`, `IOReport`
  subscriptions fail, and process enumeration / `/bin/ps` is denied.

## Decision

The first version samples in process, on a utility queue, only while the
performance tab is visible. It uses:

- `host_statistics` for CPU tick deltas,
- `host_statistics64` plus `sysctl` for memory and memory pressure,
- `IOAccelerator` for GPU utilization and GPU memory,
- `sysctl(NET_RT_IFLIST2)` for 64-bit network counters,
- `IOBlockStorageDriver` plus `statfs` for disk rates and capacity,
- `IOHIDEventSystemClient` SPI for temperatures.

There is no privileged helper, no new entitlement, no root, no shelling out to
stats/btop/powermetrics, and no third-party dependency. Fan speed, power draw,
CPU/GPU frequency, and per-process rankings are out of scope for v1. They can
use the existing non-sandboxed XPC helper later.

The tab is opt-in (`performanceTabEnabled`, default false). It appears as a
third tab and does not change the shelf's visibility rules.

## Considered Options

- **Vendor Stats modules.** Rejected: Stats is an app with Kit/DB/XPC/AppKit
  dependencies, not a library, and it is not sandboxed.
- **Embed btop.** Rejected: btop is a C++ TUI, not a library, and cannot render
  into SwiftUI.
- **Extend the XPC helper for every metric.** Rejected for v1: every metric that
  works in process would pay IPC and state-synchronization costs for no benefit.
- **Use SMC or IOReport in process.** Rejected: the sandbox denies the SMC user
  client and IOReport subscriptions.

## Consequences

- The temperature reader depends on IOHID SPI. That is acceptable for the
  project's Developer ID/Homebrew distribution and matches the existing use of
  private APIs (CGSSpace, MediaRemote), but it is not Mac App Store compatible.
- Sensor names vary by chip. Missing sensors render as "Unavailable" or "—".
- The tab's cost is bounded by sampling only while it is on screen, at one
  second by default, and by reading a filtered temperature sensor list.
- Adding fan speed, power, or frequency later requires extending the helper;
  the snapshot type has room for those fields.
