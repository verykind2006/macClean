// 用法：swift scripts/make-icon.swift <方形图稿.png> <输出目录>
// 按 macOS 图标网格（1024 画布、824 圆角方形、轻投影）裁形，导出 AppIcon-1024.png 与 AppIcon.icns。
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1]) else {
    print("用法：swift make-icon.swift <方形图稿.png> <输出目录>"); exit(1)
}
let outDir = args[2]
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(size) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    // 投影
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 图稿裁进圆角方形
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    art.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // 细内描边，深色背景上更清楚
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = 2 * s
    path.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

png(render(1024), outDir + "/AppIcon-1024.png")

let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    png(render(base), "\(iconset)/icon_\(base)x\(base).png")
    png(render(base * 2), "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", outDir + "/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print(p.terminationStatus == 0 ? "✅ \(outDir)/AppIcon.icns" : "iconutil 失败")
