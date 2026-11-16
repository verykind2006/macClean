import SwiftUI

/// 顶部：磁盘总览 + 扫描按钮
struct DiskHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.disk
        let reclaim = model.results.isEmpty ? 0 : model.cleanable(.safe)

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.machineName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 10) {
                        Text("磁盘空间")
                            .font(.system(size: Theme.body))
                            .foregroundStyle(Theme.ink2)
                        Pill(text: "每一项删除都要你确认", symbol: "hand.raised", color: Theme.keep)
                    }
                }
                Spacer()
                Button {
                    Task { await model.scan() }
                } label: {
                    Label(model.isScanning ? "扫描中…" : (model.results.isEmpty ? "开始扫描" : "重新扫描"),
                          systemImage: model.isScanning ? "hourglass" : "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isScanning)
                .keyboardShortcut("r", modifiers: .command)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.bytes(d.free))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("可用")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Text("总共 \(Fmt.bytes(d.total))")
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
            }

            CapacityBar(total: d.total, used: d.used, reclaim: reclaim)

            HStack(spacing: 26) {
                Legend(color: Theme.barUsed, text: "已用 \(Fmt.bytes(d.used - reclaim))")
                if reclaim > 0 {
                    Legend(color: Theme.barReclaim, text: "其中可以删（估计）\(Fmt.bytes(reclaim))")
                }
                Legend(color: Theme.barFree, text: "可用 \(Fmt.bytes(d.free))", bordered: true)
                Spacer()
            }

            if model.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(model.progressDone), total: Double(max(model.rules.count, 1)))
                        .tint(Theme.primary)
                    Text("正在统计：已完成 \(model.progressDone) / \(model.rules.count) 项"
                         + (model.lastFinished.isEmpty ? "" : "　刚完成「\(model.lastFinished)」"))
                        .font(.system(size: Theme.small))
                        .foregroundStyle(Theme.ink2)
                        .monospacedDigit()
                }
                .transition(.opacity)
            }
        }
        .padding(28)
        .card()
        .animation(.easeInOut(duration: 0.25), value: model.isScanning)
    }
}

/// 容量条：已用 | 已用中可以删的部分 | 可用
struct CapacityBar: View {
    let total: Int64
    let used: Int64
    let reclaim: Int64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = Double(max(total, 1))
            let reclaimW = w * Double(reclaim) / t
            let usedW = w * Double(used) / t - reclaimW
            HStack(spacing: 0) {
                Rectangle().fill(Theme.barUsed).frame(width: max(usedW, 0))
                Rectangle().fill(Theme.barReclaim).frame(width: max(reclaimW, 0))
                Rectangle().fill(Theme.barFree)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .animation(.easeInOut(duration: 0.5), value: reclaim)
        }
        .frame(height: 24)
        .accessibilityLabel("已用 \(Fmt.bytes(used))，可用 \(Fmt.bytes(total - used))")
    }
}

struct Legend: View {
    let color: Color
    let text: String
    var bordered = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(bordered ? Theme.ink3.opacity(0.5) : .clear, lineWidth: 1))
            Text(text)
                .font(.system(size: Theme.small + 1))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }
}
