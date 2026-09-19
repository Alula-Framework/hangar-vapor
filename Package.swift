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
        // 0.6.0 or later. The floor moves with what this package is tested
        // against rather than with what it happens to compile against: it said
        // 0.3.0 while hangar shipped 0.5.0, 0.5.1 and 0.6.0, and no run here
        // ever saw any of them — CI last fired on 2026-08-31, the day 0.4.0
        // was tagged.
        // To develop against a checkout instead:
        //   ./scripts/dev-link.sh ../hangar   (and --undo before committing)
        .package(url: "https://github.com/Flight-Framework/hangar.git", from: "0.8.0"),
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
