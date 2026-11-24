# Murmac

**Private, 100% on-device dictation for macOS (Apple Silicon).**

Native Swift (SwiftUI + AppKit) port of [Murmur](https://github.com/freQuensy23-coder/murmur), keeping the same local-first pipeline, prompts, Output Guard, model catalog, and screens — adapted natively for macOS.

## How it works

1. Press **Right ⌘ + Right ⌥** anywhere to start dictating; press **Right ⌘ + Right ⌥** again to stop (press **Esc** to cancel).
2. **Speech recognition (ASR + VAD)**: runs locally via `sherpa-onnx` v2.0.1 + Silero VAD v5 (Parakeet TDT 0.6B v3, GigaAM v3, Whisper Large v3 Turbo, T-one, Qwen3-ASR).
3. **Screen context (OCR)**: optionally captures only the active window in RAM via `ScreenCaptureKit` and reads text on the Apple Neural Engine using **Apple Vision** (`VNRecognizeTextRequest`, RU + EN, 0 MB models). Screenshots and OCR text are never written to disk or sent over the network.
4. **Local LLM cleanup**: runs `llama.cpp` on **Metal GPU** via `murmur_llm` with persistent prefix KV-cache snapshots, Murmur's byte-exact `PromptRenderer`, and `OutputGuard` (R1–R7 hallucination/script/loop/distractor checks).
5. **Text insertion**: inserts into the focused text field (Wispr Flow style: transient pasteboard swap + `⌘V` + automatic clipboard restoration after 450 ms, or copies to clipboard if no field is focused). Password fields (`AXSecureTextField`) and password managers are automatically excluded.

## App Surfaces

- **Menu Bar** (`NSStatusItem`): live status icon, start/stop dictation, quick toggles for Cleanup and Screen Context.
- **Floating HUD** (`NSPanel` `.nonactivatingPanel`): compact pill with live 7-bar audio level meter & timer that never steals focus from your active editor.
- **Main Window**: **History** (Final / Original / Changes diff, audio playback, Retry, search, multi-delete), **Dashboard** (stats, 7-day chart, WPM, hardware backend status), **Models** (Speech/Cleanup hub with SHA-256 verified downloads, local GGUF import, Metal/ASR benchmarks), **Settings** (hotkey, language, prompt/preferences editor, excluded apps, privacy, permissions), and **Onboarding** (with in-app Practice).

## Build & Run from Source

Requirements: macOS 14+ (Apple Silicon `arm64`), Swift 6+, CMake 3.22+.

```bash
# 1. Build libmurmur_llm.dylib (llama.cpp + Metal) and fetch pinned sherpa-onnx v2.0.1
./native/build_native.sh all

# 2. Run all unit, golden parity (PromptRenderer + OutputGuard), Vision OCR, and native probe tests
swift test --disable-xctest

# 3. Package self-contained Murmac.app
./Scripts/bundle_app.sh release

# 4. Launch
open dist/Murmac.app
```

Grant **Microphone**, **Accessibility** (for global hotkey & pasting), and optionally **Screen Recording** (for Apple Vision window OCR) in System Settings.

## License

[Apache-2.0](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Downloadable models retain their own licenses.
