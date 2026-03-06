import Cocoa
import Foundation

// ── helpers ──────────────────────────────────────────────────────────────────
func sysctl_int(_ key: String) -> Int {
    var value: Int = 0
    var size = MemoryLayout<Int>.size
    sysctlbyname(key, &value, &size, nil, 0)
    return value
}

// Thermal level (0–100+) is the real throttle indicator on Intel Macs.
// The CPU throttles itself via PROCHOT/RAPL at hardware level before macOS
// even lowers the P-state ceiling, so thermal level is more accurate.
func thermalInfo() -> (level: Int, freqCeilMHz: Int, maxMHz: Int) {
    let thermal  = sysctl_int("machdep.xcpm.cpu_thermal_level")
    let bootMax  = sysctl_int("machdep.xcpm.bootpst")
    let hardLim  = sysctl_int("machdep.xcpm.hard_plimit_max_100mhz_ratio")
    return (thermal, hardLim * 100, bootMax * 100)
}

// Map thermal level → emoji + status text
func thermalStatus(_ level: Int) -> (emoji: String, text: String) {
    switch level {
    case 0..<15:  return ("✅", "Cool — full speed")
    case 15..<35: return ("🟡", "Warm — light throttle")
    case 35..<60: return ("🟠", "Hot — moderate throttle")
    case 60..<80: return ("🔴", "Very hot — heavy throttle")
    default:       return ("🚨", "Critical — severe throttle")
    }
}

// Matches Activity Monitor: Used = active + wired + compressed
func memInfo() -> (usedGB: Double, totalGB: Double, swapGB: Double) {
    let total    = Double(ProcessInfo.processInfo.physicalMemory) / 1e9
    var stats    = vm_statistics64()
    var count    = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let pageSize = Double(vm_kernel_page_size)
    withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            _ = host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    // active + wired + compressor = what Activity Monitor calls "Used"
    let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize / 1e9

    var swapUsage = xsw_usage()
    var swapSize  = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
    let swap = Double(swapUsage.xsu_used) / 1e9

    return (used, total, swap)
}

// ── app ───────────────────────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var menu: NSMenu!

    // CPU items
    let itemStatus   = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemLevel    = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemLevelBar = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemFreq     = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    // Memory items
    let itemMem      = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemSwap     = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    // Footer
    let itemUpdated  = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "── CPU Heat & Throttle ──", action: nil, keyEquivalent: ""))
        menu.addItem(itemStatus)
        menu.addItem(itemLevel)
        menu.addItem(itemLevelBar)
        menu.addItem(itemFreq)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "── Memory ───────────────", action: nil, keyEquivalent: ""))
        menu.addItem(itemMem)
        menu.addItem(itemSwap)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemUpdated)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Mac Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // Visual heat bar e.g. [████████░░] 80
    func heatBar(_ level: Int) -> String {
        let capped = min(level, 100)
        let filled = capped / 10
        let empty  = 10 - filled
        let bar    = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        return "  [\(bar)] \(level)/100"
    }

    func tick() {
        let cpu = thermalInfo()
        let mem = memInfo()
        let (emoji, text) = thermalStatus(cpu.level)

        // ── menubar: just emoji + thermal level ───────────────
        let label = "\(emoji) \(cpu.level)"
        DispatchQueue.main.async {
            self.statusItem.button?.title = label
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        let timeStr = fmt.string(from: Date())

        DispatchQueue.main.async {
            self.itemStatus.title   = "  \(emoji)  \(text)"
            self.itemLevel.title    = "  Thermal level : \(cpu.level) / 100"
            self.itemLevelBar.title = self.heatBar(cpu.level)
            self.itemFreq.title     = "  Freq ceiling  : \(cpu.freqCeilMHz) MHz (max \(cpu.maxMHz) MHz)"
            self.itemMem.title      = "  Used RAM  : \(String(format: "%.1f", mem.usedGB)) / \(String(format: "%.1f", mem.totalGB)) GB"
            self.itemSwap.title     = "  Swap used : \(String(format: "%.2f", mem.swapGB)) GB"
            self.itemUpdated.title  = "  Updated: \(timeStr)  (every 5s)"
        }
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
