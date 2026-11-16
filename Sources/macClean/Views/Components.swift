import SwiftUI
import AppKit

/// 白色圆角卡片
struct CardBackground: ViewModifier {
    var hovered = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovered ? Theme.cardHover : Theme.card)
                    .shadow(color: .black.opacity(hovered ? 0.08 : 0.045), radius: hovered ? 14 : 8, y: hovered ? 5 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(hovered: Bool = false) -> some View { modifier(CardBackground(hovered: hovered)) }
}

/// 带符号的小标签：颜色之外一定有文字
struct Pill: View {
    let text: String
    let symbol: String
    var color: Color = Theme.neutral

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: Theme.small, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        .fixedSize()
    }
}

/// 规则图标：分组颜色的圆角方块
struct IconTile: View {
    let symbol: String
    let level: Level
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(level.tint)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(level.color)
            )
    }
}

/// 主按钮：深墨蓝、白字、大号
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(
                Capsule().fill(configuration.isPressed ? Theme.primaryPressed : Theme.primary)
            )
            .opacity(enabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次要按钮：白底描边
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.small, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(configuration.isPressed ? Theme.well : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// 自动换行的横向排列（放标签用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

enum Finder {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// 大号勾选框（24pt）。不能勾选时显示锁，并在悬停提示里说明原因。
struct CheckBox: View {
    let state: AppModel.CheckState
    var disabledReason: String? = nil
    let action: () -> Void

    var body: some View {
        if let reason = disabledReason {
            Image(systemName: "lock.square")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Theme.ink3.opacity(0.7))
                .frame(width: 30, height: 30)
                .help(reason)
        } else {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(state == .off ? Theme.ink3 : Theme.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state == .on ? "取消勾选" : "勾选")
        }
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}

/// 危险操作按钮：深红底白字
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(Capsule().fill(Level.never.color.opacity(configuration.isPressed ? 0.85 : 1)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// 大号次要按钮（和主按钮同高）
struct LargeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(configuration.isPressed ? Theme.well : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1.5))
    }
}
