import Foundation

/// 只读：展开规则里的路径并统计占用。不会修改任何文件。
enum Scanner {
    static func scan(_ rule: Rule, decisions: [Decision]) -> RuleResult {
        let excludes = rule.exclude ?? []
        let cutoff = rule.olderThanDays.map { Date().addingTimeInterval(-$0 * 86_400) }
        let keptPaths = decisions.compactMap { d -> (String, Decision)? in
            guard let p = d.path else { return nil }
            return (Paths.expand(p), d)
        }

        var seen = Set<String>()
        var items: [MatchedItem] = []
        for pattern in rule.paths {
            for path in Paths.glob(Paths.expand(pattern)) where !seen.contains(path) {
                seen.insert(path)
                let name = (path as NSString).lastPathComponent
                if excludes.contains(where: { Paths.matches(name, pattern: $0) }) { continue }

                let url = URL(fileURLWithPath: path)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if rule.action != .codexTrim, let cutoff, let modified, modified > cutoff { continue }

                var (size, unreadable) = allocatedSize(of: url)
                var info: String? = nil
                if rule.action == .codexTrim {
                    let days = rule.olderThanDays ?? 7
                    if let est = CodexTrim.estimate(path, days: days) {
                        info = "数据库共 \(Fmt.bytes(size))、\(Fmt.count(est.total)) 个对话；其中 \(Int(days)) 天以前的 \(Fmt.count(est.threads)) 个（内容约 \(Fmt.bytes(est.bytes))）"
                        size = est.bytes
                    } else {
                        info = "数据库共 \(Fmt.bytes(size))；读不出对话统计（可能正被 Codex 锁住）"
                        size = 0
                    }
                }
                let keep = keptPaths.first { path == $0.0 || path.hasPrefix($0.0 + "/") }?.1
                let containsKept = keep == nil ? keptPaths.first { $0.0.hasPrefix(path + "/") }?.1 : nil
                items.append(MatchedItem(
                    path: path, size: size, modified: modified, unreadable: unreadable,
                    keep: keep, containsKept: containsKept,
                    protection: Guards.protectionReason(path), info: info,
                    volume: Paths.externalVolume(path)))
            }
        }
        items.sort { $0.size > $1.size }
        let ruleKeep = decisions.first { $0.ruleId == rule.id }
        return RuleResult(rule: rule, items: items, ruleKeep: ruleKeep)
    }

    /// 统计实际分配的磁盘大小（不跟随符号链接）。返回 (字节数, 无权读取的数量)
    static func allocatedSize(of url: URL) -> (Int64, Int) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return (0, 1) }
        if rv.isSymbolicLink == true { return (0, 0) }
        if rv.isDirectory != true { return (Int64(rv.totalFileAllocatedSize ?? 0), 0) }

        final class Counter { var n = 0 }
        let errors = Counter()
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in errors.n += 1; return true })
        else { return (0, 1) }

        var total: Int64 = 0
        for case let child as URL in e {
            guard let v = try? child.resourceValues(forKeys: keys) else { continue }
            if v.isSymbolicLink == true || v.isDirectory == true { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return (total, errors.n)
    }
}

struct DiskInfo: Sendable {
    let total: Int64
    let free: Int64
    var used: Int64 { total - free }

    /// 与 `df /` 的口径一致
    static func current() -> DiskInfo {
        var s = statfs()
        guard statfs("/", &s) == 0 else { return DiskInfo(total: 0, free: 0) }
        let bs = Int64(s.f_bsize)
        return DiskInfo(total: Int64(s.f_blocks) * bs, free: Int64(s.f_bavail) * bs)
    }
}
