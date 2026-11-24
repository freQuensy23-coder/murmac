import Foundation
import Testing
@testable import MurmacCore
@testable import MurmacPlatform

@Suite("Hotkey & Orchestrator Integration Tests")
struct PlatformAndOrchestratorTests {
    @Test("Right Command + Right Option toggles recording without firing on left modifiers")
    func rightCmdOptionToggle() {
        var det = HotkeyDetector(config: HotkeyConfig(mode: .toggle, useRightCommandOption: true))

        // Left Command + Left Option must NOT trigger
        let leftBoth = HotkeyDetector.leftCommandMask | HotkeyDetector.leftOptionMask
        #expect(det.handleFlagsChanged(rawFlags: leftBoth) == .none)

        // Right Command alone -> none
        #expect(det.handleFlagsChanged(rawFlags: HotkeyDetector.rightCommandMask) == .none)

        // Right Command + Right Option -> toggle!
        let rightBoth = HotkeyDetector.rightCommandMask | HotkeyDetector.rightOptionMask
        #expect(det.handleFlagsChanged(rawFlags: rightBoth) == .toggle)

        // Holding both still -> none (latched until release)
        #expect(det.handleFlagsChanged(rawFlags: rightBoth) == .none)

        // Release -> none
        #expect(det.handleFlagsChanged(rawFlags: 0) == .none)

        // Press again -> toggle (stop)
        #expect(det.handleFlagsChanged(rawFlags: rightBoth) == .toggle)
    }

    @Test("Hold mode emits holdStart and holdStop; Escape cancels while recording")
    func holdModeAndEscape() {
        var det = HotkeyDetector(config: HotkeyConfig(mode: .hold, useRightCommandOption: true))
        let rightBoth = HotkeyDetector.rightCommandMask | HotkeyDetector.rightOptionMask
        #expect(det.handleFlagsChanged(rawFlags: rightBoth) == .holdStart)
        #expect(det.handleFlagsChanged(rawFlags: HotkeyDetector.rightCommandMask) == .holdStop)
        #expect(det.handleKeyDown(keyCode: 53, flags: 0, isRecording: true) == .cancel)
        #expect(det.handleKeyDown(keyCode: 53, flags: 0, isRecording: false) == .none)
    }

    @Test("Custom key hotkey ignores OS autorepeat events")
    func customHotkeyIgnoresAutorepeat() {
        let optMask: UInt64 = 1 << 19
        var det = HotkeyDetector(config: HotkeyConfig(
            mode: .toggle,
            useRightCommandOption: false,
            customKeyCode: 49,
            customModifierMask: optMask
        ))
        #expect(det.handleKeyDown(keyCode: 49, flags: optMask, isRecording: false, isAutorepeat: false) == .toggle)
        #expect(det.handleKeyDown(keyCode: 49, flags: optMask, isRecording: true, isAutorepeat: true) == .none)
    }

    @Test("DictationOrchestrator cancels slow LLM on timeout and falls back to raw transcript")
    func orchestratorCancelsSlowLlmOnTimeout() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-timeout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try SqliteStore(path: tmpDir.appendingPathComponent("test.sqlite").path)
        let settingsStore = SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
        settingsStore.save(AppSettings(
            language: .en,
            selectedAsrModelId: "parakeet-tdt-0.6b-v3",
            selectedLlmModelId: "murmur-cleanup-qwen3.5-2b",
            cleanupEnabled: true,
            useScreenContext: false,
            restoreClipboard: true,
            keepAudioHistory: false,
            historyRetentionDays: 30
        ))

        let fakeAsr = FakeAsrEngine(transcript: "raw fallback transcript")
        let slowLlm = HangingLlmEngine()
        let fakeEngines = FakeEngines(asr: fakeAsr, llm: slowLlm, ocr: FakeOcrEngine(lines: []))
        let fakeInserter = FakeTextInserter()
        let orch = DictationOrchestrator(
            engines: fakeEngines,
            audioCapture: FakeAudioCapture(),
            targetReader: FakeTargetReader(snapshot: A11ySnapshot(
                bundleId: "com.apple.Notes",
                appName: "Notes",
                field: FieldSnapshot(role: "AXTextArea", isEditable: true)
            )),
            inserter: fakeInserter,
            audioStore: MacAudioStore(rootURL: tmpDir.appendingPathComponent("audio")),
            permissions: FakePermissions(snapshot: PermissionSnapshot(microphone: true, accessibility: true, screenRecording: false)),
            feedback: FakeFeedback(),
            resolver: FakeModelResolver(),
            settingsStore: settingsStore,
            db: db,
            clock: FakeClock(),
            config: DictationConfig(llmBaseMs: 80, llmHardCapMs: 120, doubleTapGuardMs: 0, insertedDismissMs: 5000),
            observer: .init(onPhase: { _ in }, onLevels: { _ in }, onHistoryUpdated: {})
        )

        let t0 = Date()
        await orch.toggle(mode: .hotkey)
        await orch.toggle(mode: .hotkey)
        let elapsed = Date().timeIntervalSince(t0)

        #expect(elapsed < 1.5)
        #expect(slowLlm.cancelCount >= 1)
        #expect(fakeInserter.lastInsertedText == "raw fallback transcript")
        let history = try db.fetchHistory()
        #expect(history.count == 1)
        #expect(history[0].cleaned == false)
        #expect(history[0].cleanupOutcome == "skipped:timeout")
    }

    @Test("DictationOrchestrator discards transcript and deletes audio if focus switches to 1Password")
    func orchestratorDiscardsAndDeletesAudioOnMidDictationPasswordSwitch() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-priv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try SqliteStore(path: tmpDir.appendingPathComponent("test.sqlite").path)
        let settingsStore = SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
        settingsStore.save(AppSettings(
            language: .en,
            selectedAsrModelId: "parakeet-tdt-0.6b-v3",
            selectedLlmModelId: nil,
            cleanupEnabled: false,
            useScreenContext: false,
            restoreClipboard: true,
            keepAudioHistory: true,
            historyRetentionDays: 30
        ))

        let audioDir = tmpDir.appendingPathComponent("audio")
        let target = SequenceTargetReader(snapshots: [
            A11ySnapshot(bundleId: "com.apple.Notes", appName: "Notes", field: FieldSnapshot(role: "AXTextArea", isEditable: true)),
            A11ySnapshot(bundleId: "com.1password.1password", appName: "1Password", field: FieldSnapshot(role: "AXTextField", isEditable: true)),
        ])
        let fakeInserter = FakeTextInserter()
        let orch = DictationOrchestrator(
            engines: FakeEngines(asr: FakeAsrEngine(transcript: "my secret password"), llm: FakeLlmEngine(output: ""), ocr: FakeOcrEngine(lines: [])),
            audioCapture: FakeAudioCapture(),
            targetReader: target,
            inserter: fakeInserter,
            audioStore: MacAudioStore(rootURL: audioDir),
            permissions: FakePermissions(snapshot: PermissionSnapshot(microphone: true, accessibility: true, screenRecording: false)),
            feedback: FakeFeedback(),
            resolver: FakeModelResolver(),
            settingsStore: settingsStore,
            db: db,
            clock: FakeClock(),
            config: DictationConfig(doubleTapGuardMs: 0, insertedDismissMs: 5000),
            observer: .init(onPhase: { _ in }, onLevels: { _ in }, onHistoryUpdated: {})
        )

        await orch.toggle(mode: .hotkey)
        await orch.toggle(mode: .hotkey)

        #expect(fakeInserter.lastInsertedText == nil)
        #expect(try db.fetchHistory().isEmpty)
        let remainingAudio = (try? FileManager.default.contentsOfDirectory(atPath: audioDir.path)) ?? []
        #expect(remainingAudio.isEmpty)
    }

    @Test("DictationOrchestrator runs full ASR + OCR + PromptRenderer + LLM + Guard + Paste pipeline")
    func orchestratorEndToEndPipeline() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-orch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try SqliteStore(path: tmpDir.appendingPathComponent("test.sqlite").path)
        let settingsStore = SettingsStore(fileURL: tmpDir.appendingPathComponent("settings.json"))
        settingsStore.save(AppSettings(
            language: .auto,
            selectedAsrModelId: "parakeet-tdt-0.6b-v3",
            selectedLlmModelId: "murmur-cleanup-qwen3.5-2b",
            cleanupEnabled: true,
            useScreenContext: true,
            restoreClipboard: true,
            keepAudioHistory: true,
            historyRetentionDays: 30
        ))

        let fakeAsr = FakeAsrEngine(transcript: "ну привет передай тимуру что кликхаус готов")
        let fakeLlm = FakeLlmEngine(output: "Привет, передай Тимуру, что ClickHouse готов.")
        let fakeOcr = FakeOcrEngine(lines: [OcrLine(text: "ClickHouse cluster", conf: 0.98, box: [20, 40, 300, 80])])
        let fakeEngines = FakeEngines(asr: fakeAsr, llm: fakeLlm, ocr: fakeOcr)
        let fakeCapture = FakeAudioCapture()
        let fakeTarget = FakeTargetReader(snapshot: A11ySnapshot(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram",
            windowTitle: "Team Chat",
            field: FieldSnapshot(role: "AXTextArea", isEditable: true),
            windowBoundsInScreen: Rect(x0: 0, y0: 0, x1: 1200, y1: 800)
        ))
        let fakeInserter = FakeTextInserter()
        let fakePerms = FakePermissions(snapshot: PermissionSnapshot(microphone: true, accessibility: true, screenRecording: true))
        let fakeAudioStore = MacAudioStore(rootURL: tmpDir.appendingPathComponent("audio"))
        let fakeFeedback = FakeFeedback()
        let fakeResolver = FakeModelResolver()
        let fakeClock = FakeClock()

        let box = ResultBox()
        let orch = DictationOrchestrator(
            engines: fakeEngines,
            audioCapture: fakeCapture,
            targetReader: fakeTarget,
            inserter: fakeInserter,
            audioStore: fakeAudioStore,
            permissions: fakePerms,
            feedback: fakeFeedback,
            resolver: fakeResolver,
            settingsStore: settingsStore,
            db: db,
            clock: fakeClock,
            config: DictationConfig(screenshotDelayMs: 10, contextWaitMs: 500, doubleTapGuardMs: 0, insertedDismissMs: 5000),
            observer: .init(
                onPhase: { box.appendPhase($0) },
                onLevels: { _ in },
                onHistoryUpdated: { box.markHistory() }
            )
        )

        await orch.toggle(mode: .hotkey)
        try await Task.sleep(nanoseconds: 50_000_000) // Allow delayed OCR to run
        await orch.toggle(mode: .hotkey)

        #expect(fakeInserter.lastInsertedText == "Привет, передай Тимуру, что ClickHouse готов.")
        #expect(fakeInserter.lastRestoreClipboard == true)
        #expect(fakeLlm.lastSuffix?.contains("ClickHouse cluster") == true)

        let history = try db.fetchHistory()
        #expect(history.count == 1)
        #expect(history[0].cleaned == true)
        #expect(history[0].status == .inserted)
        #expect(history[0].finalText == "Привет, передай Тимуру, что ClickHouse готов.")
        #expect(history[0].fillersRemoved >= 1)
        #expect(history[0].audioPath != nil)
    }
}

// MARK: - Deterministic Fakes

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    var phases: [DictationPhase] = []
    var historyUpdated = false
    func appendPhase(_ p: DictationPhase) { lock.lock(); phases.append(p); lock.unlock() }
    func markHistory() { lock.lock(); historyUpdated = true; lock.unlock() }
}

private final class FakeClock: MurmurClock, @unchecked Sendable {
    func nowMs() -> Int64 { 1_700_000_000_000 }
    func monotonicMs() -> Int64 { 10_000 }
}

private final class FakeAsrSession: AsrSession, @unchecked Sendable {
    let text: String
    init(text: String) { self.text = text }
    func feed(_ chunk: PcmChunk) async {}
    func finish() async throws -> Transcript { Transcript(text: text, speechMs: 1500, decodeMs: 90, language: "ru") }
    func cancel() async {}
}

private final class FakeAsrEngine: AsrEngine, @unchecked Sendable {
    let transcript: String
    init(transcript: String) { self.transcript = transcript }
    func probe() async -> EngineProbe { EngineProbe(availableUnits: [.cpu], runtimes: [RuntimeKeys.sherpaOfflineTransducer]) }
    func load(asr: LoadSpec, vad: LoadSpec?) async throws -> LoadInfo { LoadInfo(unit: .cpu, loadMs: 10, deviceName: "FakeCPU") }
    func startSession(options: AsrSessionOptions) async throws -> AsrSession { FakeAsrSession(text: transcript) }
    func unload() async {}
}

private final class FakeLlmEngine: LlmEngine, @unchecked Sendable {
    let output: String
    private let lock = NSLock()
    private var _lastSuffix: String?
    var lastSuffix: String? { lock.lock(); defer { lock.unlock() }; return _lastSuffix }

    init(output: String) { self.output = output }
    func probe() async -> EngineProbe { EngineProbe(availableUnits: [.gpu, .cpu], runtimes: [RuntimeKeys.llamaGguf]) }
    func load(spec: LoadSpec) async throws -> LoadInfo { LoadInfo(unit: .gpu, loadMs: 20, deviceName: "MTL0") }
    func setPrefix(_ spec: PrefixSpec) async throws -> PrefixInfo { PrefixInfo(tokens: 480, prefillMs: 12, restoredFromDisk: true, bytes: 1024) }
    func generate(request: LlmRequest, onPiece: (@Sendable (String) -> Void)?) async throws -> LlmGenerationResult {
        lock.withLock { _lastSuffix = request.suffix }
        return LlmGenerationResult(
            text: output,
            stats: LlmStats(promptTokens: 80, generatedTokens: 16, restoreMs: 2, prefillMs: 15, ttftMs: 20, decodeMs: 80, totalMs: 100, truncated: false)
        )
    }
    func bench(nPrompt: Int, nGen: Int, reps: Int) async throws -> SyntheticBench { SyntheticBench(prefillTps: 600, decodeTps: 80, prefillMs: 10, decodeMs: 20) }
    func cancel() {}
    func unload() async {}
}

private final class FakeOcrEngine: ScreenOcrEngine, @unchecked Sendable {
    let lines: [OcrLine]
    init(lines: [OcrLine]) { self.lines = lines }
    func recognize(image: ScreenImageData) async throws -> ScreenText { ScreenText(size: [image.width, image.height], lines: lines) }
}

private final class FakeEngines: Engines, @unchecked Sendable {
    let asr: AsrEngine
    let llm: LlmEngine
    let ocr: ScreenOcrEngine
    init(asr: AsrEngine, llm: LlmEngine, ocr: ScreenOcrEngine) { self.asr = asr; self.llm = llm; self.ocr = ocr }
    func scheduleIdleUnload(afterMs: Int64) {}
    func holdActive() {}
    func unloadAll() async {}
}

private final class FakeCaptureHandle: CaptureHandlePort, @unchecked Sendable {
    let chunks: AsyncStream<PcmChunk>
    private let cont: AsyncStream<PcmChunk>.Continuation
    init() {
        var c: AsyncStream<PcmChunk>.Continuation!
        chunks = AsyncStream { c = $0 }
        cont = c
        cont.yield(PcmChunk(samples: [Int16](repeating: 100, count: 1600), startSample: 0))
    }
    func currentLevels() -> [Float] { [0.2, 0.4, 0.6, 0.4, 0.5, 0.3, 0.2] }
    func stop() async -> (durationMs: Int64, samples: [Int16]) {
        cont.finish()
        return (1500, [Int16](repeating: 100, count: 1600))
    }
    func cancel() { cont.finish() }
}

private final class FakeAudioCapture: AudioCapturePort, @unchecked Sendable {
    func start(onLevels: @escaping @Sendable ([Float]) -> Void) async throws -> CaptureHandlePort { FakeCaptureHandle() }
}

private final class FakeTargetReader: TargetReaderPort, @unchecked Sendable {
    let snap: A11ySnapshot
    init(snapshot: A11ySnapshot) { self.snap = snapshot }
    func snapshot() async -> A11ySnapshot? { snap }
    func screenshot(target: A11ySnapshot) async throws -> ScreenImageData { ScreenImageData(width: 1200, height: 800) }
}

private final class SequenceTargetReader: TargetReaderPort, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [A11ySnapshot]
    private var index = 0
    init(snapshots: [A11ySnapshot]) { self.snapshots = snapshots }
    func snapshot() async -> A11ySnapshot? {
        lock.withLock {
            guard !snapshots.isEmpty else { return nil }
            let s = snapshots[min(index, snapshots.count - 1)]
            index += 1
            return s
        }
    }
    func screenshot(target: A11ySnapshot) async throws -> ScreenImageData { ScreenImageData(width: 1200, height: 800) }
}

private final class HangingLlmEngine: LlmEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelCount = 0
    var cancelCount: Int { lock.withLock { _cancelCount } }

    func probe() async -> EngineProbe { EngineProbe(availableUnits: [.gpu], runtimes: [RuntimeKeys.llamaGguf]) }
    func load(spec: LoadSpec) async throws -> LoadInfo { LoadInfo(unit: .gpu, loadMs: 5, deviceName: "MTL0") }
    func setPrefix(_ spec: PrefixSpec) async throws -> PrefixInfo { PrefixInfo(tokens: 100, prefillMs: 5, restoredFromDisk: true, bytes: 128) }
    func generate(request: LlmRequest, onPiece: (@Sendable (String) -> Void)?) async throws -> LlmGenerationResult {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return LlmGenerationResult(
            text: "too late",
            stats: LlmStats(promptTokens: 10, generatedTokens: 2, restoreMs: 0, prefillMs: 1, ttftMs: 1, decodeMs: 1, totalMs: 2, truncated: false)
        )
    }
    func bench(nPrompt: Int, nGen: Int, reps: Int) async throws -> SyntheticBench { SyntheticBench(prefillTps: 1, decodeTps: 1, prefillMs: 1, decodeMs: 1) }
    func cancel() { lock.withLock { _cancelCount += 1 } }
    func unload() async {}
}

private final class FakeTextInserter: TextInserterPort, @unchecked Sendable {
    private let lock = NSLock()
    private var _text: String?
    private var _restore: Bool?
    var lastInsertedText: String? { lock.lock(); defer { lock.unlock() }; return _text }
    var lastRestoreClipboard: Bool? { lock.lock(); defer { lock.unlock() }; return _restore }
    func insert(text: String, target: A11ySnapshot?, restoreClipboard: Bool) async -> InsertOutcome {
        lock.withLock { _text = text; _restore = restoreClipboard }
        return .inserted(.paste)
    }
    func copyToClipboard(_ text: String) {
        lock.lock(); _text = text; lock.unlock()
    }
}

private final class FakePermissions: PermissionMonitorPort, @unchecked Sendable {
    let snap: PermissionSnapshot
    init(snapshot: PermissionSnapshot) { self.snap = snapshot }
    func check() -> PermissionSnapshot { snap }
    func requestMicrophone() async -> Bool { snap.microphone }
    func requestAccessibilityPrompt() {}
    func requestScreenRecordingPrompt() {}
    func openSystemSettings(_ pane: PermissionPane) {}
}

private final class FakeFeedback: FeedbackPort, @unchecked Sendable {
    func playStart() {}
    func playStop() {}
    func playDone() {}
    func playError() {}
}

private final class FakeModelResolver: ModelResolverPort, @unchecked Sendable {
    func resolve(settings: AppSettings) throws -> ResolvedModels {
        ResolvedModels(
            asr: LoadSpec(artifactId: "parakeet", kind: .asr, runtime: RuntimeKeys.sherpaOfflineTransducer, unit: .cpu, dir: "/tmp", layout: [:]),
            asrModelId: "parakeet-tdt-0.6b-v3",
            asrTraits: AsrTraits(),
            vad: nil,
            llm: ResolvedLlm(
                spec: LoadSpec(artifactId: "cleanup", kind: .llm, runtime: RuntimeKeys.llamaGguf, unit: .gpu, dir: "/tmp", layout: [:]),
                fallbackSpec: nil,
                modelId: "murmur-cleanup-qwen3.5-2b",
                template: "qwen3.5",
                profileName: "finetuned.v1",
                nCtx: 6144,
                prefixTokens: 480,
                modelSha256: "abc",
                speed: LlmSpeed(prefillTps: 600, decodeTps: 80)
            ),
            llmUnavailableReason: nil
        )
    }
}
