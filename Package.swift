// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SignPDF",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SignPDF", targets: ["SignPDF"])
    ],
    targets: [
        .executableTarget(
            name: "SignPDF",
            path: "Sources/SignPDF"
        ),
        .testTarget(
            name: "SignPDFTests",
            dependencies: ["SignPDF"],
            path: "Tests/SignPDFTests"
        )
    ]
)
