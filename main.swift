import Cocoa
import Foundation

// ── helpers ──────────────────────────────────────────────────────────────────
func sysctl_int(_ key: String) -> Int {
    var value: Int = 0
    var size = MemoryLayout<Int>.size
    sysctlbyname(key, &value, &size, nil, 0)
    return value
}

func thermalInfo() -> (level: Int, throttlePct: Int, freqMHz: Int, maxMHz: Int) {
    let thermal  = sysctl_int("machdep.xcpm.cpu_thermal_level")
    let bootMax  = sysctl_int("machdep.xcpm.bootpst")               // max P-state ratio
    let hardLim  = sysctl_int("machdep.xcpm.hard_plimit_max_100mhz_ratio")
    let freqMHz  = hardLim * 100
    let maxMHz   = bootMax * 100
    let throttle = bootMax > 0 ? ((bootMax - hardLim) * 100 / bootMax) : 0
    return (thermal, throttle, freqMHz, maxMHz)
}

func memInfo() -> (usedGB: Double, totalGB: Double, swapGB: Double) {
    let total = Double(ProcessInfo.processInfo.physicalMemory) / 1e9

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let pageSize = Double(vm_kernel_page_size)
    withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            _ = host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    let used = Double(stats.active_count + stats.wire_count) * pageSize / 1e9

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

    // menu items
    let itemThrottle  = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemFreq      = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemThermal   = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemMem       = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemSwap      = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "── CPU ──────────────────", action: nil, keyEquivalent: ""))
        menu.addItem(itemThrottle)
        menu.addItem(itemFreq)
        menu.addItem(itemThermal)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "── Memory ───────────────", action: nil, keyEquivalent: ""))
        menu.addItem(itemMem)
        menu.addItem(itemSwap)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Mac Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        tick()   // immediate first update
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        let cpu = thermalInfo()
        let mem = memInfo()

        // ── menubar label ──────────────────────────────────────
        let emoji: String
        switch cpu.throttlePct {
        case 0:       emoji = "✅"
        case 1..<25:  emoji = "🟡"
        case 25..<50: emoji = "🟠"
        default:      emoji = "🔴"
        }
        let label = "\(emoji) \(cpu.throttlePct)% throttle | \(String(format: "%.1f", mem.usedGB))GB RAM"
        DispatchQueue.main.async {
            self.statusItem.button?.title = label
        }

        // ── dropdown items ─────────────────────────────────────
        let statusText: String
        switch cpu.throttlePct {
        case 0:       statusText = "✅ No throttling"
        case 1..<25:  statusText = "🟡 Light throttle"
        case 25..<50: statusText = "🟠 Moderate throttle"
        default:      statusText = "🔴 Heavy throttle"
        }

        DispatchQueue.main.async {
            self.itemThrottle.title = "  Throttled by : \(cpu.throttlePct)%  \(statusText)"
            self.itemFreq.title     = "  Frequency    : \(cpu.freqMHz) MHz / \(cpu.maxMHz) MHz"
            self.itemThermal.title  = "  Thermal level: \(cpu.level) / 100"
            self.itemMem.title      = "  Used RAM     : \(String(format: "%.1f", mem.usedGB)) / \(String(format: "%.1f", mem.totalGB)) GB"
            self.itemSwap.title     = "  Swap used    : \(String(format: "%.2f", mem.swapGB)) GB"
        }
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no dock icon
app.run()
