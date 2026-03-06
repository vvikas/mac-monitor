import Cocoa
import Foundation

// ── helpers ──────────────────────────────────────────────────────────────────
func sysctl_int(_ key: String) -> Int {
    var value: Int = 0
    var size = MemoryLayout<Int>.size
    sysctlbyname(key, &value, &size, nil, 0)
    return value
}

func thermalLevel() -> Int {
    sysctl_int("machdep.xcpm.cpu_thermal_level")
}

func thermalStatus(_ level: Int) -> (emoji: String, text: String) {
    switch level {
    case 0..<15:  return ("✅", "Cool — full speed")
    case 15..<35: return ("🟡", "Warm — light throttle")
    case 35..<60: return ("🟠", "Hot — moderate throttle")
    case 60..<80: return ("🔴", "Very hot — heavy throttle")
    default:       return ("🚨", "Critical — severe throttle")
    }
}

// CPU usage % across all cores via host_processor_info (no sudo needed)
struct CPUUsage {
    let user: Double    // user-space work
    let system: Double  // kernel work
    let idle: Double    // doing nothing
    var active: Double { user + system }
}

var prevTicks: [Int32] = []

func cpuUsage() -> CPUUsage {
    var numCPUs: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numCPUInfo: mach_msg_type_number_t = 0

    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                               &numCPUs, &cpuInfo, &numCPUInfo) == KERN_SUCCESS,
          let info = cpuInfo else {
        return CPUUsage(user: 0, system: 0, idle: 100)
    }

    let stride = Int(CPU_STATE_MAX)
    var totalUser: Int32 = 0
    var totalSys:  Int32 = 0
    var totalIdle: Int32 = 0
    var totalAll:  Int32 = 0
    var curTicks:  [Int32] = []

    for i in 0..<Int(numCPUs) {
        let base = i * stride
        curTicks.append(info[base + Int(CPU_STATE_USER)])
        curTicks.append(info[base + Int(CPU_STATE_SYSTEM)])
        curTicks.append(info[base + Int(CPU_STATE_IDLE)])
        curTicks.append(info[base + Int(CPU_STATE_NICE)])
    }

    if prevTicks.count == curTicks.count {
        for i in 0..<Int(numCPUs) {
            let base = i * stride
            let dUser = curTicks[base]   - prevTicks[base]
            let dSys  = curTicks[base+1] - prevTicks[base+1]
            let dIdle = curTicks[base+2] - prevTicks[base+2]
            let dNice = curTicks[base+3] - prevTicks[base+3]
            totalUser += dUser + dNice
            totalSys  += dSys
            totalIdle += dIdle
            totalAll  += dUser + dSys + dIdle + dNice
        }
    }
    prevTicks = curTicks
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.size))

    guard totalAll > 0 else { return CPUUsage(user: 0, system: 0, idle: 100) }
    let d = Double(totalAll)
    return CPUUsage(
        user:   Double(totalUser) / d * 100,
        system: Double(totalSys)  / d * 100,
        idle:   Double(totalIdle) / d * 100
    )
}

// Visual heat bar e.g. [████████░░] 80/100
func heatBar(_ level: Int) -> String {
    let capped = min(level, 100)
    let filled = capped / 10
    let bar    = String(repeating: "█", count: filled) + String(repeating: "░", count: 10 - filled)
    return "  [\(bar)] \(level)/100"
}

// ── app ───────────────────────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var menu: NSMenu!

    let itemStatus  = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemLevel   = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemBar     = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemCPU     = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let itemUpdated = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "── CPU Monitor ──────────", action: nil, keyEquivalent: ""))
        menu.addItem(itemStatus)
        menu.addItem(itemLevel)
        menu.addItem(itemBar)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemCPU)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemUpdated)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        let level = thermalLevel()
        let cpu   = cpuUsage()
        let (emoji, text) = thermalStatus(level)

        // menubar: emoji + thermal level + cpu usage
        let label = "\(emoji) \(level)  CPU:\(Int(cpu.active))%"
        DispatchQueue.main.async {
            self.statusItem.button?.title = label
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"

        DispatchQueue.main.async {
            self.itemStatus.title  = "  \(emoji)  \(text)"
            self.itemLevel.title   = "  Thermal level : \(level) / 100"
            self.itemBar.title     = heatBar(level)
            self.itemCPU.title     = "  CPU usage     : \(Int(cpu.active))%  (usr \(Int(cpu.user))%  sys \(Int(cpu.system))%)"
            self.itemUpdated.title = "  Updated: \(fmt.string(from: Date()))  (every 5s)"
        }
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
