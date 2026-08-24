// swift-tools-version: 6.2
// HangarVapor — Hangar in a Vapor application.
//
// Deliberately a separate package. Hangar has no framework coupling and
// should keep none; a Vapor app should not have to care that Hangar could
// also be used from Flight, a script, or a job runner. This package is the
// thin seam between the two, and nothing else depends on it.
import PackageDescription

let package = Package(
    name: "hangar-vapor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "HangarVapor", targets: ["HangarVapor"])
    ],
    dependencies: [
        // Needs 0.2.0: soft delete, pagination and CTEs all landed after
        // the 0.1.0 tag, and the generated `ColumnDefinition` shape changed
        // with them. To develop against a checkout instead:
        //   ./scripts/dev-link.sh ../hangar   (and --undo before committing)
        .package(url: "https://github.com/Swift-Flight/hangar.git", from: "0.2.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .target(
            name: "HangarVapor",
            dependencies: [
                .product(name: "Hangar", package: "hangar"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .testTarget(
            name: "HangarVaporTests",
            dependencies: [
                "HangarVapor",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ]
)
