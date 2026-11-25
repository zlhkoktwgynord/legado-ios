// swift-tools-version:5.9
import PackageDescription

// 仅用于在 macOS / Linux 上做核心逻辑的编译校验；
// iOS App 本身用 LegadoIOS.xcodeproj 构建。
let package = Package(
    name: "LegadoCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LegadoCore", targets: ["LegadoCore"])
    ],
    targets: [
        .testTarget(
            name: "LegadoCoreTests",
            dependencies: ["LegadoCore"],
            path: "Tests/LegadoCoreTests"
        ),
        .target(
            name: "LegadoCore",
            path: ".",
            exclude: ["LegadoIOS/App", "LegadoIOS/UI", "LegadoIOS/Resources", "tools", "README.md", "Vendor/SwiftSoup/LICENSE.txt"],
            sources: ["LegadoIOS/Core", "LegadoIOS/Models", "Vendor/SwiftSoup"]
        )
    ]
)
