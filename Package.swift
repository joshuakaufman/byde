// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Byde",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Byde", path: "Sources/Byde")]
)
