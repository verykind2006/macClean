import Foundation
import Darwin
import IOKit
import Observation

/// 此刻状态：CPU / GPU / 内存 / 磁盘读写，以及各进程的占用。
/// 全部只读：只看数字，不结束、不改动任何进程。

enum Metric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, io
    var id: String { rawValue }
}

struct ProcStat: Identifiable, Sendable {
    let pid: Int32
    let name: String
    var cpu: Double = 0          // ps 的 %CPU：100% = 占满一个核心
    var gpu: Double = 0          // 占 GPU 时间的百分比
    var memory: Int64 = 0        // 内存占用（和「活动监视器」的「内存」一列同口径；拿不到时用常驻内存）
    var readRate: Double = 0     // 字节/秒
    var writeRate: Double = 0
    var id: Int32 { pid }
    var ioRate: Double { readRate + writeRate }

    func value(_ m: Metric) -> Double {
        switch m {
        case .cpu: cpu
        case .gpu: gpu
        case .memory: Double(memory)
        case .io: ioRate
        }
    }
}

struct MonitorSample: Sendable {
    var cpu: Double = 0              // 整机 0–100
    var cores = 0
    var gpu: Double = 0              // 0–100；读不到时为 nil 的语义用 gpuAvailable
    var gpuAvailable = false
    var memTotal: Int64 = 0
    var memUsed: Int64 = 0           // App 内存 + 联动内存 + 被压缩
    var memCached: Int64 = 0         // 已缓存文件
    var swapUsed: Int64 = 0
    var pressure = 1                 // 1 正常 / 2 紧张 / 4 危险
    var readRate: Double = 0
    var writeRate: Double = 0
    var procs: [ProcStat] = []
    var ioUnreadable = 0             // 读不到磁盘读写的进程数（系统进程需要管理员权限）
}

/// 采样器：保存上一次的累计值，用差值算速率。只在一个后台任务里串行调用。
final class Sampler: @unchecked Sendable {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastDisk: (read: UInt64, write: UInt64, at: Date)?
    private var lastGPU: [Int32: UInt64] = [:]
    private var lastGPUAt: Date?
    private var lastProcIO: [Int32: (UInt64, UInt64)] = [:]
    private var lastProcIOAt: Date?
    private var footprints: [Int32: Int64] = [:]
    private var tick = 0

    func sample() -> MonitorSample {
        var s = MonitorSample()
        let now = Date()
        (s.cpu, s.cores) = cpuLoad()
        memory(&s)
        if let g = gpuUtilization() { s.gpu = g; s.gpuAvailable = true }
        diskIO(&s, now: now)

        // 进程：ps 是 setuid 的，能看到所有进程的 CPU 和常驻内存
        var procs = psList()
        // 内存：top 给的是和活动监视器一样的「内存占用」；它比 ps 慢，每 3 次采一次
        if tick % 3 == 0 { footprints = topFootprints() }
        tick += 1
        let gpuByPid = gpuPerProcess(now: now)
        let io = procIO(procs.map(\.pid), now: now)
        s.ioUnreadable = io.unreadable
        for i in procs.indices {
            let pid = procs[i].pid
            if let f = footprints[pid] { procs[i].memory = f }
            procs[i].gpu = gpuByPid[pid] ?? 0
            if let r = io.rates[pid] { procs[i].readRate = r.0; procs[i].writeRate = r.1 }
        }
        s.procs = procs
        return s
    }

    // MARK: CPU

    private func cpuLoad() -> (Double, Int) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return (0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let sys = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total, busy >= last.busy else { return (0, Int(cpuCount)) }
        return (min(100, Double(busy - last.busy) / Double(total - last.total) * 100), Int(cpuCount))
    }

    // MARK: 内存

    private func memory(_ s: inout MonitorSample) {
        s.memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            s.memUsed = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
            s.memCached = (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * page
        }
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 { s.swapUsed = Int64(xsw.xsu_used) }
        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0) == 0 { s.pressure = Int(level) }
    }

    // MARK: GPU（IOKit 的 IOAccelerator，不需要管理员权限）

    private func gpuUtilization() -> Double? {
        var result: Double?
        forEachService("IOAccelerator") { svc in
            if let stats = Self.property(svc, "PerformanceStatistics") as? [String: Any],
               let u = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                result = max(result ?? 0, u)
            }
        }
        return result
    }

    /// 每个进程在 GPU 上累计用掉的时间（纳秒），和上次相比得到占用百分比
    private func gpuPerProcess(now: Date) -> [Int32: Double] {
        var totals: [Int32: UInt64] = [:]
        forEachService("IOAccelerator") { svc in
            var iter = io_iterator_t()
            guard IORegistryEntryGetChildIterator(svc, kIOServicePlane, &iter) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iter) }
            while case let child = IOIteratorNext(iter), child != 0 {
                defer { IOObjectRelease(child) }
                guard let creator = Self.property(child, "IOUserClientCreator") as? String,
                      let pid = Self.pid(fromCreator: creator),
                      let usage = Self.property(child, "AppUsage") as? [[String: Any]] else { continue }
                let ns = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
                totals[pid, default: 0] += ns
            }
        }
        defer { lastGPU = totals; lastGPUAt = now }
        guard let at = lastGPUAt else { return [:] }
        let elapsed = now.timeIntervalSince(at) * 1e9
        guard elapsed > 0 else { return [:] }
        var out: [Int32: Double] = [:]
        for (pid, ns) in totals {
            guard let prev = lastGPU[pid], ns > prev else { continue }
            out[pid] = min(100, Double(ns - prev) / elapsed * 100)
        }
        return out
    }

    /// "pid 622, WindowServer" → 622
    static func pid(fromCreator s: String) -> Int32? {
        guard s.hasPrefix("pid ") else { return nil }
        let num = s.dropFirst(4).prefix { $0.isNumber }
        return Int32(num)
    }

    // MARK: 磁盘读写（IOBlockStorageDriver 的累计字节数）

    private func diskIO(_ s: inout MonitorSample, now: Date) {
        var read: UInt64 = 0, write: UInt64 = 0
        forEachService("IOBlockStorageDriver") { svc in
            if let st = Self.property(svc, "Statistics") as? [String: Any] {
                read += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
        }
        defer { lastDisk = (read, write, now) }
        guard let last = lastDisk else { return }
        let dt = now.timeIntervalSince(last.at)
        guard dt > 0 else { return }
        s.readRate = read >= last.read ? Double(read - last.read) / dt : 0
        s.writeRate = write >= last.write ? Double(write - last.write) / dt : 0
    }

    /// 每个进程的磁盘读写：proc_pid_rusage 只能读自己用户的进程，系统进程会读不到
    private func procIO(_ pids: [Int32], now: Date) -> (rates: [Int32: (Double, Double)], unreadable: Int) {
        var cur: [Int32: (UInt64, UInt64)] = [:]
        var unreadable = 0
        for pid in pids {
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            if r == 0 { cur[pid] = (ri.ri_diskio_bytesread, ri.ri_diskio_byteswritten) } else { unreadable += 1 }
        }
        defer { lastProcIO = cur; lastProcIOAt = now }
        guard let at = lastProcIOAt else { return ([:], unreadable) }
        let dt = now.timeIntervalSince(at)
        guard dt > 0 else { return ([:], unreadable) }
        var out: [Int32: (Double, Double)] = [:]
        for (pid, v) in cur {
            guard let p = lastProcIO[pid] else { continue }
            let rd = v.0 >= p.0 ? Double(v.0 - p.0) / dt : 0
            let wr = v.1 >= p.1 ? Double(v.1 - p.1) / dt : 0
            if rd > 0 || wr > 0 { out[pid] = (rd, wr) }
        }
        return (out, unreadable)
    }

    // MARK: 进程列表

    private func psList() -> [ProcStat] {
        let out = Self.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="])
        var list: [ProcStat] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), pid > 0 else { continue }
            var p = ProcStat(pid: pid, name: String(parts[3]))
            p.cpu = Double(parts[1]) ?? 0
            p.memory = (Int64(parts[2]) ?? 0) * 1024
            list.append(p)
        }
        return list
    }

    private func topFootprints() -> [Int32: Int64] {
        let out = Self.run("/usr/bin/top", ["-l", "1", "-stats", "pid,mem"])
        var map: [Int32: Int64] = [:]
        var inTable = false
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if !inTable { inTable = parts.first == "PID"; continue }
            guard parts.count >= 2, let pid = Int32(parts[0]), let b = Self.parseSize(String(parts[1])) else { continue }
            map[pid] = b
        }
        return map
    }

    /// top 的写法：12K、480M+、20G-、1234B
    static func parseSize(_ raw: String) -> Int64? {
        var s = raw
        while let c = s.last, c == "+" || c == "-" { s.removeLast() }
        guard let unit = s.last else { return nil }
        let mult: Double
        switch unit {
        case "B": mult = 1
        case "K": mult = 1024
        case "M": mult = 1024 * 1024
        case "G": mult = 1024 * 1024 * 1024
        case "T": mult = 1024 * 1024 * 1024 * 1024
        default: return Int64(s)
        }
        guard let v = Double(s.dropLast()) else { return nil }
        return Int64(v * mult)
    }

    // MARK: 工具

    private func forEachService(_ cls: String, _ body: (io_service_t) -> Void) {
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        while case let svc = IOIteratorNext(iter), svc != 0 {
            body(svc)
            IOObjectRelease(svc)
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// 界面用的模型：每 2 秒采一次，保留最近 2 分钟的曲线
@MainActor
@Observable
final class SystemMonitor {
    private(set) var latest = MonitorSample()
    private(set) var history: [Metric: [Double]] = [:]
    private(set) var samples = 0
    static let interval: Double = 2
    static let historyLength = 60

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func refresh() async {
        let sampler = self.sampler
        let s = await Task.detached(priority: .utility) { sampler.sample() }.value
        latest = s
        samples += 1
        // 第一次采样没有差值（CPU / 读写都是 0），不画进曲线
        guard samples > 1 else { return }
        append(.cpu, s.cpu)
        append(.gpu, s.gpu)
        append(.memory, s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) * 100 : 0)
        append(.io, s.readRate + s.writeRate)
    }

    private func append(_ m: Metric, _ v: Double) {
        var h = history[m] ?? []
        h.append(v)
        if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
        history[m] = h
    }

    var ready: Bool { samples > 1 }

    func top(_ m: Metric, _ n: Int = 12) -> [ProcStat] {
        latest.procs
            .filter { $0.value(m) > 0 }
            .sorted { $0.value(m) > $1.value(m) }
            .prefix(n)
            .map { $0 }
    }
}
