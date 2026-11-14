// swift-tools-version:5.9
// Padlet — trackpad gestures and edge controls for macOS.
// `swift build` / `swift test`; ./build.sh makes the signed .app and DMG.
import PackageDescription

let package = Package(
    name: "Padlet",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Shared updater / About / Settings shell, a git submodule (git submodule update --init).
        .package(path: "Vendor/app-shell"),
    ],
    targets: [
        .executableTarget(
            name: "Padlet",
            dependencies: [
                .product(name: "AppShellCore", package: "app-shell"),
                .product(name: "UpdaterKit", package: "app-shell"),
                .product(name: "AboutKit", package: "app-shell"),
                .product(name: "SettingsKit", package: "app-shell"),
            ],
            path: "Sources/Padlet",
            // Info.plist and the icon are copied into the .app by build.sh, not SPM.
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PadletTests",
            dependencies: ["Padlet"],
            path: "Tests/PadletTests"
        ),
    ]
)
