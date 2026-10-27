// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudyManagerFC",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StudyManagerFC", targets: ["StudyManagerFC"])
    ],
    targets: [
        .executableTarget(
            name: "StudyManagerFC",
            path: "Sources/StudyManagerFC",
            resources: [.copy("Resources")]
        )
    ]
)
