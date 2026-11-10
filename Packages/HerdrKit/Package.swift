// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrKit",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "HerdrKit", targets: ["HerdrKit"]),
        .library(name: "HerdrSSH", targets: ["HerdrSSH"]),
        .executable(name: "herdr-notify", targets: ["HerdrNotify"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
    ],
    targets: [
        .target(name: "HerdrKit", swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]),
        .target(name: "HerdrSSH", dependencies: [
            "HerdrKit",
            .product(name: "Citadel", package: "Citadel"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
        ]),
        .executableTarget(name: "HerdrNotify", dependencies: ["HerdrKit"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit"]),
    ],
    swiftLanguageModes: [.v5]
)
