import SwiftUI
import AppKit

/// 体检：一排小卡片（角标 + 关键数字），点一块在下面展开详情
struct HealthSection: View {
    @Environment(AppModel.self) private var model
    @State private var openID: String?

    init(initialOpen: String? = nil) {
        _openID = State(initialValue: initialOpen)
    }

    private let columns = [GridItem(.adaptive(minimum: 196, maximum: 400), spacing: 12)]

    var body: some View {
        let problems = model.findings.filter { $0.severity >= .warn }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("体检")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if model.isChecking {
                    ProgressView().controlSize(.small)
                    Text("正在检查 OneDrive 和项目目录…")
                        .font(.system(size: Theme.body))
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text(problems == 0 ? "一切正常" : "有 \(problems) 处需要你留意，点卡片看详情")
                        .font(.system(size: Theme.body, weight: .medium))
                        .foregroundStyle(problems == 0 ? Level.safe.color : Theme.ink2)
                }
                Spacer()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.findings) { f in
                    HealthTile(f: f, selected: openID == f.id) {
                        withAnimation(.snappy(duration: 0.25)) { openID = openID == f.id ? nil : f.id }
                    }
                }
            }

            if let id = openID, let f = model.findings.first(where: { $0.id == id }) {
                FindingCard(f: f) {
                    withAnimation(.snappy(duration: 0.25)) { openID = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .bad: Level.never.color
        case .warn: Theme.warn
        case .info: Theme.keep
        case .ok: Level.safe.color
        }
    }
    var tint: Color {
        switch self {
        case .bad: Level.never.tint
        case .warn: Level.ask.tint
        case .info: Color(hex: 0xE4ECF5)
        case .ok: Level.safe.tint
        }
    }
}

/// 小卡片：图标、标题、关键数字、右上角状态角标
struct HealthTile: View {
    let f: Finding
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(f.severity.tint)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: f.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(f.severity.color)
                        )
                    Spacer()
                    SeverityBadge(s: f.severity)
                }
                Text(f.short.isEmpty ? f.title : f.short)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(f.headline)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(f.severity >= .warn ? f.severity.color : Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Image(systemName: selected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovered || selected ? Theme.cardHover : Theme.card)
                    .shadow(color: .black.opacity(hovered ? 0.08 : 0.04), radius: hovered ? 10 : 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? f.severity.color : (f.severity >= .warn ? f.severity.color.opacity(0.4) : Theme.line),
                                  lineWidth: selected ? 2.5 : 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
        .help(selected ? "收起详情" : "\(f.title)：点击查看详情")
    }
}

struct SeverityBadge: View {
    let s: Severity
    var body: some View {
        switch s {
        case .ok: Pill(text: "正常", symbol: "checkmark.circle.fill", color: Level.safe.color)
        case .info: Pill(text: "参考", symbol: "info.circle.fill", color: Theme.keep)
        case .warn: Pill(text: "注意", symbol: "exclamationmark.triangle.fill", color: Theme.warn)
        case .bad: Pill(text: "严重", symbol: "exclamationmark.octagon.fill", color: Level.never.color)
        }
    }
}

struct FindingCard: View {
    let f: Finding
    var onClose: (() -> Void)? = nil
    @State private var copied = false

    private var color: Color { f.severity.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SeverityBadge(s: f.severity)
                Text(f.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let p = f.revealPath {
                    Button { Finder.reveal(p) } label: { Label("显示", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("在 Finder 中显示")
                }
                if let onClose {
                    Button(action: onClose) { Label("收起", systemImage: "chevron.up") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            Text(f.summary)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !f.details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(f.details, id: \.self) { d in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(Theme.ink3)
                            Text(d)
                                .font(.system(size: Theme.body))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.well))
            }

            if !f.advice.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("建议")
                        .font(.system(size: Theme.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    ForEach(Array(f.advice.enumerated()), id: \.offset) { i, a in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.system(size: Theme.body, weight: .semibold))
                                .foregroundStyle(Theme.ink2)
                            Text(a)
                                .font(.system(size: Theme.body))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let cmd = f.copyCommand {
                HStack(spacing: 12) {
                    Text(cmd)
                        .font(.system(size: Theme.mono, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制命令", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.well))
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(color)
                .frame(width: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
