// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TankarrReaderCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "TankarrReaderCore", targets: ["TankarrReaderCore"])],
    targets: [
        .target(name: "TankarrReaderCore"),
        .testTarget(name: "TankarrReaderCoreTests", dependencies: ["TankarrReaderCore"])
    ]
)
