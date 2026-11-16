import Foundation
import Darwin

enum Paths {
    static let home = NSHomeDirectory()
    /// /var/folders/xx/yyyy/T
    static let tmpDir: String = {
        var s = NSTemporaryDirectory()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }()
    /// /var/folders/xx/yyyy（下面有 C、T、X 等）
    static let darwinUserDir = (tmpDir as NSString).deletingLastPathComponent


    /// 展开 ~、$TMPDIR、$DARWIN_USER_DIR
    static func expand(_ pattern: String) -> String {
        var s = pattern
            .replacingOccurrences(of: "$DARWIN_USER_DIR", with: darwinUserDir)
            .replacingOccurrences(of: "$TMPDIR", with: tmpDir)
        if s == "~" { s = home }
        else if s.hasPrefix("~/") { s = home + s.dropFirst(1) }
        return s
    }

    /// 显示用：把家目录换成 ~
    static func display(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// 用系统 glob 展开（支持 * ? [] 和 {a,b}）
    static func glob(_ pattern: String) -> [String] {
        let magic = CharacterSet(charactersIn: "*?[{")
        if pattern.rangeOfCharacter(from: magic) == nil {
            var st = stat()
            return lstat(pattern, &st) == 0 ? [pattern] : []
        }
        var gt = glob_t()
        defer { globfree(&gt) }
        guard Darwin.glob(pattern, GLOB_BRACE | GLOB_TILDE, nil, &gt) == 0 else { return [] }
        var out: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let p = gt.gl_pathv[i] { out.append(String(cString: p)) }
        }
        return out
    }

    static func matches(_ name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
