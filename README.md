# Mac Monitor

A lightweight native macOS menubar app that shows real-time CPU throttling and memory stats — built with Swift, zero dependencies.

## What it shows

In the menubar:
```
✅ 0% throttle | 4.2GB RAM
```

Click to expand:
```
── CPU ──────────────────
  Throttled by : 0%  ✅ No throttling
  Frequency    : 2700 MHz / 2700 MHz
  Thermal level: 16 / 100
── Memory ───────────────
  Used RAM     : 4.2 / 8.0 GB
  Swap used    : 0.00 GB
```

## Throttle status

| Emoji | Meaning |
|-------|---------|
| ✅ | No throttling — full speed |
| 🟡 | Light throttle (< 25%) |
| 🟠 | Moderate throttle (25–50%) |
| 🔴 | Heavy throttle (> 50%) |

## Build & Run

```bash
swiftc main.swift -o MacMonitor -framework Cocoa
./MacMonitor
```

## Auto-start on login

```bash
cp com.macmonitor.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.macmonitor.plist
```

## Requirements

- macOS 12 Monterey or later
- Swift 5.7+
- Intel or Apple Silicon Mac

## Why this exists

Built during a Mac cleanup session to monitor CPU thermal throttling in real time.
The `machdep.xcpm.cpu_thermal_level` sysctl tells you how aggressively macOS is 
slowing your CPU to manage heat — something no native app shows clearly.

Updates every 60 seconds. No dock icon. Minimal CPU/RAM usage.
