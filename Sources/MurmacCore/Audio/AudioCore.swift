import Foundation

public enum PcmFormat {
    public static let sampleRate: Int = 16_000
    public static let channels: Int = 1
    public static let bitsPerSample: Int = 16
    public static let bytesPerSample: Int = 2
}

public struct PcmChunk: Sendable, Equatable {
    public let samples: [Int16]
    public let startSample: Int64

    public init(samples: [Int16], startSample: Int64) {
        self.samples = samples
        self.startSample = startSample
    }

    public var endSample: Int64 { startSample + Int64(samples.count) }
}

/// Thread-safe in-memory session audio buffer (capped at 5 min @ 16 kHz = 4,800,000 samples ≈ 9.6 MB).
public final class PcmSessionBuffer: @unchecked Sendable {
    public static let maxSamples = PcmFormat.sampleRate * 300
    private let lock = NSLock()
    private var buffer: [Int16] = []

    public init(capacity: Int = PcmFormat.sampleRate * 10) {
        buffer.reserveCapacity(capacity)
    }

    public func append(_ samples: [Int16]) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = Self.maxSamples - buffer.count
        guard remaining > 0 else { return }
        if samples.count <= remaining {
            buffer.append(contentsOf: samples)
        } else {
            buffer.append(contentsOf: samples.prefix(remaining))
        }
    }

    public func slice(startSample: Int64, endSample: Int64) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        let s = max(0, min(Int(startSample), buffer.count))
        let e = max(s, min(Int(endSample), buffer.count))
        return Array(buffer[s..<e])
    }

    public func allSamples() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    public var durationMs: Int64 {
        Int64(count) * 1000 / Int64(PcmFormat.sampleRate)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: false)
    }
}

/// Port of Murmur's LevelMeter: 7 bars, 30 Hz RMS sampling, attack 40 ms / release 120 ms, flat 0 on silence.
public final class LevelMeter: @unchecked Sendable {
    public let weights: [Float]
    public let attackMs: Int
    public let releaseMs: Int
    public let rateHz: Int
    public let windowMs: Int
    public let floorDb: Double
    public let ceilDb: Double
    public let sampleRate: Int

    private let windowSamples: Int
    private let attackStep: Double
    private let releaseStep: Double

    private let lock = NSLock()
    private var ring: [Int16]
    private var ringPos: Int = 0
    private var ringFill: Int = 0
    private var sumSquares: Double = 0.0
    private var samplesSeen: Int64 = 0
    private var nextTickAt: Int64
    private var smoothed: Double = 0.0
    private var barValues: [Float]
    private var _ticks: Int64 = 0
    public var ticks: Int64 { lock.withLock { _ticks } }

    private static let fullScale: Double = 32768.0
    private static let snapToZero: Double = 1e-3

    public init(
        weights: [Float] = [0.35, 0.7, 1.0, 0.6, 0.85, 0.45, 0.25],
        attackMs: Int = 40,
        releaseMs: Int = 120,
        rateHz: Int = 30,
        windowMs: Int = 50,
        floorDb: Double = -55.0,
        ceilDb: Double = -10.0,
        sampleRate: Int = PcmFormat.sampleRate
    ) {
        self.weights = weights
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.rateHz = rateHz
        self.windowMs = windowMs
        self.floorDb = floorDb
        self.ceilDb = ceilDb
        self.sampleRate = sampleRate
        self.windowSamples = max(1, Int(Int64(sampleRate) * Int64(windowMs) / 1000))
        let tickSeconds = 1.0 / Double(rateHz)
        self.attackStep = 1.0 - exp(-tickSeconds * 1000.0 / Double(attackMs))
        self.releaseStep = 1.0 - exp(-tickSeconds * 1000.0 / Double(releaseMs))
        self.ring = Array(repeating: 0, count: windowSamples)
        self.barValues = Array(repeating: 0, count: weights.count)
        self.nextTickAt = (Int64(sampleRate) + Int64(rateHz) - 1) / Int64(rateHz)
    }

    public var level: Double { lock.withLock { smoothed } }

    @discardableResult
    public func push(_ samples: [Int16]) -> [Float] {
        lock.withLock {
            for s in samples {
                let old = ring[ringPos]
                if ringFill == windowSamples {
                    sumSquares -= Double(old) * Double(old)
                } else {
                    ringFill += 1
                }
                sumSquares += Double(s) * Double(s)
                ring[ringPos] = s
                ringPos = (ringPos + 1) % windowSamples
                samplesSeen += 1
                if samplesSeen >= nextTickAt {
                    tickLocked()
                    nextTickAt = tickDue(_ticks + 1)
                }
            }
            return barValues
        }
    }

    public func bars() -> [Float] { lock.withLock { barValues } }

    public func reset() {
        lock.withLock {
            for i in ring.indices { ring[i] = 0 }
            ringPos = 0
            ringFill = 0
            sumSquares = 0.0
            samplesSeen = 0
            _ticks = 0
            nextTickAt = tickDue(1)
            smoothed = 0.0
            for i in barValues.indices { barValues[i] = 0 }
        }
    }

    private func tickLocked() {
        if _ticks % 300 == 0 {
            var acc = 0.0
            for x in ring { acc += Double(x) * Double(x) }
            sumSquares = acc
        }
        let rms = sqrt(max(0.0, sumSquares / Double(max(1, ringFill))))
        let target = levelOf(rms: rms)
        smoothed += (target - smoothed) * (target > smoothed ? attackStep : releaseStep)
        if smoothed < Self.snapToZero { smoothed = 0.0 }
        for i in barValues.indices {
            barValues[i] = min(1.0, max(0.0, Float(smoothed) * weights[i]))
        }
        _ticks += 1
    }

    private func tickDue(_ k: Int64) -> Int64 {
        (k * Int64(sampleRate) + Int64(rateHz) - 1) / Int64(rateHz)
    }

    public func levelOf(rms: Double) -> Double {
        guard rms > 0.0 else { return 0.0 }
        let db = 20.0 * log10(rms / Self.fullScale)
        return min(1.0, max(0.0, (db - floorDb) / (ceilDb - floorDb)))
    }
}

public struct SegmenterConfig: Sendable, Equatable {
    public let frameSamples: Int
    public let speechThreshold: Float
    public let silenceThreshold: Float
    public let minSilenceMs: Int
    public let softSilenceMs: Int
    public let softAfterMs: Int
    public let preRollMs: Int
    public let postRollMs: Int
    public let hardMaxMs: Int
    public let forcedCutSearchMs: Int
    public let minSpeechMs: Int

    public init(
        frameSamples: Int = 512,
        speechThreshold: Float = 0.5,
        silenceThreshold: Float = 0.35,
        minSilenceMs: Int = 500,
        softSilenceMs: Int = 150,
        softAfterMs: Int = 14_000,
        preRollMs: Int = 300,
        postRollMs: Int = 300,
        hardMaxMs: Int = 19_500,
        forcedCutSearchMs: Int = 2_000,
        minSpeechMs: Int = 250
    ) {
        self.frameSamples = frameSamples
        self.speechThreshold = speechThreshold
        self.silenceThreshold = silenceThreshold
        self.minSilenceMs = minSilenceMs
        self.softSilenceMs = softSilenceMs
        self.softAfterMs = softAfterMs
        self.preRollMs = preRollMs
        self.postRollMs = postRollMs
        self.hardMaxMs = hardMaxMs
        self.forcedCutSearchMs = forcedCutSearchMs
        self.minSpeechMs = minSpeechMs
    }

    public static func forWindow(maxWindowSec: Double?) -> SegmenterConfig {
        let hardMax = min(29_500, Int(((maxWindowSec ?? 20.0) * 1000.0) - 500.0))
        return SegmenterConfig(hardMaxMs: hardMax)
    }
}

public struct Segment: Sendable, Equatable {
    public let index: Int
    public let startSample: Int64
    public let endSample: Int64
    public let forced: BooleanLiteralType
    public let speechMs: Int64

    public init(index: Int, startSample: Int64, endSample: Int64, forced: Bool, speechMs: Int64 = 0) {
        self.index = index
        self.startSample = startSample
        self.endSample = endSample
        self.forced = forced
        self.speechMs = speechMs
    }
}

public protocol VadModel: AnyObject {
    func probability(frame: [Float]) -> Float
    func reset()
}

/// Exact port of Murmur's PauseSegmenter (VAD-segmented incremental decoding for batch ASR models).
public final class PauseSegmenter {
    public let config: SegmenterConfig
    private let sampleRate: Int
    private let frame: Int64
    private let minSilence: Int64
    private let softSilence: Int64
    private let softAfter: Int64
    private let preRoll: Int64
    private let postRoll: Int64
    private let hardMax: Int64
    private let search: Int64
    private let minSpeech: Int64

    private let ringSize: Int
    private var ringProb: [Float]
    private var ringEnd: [Int64]
    private var ringSpeech: [Bool]
    private var ringCount: Int = 0
    private var ringHead: Int = 0

    private var index: Int = 0
    private var prevEnd: Int64 = 0
    private var segStart: Int64 = -1
    private var lastSpeechEnd: Int64 = 0
    private var silenceRun: Int64 = 0
    private var openSpeech: Int64 = 0
    private var committedSpeech: Int64 = 0

    public private(set) var speaking: Bool = false

    public var openStartSample: Int64? { segStart >= 0 ? segStart : nil }
    public var lastSpeechEndSample: Int64 { lastSpeechEnd }
    public var speechMs: Int64 { toMs(committedSpeech + openSpeech) }

    public init(config: SegmenterConfig = SegmenterConfig(), sampleRate: Int = PcmFormat.sampleRate) {
        self.config = config
        self.sampleRate = sampleRate
        self.frame = Int64(config.frameSamples)
        func toSamples(_ ms: Int) -> Int64 { Int64(ms) * Int64(sampleRate) / 1000 }
        self.minSilence = toSamples(config.minSilenceMs)
        self.softSilence = toSamples(config.softSilenceMs)
        self.softAfter = toSamples(config.softAfterMs)
        self.preRoll = toSamples(config.preRollMs)
        self.postRoll = toSamples(config.postRollMs)
        self.hardMax = toSamples(config.hardMaxMs)
        self.search = toSamples(config.forcedCutSearchMs)
        self.minSpeech = toSamples(config.minSpeechMs)
        self.ringSize = Int(self.search / self.frame) + 2
        self.ringProb = Array(repeating: 0, count: ringSize)
        self.ringEnd = Array(repeating: 0, count: ringSize)
        self.ringSpeech = Array(repeating: false, count: ringSize)
    }

    public func onFrame(probability: Float, frameEndSample: Int64) -> Segment? {
        let now = frameEndSample
        let isSpeech = probability >= config.speechThreshold
        if isSpeech {
            if segStart < 0 {
                segStart = max(0, max(now - frame - preRoll, prevEnd))
                ringCount = 0
            }
            speaking = true
            silenceRun = 0
            lastSpeechEnd = now
            openSpeech += frame
        } else if probability < config.silenceThreshold && speaking {
            silenceRun += frame
        }
        if segStart < 0 { return nil }
        push(probability, now, isSpeech)

        let length = now - segStart
        let need = length >= softAfter ? softSilence : minSilence
        if speaking && silenceRun >= need {
            return close(end: min(lastSpeechEnd + postRoll, now), forced: false)
        }
        if length >= hardMax {
            return forcedCut(now: now)
        }
        return nil
    }

    public func flush(endSample: Int64) -> Segment? {
        guard segStart >= 0 else { return nil }
        return close(end: max(endSample, segStart), forced: false)
    }

    private func close(end: Int64, forced: Bool) -> Segment? {
        let speech = openSpeech
        let seg: Segment?
        if speech >= minSpeech {
            committedSpeech += speech
            seg = Segment(index: index, startSample: segStart, endSample: end, forced: forced, speechMs: toMs(speech))
            index += 1
        } else {
            seg = nil
        }
        prevEnd = max(prevEnd, end)
        segStart = -1
        speaking = false
        silenceRun = 0
        openSpeech = 0
        ringCount = 0
        return seg
    }

    private func forcedCut(now: Int64) -> Segment? {
        let from = max(now - search, segStart)
        var best = -1
        var bestProb = Float.greatestFiniteMagnitude
        for i in 0..<ringCount {
            let s = slot(i)
            if ringEnd[s] > from && ringProb[s] < bestProb {
                bestProb = ringProb[s]
                best = i
            }
        }
        if best < 0 { best = max(0, ringCount - 1) }
        let cut = ringEnd[slot(best)] - frame / 2
        let tail = ringCount - best - 1
        var tailProb: [Float] = []
        var tailEnd: [Int64] = []
        var tailSpeech: [Bool] = []
        tailProb.reserveCapacity(tail)
        tailEnd.reserveCapacity(tail)
        tailSpeech.reserveCapacity(tail)
        for i in 0..<tail {
            let s = slot(best + 1 + i)
            tailProb.append(ringProb[s])
            tailEnd.append(ringEnd[s])
            tailSpeech.append(ringSpeech[s])
        }
        let moved = Int64(tailSpeech.filter { $0 }.count) * frame
        let run = silenceRun
        openSpeech -= moved
        let seg = close(end: cut, forced: true)
        segStart = cut
        speaking = true
        silenceRun = run
        openSpeech = moved
        for i in 0..<tail {
            push(tailProb[i], tailEnd[i], tailSpeech[i])
        }
        return seg
    }

    private func slot(_ i: Int) -> Int {
        let raw = (ringHead - ringCount + i) % ringSize
        return raw >= 0 ? raw : raw + ringSize
    }

    private func push(_ p: Float, _ end: Int64, _ speech: Bool) {
        ringProb[ringHead] = p
        ringEnd[ringHead] = end
        ringSpeech[ringHead] = speech
        ringHead = (ringHead + 1) % ringSize
        if ringCount < ringSize { ringCount += 1 }
    }

    private func toMs(_ samples: Int64) -> Int64 {
        samples * 1000 / Int64(sampleRate)
    }
}

/// Minimal PCM16 LE mono 16 kHz WAV encoder/decoder for history audio storage and testing.
public enum WavCodec {
    public static func encode(samples: [Int16], sampleRate: Int = PcmFormat.sampleRate) -> Data {
        let dataBytes = UInt32(samples.count * 2)
        let riffSize = UInt32(36) + dataBytes
        var out = Data(capacity: Int(44 + dataBytes))
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: "RIFF".utf8)
        appendLE(riffSize)
        out.append(contentsOf: "WAVE".utf8)
        out.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))
        appendLE(UInt16(1)) // PCM
        appendLE(UInt16(1)) // mono
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(sampleRate * 2))
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        out.append(contentsOf: "data".utf8)
        appendLE(dataBytes)
        samples.withUnsafeBufferPointer { buf in
            for sample in buf {
                appendLE(sample)
            }
        }
        return out
    }

    public static func decode(data: Data) throws -> [Int16] {
        guard data.count >= 44,
              String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: data[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw MurmurError.storageFailed("invalid_wav")
        }
        var offset = 12
        while offset + 8 <= data.count {
            let chunkId = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(data.withUnsafeBytes { raw -> UInt32 in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            })
            let bodyStart = offset + 8
            if chunkId == "data" {
                let avail = min(size, data.count - bodyStart)
                let count = avail / 2
                var samples = [Int16](repeating: 0, count: count)
                data.withUnsafeBytes { raw in
                    for i in 0..<count {
                        samples[i] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: bodyStart + i * 2, as: Int16.self))
                    }
                }
                return samples
            }
            offset = bodyStart + size + (size % 2)
        }
        throw MurmurError.storageFailed("wav_no_data_chunk")
    }
}
