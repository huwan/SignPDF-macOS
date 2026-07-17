// swift-tools-version: 5.10

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let sparkleTestFrameworkPath = packageRoot
    + "/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"

let package = Package(
    name: "SignPDF",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SignPDF", targets: ["SignPDF"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "SignPDF",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SignPDF",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ]),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", sparkleTestFrameworkPath
                ], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "SignPDFTests",
            dependencies: ["SignPDF"],
            path: "Tests/SignPDFTests"
        )
    ]
)
