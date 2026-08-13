// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "usagent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "usagent",
            path: "Sources/usagent"
        ),
        .testTarget(
            name: "usagentTests",
            dependencies: ["usagent"],
            path: "Tests/usagentTests"
        )
    ]
)
