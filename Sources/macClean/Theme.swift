import SwiftUI

/// 高可读性主题：米白底、深色字、大字号。不使用低对比度灰字。
enum Theme {
    static let paper = Color(hex: 0xF6F3EC)     // 窗口底色（米白，不刺眼）
    static let card = Color.white
    static let cardHover = Color(hex: 0xFFFDF8)
    static let well = Color(hex: 0xF9F7F2)      // 卡片里的次级区域
    static let line = Color(hex: 0xE3DDD0)
    static let ink = Color(hex: 0x1C1C1E)       // 正文
    static let ink2 = Color(hex: 0x3D3D44)      // 说明文字（仍是高对比）
    static let ink3 = Color(hex: 0x55555E)      // 最浅的文字，不再更浅

    static let primary = Color(hex: 0x1F4E79)   // 主按钮：深墨蓝
    static let primaryPressed = Color(hex: 0x173C5D)

    static let barUsed = Color(hex: 0x46505C)
    static let barReclaim = Color(hex: 0x3E9A62)
    static let barFree = Color(hex: 0xD4EBDC)

    static let keep = Color(hex: 0x2D5B8A)
    static let warn = Color(hex: 0x8A5300)
    static let neutral = Color(hex: 0x45454D)

    // 字号（pt）：正文 17 起
    static let body: CGFloat = 17
    static let small: CGFloat = 15   // 最小字号
    static let mono: CGFloat = 15
}

extension Level {
    var title: String {
        switch self {
        case .safe: "可以删"
        case .ask: "要核对"
        case .never: "不能动"
        }
    }
    var mark: String {
        switch self {
        case .safe: "✅"
        case .ask: "❓"
        case .never: "⛔"
        }
    }
    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .ask: "questionmark.circle.fill"
        case .never: "nosign"
        }
    }
    var explain: String {
        switch self {
        case .safe: "删了能自动重新生成或重新下载。"
        case .ask: "删之前要先核对，或者需要你来决定。"
        case .never: "只显示占用，App 不会提供删除。"
        }
    }
    var color: Color {
        switch self {
        case .safe: Color(hex: 0x1E7343)
        case .ask: Color(hex: 0x8F5600)
        case .never: Color(hex: 0xA3302A)
        }
    }
    var tint: Color {
        switch self {
        case .safe: Color(hex: 0xE5F2E9)
        case .ask: Color(hex: 0xFAEFD9)
        case .never: Color(hex: 0xF8E5E2)
        }
    }
}

extension Rule {
    var symbol: String {
        switch category {
        case "logs": "doc.text.magnifyingglass"
        case "packages": "shippingbox"
        case "appcache": "square.stack.3d.up"
        case "build": "hammer"
        case "temp": "clock.arrow.circlepath"
        case "ai": "sparkles"
        case "media": "film"
        case "cloud": "icloud"
        case "data": "lock.shield"
        case "system": "gearshape"
        case "trash": "trash"
        case "download": "arrow.down.circle"
        default: "folder"
        }
    }

    var actionLabel: (String, String) {
        switch action {
        case .delete: ("直接删除", "xmark.bin")
        case .trash: ("移到废纸篓", "trash")
        case .command: ("运行 \(command ?? "命令")", "terminal")
        case .finder: ("在 Finder 里操作", "folder")
        case .none: ("App 不删除", "hand.raised")
        case .codexTrim: ("删 \(Int(olderThanDays ?? 7)) 天以前的对话并压缩", "cylinder.split.1x2")
        }
    }
}

enum Precondition {
    static func label(_ key: String) -> String {
        switch key {
        case "onedrive-paused": "删前先暂停 OneDrive 同步"
        case "app-not-running": "删前先退出相关应用"
        case "codex-stopped": "删前先停掉 Codex 后台服务"
        default: key
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Fmt {
    /// 二进制单位（1 GB = 1024³ 字节），和 df -h 的口径一致；固定用小数点，不跟随系统地区
    static func bytes(_ b: Int64) -> String {
        if b <= 0 { return "0 KB" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(b), i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        let num = (i <= 1 || v >= 100) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return "\(num) \(units[i])"
    }

    /// 整数千分位用逗号（不跟随系统地区，避免 5.855 被看成小数）
    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
