import SwiftUI
import AppKit

/// 体检结果：有问题的展开显示，正常的收成一行
struct HealthSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let problems = model.findings.filter { $0.severity != .ok }
        let fine = model.findings.filter { $0.severity == .ok }
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
                    Text(problems.isEmpty ? "一切正常" : "有 \(problems.count) 处需要你留意")
                        .font(.system(size: Theme.body, weight: .medium))
                        .foregroundStyle(problems.isEmpty ? Level.safe.color : Theme.ink2)
                }
                Spacer()
            }
            ForEach(problems) { FindingCard(f: $0) }
            if !fine.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(fine) { f in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            SeverityBadge(s: .ok)
                            Text(f.title)
                                .font(.system(size: Theme.body, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(f.summary)
                                .font(.system(size: Theme.body))
                                .foregroundStyle(Theme.ink2)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}

struct SeverityBadge: View {
    let s: Severity
    var body: some View {
        switch s {
        case .ok: Pill(text: "正常", symbol: "checkmark.circle.fill", color: Level.safe.color)
        case .warn: Pill(text: "注意", symbol: "exclamationmark.triangle.fill", color: Theme.warn)
        case .bad: Pill(text: "严重", symbol: "exclamationmark.octagon.fill", color: Level.never.color)
        }
    }
}

struct FindingCard: View {
    let f: Finding
    @State private var copied = false

    private var color: Color { f.severity == .bad ? Level.never.color : Theme.warn }

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
