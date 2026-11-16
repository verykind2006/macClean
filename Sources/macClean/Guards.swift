import Foundation

/// 代码里写死的保护名单。规则文件写错了也不会误删这些地方。
/// 第 2 期的删除功能在执行前必须再调用一次 `protectionReason`。
enum Guards {
    static let oneDriveRoots = [
        Paths.home + "/Library/CloudStorage/OneDrive-个人",
        Paths.home + "/OneDrive",
    ]

    static let protectedPrefixes: [(String, String)] = [
        (Paths.home + "/.claude", "Claude 会话与配置"),
        (Paths.home + "/.ssh", "SSH 密钥"),
        (Paths.home + "/api-keys", "API 密钥"),
        (Paths.home + "/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite", "OneDrive 内部数据"),
        (Paths.home + "/Library/Application Support/OmniVoice", "VoiceStudio 数据"),
        (Paths.home + "/Library/Metadata/CoreSpotlight", "Spotlight 索引"),
        (Paths.home + "/Library/Containers/com.tencent.xinWeChat", "微信数据"),
        ("/System", "系统文件"),
        ("/Applications/Xcode.app", "Xcode"),
    ]

    /// 只允许删除这些目录下面的东西
    static let allowedRoots = [Paths.home + "/", "/var/folders/", "/private/var/folders/"]

    /// 这些目录本身绝不整个删除（删它们下面的条目可以）
    static let tooBroad: Set<String> = {
        let h = Paths.home
        var s: Set<String> = [h, "/", "/var/folders", "/private/var/folders",
                              Paths.darwinUserDir, Paths.tmpDir,
                              Paths.darwinUserDir + "/C", Paths.darwinUserDir + "/X", Paths.darwinUserDir + "/T"]
        for sub in ["Library", "Library/Caches", "Library/Application Support", "Library/Developer",
                    "Library/Containers", "Library/Group Containers", "Library/Logs", "Library/CloudStorage",
                    "Movies", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Applications",
                    ".cache", ".cache/huggingface", ".cache/huggingface/hub", ".codex", ".codex/sessions",
                    ".Trash", ".bun", ".npm", ".config", ".local"] {
            s.insert(h + "/" + sub)
        }
        return s
    }()

    /// 执行删除前的最后一道关：返回 nil 才允许删除。规则文件写错也绕不过这里。
    static func deletionBlock(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("//") else {
            return "路径格式不对"
        }
        if let reason = protectionReason(path) { return "代码保护：\(reason)" }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if tooBroad.contains(trimmed) || tooBroad.contains(resolved) {
            return "范围太大：不会整个删除这个目录"
        }
        guard allowedRoots.contains(where: { path.hasPrefix($0) }) else {
            return "不在允许清理的范围内（只允许家目录和 /var/folders）"
        }
        var st = stat()
        if lstat(path, &st) != 0 { return "已经不存在了" }
        return nil
    }

    /// 返回 nil 表示没有被代码保护；否则返回原因
    static func protectionReason(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for p in [path, resolved] {
            for root in oneDriveRoots where p == root || p.hasPrefix(root + "/") {
                return "在 OneDrive 里：删除会连云端一起删"
            }
            for (prefix, label) in protectedPrefixes where p == prefix || p.hasPrefix(prefix + "/") {
                return label
            }
            let parts = p.split(separator: "/")
            if parts.contains(".git") { return ".git 目录（只能用 git gc 整理）" }
            if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return "照片图库" }
        }
        return nil
    }
}
