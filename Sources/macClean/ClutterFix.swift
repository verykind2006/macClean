import Foundation
import AppKit
import Observation

/// 「零碎文件」卡片的一键整理：git 仓库打包（git gc）、可重新生成的目录移到废纸篓。
/// 执行前先退出 OneDrive（相当于暂停同步），做完再重新打开。
struct FixTarget: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case gitGC, trashDir }
    let kind: Kind
    /// gitGC：仓库目录；trashDir：要移走的目录
    let path: String
    /// 显示用，如 "eLiteSeries-new"、"games/node_modules"
    let label: String
    /// 松散对象数 / 目录里的文件数
    let files: Int
    var id: String { kind.rawValue + ":" + path }
}

struct FixResult: Identifiable, Sendable {
    var id: String { target.id }
    let target: FixTarget
    let outcome: Outcome
    /// 整理后的松散对象数（只对 git）
    var after: Int? = nil
}

enum ClutterFix {
    /// 允许移到废纸篓的目录名，以及证明它确实能重新生成的标记
    static let trashable: [String: String] = [
        "node_modules": "旁边有 package.json",
        ".venv": "里面有 pyvenv.cfg",
        "venv": "里面有 pyvenv.cfg",
        ".build": "旁边有 Package.swift",
        ".xcbuild": "里面有 info.plist 和 Build（xcodebuild 的 DerivedData）",
    ]
    static var projectsRoot: String { Detectors.oneDriveRoot + "/projects" }

    /// OneDrive 里唯一允许移走的东西：projects/<项目>/<可重新生成的目录>。返回 nil 才允许。
    /// 这是 Guards「OneDrive 不能删」的唯一例外，用户在 2026-11-18 决定开放，只走废纸篓、不用 rm。
    static func trashBlock(_ path: String, root projectsRoot: String = projectsRoot) -> String? {
        guard path.hasPrefix(projectsRoot + "/"), !path.contains("//"),
              !path.split(separator: "/").contains("..") else { return "不在 OneDrive 的 projects 目录里" }
        let rel = path.dropFirst(projectsRoot.count + 1).split(separator: "/")
        guard rel.count == 2 else { return "只处理项目下第一层的目录" }
        let project = projectsRoot + "/" + rel[0]
        let name = String(rel[1])
        guard trashable[name] != nil else { return "\(name) 不在可移走的名单里" }
        var st = stat()
        guard lstat(path, &st) == 0 else { return "已经不存在了" }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return "不是普通目录（可能是链接）" }
        guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path else { return "路径里有链接，不处理" }
        let fm = FileManager.default
        let marked: Bool
        switch name {
        case "node_modules": marked = fm.fileExists(atPath: project + "/package.json")
        case ".build": marked = fm.fileExists(atPath: project + "/Package.swift")
        case ".xcbuild": marked = fm.fileExists(atPath: path + "/info.plist") && fm.fileExists(atPath: path + "/Build")
        default: marked = fm.fileExists(atPath: path + "/pyvenv.cfg")
        }
        guard marked else { return "看不出能重新生成（应该\(trashable[name]!)）" }
        return nil
    }

    /// git gc 前的检查。返回 nil 才允许。
    static func gcBlock(_ repo: String, root projectsRoot: String = projectsRoot) -> String? {
        guard repo.hasPrefix(projectsRoot + "/") else { return "不在 OneDrive 的 projects 目录里" }
        let git = repo + "/.git"
        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: git, isDirectory: &isDir), isDir.boolValue else { return "没有 .git 目录" }
        guard Shell.which("git") != nil else { return "找不到 git 命令" }
        if fm.fileExists(atPath: git + "/index.lock") { return "仓库正在被别的 git 操作使用（有 index.lock）" }
        let (_, empty) = Detectors.looseObjects(git + "/objects")
        if empty > 0 { return "有 \(empty) 个空对象，仓库已损坏，要先修复" }
        if let e = fm.enumerator(atPath: git) {
            while let rel = e.nextObject() as? String {
                if Verifier.isDataless(git + "/" + rel) {
                    return "有 git 文件只在云端（已释放空间），先在 Finder 里对这个项目选「始终保留在此设备上」"
                }
            }
        }
        return nil
    }

    static func block(_ t: FixTarget, root: String = projectsRoot) -> String? {
        t.kind == .gitGC ? gcBlock(t.path, root: root) : trashBlock(t.path, root: root)
    }

    /// 在后台线程上调用
    /// root 只在自检时换成临时目录
    static func execute(_ t: FixTarget, root: String = projectsRoot) -> FixResult {
        if let why = block(t, root: root) { return FixResult(target: t, outcome: .skipped(why)) }
        switch t.kind {
        case .gitGC:
            let r = Shell.run(Shell.which("git")!, ["-C", t.path, "gc", "--quiet"])
            let (after, _) = Detectors.looseObjects(t.path + "/.git/objects")
            let tail = r.output.split(separator: "\n").suffix(3).joined(separator: "\n")
            return r.status == 0
                ? FixResult(target: t, outcome: .done(nil), after: after)
                : FixResult(target: t, outcome: .failed("git gc 退出码 \(r.status)：\(tail)"), after: after)
        case .trashDir:
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: t.path), resultingItemURL: nil)
                return FixResult(target: t, outcome: .done(nil))
            } catch {
                return FixResult(target: t, outcome: .failed(error.localizedDescription))
            }
        }
    }
}

/// 退出 / 重新打开 OneDrive（退出即停止同步）
@MainActor
enum OneDriveControl {
    static let bundleIDs = ["com.microsoft.OneDrive-mac", "com.microsoft.OneDrive"]

    static func running() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { bundleIDs.contains($0.bundleIdentifier ?? "") }
    }

    /// 返回 OneDrive 的位置（用来重新打开）；没在运行返回 nil。退不掉会抛错。
    static func quit() async throws -> URL? {
        guard let app = running() else { return nil }
        let url = app.bundleURL
        app.terminate()
        for _ in 0..<60 {
            if app.isTerminated || running() == nil { return url }
            try? await Task.sleep(for: .milliseconds(500))
        }
        throw NSError(domain: "macClean", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "OneDrive 30 秒内没有退出，已停止整理，什么都没动"])
    }

    static func relaunch(_ url: URL) async -> Bool {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)) != nil
    }
}

@MainActor
@Observable
final class ClutterFixModel {
    enum Stage { case confirm, running, done }
    var stage: Stage?
    var targets: [FixTarget] = []
    var blocks: [String: String] = [:]
    var selected: Set<String> = []
    var acknowledged = false
    var current = ""
    var index = 0
    var results: [FixResult] = []
    var freeBefore: Int64 = 0
    var freeAfter: Int64 = 0
    /// nil：OneDrive 本来就没开；true/false：是否已重新打开
    var relaunched: Bool?
    var error: String?
    var logPath: String?

    static let trashAck = "我知道这些目录会在云端和 MacBook 上一起删除，用到时要重新安装或编译"

    var chosen: [FixTarget] { targets.filter { selected.contains($0.id) && blocks[$0.id] == nil } }
    var needsAck: Bool { chosen.contains { $0.kind == .trashDir } }
    var canRun: Bool { !chosen.isEmpty && (!needsAck || acknowledged) }

    func open(_ targets: [FixTarget]) {
        self.targets = targets
        blocks = [:]
        for t in targets { if let b = ClutterFix.block(t) { blocks[t.id] = b } }
        // git 整理默认勾上；移到废纸篓的要用户自己勾
        selected = Set(targets.filter { $0.kind == .gitGC && blocks[$0.id] == nil }.map(\.id))
        acknowledged = false
        results = []
        error = nil
        relaunched = nil
        logPath = nil
        stage = .confirm
    }

    func toggle(_ t: FixTarget) {
        if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) }
    }

    func run(dryRun: Bool = false) async {
        guard canRun else { return }
        let items = chosen
        stage = .running
        index = 0
        freeBefore = DiskInfo.current().free
        let started = Date()

        var oneDriveURL: URL?
        if !dryRun {
            current = "正在退出 OneDrive（暂停同步）…"
            do { oneDriveURL = try await OneDriveControl.quit() }
            catch {
                self.error = error.localizedDescription
                stage = .done
                return
            }
        }

        var out: [FixResult] = []
        for (i, t) in items.enumerated() {
            index = i
            current = t.kind == .gitGC ? "正在整理 \(t.label) 的 git 仓库…" : "正在把 \(t.label) 移到废纸篓…"
            if dryRun {
                out.append(FixResult(target: t, outcome: .done("演练：没有真正执行"), after: t.kind == .gitGC ? 0 : nil))
                continue
            }
            out.append(await Task.detached(priority: .userInitiated) { ClutterFix.execute(t) }.value)
        }
        index = items.count
        results = out

        if let url = oneDriveURL {
            current = "正在重新打开 OneDrive…"
            relaunched = await OneDriveControl.relaunch(url)
        }
        try? await Task.sleep(for: .seconds(dryRun ? 0 : 2))
        freeAfter = DiskInfo.current().free
        if !dryRun { logPath = writeLog(started: started) }
        stage = .done
    }

    private func writeLog(started: Date) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: RunLog.dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd_HHmmss"
        let path = "\(RunLog.dir)/\(stamp.string(from: started))_整理零碎文件.log"
        var lines = ["macClean 整理 OneDrive 零碎文件 \(Fmt.time(started))",
                     "可用空间（df）：\(Fmt.bytes(freeBefore)) → \(Fmt.bytes(freeAfter))",
                     "OneDrive：" + (relaunched == nil ? "本来没在运行" : (relaunched! ? "已退出并重新打开" : "已退出，重新打开失败")),
                     ""]
        for r in results {
            let what = r.target.kind == .gitGC
                ? "git gc \(r.target.path)  松散对象 \(r.target.files) → \(r.after.map(String.init) ?? "?")"
                : "废纸篓 \(r.target.path)  \(r.target.files) 个文件"
            switch r.outcome {
            case .done: lines.append("[成功] " + what)
            case .failed(let w): lines.append("[失败] " + what + "  " + w)
            case .skipped(let w): lines.append("[跳过] " + what + "  " + w)
            }
        }
        try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
