// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "vger",
    platforms: [.macOS(.v11), .iOS(.v14)],
    products: [.library(name: "vger", targets: ["vger", "vgerSwift"])],
    dependencies: [.package(url: "https://github.com/wtholliday/MetalNanoVG", branch: "spm")],
    targets: [
        .target(name: "vger", dependencies: [], resources: [.copy("fonts")]),
        .target(name: "vgerSwift", dependencies: ["vger"]),
        .testTarget(name: "vgerTests", dependencies: ["vger", "MetalNanoVG"], resources: [.copy("images")]),
    ],
    cxxLanguageStandard: .cxx14
)
