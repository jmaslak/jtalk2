// swift-tools-version:5.9
//
// This exists so editors and sourcekit-lsp understand the sources as one
// module. The shipping app is built by the Makefile, which wraps the binary in
// a .app bundle with Info.plist — `swift build` produces a bare executable.

import PackageDescription

let package = Package(
    name: "jtalk2",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "jtalk2", path: "Sources")
    ]
)
