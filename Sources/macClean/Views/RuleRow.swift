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
