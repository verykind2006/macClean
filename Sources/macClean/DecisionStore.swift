import Foundation

/// 用户自己的「决定保留」清单：~/Library/Application Support/macClean/decisions.json
/// 一开始是空的，用户在界面上点「保留」时逐条记录。不进安装包。
enum DecisionStore {
    static let dir = Paths.home + "/Library/Application Support/macClean"
    static var path: String { dir + "/decisions.json" }

    static func load(from file: String = path) throws -> [Decision] {
        guard FileManager.default.fileExists(atPath: file) else { return [] }
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        return try JSONDecoder().decode(DecisionFile.self, from: data).decisions
    }

    static func save(_ decisions: [Decision], to file: String = path) throws {
        try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(DecisionFile(version: 1, decisions: decisions))
        try data.write(to: URL(fileURLWithPath: file), options: .atomic)
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 存盘时把家目录写成 ~，换机器也能用
    static func portable(_ path: String) -> String { Paths.display(path) }
}

extension Scanner {
    /// 把保留决定套到已有的扫描结果上（保留/取消保留后不用重新扫描）
    static func apply(_ decisions: [Decision], to r: RuleResult) -> RuleResult {
        let kept = decisions.compactMap { d -> (String, Decision)? in
            d.path.map { (Paths.expand($0), d) }
        }
        let items = r.items.map { m -> MatchedItem in
            let keep = kept.first { m.path == $0.0 || m.path.hasPrefix($0.0 + "/") }?.1
            let containsKept = keep == nil ? kept.first { $0.0.hasPrefix(m.path + "/") }?.1 : nil
            return MatchedItem(path: m.path, size: m.size, modified: m.modified, unreadable: m.unreadable,
                               keep: keep, containsKept: containsKept, protection: m.protection, info: m.info, volume: m.volume)
        }
        return RuleResult(rule: r.rule, items: items, ruleKeep: decisions.first { $0.ruleId == r.rule.id })
    }
}
