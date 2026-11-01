// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SwiftTUI",
            targets: ["SwiftTUI"]
        ),
        .library(
            name: "SwiftTUITesting",
            targets: ["SwiftTUITesting"]
        ),
        .library(
            name: "SwiftGripKit",
            targets: ["SwiftGrip"]
        ),
        .executable(
            name: "SwiftGrip",
            targets: ["SwiftGripCLI"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"])
            ]
        ),
        .target(
            name: "SwiftTUI",
            dependencies: [],
            path: "Sources/SwiftTUI"
        ),
        .target(
            name: "SwiftTUITesting",
            dependencies: ["SwiftTUI"],
            path: "Sources/SwiftTUITesting"
        ),
        .target(
            name: "SwiftGrip",
            dependencies: [
                "SwiftTUI",
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/SwiftGrip",
            linkerSettings: [
                .linkedLibrary("sqlite3", .when(platforms: [.macOS, .linux]))
            ]
        ),
        .executableTarget(
            name: "SwiftGripCLI",
            dependencies: [
                "SwiftTUI",
                "SwiftGrip"
            ],
            path: "Sources/SwiftGripCLI"
        ),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: [
                "SwiftTUI",
                "SwiftTUITesting",
                "SwiftGrip"
            ],
            path: "Tests/SwiftTUITests"
        )
    ]
)
