// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeepMeUp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeepMeUp",
            path: "Sources/KeepMeUp",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
