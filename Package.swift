// swift-tools-version: 5.9
// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

let package = Package(
    name: "NotchPal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchPal", targets: ["NotchPal"]),
        // Loaded at runtime by /usr/bin/perl and never linked into the app. See MediaBridge.swift.
        .library(name: "NotchPalMediaBridge", type: .dynamic, targets: ["NotchPalMediaBridge"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchPal",
            path: "Sources/NotchPal"
        ),
        .target(
            name: "NotchPalMediaBridge",
            path: "Sources/NotchPalMediaBridge",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation")]
        ),
    ]
)
