// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TwinFiles",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TwinFiles", targets: ["TwinFiles"])],
    targets: [
        .executableTarget(name: "TwinFiles"),
        .testTarget(name: "TwinFilesTests", dependencies: ["TwinFiles"])
    ]
)
