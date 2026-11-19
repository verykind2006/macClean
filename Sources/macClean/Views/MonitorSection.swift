import SwiftUI
import AppKit

/// 此刻状态：CPU / GPU / 内存 / 磁盘读写 四张卡片，点一张在下面展开「哪些进程在占用」
struct MonitorSection: View {
    @Environment(AppModel.self) private var model
    @State private var open: Metric?

    init(initialOpen: Metric? = nil) {
        _open = State(initialValue: initialOpen)
    }

    var body: some View {
        let mon = model.monitor
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("此刻状态")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(mon.ready ? "每 2 秒刷新 · 点卡片看是哪些进程在占用" : "正在读取…")
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label("打开活动监视器", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("要结束某个进程，请在「活动监视器」里操作；macClean 只看不动")
            }

            HStack(spacing: 14) {
                ForEach(Metric.allCases) { m in
                    MetricTile(metric: m, selected: open == m) {
                        withAnimation(.snappy(duration: 0.25)) { open = open == m ? nil : m }
                    }
                }
            }

            if let m = open {
                ProcessCard(metric: m) {
                    withAnimation(.snappy(duration: 0.25)) { open = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: 状态等级（颜色之外一定有文字）

struct LoadLevel {
    let text: String
    let severity: Severity

    static func percent(_ v: Double) -> LoadLevel {
        v >= 85 ? LoadLevel(text: "很忙", severity: .bad)
            : v >= 50 ? LoadLevel(text: "偏忙", severity: .warn)
            : LoadLevel(text: "正常", severity: .ok)
    }
    static func pressure(_ p: Int) -> LoadLevel {
        p >= 4 ? LoadLevel(text: "危险", severity: .bad)
            : p >= 2 ? LoadLevel(text: "紧张", severity: .warn)
            : LoadLevel(text: "正常", severity: .ok)
    }
    static func io(_ bytesPerSec: Double) -> LoadLevel {
        let mb = bytesPerSec / 1_048_576
        return mb >= 300 ? LoadLevel(text: "很忙", severity: .warn)
            : mb >= 20 ? LoadLevel(text: "在读写", severity: .info)
            : LoadLevel(text: "平静", severity: .ok)
    }
}

extension Metric {
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "内存"
        case .io: "磁盘读写"
        }
    }
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.down.right"
        case .memory: "memorychip"
        case .io: "arrow.up.arrow.down.circle"
        }
    }
}

struct LoadBadge: View {
    let level: LoadLevel
    var body: some View {
        Text(level.text)
            .font(.system(size: Theme.small, weight: .semibold))
            .foregroundStyle(level.severity.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(level.severity.tint))
            .overlay(Capsule().strokeBorder(level.severity.color.opacity(0.35), lineWidth: 1))
            .fixedSize()
    }
}

// MARK: 小卡片

struct MetricTile: View {
    @Environment(AppModel.self) private var model
    let metric: Metric
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        let mon = model.monitor
        let s = mon.latest
        let level = self.level(s)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(level.severity.tint)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: metric.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(level.severity.color)
                        )
                    Text(metric.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 4)
                    if mon.ready { LoadBadge(level: level) }
                }

                bigNumber(s)
                    .frame(height: 44, alignment: .bottomLeading)

                Text(mon.ready ? subline(s) : "正在读取…")
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(alignment: .bottom, spacing: 6) {
                    Sparkline(values: mon.history[metric] ?? [],
                              maxValue: metric == .io ? nil : 100,
                              color: level.severity == .ok ? Theme.primary : level.severity.color)
                        .frame(height: 34)
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
                    .strokeBorder(selected ? Theme.primary : Theme.line, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
        .help(selected ? "收起" : "看哪些进程占用\(metric.title)最多")
    }

    private func level(_ s: MonitorSample) -> LoadLevel {
        switch metric {
        case .cpu: .percent(s.cpu)
        case .gpu: .percent(s.gpu)
        case .memory: .pressure(s.pressure)
        case .io: .io(s.readRate + s.writeRate)
        }
    }

    @ViewBuilder
    private func bigNumber(_ s: MonitorSample) -> some View {
        let big = Font.system(size: 34, weight: .bold, design: .rounded)
        let unit = Font.system(size: 18, weight: .semibold)
        switch metric {
        case .cpu, .gpu:
            let v = metric == .cpu ? s.cpu : s.gpu
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metric == .gpu && !s.gpuAvailable ? "—" : Fmt.int(v)).font(big)
                Text("%").font(unit).foregroundStyle(Theme.ink2)
            }
            .monospacedDigit().foregroundStyle(Theme.ink)
        case .memory:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.bytes(s.memUsed)).font(big)
                Text("/ \(Fmt.bytes(s.memTotal))").font(unit).foregroundStyle(Theme.ink2)
            }
            .monospacedDigit().foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.7)
        case .io:
            VStack(alignment: .leading, spacing: 0) {
                Text("读 \(Fmt.rate(s.readRate))")
                Text("写 \(Fmt.rate(s.writeRate))")
            }
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .monospacedDigit().foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func subline(_ s: MonitorSample) -> String {
        let busiest = model.monitor.top(metric, 1).first
        switch metric {
        case .cpu:
            return busiest.map { "最忙：\(ProcName.of($0)) \(Fmt.int($0.cpu))%" } ?? "\(s.cores) 核"
        case .gpu:
            if !s.gpuAvailable { return "读不到 GPU 数据" }
            return busiest.map { "最忙：\(ProcName.of($0)) \(Fmt.int($0.gpu))%" } ?? "没有程序在用 GPU"
        case .memory:
            return s.swapUsed > 0 ? "交换文件 \(Fmt.bytes(s.swapUsed))" : "没有用到交换文件"
        case .io:
            return busiest.map { "最忙：\(ProcName.of($0)) \(Fmt.rate($0.ioRate))" } ?? "最近 2 秒几乎没有读写"
        }
    }
}

/// 最近 2 分钟的曲线（只是走势，具体数字看卡片上的大字）
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = 100
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let n = SystemMonitor.historyLength
            let top = max(maxValue ?? (values.max() ?? 1), 1)
            let step = geo.size.width / CGFloat(max(n - 1, 1))
            let x0 = geo.size.width - CGFloat(max(values.count - 1, 0)) * step
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: x0 + CGFloat(i) * step,
                        y: geo.size.height - CGFloat(min(v, top) / top) * (geo.size.height - 2) - 1)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.well)
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.14))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityHidden(true)
    }
}

// MARK: 进程明细

struct ProcessCard: View {
    @Environment(AppModel.self) private var model
    let metric: Metric
    let onClose: () -> Void

    var body: some View {
        let mon = model.monitor
        let rows = mon.top(metric, 12)
        let maxV = rows.first?.value(metric) ?? 1

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(metric == .memory || metric == .io ? "占用\(metric.title)最多的进程" : "占用 \(metric.title) 最多的进程")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("收起", action: onClose).buttonStyle(SecondaryButtonStyle())
            }
            Text(note(mon.latest))
                .font(.system(size: Theme.small))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty {
                Text(mon.ready ? "最近 2 秒没有进程在占用\(metric.title)。" : "正在读取…")
                    .font(.system(size: Theme.body))
                    .foregroundStyle(Theme.ink2)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in
                        ProcessRow(p: p, metric: metric, fraction: p.value(metric) / max(maxV, 1e-9))
                        if i < rows.count - 1 { Divider().overlay(Theme.line) }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func note(_ s: MonitorSample) -> String {
        switch metric {
        case .cpu: "按 CPU 排序。100% 表示占满一个核心，这台 Mac 有 \(s.cores) 个核心，所以单个进程可能超过 100%。"
        case .gpu: "按最近 2 秒占用 GPU 的时间排序。WindowServer 是负责画屏幕的系统进程，它占一些是正常的。"
        case .memory: "按内存占用排序，口径和「活动监视器」的「内存」一列相同。内存压力「正常」时，占得多不一定是问题。"
        case .io: "按最近 2 秒的磁盘读写速度排序。"
            + (s.ioUnreadable > 0 ? "系统进程（\(s.ioUnreadable) 个）的读写需要管理员权限才能看到，没有列出。" : "")
        }
    }
}

struct ProcessRow: View {
    let p: ProcStat
    let metric: Metric
    let fraction: Double

    var body: some View {
        HStack(spacing: 14) {
            ProcIcon(pid: p.pid)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProcName.of(p))
                    .font(.system(size: Theme.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondary)
                    .font(.system(size: Theme.small))
                    .foregroundStyle(Theme.ink3)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: 300, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    Capsule().fill(Theme.primary.opacity(0.75))
                        .frame(width: max(geo.size.width * min(fraction, 1), 4))
                }
            }
            .frame(height: 12)

            Text(primary)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(width: metric == .io ? 300 : 150, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 9)
    }

    private var primary: String {
        switch metric {
        case .cpu: "\(Fmt.int(p.cpu))%"
        case .gpu: "\(Fmt.int(p.gpu))%"
        case .memory: Fmt.bytes(p.memory)
        case .io: "读 \(Fmt.rate(p.readRate))  写 \(Fmt.rate(p.writeRate))"
        }
    }

    /// 第二行：进程号 + 另外两项
    private var secondary: String {
        var parts = ["进程号 \(p.pid)"]
        if metric != .cpu { parts.append("CPU \(Fmt.int(p.cpu))%") }
        if metric != .memory { parts.append("内存 \(Fmt.bytes(p.memory))") }
        if metric == .memory && p.gpu >= 1 { parts.append("GPU \(Fmt.int(p.gpu))%") }
        return parts.joined(separator: " · ")
    }
}

/// 进程名：有界面的 App 用它的显示名
enum ProcName {
    static func of(_ p: ProcStat) -> String {
        NSRunningApplication(processIdentifier: p.pid)?.localizedName ?? p.name
    }
}

struct ProcIcon: View {
    let pid: Int32
    var body: some View {
        if let icon = IconCache.icon(pid) {
            Image(decorative: icon, scale: 2).resizable().frame(width: 30, height: 30)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.well)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "gearshape").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink3))
        }
    }
}

/// App 图标先画成 60×60 的位图再缓存：每 2 秒刷新时不用反复取图标；
/// 直接用 NSImage 的话，截图模式（ImageRenderer）会把整张图画成灰蒙蒙的
@MainActor
enum IconCache {
    private static var cache: [Int32: CGImage?] = [:]

    static func icon(_ pid: Int32) -> CGImage? {
        if let hit = cache[pid] { return hit }
        var out: CGImage?
        if let app = NSRunningApplication(processIdentifier: pid), let img = app.icon {
            let px = 60
            if let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                out = ctx.makeImage()
            }
        }
        if cache.count > 500 { cache.removeAll() }
        cache[pid] = out
        return out
    }
}
