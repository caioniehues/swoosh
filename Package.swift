// swift-tools-version: 6.0
import PackageDescription

// Swoosh — open-source macOS window snapping via two-finger trackpad gestures.
// macOS 26 only (latest-macOS-only scope, 2026-05-31). The four-layer architecture
// (SPEC §6) maps onto these targets:
//
//   SwooshCore     — Layer-4 snap math + the pure suppress/pass Recognizer (no system deps).
//                    The seam the headless replayer (DERISK §3) exercises with no hardware.
//   SwooshFixtures — the record/replay fixture format + headless replayer (DERISK §2–3).
//   SwooshKit      — Layers 1–4 runtime: EventTap, FingerCountSource, FastLocate, AX apply.
//   swooshd        — the executable daemon that wires the layers together.
let package = Package(
    name: "Swoosh",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SwooshCore", targets: ["SwooshCore"]),
        .library(name: "SwooshFixtures", targets: ["SwooshFixtures"]),
        .library(name: "SwooshKit", targets: ["SwooshKit"]),
        .library(name: "SwooshUI", targets: ["SwooshUI"]),
        .executable(name: "swooshd", targets: ["swooshd"]),
    ],
    targets: [
        .target(name: "SwooshCore"),
        .target(name: "SwooshFixtures", dependencies: ["SwooshCore"]),
        // SwooshKit / swooshd are in Swift 5 language mode: they bridge CGEventTap,
        // AXUIElement, and the private MultitouchSupport framework via @convention(c)
        // trampolines that recover `self` from a refcon and share mutable state across
        // the tap, MT-callback, and swoosh.ax threads — patterns Swift 6 strict
        // concurrency rejects. The pure, fully-tested core stays in Swift 6 mode.
        .target(name: "SwooshKit", dependencies: ["SwooshCore", "SwooshFixtures"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // SwiftUI settings + onboarding views (SPEC §8). A compiling library bound to the tested
        // settings model; the .app bundle (@main, Info.plist, LSUIElement) is an Xcode/release
        // step SwiftPM can't express, and the visual check is user-run.
        .target(name: "SwooshUI", dependencies: ["SwooshCore", "SwooshKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "swooshd", dependencies: ["SwooshKit"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwooshCoreTests", dependencies: ["SwooshCore"]),
        .testTarget(name: "SwooshFixturesTests", dependencies: ["SwooshFixtures", "SwooshCore"]),
    ]
)
