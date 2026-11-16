import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                MainContent { level in
                    withAnimation(.easeInOut) { proxy.scrollTo(level, anchor: .top) }
                }
                .padding(.bottom, model.selected.isEmpty ? 0 : 110)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if !model.selectedPlan.isEmpty && !model.isScanning {
                ActionBar().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.selectedPlan.isEmpty)
        .sheet(isPresented: Binding(get: { model.stage != nil },
                                    set: { if !$0 && model.stage != .running { model.stage = nil } })) {
            RunSheet()
                .environment(model)
                .preferredColorScheme(.light)
                .interactiveDismissDisabled(model.stage == .running)
        }
    }
}

/// 页面主体（不含滚动），截图模式也直接渲染它
struct MainContent: View {
    @Environment(AppModel.self) private var model
    @State private var showEmpty = false
    var onSelectLevel: (Level) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            DiskHeader()

            if let err = model.loadError {
                Banner(symbol: "exclamationmark.octagon.fill", color: Level.never.color,
                       title: "规则没有载入", text: err)
            }

            if model.results.isEmpty && !model.isScanning {
                EmptyState()
            } else {
                if model.unreadableCount > 0 && !model.isScanning {
                    Banner(symbol: "lock.slash.fill", color: Theme.warn,
                           title: "有 \(model.unreadableCount) 处没有读取权限，统计会偏小",
                           text: "打开「系统设置 → 隐私与安全性 → 完全磁盘访问权限」，把 macClean 加进去，然后重新扫描。",
                           buttonTitle: "打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                SummaryTiles(onSelect: onSelectLevel)

                ForEach(Level.allCases, id: \.self) { level in
                    LevelSection(level: level).id(level)
                }

                if !model.emptyResults.isEmpty && !model.isScanning {
                    NotFoundSection(results: model.emptyResults, expanded: $showEmpty)
                }
            }

            Footer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 40)
        .frame(maxWidth: 1160)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }
}

// MARK: 三张汇总卡

struct SummaryTiles: View {
    @Environment(AppModel.self) private var model
    let onSelect: (Level) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Level.allCases, id: \.self) { level in
                SummaryTile(level: level,
                            size: level == .never ? model.total(level) : model.cleanable(level),
                            kept: level == .never ? 0 : model.total(level) - model.cleanable(level),
                            count: model.results(for: level).count,
                            onTap: { onSelect(level) })
            }
        }
    }
}

struct SummaryTile: View {
    let level: Level
    let size: Int64
    let kept: Int64
    let count: Int
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: level.symbol)
                        .font(.system(size: 19, weight: .semibold))
                    Text(level.title)
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("\(count) 项")
                        .font(.system(size: Theme.small, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                }
                .foregroundStyle(level.color)

                Text(Fmt.bytes(size))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)

                Text(subtitle)
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                level.color.frame(height: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .card(hovered: hovered)
            .offset(y: hovered ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
        .help("跳到「\(level.title)」")
    }

    private var subtitle: String {
        switch level {
        case .safe: kept > 0 ? "估计能清理；另有 \(Fmt.bytes(kept)) 你决定保留" : "估计能清理"
        case .ask: kept > 0 ? "待核对；另有 \(Fmt.bytes(kept)) 你决定保留" : "需要核对后再决定"
        case .never: "只是告诉你它们占了多少"
        }
    }
}

// MARK: 分组

struct LevelSection: View {
    @Environment(AppModel.self) private var model
    let level: Level

    var body: some View {
        let rows = model.results(for: level)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(level.mark) \(level.title)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(level.color)
                    Text("\(rows.count) 项 · 共 \(Fmt.bytes(model.total(level)))")
                        .font(.system(size: Theme.body, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()
                    Spacer()
                }
                Text(level.explain)
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
                    .padding(.bottom, 2)

                LazyVStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        RuleRow(result: r, startExpanded: model.snapshotExpandFirst && i == 0)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

struct NotFoundSection: View {
    let results: [RuleResult]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 18)
                    Text("这台机器上没找到的项目（\(results.count)）")
                        .font(.system(size: 19, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { r in
                        HStack(spacing: 12) {
                            Text("\(r.rule.level.mark) \(r.rule.name)")
                                .font(.system(size: Theme.body))
                                .foregroundStyle(Theme.ink)
                            Text(r.rule.paths.joined(separator: "　"))
                                .font(.system(size: Theme.mono, design: .monospaced))
                                .foregroundStyle(Theme.ink3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
        .padding(.top, 8)
    }
}

// MARK: 其他

struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.primary)
                .padding(22)
                .background(Circle().fill(Theme.primary.opacity(0.08)))
            Text("还没扫描")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("点右上角的「开始扫描」，看看空间都去哪儿了。\n扫描只统计大小，不会删除、移动任何文件。")
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            if !model.rules.isEmpty {
                Text("已载入 \(model.rules.count) 条规则、\(model.decisions.count) 条保留决定")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .card()
    }
}

struct Banner: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1.5))
    }
}

struct Footer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text")
                .foregroundStyle(Theme.ink3)
            Text("规则：\(Paths.display(model.rulesDir))/rules.json")
                .font(.system(size: Theme.small, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("显示规则文件") { Finder.reveal(model.rulesDir + "/rules.json") }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            if let at = model.scanFinishedAt, let secs = model.scanSeconds {
                Text("上次扫描 \(Fmt.time(at)) · 用时 \(Int(secs.rounded())) 秒")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.top, 10)
    }
}
