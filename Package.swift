// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pdf-visual-diff-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFVisualDiff", targets: ["PDFVisualDiff"])
    ],
    targets: [
        .target(name: "PDFVisualDiff"),
        .testTarget(
            name: "PDFVisualDiffTests",
            dependencies: ["PDFVisualDiff"]
        )
    ]
)
