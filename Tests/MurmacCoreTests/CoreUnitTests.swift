import Foundation
import Testing
@testable import MurmacCore

@Suite("MurmacCore Unit Tests")
struct CoreUnitTests {
    @Test("LevelMeter stays flat on silence and responds to tone")
    func levelMeterSilenceAndTone() {
        let meter = LevelMeter()
        let silence = [Int16](repeating: 0, count: 1600)
        let silentBars = meter.push(silence)
        #expect(silentBars.count == 7)
        #expect(silentBars.allSatisfy { $0 == 0 })

        let loud = (0..<1600).map { Int16(sin(Double($0) * 0.2) * 16000.0) }
        let loudBars = meter.push(loud)
        #expect(loudBars.allSatisfy { $0 > 0.1 })
        #expect(loudBars[2] > loudBars[6])
    }

    @Test("PauseSegmenter drops short clicks and cuts on silence")
    func pauseSegmenterCutsOnSilence() {
        let seg = PauseSegmenter()
        let frame = Int64(seg.config.frameSamples)
        var pos: Int64 = 0

        for _ in 0..<2 {
            pos += frame
            #expect(seg.onFrame(probability: 0.9, frameEndSample: pos) == nil)
        }
        for _ in 0..<20 {
            pos += frame
            #expect(seg.onFrame(probability: 0.05, frameEndSample: pos) == nil)
        }
        #expect(seg.speechMs == 0)

        var emitted: [Segment] = []
        for _ in 0..<15 {
            pos += frame
            if let s = seg.onFrame(probability: 0.9, frameEndSample: pos) { emitted.append(s) }
        }
        for _ in 0..<20 {
            pos += frame
            if let s = seg.onFrame(probability: 0.05, frameEndSample: pos) { emitted.append(s) }
        }
        #expect(emitted.count == 1)
        #expect(!emitted[0].forced)
        #expect(emitted[0].speechMs >= 450)
    }

    @Test("WAV encoder/decoder round-trip")
    func wavRoundTrip() throws {
        let original: [Int16] = [0, 1000, -1000, 32767, -32768, 42, -42]
        let wav = WavCodec.encode(samples: original)
        let decoded = try WavCodec.decode(data: wav)
        #expect(decoded == original)
    }

    @Test("ContextAssembler enforces password privacy and macOS categories")
    func contextAssemblerPrivacyAndPasswords() {
        let assembler = DefaultContextAssembler()
        let passwordSnap = A11ySnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            field: FieldSnapshot(subrole: "AXSecureTextField", beforeCursor: "secret", isPassword: true)
        )
        let pwDec = assembler.decide(snapshot: passwordSnap, settings: ContextSettings())
        #expect(!pwDec.dictationAllowed)
        #expect(pwDec.skipLlm)
        #expect(pwDec.level == PrivacyLevel.none)

        let ctx = assembler.assemble(snapshot: passwordSnap, decision: pwDec, screen: .notTaken, asrLanguage: "en")
        #expect(ctx.field?.beforeCursor == nil)
        #expect(ctx.screen == nil)
        #expect(ctx.privacy?.reason == PrivacyReason.passwordField)

        let tgSnap = A11ySnapshot(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram",
            windowTitle: "Saved Messages",
            field: FieldSnapshot(role: "AXTextArea", beforeCursor: "Привет, "),
            windowBoundsInScreen: Rect(x0: 100, y0: 100, x1: 1100, y1: 900)
        )
        let tgDec = assembler.decide(snapshot: tgSnap, settings: ContextSettings(useScreen: true))
        #expect(tgDec.dictationAllowed)
        #expect(tgDec.takeScreenshot)
        let screenText = ScreenText(size: [2000, 1600], lines: [OcrLine(text: "ClickHouse", conf: 0.99, box: [10, 10, 200, 40])])
        let tgCtx = assembler.assemble(snapshot: tgSnap, decision: tgDec, screen: .text(screenText), asrLanguage: "ru")
        #expect(tgCtx.app.category == "messaging")
        #expect(tgCtx.field?.kind == "message")
        #expect(tgCtx.screen?.lines.count == 1)
    }

    @Test("SqliteStore CRUD, search, and retention pruning")
    func sqliteStoreCrudAndRetention() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let db = try SqliteStore(path: tmp.path)

        let e1 = HistoryEntry(
            sessionId: "s1", createdAtMs: 1_000, appBundleId: "ru.keepcoder.Telegram", appName: "Telegram",
            rawText: "ну привет мир", finalText: "Привет, мир.", cleaned: true, cleanupOutcome: "accept:ok",
            status: .inserted, durationMs: 2500, speechMs: 2000, asrMs: 180, llmMs: 220, ocrMs: 45,
            totalLatencyMs: 450, wordsCount: 2, fillersRemoved: 1, asrModelId: "parakeet-tdt-0.6b-v3",
            llmModelId: "murmur-cleanup-qwen3.5-2b", audioPath: "/tmp/a.wav"
        )
        let id = try db.insertHistory(e1)
        #expect(id > 0)

        let all = try db.fetchHistory()
        #expect(all.count == 1)
        #expect(all[0].finalText == "Привет, мир.")

        let hits = try db.fetchHistory(search: "мир")
        #expect(hits.count == 1)

        let pruned = try db.pruneHistory(olderThanMs: 5_000)
        #expect(pruned == ["/tmp/a.wav"])
        #expect(try db.fetchHistory().isEmpty)
    }

    @Test("SqliteStore escapes SQL LIKE wildcards (% and _)")
    func sqliteStoreEscapesLikeWildcards() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-like-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let db = try SqliteStore(path: tmp.path)

        func makeEntry(_ sid: String, _ ts: Int64, _ text: String) -> HistoryEntry {
            HistoryEntry(
                sessionId: sid, createdAtMs: ts, appBundleId: "com.apple.Notes", appName: "Notes",
                rawText: text, finalText: text, cleaned: false, cleanupOutcome: "skipped:disabled",
                status: .inserted, durationMs: 1000, speechMs: 800, asrMs: 50, llmMs: 0, ocrMs: 0,
                totalLatencyMs: 50, wordsCount: 2, fillersRemoved: 0, asrModelId: "asr", llmModelId: nil
            )
        }
        _ = try db.insertHistory(makeEntry("p1", 1_000, "hello world"))
        _ = try db.insertHistory(makeEntry("p2", 2_000, "100% done"))
        _ = try db.insertHistory(makeEntry("p3", 3_000, "snake_case"))

        let pctHits = try db.fetchHistory(search: "%")
        #expect(pctHits.count == 1)
        #expect(pctHits[0].sessionId == "p2")

        let underHits = try db.fetchHistory(search: "_")
        #expect(underHits.count == 1)
        #expect(underHits[0].sessionId == "p3")
    }

    @Test("ContextAssembler omits field.box when window bounds are unavailable")
    func contextAssemblerOmitsFieldBoxWithoutWindowBounds() {
        let assembler = DefaultContextAssembler()
        let snap = A11ySnapshot(
            bundleId: "com.apple.Notes",
            appName: "Notes",
            field: FieldSnapshot(role: "AXTextArea", boundsInScreen: Rect(x0: 50, y0: 50, x1: 400, y1: 200)),
            windowBoundsInScreen: nil
        )
        let dec = assembler.decide(snapshot: snap, settings: ContextSettings(useScreen: false))
        let ctx = assembler.assemble(snapshot: snap, decision: dec, screen: .notTaken, asrLanguage: "en")
        #expect(ctx.field?.box == nil)
    }

    @Test("CleanupBudget and WER calculator")
    func cleanupBudgetAndWer() {
        let cfg = DictationConfig()
        let plan = CleanupBudget.plan(
            transcriptChars: 120,
            prefixTokens: 1050,
            nCtx: 7168,
            speed: LlmSpeed(prefillTps: 500, decodeTps: 60),
            config: cfg
        )
        #expect(plan.fits)
        #expect(plan.maxTokens > 50)

        let overflow = CleanupBudget.plan(
            transcriptChars: 30_000,
            prefixTokens: 1050,
            nCtx: 7168,
            speed: LlmSpeed(prefillTps: 500, decodeTps: 60),
            config: cfg
        )
        #expect(!overflow.fits)
        #expect(overflow.skipReason == "too_long")

        #expect(WerCalculator.wer(reference: "Привет, мир!", hypothesis: "привет мир") == 0.0)
        #expect(WerCalculator.wer(reference: "one two three four", hypothesis: "one two five four") == 0.25)
    }

    @Test("GGUF v3 header parser reads architecture and template")
    func ggufHeaderParser() throws {
        var d = Data()
        func appendLE<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        appendLE(GgufHeader.magic)
        appendLE(UInt32(3))
        appendLE(UInt64(0))
        appendLE(UInt64(1))
        let key = "general.architecture"
        appendLE(UInt64(key.utf8.count))
        d.append(contentsOf: key.utf8)
        appendLE(UInt32(8))
        let val = "qwen3"
        appendLE(UInt64(val.utf8.count))
        d.append(contentsOf: val.utf8)

        let meta = try GgufHeader.parse(d)
        #expect(meta.complete)
        #expect(meta.version == 3)
        #expect(meta.string("general.architecture") == "qwen3")
        #expect(GgufTemplates.templateForArchitecture(meta.string("general.architecture")) == "qwen3")
    }
}
