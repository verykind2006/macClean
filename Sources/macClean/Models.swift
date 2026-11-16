import Foundation

enum Level: String, Codable, CaseIterable, Sendable {
    case safe, ask, never
}

enum CleanAction: String, Codable, Sendable {
    case delete    // 直接删除（能重新生成的东西）
    case trash     // 移到废纸篓（用户文件）
    case command   // 运行工具自带的清理命令
    case finder    // 需要管理员权限：让用户在 Finder 里操作
    case none      // 不提供删除
}

struct Rule: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let level: Level
    let category: String?
    let paths: [String]
    let exclude: [String]?
    let action: CleanAction
    let command: String?
    let olderThanDays: Double?
    let preconditions: [String]?
    /// 这些应用（bundle id）在运行时不删
    let apps: [String]?
    let note: String?
    let regenerates: Bool?
    let cloneInflated: Bool?
}

struct RuleFile: Codable {
    let version: Int
    let rules: [Rule]
}

struct Decision: Codable, Sendable {
    let ruleId: String?
    let path: String?
    let note: String
    let date: String?
}

struct DecisionFile: Codable {
    let version: Int
    let decisions: [Decision]
}

/// 规则匹配到的一个具体路径
struct MatchedItem: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date?
    let unreadable: Int
    /// 用户决定保留（整项）
    let keep: Decision?
    /// 这一项里面有用户决定保留的子路径
    let containsKept: Decision?
    /// 代码写死的保护原因（OneDrive、.git 等），有值就绝不会删
    let protection: String?
}

struct RuleResult: Identifiable, Sendable {
    var id: String { rule.id }
    let rule: Rule
    let items: [MatchedItem]
    let ruleKeep: Decision?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    /// 去掉「决定保留」之后，估计能清理的大小
    var cleanableSize: Int64 {
        if ruleKeep != nil { return 0 }
        return items.filter { $0.keep == nil }.reduce(0) { $0 + $1.size }
    }
    var keptSize: Int64 { totalSize - cleanableSize }
    var unreadable: Int { items.reduce(0) { $0 + $1.unreadable } }
    var isEmpty: Bool { items.isEmpty }
}
