// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HookhausKit",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .visionOS(.v1)],
    products: [
        .library(name: "HookhausKit", targets: ["HookhausKit"]),
    ],
    targets: [
        .target(
            name: "HookhausKit",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]
        ),
        .testTarget(name: "HookhausKitTests", dependencies: ["HookhausKit"]),
    ]
)
