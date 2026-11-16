// swift-tools-version:5.10
// 编译产物不要放在这里（OneDrive）：一律用 scripts/build-app.sh，它会把 --scratch-path 指到 ~/Library/Developer/macClean-build
import PackageDescription

let package = Package(
    name: "macClean",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "macClean", path: "Sources/macClean")
    ]
)
