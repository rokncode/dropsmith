// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools (no Xcode) ship Swift Testing but SwiftPM doesn't wire up its macro plugin
// or runtime search path, so point at them explicitly. Only when the CLT is the active toolchain
// (the Makefile sets DROPSMITH_CLT): Xcode's compiler can't load the CLT's macro plugin.
let cltDeveloper = "/Library/Developer/CommandLineTools"
let usingCLT = Context.environment["DROPSMITH_CLT"] == "1"

let package = Package(
    name: "Dropsmith",
    platforms: [.macOS(.v14)],
    dependencies: [
        // ImageIO can read WebP but not write it; libwebp is compiled from source into the app.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0"),
    ],
    targets: [
        .target(name: "ImageKit", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
        .executableTarget(name: "Dropsmith", dependencies: ["ImageKit"]),
        .testTarget(
            name: "ImageKitTests",
            dependencies: ["ImageKit"],
            swiftSettings: usingCLT ? [
                .unsafeFlags(["-plugin-path", "\(cltDeveloper)/usr/lib/swift/host/plugins/testing"]),
            ] : [],
            linkerSettings: usingCLT ? [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/Library/Developer/usr/lib",
                ]),
            ] : []
        ),
    ]
)
