import Foundation

enum Outcome: Sendable {
    case done(String?)      // 成功（附带说明，比如命令输出）
    case failed(String)
    case skipped(String)

    var isDone: Bool { if case .done = self { true } else { false } }
    var isFailed: Bool { if case .failed = self { true } else { false } }
}

struct ExecResult: Identifiable, Sendable {
    var id: String { item.id }
    let item: PlanItem
    let outcome: Outcome
}

struct RunReport: Sendable {
    let results: [ExecResult]
    let before: DiskInfo
    let after: DiskInfo
    let startedAt: Date
    let dryRun: Bool
    var logPath: String?

    var freed: Int64 { after.free - before.free }
    var estimated: Int64 { results.filter { $0.outcome.isDone }.reduce(0) { $0 + $1.item.size } }
    var trashed: Int64 {
        results.filter { $0.outcome.isDone && $0.item.action == .trash }.reduce(0) { $0 + $1.item.size }
    }
    var doneCount: Int { results.filter { $0.outcome.isDone }.count }
    var failedCount: Int { results.filter { $0.outcome.isFailed }.count }
    var skippedCount: Int { results.count - doneCount - failedCount }
}

enum Executor {
    /// 逐项执行。每一项执行前都会再过一遍 Guards.deletionBlock。
    static func run(_ items: [CheckedItem], dryRun: Bool,
                    progress: @escaping @Sendable (Int, String) async -> Void) async -> [ExecResult] {
        var out: [ExecResult] = []
        for (i, c) in items.enumerated() {
            await progress(i, c.item.title)
            out.append(ExecResult(item: c.item, outcome: execute(c, dryRun: dryRun)))
        }
        await progress(items.count, "")
        return out
    }

    static func execute(_ c: CheckedItem, dryRun: Bool) -> Outcome {
        if case .blocked(let why) = c.check { return .skipped(why) }
        let item = c.item
        if let path = item.path, let why = Guards.deletionBlock(path) { return .skipped(why) }
        if dryRun { return .done("演练：没有真正执行") }

        switch item.action {
        case .delete:
            guard let path = item.path else { return .failed("缺少路径") }
            do {
                try FileManager.default.removeItem(atPath: path)
                return .done(nil)
            } catch {
                return .failed(error.localizedDescription)
            }
        case .trash:
            guard let path = item.path else { return .failed("缺少路径") }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                return .done(nil)
            } catch {
                return .failed(error.localizedDescription)
            }
        case .command:
            guard let cmd = item.rule.command else { return .failed("规则里没有命令") }
            let r = Shell.zsh(cmd)
            let tail = r.output.split(separator: "\n").suffix(3).joined(separator: "\n")
            return r.status == 0 ? .done(tail.isEmpty ? nil : tail) : .failed("退出码 \(r.status)：\(tail)")
        case .codexTrim:
            guard let path = item.path else { return .failed("缺少路径") }
            return CodexTrim.run(path, days: item.rule.olderThanDays ?? 7)
        case .finder, .none:
            return .skipped("这一项不由 App 删除")
        }
    }
}

/// 运行记录：每次一份详细日志 + 项目里 HISTORY.md 追加一行
enum RunLog {
    static let dir = Paths.home + "/Library/Logs/macClean"

    static func write(_ r: RunReport, machine: String) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd_HHmmss"
        let path = "\(dir)/\(stamp.string(from: r.startedAt))\(r.dryRun ? "_演练" : "").log"

        var lines = [
            "macClean 运行记录 \(Fmt.time(r.startedAt))  \(machine)\(r.dryRun ? "（演练，没有真正删除）" : "")",
            "可用空间（df）：\(Fmt.bytes(r.before.free)) → \(Fmt.bytes(r.after.free))，实际释放 \(Fmt.bytes(r.freed))",
            "估计：\(Fmt.bytes(r.estimated))；其中移到废纸篓 \(Fmt.bytes(r.trashed))",
            "成功 \(r.doneCount) · 失败 \(r.failedCount) · 跳过 \(r.skippedCount)",
            "",
        ]
        for x in r.results {
            let mark: String
            var detail = ""
            switch x.outcome {
            case .done(let note): mark = "[成功]"; detail = note ?? ""
            case .failed(let why): mark = "[失败]"; detail = why
            case .skipped(let why): mark = "[跳过]"; detail = why
            }
            lines.append("\(mark) \(actionWord(x.item.action)) \(x.item.path ?? x.item.title)  估计 \(Fmt.bytes(x.item.size))  \(detail)")
        }
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)

        if !r.dryRun { appendHistory(r, machine: machine) }
        return path
    }

    static func actionWord(_ a: CleanAction) -> String {
        switch a {
        case .delete: "删除"
        case .trash: "废纸篓"
        case .command: "命令"
        case .codexTrim: "整理数据库"
        case .finder, .none: "—"
        }
    }

    private static func appendHistory(_ r: RunReport, machine: String) {
        let path = DecisionStore.dir + "/HISTORY.md"
        try? FileManager.default.createDirectory(atPath: DecisionStore.dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            let header = "# 清理记录\n\n由 macClean 自动追加。「实际释放」来自 df 前后对比。\n\n| 时间 | 机器 | 项数 | 估计 | 实际释放（df） | 进废纸篓 |\n|---|---|---|---|---|---|\n"
            try? header.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let line = "| \(df.string(from: r.startedAt)) | \(machine) | \(r.doneCount) | \(Fmt.bytes(r.estimated)) | \(Fmt.bytes(r.freed)) | \(Fmt.bytes(r.trashed)) |\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }
}
