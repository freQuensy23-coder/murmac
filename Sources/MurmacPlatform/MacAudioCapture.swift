import AVFoundation
import Foundation
import MurmacCore

/// Captures microphone audio via `AVAudioEngine` and converts any device format (incl. AirPods/USB mics)
/// to 16 kHz mono Int16 PCM, driving Murmur's `LevelMeter` and `PcmSessionBuffer`.
public final class MacAudioCapture: AudioCapturePort, @unchecked Sendable {
    public init() {}

    public func start(onLevels: @escaping @Sendable ([Float]) -> Void) async throws -> CaptureHandlePort {
        let handle = try MacCaptureHandle(onLevels: onLevels)
        try handle.begin()
        return handle
    }
}

private final class MacCaptureHandle: CaptureHandlePort, @unchecked Sendable {
    let chunks: AsyncStream<PcmChunk>
    private let continuation: AsyncStream<PcmChunk>.Continuation
    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private let sessionBuffer = PcmSessionBuffer()
    private let onLevels: @Sendable ([Float]) -> Void
    private let lock = NSLock()
    private var sampleOffset: Int64 = 0
    private var stopped = false

    init(onLevels: @escaping @Sendable ([Float]) -> Void) throws {
        self.onLevels = onLevels
        var cont: AsyncStream<PcmChunk>.Continuation!
        self.chunks = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    deinit {
        cancel()
    }

    func begin() throws {
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
            throw MurmurError.micStartFailed("no_input_device")
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(PcmFormat.sampleRate),
            channels: AVAudioChannelCount(PcmFormat.channels),
            interleaved: true
        ) else {
            throw MurmurError.micStartFailed("target_format_failed")
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw MurmurError.micStartFailed("converter_failed")
        }

        let ratio = Double(PcmFormat.sampleRate) / hwFormat.sampleRate
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if self.lock.withLock({ self.stopped }) { return }

            let outCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 64
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: outBuf, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error != nil {
                converter.reset()
                return
            }

            let count = Int(outBuf.frameLength)
            guard count > 0, let int16Ptr = outBuf.int16ChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: int16Ptr, count: count))

            let prevTicks = self.meter.ticks
            let bars = self.meter.push(samples)
            if self.meter.ticks != prevTicks {
                self.onLevels(bars)
            }

            let chunkToYield: PcmChunk? = self.lock.withLock {
                guard !self.stopped else { return nil }
                self.sessionBuffer.append(samples)
                let start = self.sampleOffset
                self.sampleOffset += Int64(count)
                return PcmChunk(samples: samples, startSample: start)
            }
            if let chunkToYield {
                self.continuation.yield(chunkToYield)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw MurmurError.micStartFailed(error.localizedDescription)
        }
    }

    func currentLevels() -> [Float] {
        meter.bars()
    }

    func stop() async -> (durationMs: Int64, samples: [Int16]) {
        let wasStopped = lock.withLock { () -> Bool in
            let prev = stopped
            stopped = true
            return prev
        }
        if !wasStopped {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            continuation.finish()
        }
        return (durationMs: sessionBuffer.durationMs, samples: sessionBuffer.allSamples())
    }

    func cancel() {
        let wasStopped = lock.withLock { () -> Bool in
            let prev = stopped
            stopped = true
            return prev
        }
        if !wasStopped {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            continuation.finish()
        }
        sessionBuffer.clear()
    }
}
