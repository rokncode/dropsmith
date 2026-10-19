// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools (no Xcode) ship Swift Testing but SwiftPM doesn't wire up its macro plugin
// or runtime search path, so point at them explicitly. Harmless when Xcode is installed.
let cltDeveloper = "/Library/Developer/CommandLineTools"

let package = Package(
    name: "DesktopEdit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ImageKit"),
        .executableTarget(name: "DesktopEdit", dependencies: ["ImageKit"]),
        .testTarget(
            name: "ImageKitTests",
            dependencies: ["ImageKit"],
            swiftSettings: [
                .unsafeFlags(["-plugin-path", "\(cltDeveloper)/usr/lib/swift/host/plugins/testing"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloper)/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
