// swift-tools-version: 6.3.1

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-observations",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "Observations",
            targets: ["Observations"]
        )
    ],
    dependencies: [
        .package(path: "../swift-kernel"),
        .package(path: "../../swift-primitives/swift-observation-primitives"),
        .package(path: "../../swift-primitives/swift-reference-primitives"),
        .package(path: "../../swift-primitives/swift-ownership-primitives"),
        .package(path: "../../swift-primitives/swift-tagged-primitives"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
    ],
    targets: [
        .target(
            name: "Observations",
            dependencies: [
                .product(name: "Kernel Thread", package: "swift-kernel"),
                .product(name: "Observation Primitives", package: "swift-observation-primitives"),
                .product(name: "Reference Primitives", package: "swift-reference-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                "Observations Macros",
            ]
        ),
        .macro(
            name: "Observations Macros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "Observations Tests",
            dependencies: ["Observations"]
        ),
        .testTarget(
            name: "Observations Macros Tests",
            dependencies: [
                "Observations Macros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
