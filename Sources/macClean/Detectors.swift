import Foundation

/// 体检：只读，不修改任何东西
enum Severity: Int, Comparable, Sendable {
    case ok, warn, bad
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

struct Finding: Identifiable, Sendable {
    let id: String
    let title: String
    let severity: Severity
    let summary: String
    var details: [String] = []
    var advice: [String] = []
    var revealPath: String? = nil
    var copyCommand: String? = nil
}

enum Detectors {
    static let oneDriveRoot = Paths.home + "/Library/CloudStorage/OneDrive-个人"
    static let logDir = Paths.home + "/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Logs/Personal"
    static let heavyDirNames: Set<String> = [".build", "node_modules", ".venv", "venv", "DerivedData", "__pycache__", ".next", ".gradle"]

    static func runAll() -> [Finding] {
        [oneDriveLogStorm(), oneDriveChurn(), oneDriveClutter()]
    }

    // MARK: 1. OneDrive 日志风暴

    static func oneDriveLogStorm() -> Finding {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: logDir) else {
            return Finding(id: "logstorm", title: "OneDrive 日志", severity: .ok, summary: "没有找到 OneDrive 日志目录")
        }
        let window: Double = 10 * 60
        let since = Date().addingTimeInterval(-window)
        var recent = 0, total = 0
        var bytes: Int64 = 0
        for n in names where ["odl", "odlgz", "odlsent", "aodl"].contains((n as NSString).pathExtension) {
            total += 1
            let url = URL(fileURLWithPath: logDir + "/" + n)
            let v = try? url.resourceValues(forKeys: [.creationDateKey, .totalFileAllocatedSizeKey])
            bytes += Int64(v?.totalFileAllocatedSize ?? 0)
            if let c = v?.creationDate, c > since { recent += 1 }
        }
        let perMin = Double(recent) / (window / 60)

        let diag = (try? String(contentsOfFile: logDir + "/SyncDiagnostics.log", encoding: .utf8)) ?? ""
        let upload = number(after: "FilesToUpload = ", in: diag)
        let download = number(after: "FilesToDownload = ", in: diag)
        let diagTime = (try? fm.attributesOfItem(atPath: logDir + "/SyncDiagnostics.log"))?[.modificationDate] as? Date

        var sev = Severity.ok
        if perMin > 10 || (upload ?? 0) > 10_000 { sev = .bad }
        else if perMin > 5 || (upload ?? 0) > 1_000 || bytes > 3 << 30 { sev = .warn }

        var details = [
            "最近 10 分钟新增 \(recent) 个日志，每分钟约 \(String(format: "%.0f", perMin)) 个（正常约 3 个）",
            "日志共 \(total) 个文件，\(Fmt.bytes(bytes))",
        ]
        if let upload {
            details.append("待上传 \(Fmt.count(upload)) 个文件，待下载 \(Fmt.count(download ?? 0)) 个"
                           + (diagTime.map { "（OneDrive \(Fmt.relative($0))报告）" } ?? ""))
        }
        var reasons: [String] = []
        if (upload ?? 0) > 1_000 { reasons.append("待上传队列很长") }
        if perMin > 5 { reasons.append("日志增长很快（每分钟约 \(String(format: "%.0f", perMin)) 个）") }
        if bytes > 3 << 30 { reasons.append("日志已经占了 \(Fmt.bytes(bytes))") }
        let summary = sev == .ok
            ? "日志增长速度正常。"
            : reasons.joined(separator: "，") + "，会持续吃掉磁盘空间。"
        var advice: [String] = []
        if sev != .ok {
            advice = [
                "在 OneDrive 菜单里先「暂停同步」，止住日志增长",
                "看下面「OneDrive 里最近变动最多的目录」，找出大量零碎文件的来源（git 仓库、.build、node_modules）",
                "源头处理掉之后，在「可以删」里勾选「OneDrive 日志」删除旧日志，再恢复同步",
            ]
        }
        return Finding(id: "logstorm", title: "OneDrive 日志风暴", severity: sev, summary: summary,
                       details: details, advice: advice, revealPath: logDir)
    }

    static func number(after key: String, in text: String) -> Int? {
        guard let r = text.range(of: key, options: .backwards) else { return nil }
        let digits = text[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: 2. 最近变动最多的目录

    static func oneDriveChurn(hours: Double = 6) -> Finding {
        let since = Date().addingTimeInterval(-hours * 3600)
        let root = URL(fileURLWithPath: oneDriveRoot)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                     options: [], errorHandler: { _, _ in true }) else {
            return Finding(id: "churn", title: "OneDrive 最近的变动", severity: .ok, summary: "没有找到 OneDrive 目录")
        }
        var counts: [String: Int] = [:]
        var total = 0, scanned = 0
        let rootLen = root.path.count + 1
        for case let u as URL in e {
            scanned += 1
            guard let v = try? u.resourceValues(forKeys: keys), v.isDirectory != true,
                  let m = v.contentModificationDate, m > since else { continue }
            total += 1
            let rel = String(u.path.dropFirst(rootLen))
            let parts = rel.split(separator: "/", maxSplits: 3)
            let key = parts.count >= 3 ? parts.prefix(2).joined(separator: "/") : (parts.first.map(String.init) ?? rel)
            counts[key, default: 0] += 1
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(6)
        let maxCount = top.first?.value ?? 0
        let sev: Severity = maxCount > 10_000 ? .bad : (maxCount > 2_000 ? .warn : .ok)
        var f = Finding(
            id: "churn", title: "OneDrive 里最近变动最多的目录", severity: sev,
            summary: total == 0
                ? "最近 \(Int(hours)) 小时没有文件变动（共检查 \(Fmt.count(scanned)) 项）。"
                : "最近 \(Int(hours)) 小时有 \(Fmt.count(total)) 个文件变动，OneDrive 都要上传一遍。",
            details: top.map { "\($0.key)　\(Fmt.count($0.value)) 个文件" },
            revealPath: top.first.map { oneDriveRoot + "/" + $0.key })
        if sev != .ok {
            f.advice = ["变动特别多的目录，通常是编译产物、依赖目录或 git 仓库；把它们移出 OneDrive，或者整理（git gc）"]
        }
        return f
    }

    // MARK: 3. OneDrive 项目里的零碎文件

    static func oneDriveClutter() -> Finding {
        let fm = FileManager.default
        let projects = oneDriveRoot + "/projects"
        guard let names = try? fm.contentsOfDirectory(atPath: projects) else {
            return Finding(id: "clutter", title: "OneDrive 项目里的零碎文件", severity: .ok, summary: "没有找到 projects 目录")
        }
        var lines: [String] = []
        var worst = Severity.ok
        var gcCommands: [String] = []
        var totalFiles = 0
        var firstPath: String?

        for name in names.sorted() where !name.hasPrefix(".") {
            let dir = projects + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }

            // 编译产物和依赖目录
            for child in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where heavyDirNames.contains(child) {
                let n = countFiles(dir + "/" + child)
                totalFiles += n
                if n >= 200 {
                    lines.append("\(name)/\(child)　\(Fmt.count(n)) 个文件")
                    worst = max(worst, n > 5_000 ? .bad : .warn)
                    firstPath = firstPath ?? dir + "/" + child
                }
            }

            // git 仓库：松散对象和空对象（只看 .git 是目录的；指针文件说明数据在别处）
            let git = dir + "/.git"
            guard fm.fileExists(atPath: git, isDirectory: &isDir), isDir.boolValue else { continue }
            let (loose, empty) = looseObjects(git + "/objects")
            totalFiles += loose
            if empty > 0 {
                lines.append("\(name)　git 有 \(empty) 个空对象（仓库已损坏，先修复再 gc）")
                worst = .bad
                firstPath = firstPath ?? dir
            } else if loose >= 1_000 {
                lines.append("\(name)　git 松散对象 \(Fmt.count(loose)) 个")
                worst = max(worst, loose > 10_000 ? .bad : .warn)
                gcCommands.append("git -C \"\(dir)\" gc")
                firstPath = firstPath ?? dir
            }
        }

        var f = Finding(
            id: "clutter", title: "OneDrive 项目里的零碎文件", severity: worst,
            summary: lines.isEmpty
                ? "projects 里没有发现大批零碎文件。"
                : "这些零碎文件 OneDrive 要一个个上传，是日志风暴的常见源头。",
            details: lines, revealPath: firstPath)
        if !lines.isEmpty {
            f.advice = ["编译目录、依赖目录：移出 OneDrive，或让工具把编译产物写到 OneDrive 外面"]
            if !gcCommands.isEmpty { f.advice.append("git 松散对象：在终端运行下面的命令打包（先暂停 OneDrive 同步）") }
            if lines.contains(where: { $0.contains("空对象") }) {
                f.advice.append("git 空对象：按「踩过的坑」第 3 条修复（fsck → 找出对应文件 → 重新 hash-object），再 gc")
            }
            f.copyCommand = gcCommands.isEmpty ? nil : gcCommands.joined(separator: " && ")
        }
        return f
    }

    static func countFiles(_ path: String, limit: Int = 200_000) -> Int {
        guard let e = FileManager.default.enumerator(atPath: path) else { return 0 }
        var n = 0
        while e.nextObject() != nil {
            n += 1
            if n >= limit { break }
        }
        return n
    }

    /// objects/xx/yyyy 形式的松散对象数量，以及其中大小为 0 的数量
    static func looseObjects(_ objects: String) -> (Int, Int) {
        let fm = FileManager.default
        var loose = 0, empty = 0
        for d in (try? fm.contentsOfDirectory(atPath: objects)) ?? [] where d.count == 2 {
            for f in (try? fm.contentsOfDirectory(atPath: objects + "/" + d)) ?? [] {
                loose += 1
                if let s = (try? fm.attributesOfItem(atPath: "\(objects)/\(d)/\(f)"))?[.size] as? Int64, s == 0 {
                    empty += 1
                }
            }
        }
        return (loose, empty)
    }
}

/// 和上次扫描比较：可用空间、OneDrive 内部数据库
struct ScanSnapshot: Codable {
    let date: Date
    let free: Int64
    let dbfs: Int64?

    static let key = "lastScanSnapshot"

    static func load() -> ScanSnapshot? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScanSnapshot.self, from: d)
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    static func compare(prev: ScanSnapshot?, now: ScanSnapshot) -> Finding? {
        guard let prev else { return nil }
        let dFree = now.free - prev.free
        var details = ["可用空间：\(Fmt.bytes(prev.free)) → \(Fmt.bytes(now.free))（\(signed(dFree))）"]
        var sev = Severity.ok
        var advice: [String] = []
        if let a = prev.dbfs, let b = now.dbfs {
            let d = b - a
            details.append("OneDrive 内部数据库：\(Fmt.bytes(a)) → \(Fmt.bytes(b))（\(signed(d))）")
            if d > 5 << 30 {
                sev = .warn
                advice.append("OneDrive 内部数据库涨得很快，通常是在下载或缓存大量文件。不要删它；先看 OneDrive 的同步状态，必要时暂停同步")
            }
        }
        if dFree < -(10 << 30) { sev = max(sev, .warn) }
        return Finding(id: "trend", title: "和上次扫描相比（\(Fmt.time(prev.date))）", severity: sev,
                       summary: dFree < 0 ? "可用空间少了 \(Fmt.bytes(-dFree))。" : "可用空间多了 \(Fmt.bytes(dFree))。",
                       details: details, advice: advice)
    }

    static func signed(_ b: Int64) -> String { (b >= 0 ? "+" : "−") + Fmt.bytes(abs(b)) }
}
