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

    /// 文件实际所在的外接盘名；本机硬盘（或读不到，如断掉的软链接）返回 nil。
    /// statfs 会跟随路径里的软链接，所以 ~/.codex/sessions → /Volumes/fast-01/... 能认出来。
    /// 判断依据是 APFS 容器：和家目录在同一个容器（如 disk3）里的卷共用空闲空间，
    /// 都算本机（/Volumes/Recovery 就是这种）；别的容器、网络盘才算外接盘。
    static func externalVolume(_ path: String) -> String? {
        guard let (from, mount) = mountInfo(path), let local = homeContainer else { return nil }
        if container(from) == local { return nil }
        return mount == "/" ? nil : (mount as NSString).lastPathComponent
    }

    /// (设备名如 /dev/disk5s1, 挂载点如 /Volumes/fast-01)
    private static func mountInfo(_ path: String) -> (String, String)? {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return nil }
        func str<T>(_ t: T) -> String {
            withUnsafeBytes(of: t) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        return (str(st.f_mntfromname), str(st.f_mntonname))
    }

    /// /dev/disk3s5、/dev/disk3s1s1 → disk3；不是 /dev/diskN 的（网络盘等）原样返回
    private static func container(_ dev: String) -> String {
        guard dev.hasPrefix("/dev/disk") else { return dev }
        let rest = dev.dropFirst("/dev/disk".count)
        return "disk" + rest.prefix { $0.isNumber }
    }

    private static let homeContainer: String? = mountInfo(home).map { container($0.0) }

    static func matches(_ name: String, pattern: String) -> Bool {
        fnmatch(pattern, name, 0) == 0
    }
}
