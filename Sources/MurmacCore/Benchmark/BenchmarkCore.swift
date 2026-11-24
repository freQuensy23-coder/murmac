import Foundation

public enum WerCalculator {
    public static func normalize(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    public static func wer(reference: String, hypothesis: String) -> Double {
        let r = normalize(reference)
        let h = normalize(hypothesis)
        if r.isEmpty { return h.isEmpty ? 0.0 : 1.0 }
        var prev = Array(0...h.count)
        for i in 1...r.count {
            var cur = Array(repeating: 0, count: h.count + 1)
            cur[0] = i
            for j in 1...h.count {
                let cost = r[i - 1] == h[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, min(cur[j - 1] + 1, prev[j - 1] + cost))
            }
            prev = cur
        }
        return Double(prev[h.count]) / Double(r.count)
    }
}

public actor BenchmarkRunner {
    private let engines: Engines
    private let storage: ModelStorage
    private let db: SqliteStore
    private let clock: MurmurClock

    public init(engines: Engines, storage: ModelStorage, db: SqliteStore, clock: MurmurClock = SystemMurmurClock()) {
        self.engines = engines
        self.storage = storage
        self.db = db
        self.clock = clock
    }

    public func benchmarkLlm(model: CatalogModel, artifact: CatalogArtifact, unit: ComputeUnit) async throws -> BenchmarkRecord {
        await engines.unloadAll()
        let spec = storage.loadSpec(for: model, artifact: artifact, unit: unit, threads: 4)
        let info = try await engines.llm.load(spec: spec)
        let syn = try await engines.llm.bench(nPrompt: 256, nGen: 64, reps: 3)
        let rec = BenchmarkRecord(
            artifactId: artifact.id,
            kind: .llm,
            unit: info.unit,
            measuredAtMs: clock.nowMs(),
            loadMs: info.loadMs,
            prefillTps: syn.prefillTps,
            decodeTps: syn.decodeTps,
            deviceName: info.deviceName
        )
        try db.saveBenchmark(rec)
        return rec
    }

    public func benchmarkAsr(model: CatalogModel, artifact: CatalogArtifact, vadSpec: LoadSpec?) async throws -> BenchmarkRecord {
        await engines.unloadAll()
        let spec = storage.loadSpec(for: model, artifact: artifact, unit: .cpu, threads: 4)
        // Load without VAD so the actual ASR encoder/decoder executes on the 3s synthetic clip
        let info = try await engines.asr.load(asr: spec, vad: nil)
        let samples = (0..<(PcmFormat.sampleRate * 3)).map { i -> Int16 in
            Int16(sin(Double(i) * 0.08) * 4000.0)
        }
        let session = try await engines.asr.startSession(options: AsrSessionOptions())
        let t0 = clock.monotonicMs()
        await session.feed(PcmChunk(samples: samples, startSample: 0))
        _ = try await session.finish()
        let durMs = max(1, clock.monotonicMs() - t0)
        let rtf = Double(durMs) / 3000.0
        let rec = BenchmarkRecord(
            artifactId: artifact.id,
            kind: .asr,
            unit: info.unit,
            measuredAtMs: clock.nowMs(),
            loadMs: info.loadMs,
            asrRtf: rtf,
            deviceName: info.deviceName
        )
        try db.saveBenchmark(rec)
        return rec
    }
}
