// swift-tools-version:5.9
// This file tells Swift Package Manager (SPM) how to build the MacShortcuts app.
// SPM is Apple's command-line build tool — it replaces the need to open Xcode
// for compiling the project. Run `swift build -c release` from this folder to build.
import PackageDescription

let package = Package(
    name: "MacShortcuts",
    platforms: [
        .macOS(.v13)   // Requires macOS 13 (Ventura) or later
    ],
    targets: [
        .executableTarget(
            name: "MacShortcuts",
            path: "Sources/MacShortcuts",
            // Info.plist and the icon are copied into the .app by build.sh, not SPM.
            exclude: ["Resources"],
            swiftSettings: []
        )
    ]
)
