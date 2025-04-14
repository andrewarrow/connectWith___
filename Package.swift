// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "connectWith___",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "connectWith___", targets: ["ConnectWith"])
    ],
    targets: [
        .executableTarget(
            name: "ConnectWith",
            resources: [
                .process("Resources")
            ]
        )
    ]
)