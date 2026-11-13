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
        .library(
            name: "SwiftTUIGalleryKit",
            targets: ["SwiftTUIGallery"]
        ),
        .executable(
            name: "SwiftGrip",
            targets: ["SwiftGripCLI"]
        ),
        .executable(
            name: "SwiftTUIGallery",
            targets: ["SwiftTUIGalleryCLI"]
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
                "SwiftGrip",
                "SwiftTUITesting"
            ],
            path: "Sources/SwiftGripCLI"
        ),
        .target(
            name: "SwiftTUIGallery",
            dependencies: [
                "SwiftTUI"
            ],
            path: "Sources/SwiftTUIGallery"
        ),
        .executableTarget(
            name: "SwiftTUIGalleryCLI",
            dependencies: [
                "SwiftTUI",
                "SwiftTUIGallery",
                "SwiftTUITesting"
            ],
            path: "Sources/SwiftTUIGalleryCLI"
        ),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: [
                "SwiftTUI",
                "SwiftTUITesting",
                "SwiftGrip",
                "SwiftTUIGallery"
            ],
            path: "Tests/SwiftTUITests"
        )
    ]
)
