import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MurmacCore
@testable import MurmacInfer

@Suite("MurmacInfer Native & Vision Tests")
struct InferTests {
    @Test("Apple Vision OCR reads Russian and English text from rendered image")
    func visionOcrReadsBilingualText() async throws {
        let width = 800
        let height = 200
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        ("Привет ClickHouse Murmac" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let cgImg = try #require(rep.cgImage)
        let ocr = VisionOcrEngine()
        let result = try await ocr.recognize(image: ScreenImageData(width: width, height: height, cgImageBox: { cgImg }))

        #expect(result.size == [width, height])
        let joined = result.lines.map(\.text).joined(separator: " ")
        #expect(joined.localizedCaseInsensitiveContains("ClickHouse"), "Vision OCR output: \(joined)")
        #expect(joined.contains("Привет"), "Vision OCR output: \(joined)")
        for line in result.lines {
            #expect(line.box.count == 4)
            #expect(line.box[0] < line.box[2])
            #expect(line.box[1] < line.box[3])
        }
    }

    @Test("LlamaLlmEngine probes Metal GPU when native libs are present")
    func llamaEngineProbe() async {
        let engine = LlamaLlmEngine()
        let probe = await engine.probe()
        if NativeLibraryLocator.locate(filename: "libmurmur_llm.dylib") != nil {
            #expect(probe.runtimes.contains(RuntimeKeys.llamaGguf))
            #expect(probe.availableUnits.contains(.cpu))
            #expect(probe.facts["native.build"]?.contains("llama.cpp") == true)
        } else {
            #expect(probe.facts["native"] == "missing")
        }
    }

    @Test("SherpaAsrEngine probes v2.0.1 and all supported runtimes when native libs are present")
    func sherpaEngineProbe() async {
        let engine = SherpaAsrEngine()
        let probe = await engine.probe()
        if NativeLibraryLocator.locate(filename: "libsherpa-onnx-c-api.dylib") != nil {
            #expect(probe.facts["sherpa.version"] == "2.0.1")
            #expect(probe.runtimes.contains(RuntimeKeys.sherpaOfflineTransducer))
            #expect(probe.runtimes.contains(RuntimeKeys.ortSileroVadV5))
            #expect(probe.availableUnits.contains(.cpu))
        } else {
            #expect(probe.facts["native"] == "missing")
        }
    }

    @Test("Live end-to-end pipeline with real downloaded Parakeet + Silero VAD + Apple Vision + Metal Qwen3.5")
    func liveEndToEndRealModels() async throws {
        guard ProcessInfo.processInfo.environment["MURMAC_LIVE_E2E"] == "1" else {
            return
        }
        let catalog = try CatalogLoader.loadBundled()
        let storage = ModelStorage()
        let downloader = ModelDownloader(storage: storage)

        let vadModel = try #require(catalog.models.first { $0.id == "silero-vad-v5" })
        let asrModel = try #require(catalog.models.first { $0.id == "parakeet-tdt-0.6b-v3" })
        let llmModel = try #require(catalog.models.first { $0.id == "murmur-cleanup-qwen3.5-0.8b" })

        let vadArt = try #require(vadModel.preferredArtifact)
        let asrArt = try #require(asrModel.preferredArtifact)
        let llmArt = try #require(llmModel.preferredArtifact)

        // 1. Real downloads with SHA-256 verification (reuses if already installed)
        for art in [vadArt, asrArt, llmArt] {
            if !storage.isInstalled(art) {
                print("[LIVE_E2E] Downloading \(art.id)...")
                _ = try await downloader.download(artifact: art) { _ in }
            }
            #expect(storage.isInstalled(art))
        }

        // 2. Synthesize real Russian speech WAV (16 kHz mono 16-bit PCM) via macOS `say` + `afconvert`
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let aiffURL = tmpDir.appendingPathComponent("speech.aiff")
        let wavURL = tmpDir.appendingPathComponent("speech.wav")

        func runTool(_ path: String, _ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0, "\(path) exited with \(p.terminationStatus)")
        }

        try runTool("/usr/bin/say", ["-v", "Milena", "-r", "160", "-o", aiffURL.path, "ну короче, передай Тимуру, что клик хаус уже готов"])
        try runTool("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiffURL.path, wavURL.path])

        let wavData = try Data(contentsOf: wavURL)
        let samples = try WavCodec.decode(data: wavData)
        #expect(samples.count > 16_000, "Expected >1s of speech PCM, got \(samples.count) samples")

        // 3. Real SherpaAsrEngine (Parakeet TDT 0.6B v3 + Silero VAD v5)
        let asrEngine = SherpaAsrEngine()
        let asrSpec = storage.loadSpec(for: asrModel, artifact: asrArt, unit: .cpu, threads: 4)
        let vadSpec = storage.loadSpec(for: vadModel, artifact: vadArt, unit: .cpu, threads: 1)
        let asrLoad = try await asrEngine.load(asr: asrSpec, vad: vadSpec)
        print("[LIVE_E2E] ASR loaded in \(asrLoad.loadMs) ms")

        let session = try await asrEngine.startSession(options: AsrSessionOptions(language: nil))
        let chunkSize = 1600
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            await session.feed(PcmChunk(samples: Array(samples[offset..<end]), startSample: Int64(offset)))
            offset = end
        }
        let transcript = try await session.finish()
        print("[LIVE_E2E] ASR transcript (\(transcript.decodeMs) ms, speech=\(transcript.speechMs) ms): \(transcript.text)")
        #expect(!transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(transcript.speechMs > 500)

        // 4. Real Apple Vision OCR on a synthetic Telegram chat screenshot
        let width = 900, height = 300
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        ("Timur: check ClickHouse cluster status" as NSString).draw(at: NSPoint(x: 40, y: 140), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let cgImg = try #require(rep.cgImage)
        let screenText = try await VisionOcrEngine().recognize(image: ScreenImageData(width: width, height: height, cgImageBox: { cgImg }))
        print("[LIVE_E2E] Vision OCR lines: \(screenText.lines.map(\.text))")
        #expect(screenText.lines.map(\.text).joined(separator: " ").localizedCaseInsensitiveContains("ClickHouse"))

        // 5. Real ContextAssembler + PromptRenderer
        let snap = A11ySnapshot(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram",
            windowTitle: "Timur",
            field: FieldSnapshot(role: "AXTextArea", isEditable: true),
            windowBoundsInScreen: Rect(x0: 0, y0: 0, x1: width, y1: height)
        )
        let assembler = DefaultContextAssembler()
        let dec = assembler.decide(snapshot: snap, settings: ContextSettings(useScreen: true))
        let ctx = assembler.assemble(snapshot: snap, decision: dec, screen: .text(screenText), asrLanguage: transcript.language)

        let assets = BundlePromptAssets()
        let renderer = RenderPyPort(assets: assets)
        let profile = try assets.profile(name: llmModel.llm?.promptProfile ?? "finetuned.v1")
        let tpl = llmModel.llm?.template ?? "qwen3.5"
        let prefixText = try renderer.cachePrefix(profile: profile, template: tpl, preferences: nil, systemOverride: nil)
        let rendered = try renderer.render(RenderInput(profile: profile, template: tpl, ctx: ctx, transcript: transcript.text))

        // 6. Real LlamaLlmEngine on Metal GPU (`murmur-cleanup-qwen3.5-0.8b`)
        let llmEngine = LlamaLlmEngine()
        let llmSpec = storage.loadSpec(for: llmModel, artifact: llmArt, unit: .gpu, threads: 4)
        let llmLoad = try await llmEngine.load(spec: llmSpec)
        print("[LIVE_E2E] LLM loaded on \(llmLoad.unit.rawValue) (\(llmLoad.deviceName)) in \(llmLoad.loadMs) ms")
        #expect(llmLoad.unit == .gpu)

        let cacheKey = RenderPyPort.sha256Hex("live-e2e-\(UUID().uuidString)|\(llmArt.id)|\(prefixText)")
        let p1 = try await llmEngine.setPrefix(PrefixSpec(text: prefixText, cacheKey: cacheKey))
        print("[LIVE_E2E] Prefix #1: tokens=\(p1.tokens) prefillMs=\(p1.prefillMs) restored=\(p1.restoredFromDisk)")
        #expect(p1.tokens > 50)

        let gen = try await llmEngine.generate(request: LlmRequest(
            suffix: rendered.suffix,
            maxTokens: 128,
            minTokens: 4,
            temperature: 0.0,
            repeatPenalty: 1.0
        ), onPiece: nil)
        print("[LIVE_E2E] LLM raw output (\(gen.stats.totalMs) ms, genTok=\(gen.stats.generatedTokens)): \(gen.text)")
        #expect(!gen.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // 7. Real OutputGuard verdict
        let verdict = GuardPyPort().guardOutput(transcript: transcript.text, output: gen.text, ctx: ctx)
        print("[LIVE_E2E] OutputGuard verdict: action=\(verdict.action) reason=\(verdict.reason) final=\(verdict.text)")
        #expect(verdict.action == .accept)

        // 8. Verify KV prefix disk cache restore on fresh engine instance
        await llmEngine.unload()
        let llmEngine2 = LlamaLlmEngine()
        _ = try await llmEngine2.load(spec: llmSpec)
        let p2 = try await llmEngine2.setPrefix(PrefixSpec(text: prefixText, cacheKey: cacheKey))
        print("[LIVE_E2E] Prefix #2: tokens=\(p2.tokens) prefillMs=\(p2.prefillMs) restored=\(p2.restoredFromDisk)")
        #expect(p2.restoredFromDisk == true)
        await llmEngine2.unload()
        await asrEngine.unload()
    }
}
