import SwiftUI

/// 一条规则的卡片：点一下展开，看每一处的明细
struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let result: RuleResult
    @State private var expanded: Bool
    @State private var hovered = false

    init(result: RuleResult, startExpanded: Bool = false) {
        self.result = result
        _expanded = State(initialValue: startExpanded)
    }

    private var rule: Rule { result.rule }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if rule.level != .never {
                    CheckBox(state: model.state(of: result),
                             disabledReason: result.planItems.isEmpty
                                ? (result.blockReason(for: nil) ?? "这一项里没有可以删的内容")
                                : nil) {
                        model.toggle(result)
                    }
                    .padding(.leading, 18)
                    .padding(.top, 28)
                }
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    header.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Rectangle().fill(Theme.line).frame(height: 1)
                ItemList(result: result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .card(hovered: hovered)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(symbol: rule.symbol, level: rule.level)

            VStack(alignment: .leading, spacing: 7) {
                Text(rule.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let note = rule.note {
                    Text(note)
                        .font(.system(size: Theme.body))
                        .foregroundStyle(Theme.ink2)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(pathSummary)
                    .font(.system(size: Theme.mono, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                FlowLayout(spacing: 8, lineSpacing: 8) { badges }
                    .padding(.top, 3)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.bytes(result.totalSize))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(result.items.count > 1 ? "\(result.items.count) 处 · 估计" : "估计")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink3)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .padding(.top, 8)
        }
        .padding(20)
    }

    private var pathSummary: String {
        if result.items.count == 1 { return Paths.display(result.items[0].path) }
        return rule.paths.map { Paths.display(Paths.expand($0)) }.joined(separator: "　")
    }

    @ViewBuilder
    private var badges: some View {
        if let keep = result.ruleKeep {
            Pill(text: "已决定保留：\(keep.note)", symbol: "bookmark.fill", color: Theme.keep)
        } else if result.keptSize > 0 {
            Pill(text: "其中 \(Fmt.bytes(result.keptSize)) 已决定保留", symbol: "bookmark.fill", color: Theme.keep)
        }
        let (label, sym) = rule.actionLabel
        Pill(text: label, symbol: sym, color: Theme.neutral)
        if rule.regenerates == true {
            Pill(text: "删了会自动长回来", symbol: "arrow.clockwise", color: Level.safe.color)
        }
        if let days = rule.olderThanDays {
            Pill(text: days == 1 ? "只算 24 小时以前的" : "只算 \(Int(days)) 天以前的", symbol: "calendar", color: Theme.neutral)
        }
        if rule.cloneInflated == true {
            Pill(text: "数字可能虚高（APFS 克隆）", symbol: "exclamationmark.triangle", color: Theme.warn)
        }
        ForEach(rule.preconditions ?? [], id: \.self) { p in
            Pill(text: Precondition.label(p), symbol: "pause.circle", color: Theme.warn)
        }
        if rule.level != .never, let reason = result.items.compactMap(\.protection).first {
            Pill(text: "代码保护：\(reason)", symbol: "lock.fill", color: Level.never.color)
        }
        if result.unreadable > 0 {
            Pill(text: "\(result.unreadable) 处无权读取", symbol: "lock.slash", color: Theme.warn)
        }
    }
}

/// 展开后的明细列表
struct ItemList: View {
    let result: RuleResult
    @State private var showAll = false
    private let limit = 12

    var body: some View {
        let items = showAll ? result.items : Array(result.items.prefix(limit))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                ItemLine(item: item, result: result)
                    .background(idx.isMultiple(of: 2) ? Theme.well : Theme.card)
            }
            if result.items.count > limit {
                Button(showAll ? "收起" : "还有 \(result.items.count - limit) 处，全部显示") {
                    withAnimation(.snappy) { showAll.toggle() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(16)
            }
        }
    }
}

struct ItemLine: View {
    @Environment(AppModel.self) private var model
    let item: MatchedItem
    let result: RuleResult
    private var ruleKept: Bool { result.ruleKeep != nil }

    var body: some View {
        HStack(spacing: 14) {
            // 命令类规则只能整条勾选；「不能动」的不显示勾选框
            if result.rule.level != .never && !result.isCommand {
                CheckBox(state: model.selected.contains(item.path) ? .on : .off,
                         disabledReason: result.blockReason(for: item)) {
                    model.toggle(id: item.path)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(Paths.display(item.path))
                    .font(.system(size: Theme.mono, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let info = item.info {
                    Text(info)
                        .font(.system(size: Theme.small))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if result.rule.verify == "onedrive-copy" {
                    VerifyView(path: item.path)
                }
                if item.keep != nil || item.containsKept != nil || item.protection != nil {
                    HStack(spacing: 8) {
                        if let k = item.keep, !ruleKept {
                            Pill(text: "已决定保留：\(k.note)", symbol: "bookmark.fill", color: Theme.keep)
                        }
                        if let k = item.containsKept {
                            Pill(text: "里面有要保留的：\(k.note)", symbol: "bookmark", color: Theme.keep)
                        }
                        if let p = item.protection {
                            Pill(text: p, symbol: "lock.fill", color: Level.never.color)
                        }
                    }
                }
            }
            Spacer(minLength: 10)
            if let m = item.modified {
                Text(Fmt.relative(m))
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink3)
                    .help("最后修改：\(Fmt.time(m))")
            }
            Text(Fmt.bytes(item.size))
                .font(.system(size: Theme.body, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 92, alignment: .trailing)
            Button {
                Finder.reveal(item.path)
            } label: {
                Label("显示", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("在 Finder 中显示")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }
}

/// 视频工程：核对成片是否已在 OneDrive
struct VerifyView: View {
    @Environment(AppModel.self) private var model
    let path: String
    @State private var showAll = false

    var body: some View {
        if model.verifying.contains(path) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在核对：在 OneDrive 里找同样的视频，并逐字节比较…")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink2)
            }
        } else if let r = model.verifications[path] {
            VStack(alignment: .leading, spacing: 6) {
                if r.checks.isEmpty {
                    Pill(text: "里面没有 5 MB 以上的视频", symbol: "film", color: Theme.neutral)
                } else {
                    HStack(spacing: 8) {
                        if r.identical > 0 {
                            Pill(text: r.identical == r.checks.count ? "全部 \(r.identical) 个已在 OneDrive（逐字节一致）" : "\(r.identical) 个已在 OneDrive（逐字节一致）",
                                 symbol: "checkmark.circle.fill", color: Level.safe.color)
                        }
                        if r.sizeOnly > 0 {
                            Pill(text: "\(r.sizeOnly) 个大小一致，云端未下载", symbol: "icloud", color: Theme.keep)
                        }
                        if r.localOnly > 0 {
                            Pill(text: r.localOnly == r.checks.count ? "全部 \(r.localOnly) 个只在本地（\(Fmt.bytes(r.localOnlyBytes))），OneDrive 里没有" : "\(r.localOnly) 个只在本地（\(Fmt.bytes(r.localOnlyBytes))）",
                                 symbol: "exclamationmark.triangle.fill", color: Theme.warn)
                        }
                    }
                    ForEach(showAll ? r.checks : Array(r.checks.prefix(6))) { c in
                        HStack(spacing: 8) {
                            Text(label(c.status))
                                .font(.system(size: Theme.small, weight: .semibold))
                                .foregroundStyle(color(c.status))
                                .frame(width: 92, alignment: .leading)
                            Text(String(c.path.dropFirst(path.count + 1)))
                                .font(.system(size: Theme.mono, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(Fmt.bytes(c.size))
                                .font(.system(size: Theme.small))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink2)
                        }
                        .help(helpText(c.status))
                    }
                    if r.checks.count > 6 {
                        Button(showAll ? "收起" : "全部 \(r.checks.count) 个视频") { showAll.toggle() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(.top, 4)
        } else {
            Button {
                Task { await model.verify(path) }
            } label: {
                Label("核对成片", systemImage: "checkmark.seal")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("只读：看里面的视频是否已在 OneDrive。云端没下载的不会去下载。")
        }
    }

    private func label(_ s: VerifyStatus) -> String {
        switch s {
        case .identical: "✓ 已在云端"
        case .sizeOnly: "≈ 大小一致"
        case .differs: "≠ 内容不同"
        case .missing: "! 只在本地"
        }
    }
    private func color(_ s: VerifyStatus) -> Color {
        switch s {
        case .identical: Level.safe.color
        case .sizeOnly: Theme.keep
        case .differs, .missing: Theme.warn
        }
    }
    private func helpText(_ s: VerifyStatus) -> String {
        switch s {
        case .identical(let p): "OneDrive 里的同一份：\(Paths.display(p))"
        case .sizeOnly(let p): "大小一致，但云端那份没下载，没有逐字节比较：\(Paths.display(p))"
        case .differs: "OneDrive 里有同样大小的文件，但内容不同"
        case .missing: "OneDrive 里没有找到同样的视频"
        }
    }
}
