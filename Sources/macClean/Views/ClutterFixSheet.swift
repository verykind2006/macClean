import SwiftUI

/// 「零碎文件」一键整理：确认 → 执行中 → 结果
struct ClutterFixSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fx = model.fixer
        Group {
            switch fx.stage {
            case .confirm: FixConfirmView()
            case .running: FixRunningView()
            case .done: FixResultView()
            case nil: EmptyView()
            }
        }
        .frame(width: 860)
        .frame(minHeight: 400, maxHeight: 820)
        .background(Theme.paper)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: Theme.body))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SheetFooter<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 14) { content }
            .padding(24)
            .background(Theme.card)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: 确认

struct FixConfirmView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fx = model.fixer
        let gc = fx.targets.filter { $0.kind == .gitGC }
        let trash = fx.targets.filter { $0.kind == .trashDir }
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "一键整理零碎文件",
                        subtitle: "开始后 App 会先退出 OneDrive（相当于暂停同步），逐项处理，做完再自动重新打开 OneDrive。勾选你要处理的项目。")

            MaybeScroll {
                VStack(alignment: .leading, spacing: 22) {
                    if !gc.isEmpty {
                        FixGroup(title: "git 仓库打包（git gc）", symbol: "shippingbox",
                                 explain: "把成千上万个松散对象打成几个包文件。不删除任何提交，git 自己的整理方式。",
                                 targets: gc)
                    }
                    if !trash.isEmpty {
                        FixGroup(title: "依赖 / 编译目录移到废纸篓", symbol: "trash",
                                 explain: "⚠ 这些目录在 OneDrive 里：移走后云端和 MacBook 上的也会一起删除。它们都能重新生成，用到时重新 npm install / uv sync / swift build / xcodebuild。清空废纸篓前都能恢复。",
                                 targets: trash)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            if fx.needsAck {
                Button { fx.acknowledged.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: fx.acknowledged ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(fx.acknowledged ? Theme.primary : Theme.ink3)
                        Text(ClutterFixModel.trashAck)
                            .font(.system(size: Theme.body, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(Theme.card)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }

            SheetFooter {
                Spacer()
                Button("取消") { fx.stage = nil }
                    .buttonStyle(LargeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await fx.run() }
                } label: {
                    Label("开始整理 \(fx.chosen.count) 项", systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!fx.canRun)
            }
        }
    }
}

private struct FixGroup: View {
    @Environment(AppModel.self) private var model
    let title: String
    let symbol: String
    let explain: String
    let targets: [FixTarget]

    var body: some View {
        let fx = model.fixer
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(explain)
                .font(.system(size: Theme.small + 1))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { i, t in
                    let block = fx.blocks[t.id]
                    HStack(alignment: .top, spacing: 12) {
                        CheckBox(state: fx.selected.contains(t.id) ? .on : .off, disabledReason: block) { fx.toggle(t) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(t.label)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(t.kind == .gitGC ? "松散对象 \(Fmt.count(t.files)) 个" : "\(Fmt.count(t.files)) 个文件")
                                    .font(.system(size: Theme.body, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink2)
                            }
                            if let block {
                                Label("不能处理：\(block)", systemImage: "lock")
                                    .font(.system(size: Theme.small))
                                    .foregroundStyle(Level.never.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(i.isMultiple(of: 2) ? Theme.card : Theme.well)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}

// MARK: 执行中

struct FixRunningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fx = model.fixer
        let total = max(fx.chosen.count, 1)
        VStack(spacing: 22) {
            Spacer()
            ProgressView(value: Double(min(fx.index, total)), total: Double(total))
                .progressViewStyle(.linear)
                .frame(width: 520)
            Text("第 \(min(fx.index + 1, total)) / \(total) 项")
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(fx.current)
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink2)
            Text("git 打包大仓库可能要一两分钟，请不要关掉 App")
                .font(.system(size: Theme.body))
                .foregroundStyle(Theme.ink2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

// MARK: 结果

struct FixResultView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let fx = model.fixer
        let done = fx.results.filter { $0.outcome.isDone }.count
        let problems = fx.results.count - done
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: fx.error != nil ? "没有开始整理" : (problems == 0 ? "整理完成" : "整理完成，有 \(problems) 项没成功"),
                subtitle: fx.error ?? "可用空间（df）：\(Fmt.bytes(fx.freeBefore)) → \(Fmt.bytes(fx.freeAfter))。"
                    + "移到废纸篓的要清空废纸篓后才真正释放空间。")

            MaybeScroll {
                VStack(alignment: .leading, spacing: 12) {
                    if let r = fx.relaunched {
                        Label(r ? "OneDrive 已重新打开，会把这些变化同步到云端" : "OneDrive 没能自动重新打开，请手动打开它",
                              systemImage: r ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: Theme.body, weight: .semibold))
                            .foregroundStyle(r ? Level.safe.color : Theme.warn)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(fx.results.enumerated()), id: \.element.id) { i, r in
                            FixResultLine(r: r)
                                .background(i.isMultiple(of: 2) ? Theme.card : Theme.well)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    if let p = fx.logPath {
                        Text("记录已写入 \(Paths.display(p))")
                            .font(.system(size: Theme.small))
                            .foregroundStyle(Theme.ink2)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            SheetFooter {
                Spacer()
                Button {
                    fx.stage = nil
                    Task { await model.refreshClutter() }
                } label: { Label("完成，重新体检", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct FixResultLine: View {
    let r: FixResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch r.outcome {
                case .done: Label("成功", systemImage: "checkmark.circle.fill").foregroundStyle(Level.safe.color)
                case .failed: Label("失败", systemImage: "xmark.octagon.fill").foregroundStyle(Level.never.color)
                case .skipped: Label("跳过", systemImage: "minus.circle.fill").foregroundStyle(Theme.warn)
                }
            }
            .font(.system(size: Theme.body, weight: .semibold))
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.target.label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: Theme.body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var detail: String {
        let base = r.target.kind == .gitGC
            ? "松散对象 \(Fmt.count(r.target.files)) → \(r.after.map(Fmt.count) ?? "?") 个"
            : "\(Fmt.count(r.target.files)) 个文件已移到废纸篓"
        switch r.outcome {
        case .done(let n): return n.map { base + "（\($0)）" } ?? base
        case .failed(let w), .skipped(let w): return w
        }
    }
}
