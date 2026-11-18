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

        // 核对成片（只读）
        if let movies = model.results(for: .ask).first(where: { $0.rule.verify != nil }) {
            for it in movies.items.prefix(4) {
                let t = Date()
                await model.verify(it.path)
                let r = model.verifications[it.path]
                print("核对 \(Paths.display(it.path))：\(r?.checks.count ?? 0) 个视频，一致 \(r?.identical ?? 0)，仅大小 \(r?.sizeOnly ?? 0)，仅本地 \(r?.localOnly ?? 0)，用时 \(Int(Date().timeIntervalSince(t))) 秒")
            }
        }
        render(MainContent(), model: model, width: 1180, to: path)
        render(ActionBar().padding(.top, 20), model: model, width: 1180, to: base + "-bar.png")
        render(HealthSection().padding(32), model: model, width: 1180, to: base + "-health.png")
        render(HealthSection(initialOpen: model.findings.first?.id).padding(32), model: model, width: 1180, to: base + "-health-open.png")
        if let clutter = model.findings.first(where: { !$0.fixes.isEmpty }) {
            render(HealthSection(initialOpen: clutter.id).padding(32), model: model, width: 1180, to: base + "-clutter.png")
            let fx = model.fixer
            fx.open(clutter.fixes)
            fx.selected.formUnion(clutter.fixes.filter { fx.blocks[$0.id] == nil }.map(\.id))
            fx.acknowledged = true
            render(ClutterFixSheet(), model: model, width: 860, to: base + "-fix-confirm.png")
            await fx.run(dryRun: true)
            render(ClutterFixSheet(), model: model, width: 860, to: base + "-fix-result.png")
            fx.stage = nil
        }
        if let movies = model.results(for: .ask).first(where: { $0.rule.verify != nil }) {
            render(RuleRow(result: movies, startExpanded: true).padding(32), model: model, width: 1180, to: base + "-movies.png")
        }

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
            // 两台机器的目录不完全一样（MacBook 没有 ~/OneDrive），不存在的路径只验证被拒绝
            let existed = fm.fileExists(atPath: p)
            let r = Executor.execute(item(p, .delete), dryRun: false)
            let skipped: Bool = { if case .skipped = r { true } else { false } }()
            expect("拒绝 \(Paths.display(p))：\(Guards.deletionBlock(p) ?? "（没有拒绝！）")",
                   skipped && Guards.deletionBlock(p) != nil && (!existed || fm.fileExists(atPath: p)))
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

        // Codex 数据库整理：只在传入的副本上测（--codex-copy <路径>）
        if let i = CommandLine.arguments.firstIndex(of: "--codex-copy"), i + 1 < CommandLine.arguments.count {
            let copy = CommandLine.arguments[i + 1]
            let est = CodexTrim.estimate(copy, days: 7)
            print("估算：\(String(describing: est))")
            let r = CodexTrim.run(copy, days: 7)
            print("执行：\(r)")
            expect("Codex 副本整理成功且完整性通过", r.isDone)
            expect("整理后没有 7 天以前的对话", CodexTrim.estimate(copy, days: 7)?.threads == 0)
        }

        // 保留清单：存取 + 套用（用临时文件，不碰用户的清单）
        let dfile = dir + "/decisions-test.json"
        let ds = [Decision(ruleId: nil, path: "~/Movies/demo", note: "测试", date: "2026-11-16"),
                  Decision(ruleId: "bun-cache", path: nil, note: "整条", date: "2026-11-16")]
        try? DecisionStore.save(ds, to: dfile)
        let back = (try? DecisionStore.load(from: dfile)) ?? []
        expect("保留清单存取", back.count == 2 && back[0].path == "~/Movies/demo")
        expect("保留清单不存在时为空", ((try? DecisionStore.load(from: dir + "/none.json")) ?? [Decision(ruleId: "x", path: nil, note: "", date: nil)]).isEmpty)
        let demo = Paths.home + "/Movies/demo"
        let rr = RuleResult(rule: rule, items: [
            MatchedItem(path: demo, size: 5, modified: nil, unreadable: 0, keep: nil, containsKept: nil, protection: nil),
            MatchedItem(path: demo + "2", size: 7, modified: nil, unreadable: 0, keep: nil, containsKept: nil, protection: nil)],
            ruleKeep: nil)
        let applied = Scanner.apply(back, to: rr)
        expect("保留后该项不能勾选、别的项不受影响", applied.planItems.map(\.path) == [demo + "2"])

        // 零碎文件一键整理：在临时的「projects」里测，不碰 OneDrive
        let proj = dir + "/projects"
        func sh(_ c: String) { _ = Shell.zsh(c) }
        try? fm.createDirectory(atPath: proj + "/web/node_modules/pkg", withIntermediateDirectories: true)
        fm.createFile(atPath: proj + "/web/package.json", contents: Data("{}".utf8))
        fm.createFile(atPath: proj + "/web/node_modules/pkg/index.js", contents: Data("x".utf8))
        try? fm.createDirectory(atPath: proj + "/py/.venv", withIntermediateDirectories: true)       // 没有 pyvenv.cfg
        try? fm.createDirectory(atPath: proj + "/web/src", withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: proj + "/py/node_modules", withDestinationPath: proj + "/web/src")
        fm.createFile(atPath: proj + "/py/package.json", contents: Data("{}".utf8))
        expect("整理：带 package.json 的 node_modules 允许", ClutterFix.trashBlock(proj + "/web/node_modules", root: proj) == nil)
        expect("整理：没有 pyvenv.cfg 的 .venv 拒绝", ClutterFix.trashBlock(proj + "/py/.venv", root: proj) != nil)
        expect("整理：链接形式的 node_modules 拒绝", ClutterFix.trashBlock(proj + "/py/node_modules", root: proj) != nil)
        expect("整理：普通源码目录拒绝", ClutterFix.trashBlock(proj + "/web/src", root: proj) != nil)
        expect("整理：更深一层的 node_modules 拒绝", ClutterFix.trashBlock(proj + "/web/node_modules/pkg", root: proj) != nil)
        expect("整理：真实 OneDrive 里的源码目录拒绝", ClutterFix.trashBlock(ClutterFix.projectsRoot + "/macClean/Sources") != nil)
        expect("整理：项目根目录拒绝", ClutterFix.trashBlock(ClutterFix.projectsRoot + "/macClean") != nil)
        expect("整理：常规删除仍然拒绝 OneDrive 里的 node_modules",
               Guards.deletionBlock(ClutterFix.projectsRoot + "/games/node_modules") != nil)
        try? fm.createDirectory(atPath: proj + "/web/.xcbuild/Build", withIntermediateDirectories: true)
        expect("整理：没有 info.plist 的 .xcbuild 拒绝", ClutterFix.trashBlock(proj + "/web/.xcbuild", root: proj) != nil)
        fm.createFile(atPath: proj + "/web/.xcbuild/info.plist", contents: Data())
        expect("整理：xcodebuild 的 .xcbuild 允许", ClutterFix.trashBlock(proj + "/web/.xcbuild", root: proj) == nil)
        let nm = FixTarget(kind: .trashDir, path: proj + "/web/node_modules", label: "web/node_modules", files: 1)
        let tr = ClutterFix.execute(nm, root: proj)
        expect("整理：node_modules 移到废纸篓", tr.outcome.isDone && !fm.fileExists(atPath: proj + "/web/node_modules")
               && fm.fileExists(atPath: proj + "/web/package.json"))
        // git：造 30 个松散对象，gc 后应该打包
        sh("cd '\(proj)/web' && git init -q && for i in $(seq 1 30); do echo $i > f$i; done && git add . && git -c user.name=t -c user.email=t@t commit -qm t")
        let (before, _) = Detectors.looseObjects(proj + "/web/.git/objects")
        let gr = ClutterFix.execute(FixTarget(kind: .gitGC, path: proj + "/web", label: "web", files: before), root: proj)
        expect("整理：git gc 打包松散对象（\(before) → \(gr.after ?? -1)）", gr.outcome.isDone && before >= 30 && (gr.after ?? 99) == 0)
        let fsck = Shell.zsh("cd '\(proj)/web' && git fsck --no-progress && git log --oneline | wc -l | tr -d ' '")
        expect("整理：gc 后仓库完好（fsck 通过、提交还在）", fsck.status == 0 && fsck.output.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("1"))
        fm.createFile(atPath: proj + "/web/.git/index.lock", contents: nil)
        expect("整理：有 index.lock 时不 gc", ClutterFix.gcBlock(proj + "/web", root: proj) != nil)
        try? fm.removeItem(atPath: proj + "/web/.git/index.lock")
        let obj = proj + "/web/.git/objects/ab"
        try? fm.createDirectory(atPath: obj, withIntermediateDirectories: true)
        fm.createFile(atPath: obj + "/cdef0123456789012345678901234567890123", contents: Data())
        expect("整理：有空对象时不 gc", ClutterFix.gcBlock(proj + "/web", root: proj)?.contains("空对象") == true)

        // 演练不删
        fm.createFile(atPath: dir + "/e.txt", contents: Data("hi".utf8))
        let o5 = Executor.execute(item(dir + "/e.txt", .delete), dryRun: true)
        expect("演练模式不删除", o5.isDone && fm.fileExists(atPath: dir + "/e.txt"))

        try? fm.removeItem(atPath: dir)
        print(ok ? "ALL PASS" : "SOME FAILED")
        exit(ok ? 0 : 1)
    }
}
