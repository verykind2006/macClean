import Foundation
import AppKit

/// 一项准备执行的清理
struct PlanItem: Identifiable, Sendable {
    /// 路径；命令类规则用 "rule:<id>"
    let id: String
    let rule: Rule
    let path: String?
    let size: Int64
    let action: CleanAction

    var title: String {
        if let path { return Paths.display(path) }
        return "运行 \(rule.command ?? "")"
    }

    static func ruleKey(_ rule: Rule) -> String { "rule:" + rule.id }
}

/// 删前检查结果
enum Check: Sendable, Equatable {
    case ok
    case confirm(String)   // 需要用户勾选确认
    case blocked(String)   // 不执行

    var isBlocked: Bool { if case .blocked = self { true } else { false } }
}

struct CheckedItem: Identifiable, Sendable {
    var id: String { item.id }
    let item: PlanItem
    let check: Check
}

extension RuleResult {
    /// 这一项为什么不能勾选；nil 表示可以勾选
    func blockReason(for item: MatchedItem?) -> String? {
        switch rule.level {
        case .never: return "不能动"
        default: break
        }
        switch rule.action {
        case .none: return "App 不提供删除"
        case .finder: return "需要你在 Finder 里操作"
        default: break
        }
        if let k = ruleKeep { return "已决定保留：\(k.note)" }
        guard let item else { return nil }
        if let k = item.keep { return "已决定保留：\(k.note)" }
        if let k = item.containsKept { return "里面有要保留的：\(k.note)" }
        if let p = item.protection { return "代码保护：\(p)" }
        return nil
    }

    var isCommand: Bool { rule.action == .command }

    /// 可以勾选的清理项
    var planItems: [PlanItem] {
        if isCommand {
            guard blockReason(for: nil) == nil, !items.isEmpty else { return [] }
            return [PlanItem(id: PlanItem.ruleKey(rule), rule: rule, path: nil, size: totalSize, action: .command)]
        }
        return items.compactMap { m in
            blockReason(for: m) == nil
                ? PlanItem(id: m.path, rule: rule, path: m.path, size: m.size, action: rule.action)
                : nil
        }
    }
}

/// 删前检查（在主线程上调用：要查询正在运行的应用）
@MainActor
enum Prechecks {
    static func check(_ item: PlanItem) -> Check {
        if let path = item.path, let reason = Guards.deletionBlock(path) {
            return .blocked(reason)
        }
        if item.action == .command, let cmd = item.rule.command {
            let tool = String(cmd.split(separator: " ").first ?? "")
            if Shell.which(tool) == nil { return .blocked("找不到 \(tool) 命令") }
        }

        // 规则里点名的应用
        for bid in item.rule.apps ?? [] {
            if let app = runningApp(bundleID: bid) {
                return .blocked("「\(app)」正在运行，请先退出")
            }
        }

        for key in item.rule.preconditions ?? [] {
            switch key {
            case "app-not-running":
                if let path = item.path {
                    let name = (path as NSString).lastPathComponent
                    if let app = runningApp(matchingCacheName: name) {
                        return .blocked("「\(app)」正在运行，请先退出")
                    }
                    if hasActiveWAL(path) {
                        return .confirm("里面有数据库日志（-wal 文件）。如果对应的应用开着，请先退出")
                    }
                }
            case "onedrive-paused":
                if runningApp(bundleID: "com.microsoft.OneDrive-mac") != nil
                    || runningApp(bundleID: "com.microsoft.OneDrive") != nil {
                    return .confirm("我已经在 OneDrive 菜单里「暂停同步」了")
                }
            case "codex-stopped":
                if item.action == .codexTrim, let path = item.path {
                    // VACUUM 需要一份和数据库差不多大的临时空间
                    let need = CodexTrim.fileSize(path) + (2 << 30)
                    if DiskInfo.current().free < need {
                        return .blocked("剩余空间不够压缩数据库（需要约 \(Fmt.bytes(need))）")
                    }
                    if item.size == 0 { return .blocked("没有 \(Int(item.rule.olderThanDays ?? 7)) 天以前的对话，不用整理") }
                }
                if Shell.pgrep("codex app-server") {
                    return .blocked("Codex 后台服务还在运行。请在终端运行：pkill -f \"codex app-server\"")
                }
            default:
                break
            }
        }
        return .ok
    }

    static func runningApp(bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier?.lowercased() == bundleID.lowercased() }
            .map { $0.localizedName ?? bundleID }
    }

    /// 缓存目录名 → 正在运行的应用（目录名通常是 bundle id，也可能是厂商名或应用名）
    static func runningApp(matchingCacheName name: String) -> String? {
        let n = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased() else { continue }
            let appName = app.localizedName?.lowercased() ?? ""
            if bid == n || bid.hasPrefix(n + ".") || n.hasPrefix(bid + ".")
                || appName == n
                || (!n.contains(".") && (bid.contains("." + n + ".") || bid.hasSuffix("." + n))) {
                return app.localizedName ?? bid
            }
        }
        return nil
    }

    /// 目录里有非空的 -wal 文件（SQLite 正在使用的迹象）
    static func hasActiveWAL(_ path: String) -> Bool {
        guard let e = FileManager.default.enumerator(atPath: path) else { return false }
        var count = 0
        while let f = e.nextObject() as? String {
            count += 1
            if count > 20_000 { break }
            if f.hasSuffix("-wal"),
               let size = (try? FileManager.default.attributesOfItem(atPath: path + "/" + f))?[.size] as? Int64,
               size > 0 {
                return true
            }
        }
        return false
    }
}

enum Shell {
    static let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(Paths.home)/.local/bin:\(Paths.home)/.bun/bin"

    static func which(_ tool: String) -> String? {
        let dirs = (extraPath + ":/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":")
        for d in dirs {
            let p = "\(d)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func pgrep(_ pattern: String) -> Bool {
        run("/usr/bin/pgrep", ["-f", pattern]).status == 0
    }

    /// 运行命令，返回 (退出码, 输出)
    static func run(_ exe: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "无法启动：\(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func zsh(_ command: String) -> (status: Int32, output: String) {
        run("/bin/zsh", ["-c", command])
    }
}
