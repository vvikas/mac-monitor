# Mac Monitor

A lightweight native macOS menubar app that shows real-time CPU thermal throttling and memory stats — built with Swift, zero dependencies, no Electron, no frameworks.

## Why this exists

macOS doesn't expose CPU throttling in any obvious way. When your Mac gets hot, Intel's CPU quietly slows itself down via hardware mechanisms (PROCHOT/RAPL) — before macOS even steps in. This causes sluggishness that's hard to diagnose.

Mac Monitor surfaces the `machdep.xcpm.cpu_thermal_level` sysctl — the true indicator of how hard your CPU is being throttled right now.

## What it shows

**Menubar** (always visible):
```
✅ 12       ← emoji status + thermal level
```

**Click to expand:**
```
── CPU Heat & Throttle ──
  ✅  Cool — full speed
  Thermal level : 12 / 100
  [█░░░░░░░░░] 12/100
  Freq ceiling  : 2700 MHz (max 2700 MHz)

── Memory ───────────────
  Used RAM  : 5.7 / 8.0 GB
  Swap used : 0.00 GB

  Updated: 14:32:05  (every 5s)

  Quit Mac Monitor
```

## Thermal level explained

The thermal level (`machdep.xcpm.cpu_thermal_level`) is Apple's internal CPU heat/throttle index. It reflects hardware-level throttling (Intel PROCHOT/RAPL) that happens *before* macOS lowers the software frequency ceiling — making it the most accurate real-time throttle indicator available without `sudo`.

| Level | Emoji | Status |
|-------|-------|--------|
| 0–14  | ✅ | Cool — full speed |
| 15–34 | 🟡 | Warm — light throttle |
| 35–59 | 🟠 | Hot — moderate throttle |
| 60–79 | 🔴 | Very hot — heavy throttle |
| 80+   | 🚨 | Critical — severe throttle |

## RAM calculation

Uses the same formula as Activity Monitor:
```
Used = (active + wired + compressed) pages × page size
```
The common mistake is omitting compressed memory, which can account for 1+ GB on a busy system.

## Build & run

Requirements: macOS 12 Monterey+, Swift 5.7+, Intel Mac (uses Intel-specific xcpm sysctls)

```bash
git clone https://github.com/vvikas/mac-monitor
cd mac-monitor
swiftc main.swift -o MacMonitor -framework Cocoa
./MacMonitor
```

## Auto-start on login

```bash
# Edit the plist to match your username if needed
cp com.macmonitor.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.macmonitor.plist
```

## Notes

- No dock icon — lives quietly in the menubar
- Updates every 5 seconds
- Zero external dependencies — pure Swift + Cocoa
- Binary is ~104 KB
- Intel Mac only (Apple Silicon uses a different thermal management system)
- Tested on MacBook Air 2015 (MacBookAir7,2), macOS Monterey 12.6
