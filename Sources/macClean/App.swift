import SwiftUI
import AppKit

@main
struct MacCleanApp: App {
    @State private var model = AppModel()

    init() {
        // 不管系统是深色还是浅色，这个 App 一律用浅色
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup("macClean") {
            ContentView()
                .environment(model)
                .preferredColorScheme(.light)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .frame(minWidth: 920, minHeight: 660)
                .onAppear {
                    model.load()
                    if !CommandLine.arguments.contains("--selftest") { model.monitor.start() }
                    // 调试用：open macClean.app --args --autoscan
                    if CommandLine.arguments.contains("--autoscan") { Task { await model.scan() } }
                    // 调试用：open macClean.app --args --snapshot /path/out.png  扫描后把页面渲染成 PNG 并退出
                    if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
                    if let i = CommandLine.arguments.firstIndex(of: "--snapshot-monitor"), i + 1 < CommandLine.arguments.count {
                        let out = CommandLine.arguments[i + 1]
                        Task { await Snapshot.runMonitor(model: model, to: out) }
                    }
                    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                        let out = CommandLine.arguments[i + 1]
                        Task { await Snapshot.run(model: model, to: out) }
                    }
                }
        }
        .defaultSize(width: 1180, height: 900)
        .windowStyle(.hiddenTitleBar)
    }
}
