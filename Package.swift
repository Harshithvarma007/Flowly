// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Flowly",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1")],
    targets: [.executableTarget(name: "Flowly", dependencies: [.product(name: "WhisperKit", package: "WhisperKit")], path: "Sources/Flowly")]
)
