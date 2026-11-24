import Foundation
import MurmacCore

/// In-process engine coordinator for macOS with automatic idle unloading (same D5 policy as Murmur).
public final class LocalEngines: Engines, @unchecked Sendable {
    public let asr: AsrEngine
    public let llm: LlmEngine
    public let ocr: ScreenOcrEngine

    private let lock = NSLock()
    private var idleTask: Task<Void, Never>?

    public init(
        asr: AsrEngine = SherpaAsrEngine(),
        llm: LlmEngine = LlamaLlmEngine(),
        ocr: ScreenOcrEngine = VisionOcrEngine()
    ) {
        self.asr = asr
        self.llm = llm
        self.ocr = ocr
    }

    public func holdActive() {
        lock.lock()
        idleTask?.cancel()
        idleTask = nil
        lock.unlock()
    }

    public func scheduleIdleUnload(afterMs: Int64) {
        lock.lock()
        idleTask?.cancel()
        let delayNs = UInt64(max(1_000, afterMs)) * 1_000_000
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await self?.unloadAll()
        }
        lock.unlock()
    }

    public func unloadAll() async {
        holdActive()
        await asr.unload()
        await llm.unload()
    }
}
