import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var disk = DiskInfo.current()
    var machineName = Host.current().localizedName ?? "这台 Mac"

    var rules: [Rule] = []
    var decisions: [Decision] = []
    var rulesDir: String = ""
    var loadError: String?

    var results: [RuleResult] = []
    var findings: [Finding] = []
    var isChecking = false
    var isScanning = false
    var progressDone = 0
    var lastFinished = ""
    var scanFinishedAt: Date?
    var scanSeconds: Double?
    /// 截图模式：每组第一张卡片默认展开
    var snapshotExpandFirst = false

    // MARK: 载入规则

    func load() {
        loadError = nil
        let fm = FileManager.default
        var candidates = [Paths.projectDir]
        if let res = Bundle.main.resourcePath { candidates.append(res) }
        guard let dir = candidates.first(where: { fm.fileExists(atPath: $0 + "/rules.json") }) else {
            loadError = "找不到 rules.json（找过：\(candidates.map(Paths.display).joined(separator: "、"))）"
            return
        }
        rulesDir = dir
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: dir + "/rules.json"))
            rules = try JSONDecoder().decode(RuleFile.self, from: data).rules
        } catch {
            loadError = "rules.json 读取失败：\(error)"
            return
        }
        let decisionURL = URL(fileURLWithPath: dir + "/decisions.json")
        if let data = try? Data(contentsOf: decisionURL) {
            do { decisions = try JSONDecoder().decode(DecisionFile.self, from: data).decisions }
            catch { loadError = "decisions.json 读取失败：\(error)" }
        } else {
            decisions = []
        }
    }

    // MARK: 扫描（只读）

    func scan() async {
        guard !isScanning else { return }
        load()
        guard loadError == nil else { return }
        isScanning = true
        progressDone = 0
        lastFinished = ""
        results = []
        disk = DiskInfo.current()
        let start = Date()
        let rules = self.rules
        let decisions = self.decisions
        findings = []
        isChecking = true
        // 体检和规则扫描同时进行
        let detectorTask = Task.detached(priority: .utility) { Detectors.runAll() }

        await withTaskGroup(of: RuleResult.self) { group in
            var next = 0
            let maxParallel = 6
            func addNext() {
                guard next < rules.count else { return }
                let rule = rules[next]
                next += 1
                group.addTask(priority: .userInitiated) {
                    Scanner.scan(rule, decisions: decisions)
                }
            }
            for _ in 0..<maxParallel { addNext() }
            for await r in group {
                results.append(r)
                progressDone += 1
                lastFinished = r.rule.name
                addNext()
            }
        }

        disk = DiskInfo.current()
        var found = await detectorTask.value
        let dbfs = results.first { $0.rule.id == "onedrive-dbfs" }?.totalSize
        let now = ScanSnapshot(date: Date(), free: disk.free, dbfs: dbfs)
        if let trend = ScanSnapshot.compare(prev: ScanSnapshot.load(), now: now) { found.append(trend) }
        if !CommandLine.arguments.contains("--snapshot") { now.save() }
        findings = found.sorted { $0.severity > $1.severity }
        isChecking = false
        scanSeconds = Date().timeIntervalSince(start)
        scanFinishedAt = Date()
        isScanning = false
    }

    // MARK: 汇总

    func results(for level: Level) -> [RuleResult] {
        results.filter { $0.rule.level == level && !$0.isEmpty }
            .sorted { $0.totalSize > $1.totalSize }
    }

    var emptyResults: [RuleResult] {
        results.filter(\.isEmpty).sorted { $0.rule.name < $1.rule.name }
    }

    func cleanable(_ level: Level) -> Int64 {
        results(for: level).reduce(0) { $0 + $1.cleanableSize }
    }

    func total(_ level: Level) -> Int64 {
        results(for: level).reduce(0) { $0 + $1.totalSize }
    }

    var unreadableCount: Int { results.reduce(0) { $0 + $1.unreadable } }

    // MARK: 核对成片（视频工程）

    var verifications: [String: VerifyReport] = [:]
    var verifying: Set<String> = []
    private var oneDriveVideoIndex: [Int64: [String]]?

    func verify(_ path: String) async {
        guard !verifying.contains(path) else { return }
        verifying.insert(path)
        let cached = oneDriveVideoIndex
        let (report, index) = await Task.detached(priority: .userInitiated) {
            let idx = cached ?? Verifier.oneDriveIndex()
            return (Verifier.verify(path, index: idx), idx)
        }.value
        oneDriveVideoIndex = index
        verifications[path] = report
        verifying.remove(path)
    }

    // MARK: 勾选

    var selected: Set<String> = []

    enum CheckState { case on, off, mixed }

    func state(of r: RuleResult) -> CheckState {
        let ids = r.planItems.map(\.id)
        let n = ids.filter(selected.contains).count
        return n == 0 ? .off : (n == ids.count ? .on : .mixed)
    }

    func toggle(_ r: RuleResult) {
        let ids = r.planItems.map(\.id)
        if state(of: r) == .on { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    func toggle(id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    var selectedPlan: [PlanItem] {
        results.flatMap(\.planItems).filter { selected.contains($0.id) }
    }

    var selectedSize: Int64 { selectedPlan.reduce(0) { $0 + $1.size } }

    // MARK: 确认与执行

    enum Stage { case confirm, running, done }
    var stage: Stage?
    var checked: [CheckedItem] = []
    var acknowledged: Set<String> = []
    var runIndex = 0
    var runCurrent = ""
    var report: RunReport?

    static let askAck = "「要核对」的项目我已经核对过，确定要删"

    /// 需要用户逐条勾选确认的话
    var requiredAcks: [String] {
        var out: [String] = []
        for c in checked {
            if case .confirm(let text) = c.check, !out.contains(text) { out.append(text) }
        }
        if checked.contains(where: { $0.item.rule.level == .ask && !$0.check.isBlocked }) {
            out.append(Self.askAck)
        }
        return out
    }

    var runnable: [CheckedItem] { checked.filter { !$0.check.isBlocked } }
    var canExecute: Bool { !runnable.isEmpty && requiredAcks.allSatisfy(acknowledged.contains) }

    func prepareConfirm() {
        // 删除顺序：直接删 → 废纸篓 → 命令
        let order: [CleanAction: Int] = [.delete: 0, .trash: 1, .command: 2, .codexTrim: 3]
        checked = selectedPlan
            .sorted { (order[$0.action] ?? 9, -$0.size) < (order[$1.action] ?? 9, -$1.size) }
            .map { CheckedItem(item: $0, check: Prechecks.check($0)) }
        acknowledged = []
        report = nil
        stage = .confirm
    }

    func recheck() {
        checked = checked.map { CheckedItem(item: $0.item, check: Prechecks.check($0.item)) }
    }

    func execute(dryRun: Bool = false) async {
        guard canExecute else { return }
        recheck()   // 确认页可能开了一会儿，执行前再查一次
        let items = checked
        stage = .running
        runIndex = 0
        let before = DiskInfo.current()
        let started = Date()
        let results = await Task.detached(priority: .userInitiated) {
            await Executor.run(items, dryRun: dryRun) { i, title in
                await MainActor.run {
                    self.runIndex = i
                    self.runCurrent = title
                }
            }
        }.value
        // APFS 释放空间有一点延迟，稍等再量
        try? await Task.sleep(for: .seconds(dryRun ? 0 : 2))
        var r = RunReport(results: results, before: before, after: DiskInfo.current(),
                          startedAt: started, dryRun: dryRun)
        r.logPath = RunLog.write(r, machine: machineName)
        report = r
        disk = r.after
        selected.subtract(results.filter { $0.outcome.isDone }.map(\.item.id))
        stage = .done
    }

    func finish() async {
        stage = nil
        checked = []
        if report?.dryRun == false { await scan() }
    }
}
