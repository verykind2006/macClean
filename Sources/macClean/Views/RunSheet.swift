import SwiftUI

/// 底部操作栏：已选多少、估计多大、删除按钮
struct ActionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = model.selectedPlan.count
        HStack(spacing: 18) {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(n) 项")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("估计 \(Fmt.bytes(model.selectedSize))，实际以 df 为准")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button("清空选择") { model.selected.removeAll() }
                .buttonStyle(LargeSecondaryButtonStyle())
            Button {
                model.prepareConfirm()
            } label: {
                Label("检查并删除…", systemImage: "trash")
            }
            .buttonStyle(DestructiveButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: 1100)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 32)
        .padding(.bottom, 18)
    }
}

/// 确认 → 执行中 → 结果，三个阶段共用一个弹窗
struct RunSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.stage {
            case .confirm: ConfirmView()
            case .running: RunningView()
            case .done: ResultView()
            case nil: EmptyView()
            }
        }
        .frame(width: 900)
        .frame(minHeight: 420, maxHeight: 820)
        .background(Theme.paper)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}

// MARK: 确认

struct ConfirmView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let runnable = model.runnable
        let blocked = model.checked.count - runnable.count
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("确认删除 \(runnable.count) 项")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                let ext = runnable.map(\.item).externalSize
                Text("估计腾出本机硬盘 \(Fmt.bytes(runnable.map(\.item).localSize))，实际以 df 前后对比为准。"
                     + (ext > 0 ? "另有 \(Fmt.bytes(ext)) 在外接盘上，删了不影响本机空间。" : "")
                     + (blocked > 0 ? "有 \(blocked) 项没通过检查，会自动跳过。" : ""))
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)

            MaybeScroll {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach([CleanAction.delete, .trash, .command, .codexTrim], id: \.self) { action in
                        let group = model.checked.filter { $0.item.action == action }
                        if !group.isEmpty { ActionGroup(action: action, items: group) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            if !model.requiredAcks.isEmpty {
                AckList()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(Theme.card)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }

            HStack(spacing: 14) {
                Button("重新检查") { model.recheck() }
                    .buttonStyle(LargeSecondaryButtonStyle())
                    .help("退出了应用或暂停了同步之后，点这里重新检查")
                Spacer()
                Button("取消") { model.stage = nil }
                    .buttonStyle(LargeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await model.execute() }
                } label: {
                    Label("删除 \(runnable.count) 项", systemImage: "trash")
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(!model.canExecute)
            }
            .padding(24)
            .background(Theme.card)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }
}

struct ActionGroup: View {
    let action: CleanAction
    let items: [CheckedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text("· \(Fmt.bytes(items.map(\.item).localSize))"
                     + (items.map(\.item).externalSize > 0 ? "（另有外接盘 \(Fmt.bytes(items.map(\.item).externalSize))）" : ""))
                    .font(.system(size: Theme.body, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .foregroundStyle(Theme.ink)
            Text(explain)
                .font(.system(size: Theme.small + 1))
                .foregroundStyle(Theme.ink2)

            VStack(spacing: 0) {
                ForEach(Array(groupByRule(items, rule: \.item.rule).enumerated()), id: \.element.id) { i, g in
                    CheckedGroupLine(rule: g.rule, items: g.items)
                        .background(i.isMultiple(of: 2) ? Theme.card : Theme.well)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private var title: String {
        switch action {
        case .delete: "直接删除"
        case .trash: "移到废纸篓"
        case .command: "运行清理命令"
        case .codexTrim: "整理数据库"
        default: ""
        }
    }
    private var symbol: String {
        switch action {
        case .delete: "xmark.bin"
        case .trash: "trash"
        case .command: "terminal"
        case .codexTrim: "cylinder.split.1x2"
        default: "questionmark"
        }
    }
    private var explain: String {
        switch action {
        case .delete: "不能恢复。只用于删了能自动重新生成的东西。"
        case .trash: "清空废纸篓之前都能找回；清空之后空间才会真正释放。"
        case .command: "由工具自己清理自己的缓存。"
        case .codexTrim: "按整个对话删除旧记录，再压缩数据库并做完整性检查。"
        default: ""
        }
    }
}

struct CheckedLine: View {
    let c: CheckedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if c.item.rule.level == .ask {
                        Pill(text: "要核对", symbol: "questionmark.circle", color: Level.ask.color)
                    }
                    Text(c.item.rule.name)
                        .font(.system(size: Theme.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(c.item.title)
                    .font(.system(size: Theme.mono, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let v = c.item.volume {
                    Pill(text: "在外接盘 \(v) 上，不占本机硬盘", symbol: "externaldrive", color: Theme.keep)
                }
                statusText
            }
            Spacer(minLength: 10)
            Text(Fmt.bytes(c.item.size))
                .font(.system(size: Theme.body, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(c.check.isBlocked ? Theme.ink3 : Theme.ink)
                .strikethrough(c.check.isBlocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var statusIcon: some View {
        switch c.check {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Level.safe.color)
        case .confirm: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warn)
        case .blocked: Image(systemName: "nosign").foregroundStyle(Level.never.color)
        }
    }

    @ViewBuilder private var statusText: some View {
        switch c.check {
        case .ok:
            Text("检查通过")
                .font(.system(size: Theme.small, weight: .medium))
                .foregroundStyle(Level.safe.color)
        case .confirm(let t):
            Text("需要你确认：\(t)")
                .font(.system(size: Theme.small, weight: .medium))
                .foregroundStyle(Theme.warn)
        case .blocked(let t):
            Text("跳过：\(t)")
                .font(.system(size: Theme.small, weight: .medium))
                .foregroundStyle(Level.never.color)
        }
    }
}

struct AckList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("执行前请逐条确认")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
            ForEach(model.requiredAcks, id: \.self) { ack in
                let on = model.acknowledged.contains(ack)
                Button {
                    if on { model.acknowledged.remove(ack) } else { model.acknowledged.insert(ack) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundStyle(on ? Theme.primary : Theme.ink3)
                        Text(ack)
                            .font(.system(size: Theme.body))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: 执行中

struct RunningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = model.checked.count
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
            Text("正在清理 \(min(model.runIndex + 1, total)) / \(total)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            ProgressView(value: Double(model.runIndex), total: Double(max(total, 1)))
                .tint(Theme.primary)
                .frame(width: 520)
            Text(model.runCurrent)
                .font(.system(size: Theme.mono, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 680)
            Text("请不要关闭窗口。")
                .font(.system(size: Theme.body))
                .foregroundStyle(Theme.ink2)
        }
        .padding(48)
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

// MARK: 结果

struct ResultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let r = model.report {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    if r.dryRun {
                        Pill(text: "演练模式：没有真正删除任何东西", symbol: "theatermasks", color: Theme.keep)
                    }
                    Text(r.dryRun ? "演练结果：如果真的执行，估计能处理" : (r.freed > 0 ? "实际释放了" : "可用空间没有明显变化"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                    if r.dryRun || r.freed > 0 {
                        Text(Fmt.bytes(r.dryRun ? r.estimated : r.freed))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(r.dryRun ? Theme.keep : Level.safe.color)
                    }
                    if !r.dryRun {
                    Text("可用空间（来自 df）：\(Fmt.bytes(r.before.free)) → \(Fmt.bytes(r.after.free))　·　估计 \(Fmt.bytes(r.estimated))")
                        .font(.system(size: Theme.body))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    }
                    HStack(spacing: 10) {
                        Pill(text: "成功 \(r.doneCount)", symbol: "checkmark.circle.fill", color: Level.safe.color)
                        if r.failedCount > 0 {
                            Pill(text: "失败 \(r.failedCount)", symbol: "xmark.octagon.fill", color: Level.never.color)
                        }
                        if r.skippedCount > 0 {
                            Pill(text: "跳过 \(r.skippedCount)", symbol: "forward.fill", color: Theme.neutral)
                        }
                    }
                    if r.trashed > 0 && !r.dryRun {
                        Banner(symbol: "trash.fill", color: Theme.warn,
                               title: "有 \(Fmt.bytes(r.trashed)) 移到了废纸篓",
                               text: "清空废纸篓之后，这部分空间才会真正释放。确认不需要了，再去清空。")
                    }
                    if r.estimatedExternal > 0 {
                        Text("另有 \(Fmt.bytes(r.estimatedExternal)) 在外接盘上\(r.dryRun ? "" : "（已处理）")，不影响本机硬盘的可用空间。"
                             + (r.dryRun ? "" : "外接盘上移到废纸篓的，在那块盘自己的废纸篓里。"))
                            .font(.system(size: Theme.small + 1))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if r.freed < r.estimated / 2 && r.trashed < r.estimated / 2 && !r.dryRun && r.estimated > 0 {
                        Text("实际释放比估计少，常见原因是 APFS 克隆：几份文件共用同一块磁盘空间，统计时被重复计算了。")
                            .font(.system(size: Theme.small + 1))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)

                MaybeScroll {
                    VStack(spacing: 0) {
                        ForEach(Array(groupByRule(r.results, rule: \.item.rule).enumerated()), id: \.element.id) { i, g in
                            ResultGroupLine(rule: g.rule, results: g.items)
                                .background(i.isMultiple(of: 2) ? Theme.card : Theme.well)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }

                HStack(spacing: 14) {
                    if let log = r.logPath {
                        Button("显示日志") { Finder.reveal(log) }
                            .buttonStyle(LargeSecondaryButtonStyle())
                    }
                    Spacer()
                    Button {
                        Task { await model.finish() }
                    } label: {
                        Label(r.dryRun ? "完成" : "完成并重新扫描", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .background(Theme.card)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }
}

struct ResultLine: View {
    let x: ExecResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch x.outcome {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Level.safe.color)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Level.never.color)
                case .skipped: Image(systemName: "forward.fill").foregroundStyle(Theme.neutral)
                }
            }
            .font(.system(size: 19, weight: .semibold))
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(x.item.title)
                    .font(.system(size: Theme.mono, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(detail)
                    .font(.system(size: Theme.small, weight: .medium))
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Text(Fmt.bytes(x.item.size))
                .font(.system(size: Theme.body, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var detail: String {
        let verb = RunLog.actionWord(x.item.action)
        switch x.outcome {
        case .done(let note): return "成功（\(verb)）" + (note.map { "：\($0)" } ?? "")
        case .failed(let why): return "失败：\(why)"
        case .skipped(let why): return "跳过：\(why)"
        }
    }
    private var detailColor: Color {
        switch x.outcome {
        case .done: Level.safe.color
        case .failed: Level.never.color
        case .skipped: Theme.neutral
        }
    }
}


// MARK: 按规则分组

struct RuleGroup<T>: Identifiable {
    var id: String { rule.id }
    let rule: Rule
    let items: [T]
}

/// 按规则分组，保持原来的先后顺序
func groupByRule<T>(_ xs: [T], rule: (T) -> Rule) -> [RuleGroup<T>] {
    var order: [String] = []
    var map: [String: (Rule, [T])] = [:]
    for x in xs {
        let r = rule(x)
        if map[r.id] == nil { order.append(r.id); map[r.id] = (r, []) }
        map[r.id]!.1.append(x)
    }
    return order.map { RuleGroup(rule: map[$0]!.0, items: map[$0]!.1) }
}

/// 把若干原因去重并计数：「Chrome 正在运行（2 项）」
func tally(_ reasons: [String]) -> [String] {
    var order: [String] = []
    var count: [String: Int] = [:]
    for r in reasons {
        if count[r] == nil { order.append(r) }
        count[r, default: 0] += 1
    }
    return order.map { count[$0]! > 1 ? "\($0)（\(count[$0]!) 项）" : $0 }
}

/// 截图模式下不用 ScrollView（ImageRenderer 画不出滚动区域里的内容）
struct MaybeScroll<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshot
    @ViewBuilder let content: Content
    var body: some View {
        if snapshot { content } else { ScrollView { content } }
    }
}

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// 确认页：一条规则一行，点开看逐项
struct CheckedGroupLine: View {
    let rule: Rule
    let items: [CheckedItem]
    @State private var expanded = false

    var body: some View {
        let ok = items.filter { !$0.check.isBlocked }
        let blocked = items.filter { $0.check.isBlocked }
        let confirms = tally(items.compactMap { if case .confirm(let t) = $0.check { t } else { nil } })
        let blockedReasons = tally(blocked.compactMap { if case .blocked(let t) = $0.check { t } else { nil } })

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if ok.isEmpty {
                        Image(systemName: "nosign").foregroundStyle(Level.never.color)
                    } else if !confirms.isEmpty || !blocked.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warn)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Level.safe.color)
                    }
                }
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        if rule.level == .ask {
                            Pill(text: "要核对", symbol: "questionmark.circle", color: Level.ask.color)
                        }
                        Text(rule.name)
                            .font(.system(size: Theme.body, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(items.count == 1 ? items[0].item.title : "\(items.count) 处")
                        .font(.system(size: Theme.mono, design: items.count == 1 ? .monospaced : .default))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !ok.isEmpty {
                        Text(blocked.isEmpty ? "检查通过" : "\(ok.count) 项检查通过")
                            .font(.system(size: Theme.small, weight: .medium))
                            .foregroundStyle(Level.safe.color)
                    }
                    ForEach(confirms, id: \.self) { t in
                        Text("需要你确认：\(t)")
                            .font(.system(size: Theme.small, weight: .medium))
                            .foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(blockedReasons, id: \.self) { t in
                        Text("跳过：\(t)")
                            .font(.system(size: Theme.small, weight: .medium))
                            .foregroundStyle(Level.never.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if items.count > 1 {
                        Button(expanded ? "收起明细" : "查看明细") {
                            withAnimation(.snappy) { expanded.toggle() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.bytes(ok.reduce(0) { $0 + $1.item.size }))
                        .font(.system(size: Theme.body, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    if let v = items.compactMap(\.item.volume).first {
                        Text("在外接盘 \(v) 上")
                            .font(.system(size: Theme.small))
                            .foregroundStyle(Theme.keep)
                    }
                    if !blocked.isEmpty {
                        Text("跳过 \(Fmt.bytes(blocked.reduce(0) { $0 + $1.item.size }))")
                            .font(.system(size: Theme.small))
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(items.prefix(50)) { c in CheckedLine(c: c).padding(.leading, 36) }
                    if items.count > 50 {
                        Text("……另外 \(items.count - 50) 项，执行后见日志")
                            .font(.system(size: Theme.small))
                            .foregroundStyle(Theme.ink2)
                            .padding(12)
                    }
                }
            }
        }
    }
}

/// 结果页：一条规则一行
struct ResultGroupLine: View {
    let rule: Rule
    let results: [ExecResult]
    @State private var expanded = false

    var body: some View {
        let done = results.filter { $0.outcome.isDone }
        let failed = results.filter { $0.outcome.isFailed }
        let skipped = results.count - done.count - failed.count
        let failReasons = tally(failed.compactMap { if case .failed(let t) = $0.outcome { t } else { nil } })
        let skipReasons = tally(results.compactMap { if case .skipped(let t) = $0.outcome { t } else { nil } })
        let notes = results.compactMap { if case .done(let n) = $0.outcome { n } else { nil } }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if !failed.isEmpty { Image(systemName: "xmark.octagon.fill").foregroundStyle(Level.never.color) }
                    else if done.isEmpty { Image(systemName: "forward.fill").foregroundStyle(Theme.neutral) }
                    else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Level.safe.color) }
                }
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.name)
                        .font(.system(size: Theme.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(results.count == 1 ? results[0].item.title : "\(results.count) 处")
                        .font(.system(size: Theme.mono, design: results.count == 1 ? .monospaced : .default))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !done.isEmpty {
                        Text("成功 \(done.count) 项（\(RunLog.actionWord(rule.action))）" + (notes.count == 1 ? "：\(notes[0])" : ""))
                            .font(.system(size: Theme.small, weight: .medium))
                            .foregroundStyle(Level.safe.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(failReasons, id: \.self) { t in
                        Text("失败：\(t)")
                            .font(.system(size: Theme.small, weight: .medium))
                            .foregroundStyle(Level.never.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if skipped > 0 {
                        ForEach(skipReasons, id: \.self) { t in
                            Text("跳过：\(t)")
                                .font(.system(size: Theme.small, weight: .medium))
                                .foregroundStyle(Theme.neutral)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if results.count > 1 {
                        Button(expanded ? "收起明细" : "查看明细") {
                            withAnimation(.snappy) { expanded.toggle() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 10)
                Text(Fmt.bytes(done.reduce(0) { $0 + $1.item.size }))
                    .font(.system(size: Theme.body, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(results.prefix(50)) { x in ResultLine(x: x).padding(.leading, 36) }
                    if results.count > 50 {
                        Text("……另外 \(results.count - 50) 项，见日志")
                            .font(.system(size: Theme.small))
                            .foregroundStyle(Theme.ink2)
                            .padding(12)
                    }
                }
            }
        }
    }
}
