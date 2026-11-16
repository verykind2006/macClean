import SwiftUI
import AppKit

/// 调试用：把界面渲染成 PNG（不需要屏幕录制权限），以及删除功能的自检。
/// 都不会删除用户的任何东西：截图里的执行是「演练」，自检只动它自己建的临时文件。
@MainActor
enum Snapshot {
    static func run(model: AppModel, to path: String) async {
        let base = path.replacingOccurrences(of: ".png", with: "")
        await model.scan()
        model.snapshotExpandFirst = true

        // 勾选：可以删的前 4 条规则 + 要核对里最大的一处
        for r in model.results(for: .safe).prefix(4) { model.toggle(r) }
        if let first = model.results(for: .ask).first?.planItems.first { model.toggle(id: first.id) }

        render(MainContent(), model: model, width: 1180, to: path)
        render(ActionBar().padding(.top, 20), model: model, width: 1180, to: base + "-bar.png")
        render(HealthSection().padding(32), model: model, width: 1180, to: base + "-health.png")

        model.prepareConfirm()
        render(RunSheet(), model: model, width: 900, to: base + "-confirm.png")

        model.acknowledged = Set(model.requiredAcks)
        await model.execute(dryRun: true)
        render(RunSheet(), model: model, width: 900, to: base + "-result.png")
        exit(0)
    }

    static func render<V: View>(_ v: V, model: AppModel, width: CGFloat, to path: String) {
        let view = v
            .environment(model)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.snapshotMode, true)
            .frame(width: width)
            .background(Theme.paper)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// 自检：在 ~/Library/Caches/macClean-selftest 里建临时文件，验证删除、废纸篓和各道保护。
@MainActor
enum SelfTest {
    static func run() {
        let fm = FileManager.default
        let dir = Paths.home + "/Library/Caches/macClean-selftest"
        try? fm.removeItem(atPath: dir)
        try? fm.createDirectory(atPath: dir + "/a/b", withIntermediateDirectories: true)
        for f in ["a/b/x.txt", "c.txt", "d.txt"] { fm.createFile(atPath: "\(dir)/\(f)", contents: Data("hi".utf8)) }

        let rule = Rule(id: "selftest", name: "自检", level: .safe, category: nil, paths: [], exclude: nil,
                        action: .delete, command: nil, olderThanDays: nil, preconditions: nil, apps: nil,
                        note: nil, regenerates: nil, cloneInflated: nil)
        func item(_ p: String, _ a: CleanAction) -> CheckedItem {
            let pi = PlanItem(id: p, rule: rule, path: p, size: 1, action: a)
            return CheckedItem(item: pi, check: Prechecks.check(pi))
        }
        var ok = true
        func expect(_ name: String, _ cond: Bool) {
            print((cond ? "PASS " : "FAIL ") + name)
            if !cond { ok = false }
        }

        let o1 = Executor.execute(item(dir + "/c.txt", .delete), dryRun: false)
        expect("直接删除文件", o1.isDone && !fm.fileExists(atPath: dir + "/c.txt"))
        let o2 = Executor.execute(item(dir + "/a", .delete), dryRun: false)
        expect("直接删除目录", o2.isDone && !fm.fileExists(atPath: dir + "/a"))
        let o3 = Executor.execute(item(dir + "/d.txt", .trash), dryRun: false)
        expect("移到废纸篓", o3.isDone && !fm.fileExists(atPath: dir + "/d.txt"))
        let o4 = Executor.execute(item(dir + "/nope.txt", .delete), dryRun: false)
        expect("不存在的路径被跳过", { if case .skipped = o4 { true } else { false } }())

        let blockedPaths = [
            Paths.home + "/Library/CloudStorage/OneDrive-个人/projects/macClean/CLAUDE.md",
            Paths.home + "/OneDrive/projects/macClean/CLAUDE.md",
            Paths.home + "/.ssh",
            Paths.home + "/.claude/CLAUDE.md",
            Paths.home + "/Library/Caches",
            Paths.home + "/Library",
            Paths.home,
            Paths.home + "/Movies",
            Paths.home + "/Library/Caches/../Caches",
            "/Applications/Xcode.app",
            "/etc/hosts",
            Paths.home + "/Library/CloudStorage/OneDrive-个人/projects/kidStory/.git",
        ]
        for p in blockedPaths {
            let r = Executor.execute(item(p, .delete), dryRun: false)
            let skipped: Bool = { if case .skipped = r { true } else { false } }()
            expect("拒绝 \(Paths.display(p))：\(Guards.deletionBlock(p) ?? "（没有拒绝！）")", skipped && fm.fileExists(atPath: p))
        }
        // 命令类：用一条无害的命令验证执行和输出
        let cmdRule = Rule(id: "selftest-cmd", name: "自检命令", level: .safe, category: nil, paths: [], exclude: nil,
                           action: .command, command: "echo macClean-ok", olderThanDays: nil, preconditions: nil, apps: nil,
                           note: nil, regenerates: nil, cloneInflated: nil)
        let cmdItem = PlanItem(id: "rule:selftest-cmd", rule: cmdRule, path: nil, size: 0, action: .command)
        let oc = Executor.execute(CheckedItem(item: cmdItem, check: Prechecks.check(cmdItem)), dryRun: false)
        expect("运行命令并取得输出", { if case .done(let n) = oc { n == "macClean-ok" } else { false } }())
        let badRule = Rule(id: "selftest-bad", name: "不存在的命令", level: .safe, category: nil, paths: [], exclude: nil,
                           action: .command, command: "no-such-tool-xyz --clean", olderThanDays: nil, preconditions: nil, apps: nil,
                           note: nil, regenerates: nil, cloneInflated: nil)
        let badItem = PlanItem(id: "rule:selftest-bad", rule: badRule, path: nil, size: 0, action: .command)
        expect("找不到的命令被拦下", Prechecks.check(badItem).isBlocked)
        // 体检解析
        expect("解析 FilesToUpload", Detectors.number(after: "FilesToUpload = ", in: "a\nFilesToUpload = 103390\nb") == 103390)

        // 演练不删
        fm.createFile(atPath: dir + "/e.txt", contents: Data("hi".utf8))
        let o5 = Executor.execute(item(dir + "/e.txt", .delete), dryRun: true)
        expect("演练模式不删除", o5.isDone && fm.fileExists(atPath: dir + "/e.txt"))

        try? fm.removeItem(atPath: dir)
        print(ok ? "ALL PASS" : "SOME FAILED")
        exit(ok ? 0 : 1)
    }
}
