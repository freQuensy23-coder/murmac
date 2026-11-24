// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Murmac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MurmacCore", targets: ["MurmacCore"]),
        .library(name: "MurmacInfer", targets: ["MurmacInfer"]),
        .library(name: "MurmacPlatform", targets: ["MurmacPlatform"]),
        .executable(name: "Murmac", targets: ["MurmacApp"]),
    ],
    targets: [
        // C ABI headers for dlopen()-loaded native engines (allows building/testing without prebuilt dylibs)
        .target(
            name: "CMurmurLlm",
            path: "Sources/CMurmurLlm",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CSherpaOnnx",
            path: "Sources/CSherpaOnnx",
            publicHeadersPath: "include"
        ),
        // Pure domain logic, prompts, output guard, context assembler, state machine, SQLite store, catalog
        .target(
            name: "MurmacCore",
            path: "Sources/MurmacCore",
            resources: [
                .copy("Resources/prompts"),
                .copy("Resources/catalog"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Native inference engines: llama.cpp (Metal), sherpa-onnx (ASR + Silero VAD), Apple Vision (ANE OCR)
        .target(
            name: "MurmacInfer",
            dependencies: ["MurmacCore", "CMurmurLlm", "CSherpaOnnx"],
            path: "Sources/MurmacInfer"
        ),
        // macOS system integration: CGEventTap hotkeys, AXUIElement, ScreenCaptureKit, AVAudioEngine, Wispr-style paste
        .target(
            name: "MurmacPlatform",
            dependencies: ["MurmacCore"],
            path: "Sources/MurmacPlatform"
        ),
        // Native macOS SwiftUI + AppKit app (Menu Bar, non-activating HUD pill, History/Dashboard/Models/Settings/Onboarding)
        .executableTarget(
            name: "MurmacApp",
            dependencies: ["MurmacCore", "MurmacInfer", "MurmacPlatform"],
            path: "Sources/MurmacApp",
            resources: [
                .copy("Resources/fonts"),
                .copy("Resources/tokens.json"),
            ]
        ),
        // Unit & golden-corpus parity tests (byte-exact with Murmur prompts/render.py & prompts/guard.py)
        .testTarget(
            name: "MurmacCoreTests",
            dependencies: ["MurmacCore"],
            path: "Tests/MurmacCoreTests",
            resources: [
                .copy("Resources/goldens"),
            ]
        ),
        // Inference & platform integration tests (Vision OCR, dlopen probe, hotkey state machine, etc.)
        .testTarget(
            name: "MurmacInferTests",
            dependencies: ["MurmacCore", "MurmacInfer", "MurmacPlatform"],
            path: "Tests/MurmacInferTests"
        ),
    ]
)
