import CSherpaOnnx
import Darwin
import Foundation
import MurmacCore

/// Process-wide singleton for dynamically loaded `libsherpa-onnx-c-api.dylib` symbols (v2.0.1 macOS arm64).
private final class SherpaSymbols: @unchecked Sendable {
    static let shared: SherpaSymbols? = SherpaSymbols()

    typealias VersionFn = @convention(c) () -> UnsafePointer<CChar>?

    typealias CreateOfflineRecFn = @convention(c) (UnsafePointer<SherpaOnnxOfflineRecognizerConfig>?) -> OpaquePointer?
    typealias DestroyOfflineRecFn = @convention(c) (OpaquePointer?) -> Void
    typealias CreateOfflineStreamFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias DestroyOfflineStreamFn = @convention(c) (OpaquePointer?) -> Void
    typealias AcceptOfflineFn = @convention(c) (OpaquePointer?, Int32, UnsafePointer<Float>?, Int32) -> Void
    typealias DecodeOfflineFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    typealias GetOfflineResultFn = @convention(c) (OpaquePointer?) -> UnsafePointer<SherpaOnnxOfflineRecognizerResult>?
    typealias DestroyOfflineResultFn = @convention(c) (UnsafePointer<SherpaOnnxOfflineRecognizerResult>?) -> Void

    typealias CreateOnlineRecFn = @convention(c) (UnsafePointer<SherpaOnnxOnlineRecognizerConfig>?) -> OpaquePointer?
    typealias DestroyOnlineRecFn = @convention(c) (OpaquePointer?) -> Void
    typealias CreateOnlineStreamFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias DestroyOnlineStreamFn = @convention(c) (OpaquePointer?) -> Void
    typealias AcceptOnlineFn = @convention(c) (OpaquePointer?, Int32, UnsafePointer<Float>?, Int32) -> Void
    typealias IsOnlineReadyFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    typealias DecodeOnlineFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    typealias FinishOnlineFn = @convention(c) (OpaquePointer?) -> Void
    typealias GetOnlineResultFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> UnsafePointer<SherpaOnnxOnlineRecognizerResult>?
    typealias DestroyOnlineResultFn = @convention(c) (UnsafePointer<SherpaOnnxOnlineRecognizerResult>?) -> Void

    typealias CreateVadFn = @convention(c) (UnsafePointer<SherpaOnnxVadModelConfig>?, Float) -> OpaquePointer?
    typealias DestroyVadFn = @convention(c) (OpaquePointer?) -> Void
    typealias AcceptVadFn = @convention(c) (OpaquePointer?, UnsafePointer<Float>?, Int32) -> Void
    typealias VadEmptyFn = @convention(c) (OpaquePointer?) -> Int32
    typealias VadFrontFn = @convention(c) (OpaquePointer?) -> UnsafePointer<SherpaOnnxSpeechSegment>?
    typealias DestroySegmentFn = @convention(c) (UnsafePointer<SherpaOnnxSpeechSegment>?) -> Void
    typealias VadPopFn = @convention(c) (OpaquePointer?) -> Void
    typealias VadFlushFn = @convention(c) (OpaquePointer?) -> Void
    typealias VadResetFn = @convention(c) (OpaquePointer?) -> Void

    let handle: UnsafeMutableRawPointer
    let version: VersionFn
    let createOfflineRec: CreateOfflineRecFn
    let destroyOfflineRec: DestroyOfflineRecFn
    let createOfflineStream: CreateOfflineStreamFn
    let destroyOfflineStream: DestroyOfflineStreamFn
    let acceptOffline: AcceptOfflineFn
    let decodeOffline: DecodeOfflineFn
    let getOfflineResult: GetOfflineResultFn
    let destroyOfflineResult: DestroyOfflineResultFn

    let createOnlineRec: CreateOnlineRecFn
    let destroyOnlineRec: DestroyOnlineRecFn
    let createOnlineStream: CreateOnlineStreamFn
    let destroyOnlineStream: DestroyOnlineStreamFn
    let acceptOnline: AcceptOnlineFn
    let isOnlineReady: IsOnlineReadyFn
    let decodeOnline: DecodeOnlineFn
    let finishOnline: FinishOnlineFn
    let getOnlineResult: GetOnlineResultFn
    let destroyOnlineResult: DestroyOnlineResultFn

    let createVad: CreateVadFn
    let destroyVad: DestroyVadFn
    let acceptVad: AcceptVadFn
    let vadEmpty: VadEmptyFn
    let vadFront: VadFrontFn
    let destroySegment: DestroySegmentFn
    let vadPop: VadPopFn
    let vadFlush: VadFlushFn
    let vadReset: VadResetFn

    private init?() {
        guard let loc = NativeLibraryLocator.locate(filename: "libsherpa-onnx-c-api.dylib") else { return nil }
        guard let h = dlopen(loc.path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let version: VersionFn = sym("SherpaOnnxGetVersionStr"),
              let createOfflineRec: CreateOfflineRecFn = sym("SherpaOnnxCreateOfflineRecognizer"),
              let destroyOfflineRec: DestroyOfflineRecFn = sym("SherpaOnnxDestroyOfflineRecognizer"),
              let createOfflineStream: CreateOfflineStreamFn = sym("SherpaOnnxCreateOfflineStream"),
              let destroyOfflineStream: DestroyOfflineStreamFn = sym("SherpaOnnxDestroyOfflineStream"),
              let acceptOffline: AcceptOfflineFn = sym("SherpaOnnxAcceptWaveformOffline"),
              let decodeOffline: DecodeOfflineFn = sym("SherpaOnnxDecodeOfflineStream"),
              let getOfflineResult: GetOfflineResultFn = sym("SherpaOnnxGetOfflineStreamResult"),
              let destroyOfflineResult: DestroyOfflineResultFn = sym("SherpaOnnxDestroyOfflineRecognizerResult"),
              let createOnlineRec: CreateOnlineRecFn = sym("SherpaOnnxCreateOnlineRecognizer"),
              let destroyOnlineRec: DestroyOnlineRecFn = sym("SherpaOnnxDestroyOnlineRecognizer"),
              let createOnlineStream: CreateOnlineStreamFn = sym("SherpaOnnxCreateOnlineStream"),
              let destroyOnlineStream: DestroyOnlineStreamFn = sym("SherpaOnnxDestroyOnlineStream"),
              let acceptOnline: AcceptOnlineFn = sym("SherpaOnnxOnlineStreamAcceptWaveform"),
              let isOnlineReady: IsOnlineReadyFn = sym("SherpaOnnxIsOnlineStreamReady"),
              let decodeOnline: DecodeOnlineFn = sym("SherpaOnnxDecodeOnlineStream"),
              let finishOnline: FinishOnlineFn = sym("SherpaOnnxOnlineStreamInputFinished"),
              let getOnlineResult: GetOnlineResultFn = sym("SherpaOnnxGetOnlineStreamResult"),
              let destroyOnlineResult: DestroyOnlineResultFn = sym("SherpaOnnxDestroyOnlineRecognizerResult"),
              let createVad: CreateVadFn = sym("SherpaOnnxCreateVoiceActivityDetector"),
              let destroyVad: DestroyVadFn = sym("SherpaOnnxDestroyVoiceActivityDetector"),
              let acceptVad: AcceptVadFn = sym("SherpaOnnxVoiceActivityDetectorAcceptWaveform"),
              let vadEmpty: VadEmptyFn = sym("SherpaOnnxVoiceActivityDetectorEmpty"),
              let vadFront: VadFrontFn = sym("SherpaOnnxVoiceActivityDetectorFront"),
              let destroySegment: DestroySegmentFn = sym("SherpaOnnxDestroySpeechSegment"),
              let vadPop: VadPopFn = sym("SherpaOnnxVoiceActivityDetectorPop"),
              let vadFlush: VadFlushFn = sym("SherpaOnnxVoiceActivityDetectorFlush"),
              let vadReset: VadResetFn = sym("SherpaOnnxVoiceActivityDetectorReset")
        else {
            dlclose(h)
            return nil
        }
        self.handle = h
        self.version = version
        self.createOfflineRec = createOfflineRec
        self.destroyOfflineRec = destroyOfflineRec
        self.createOfflineStream = createOfflineStream
        self.destroyOfflineStream = destroyOfflineStream
        self.acceptOffline = acceptOffline
        self.decodeOffline = decodeOffline
        self.getOfflineResult = getOfflineResult
        self.destroyOfflineResult = destroyOfflineResult
        self.createOnlineRec = createOnlineRec
        self.destroyOnlineRec = destroyOnlineRec
        self.createOnlineStream = createOnlineStream
        self.destroyOnlineStream = destroyOnlineStream
        self.acceptOnline = acceptOnline
        self.isOnlineReady = isOnlineReady
        self.decodeOnline = decodeOnline
        self.finishOnline = finishOnline
        self.getOnlineResult = getOnlineResult
        self.destroyOnlineResult = destroyOnlineResult
        self.createVad = createVad
        self.destroyVad = destroyVad
        self.acceptVad = acceptVad
        self.vadEmpty = vadEmpty
        self.vadFront = vadFront
        self.destroySegment = destroySegment
        self.vadPop = vadPop
        self.vadFlush = vadFlush
        self.vadReset = vadReset
    }
}

/// Scoped C-string arena guaranteeing every `strdup` lives until the C call finishes (even under Swift `-O`).
private final class CStringArena {
    private var ptrs: [UnsafeMutablePointer<CChar>] = []

    func dup(_ s: String?) -> UnsafePointer<CChar>? {
        guard let s, !s.isEmpty else { return nil }
        guard let p = strdup(s) else { return nil }
        ptrs.append(p)
        return UnsafePointer(p)
    }

    func releaseAll() {
        for p in ptrs { free(p) }
        ptrs.removeAll()
    }

    deinit { releaseAll() }

    static func withArena<T>(_ body: (CStringArena) -> T) -> T {
        let arena = CStringArena()
        defer { arena.releaseAll() }
        return body(arena)
    }
}

private struct SendableOpaquePtr: @unchecked Sendable {
    let raw: OpaquePointer
}

/// Reference-counted native handle holders so live sessions never suffer UAF if `unload()` or reload runs.
private final class ManagedOfflineRec: @unchecked Sendable {
    let ptr: OpaquePointer
    private let queue: DispatchQueue
    private let symbols: SherpaSymbols
    init(ptr: OpaquePointer, queue: DispatchQueue, symbols: SherpaSymbols) {
        self.ptr = ptr; self.queue = queue; self.symbols = symbols
    }
    deinit {
        let p = SendableOpaquePtr(raw: ptr); let s = symbols
        queue.async { s.destroyOfflineRec(p.raw) }
    }
}

private final class ManagedOnlineRec: @unchecked Sendable {
    let ptr: OpaquePointer
    private let queue: DispatchQueue
    private let symbols: SherpaSymbols
    init(ptr: OpaquePointer, queue: DispatchQueue, symbols: SherpaSymbols) {
        self.ptr = ptr; self.queue = queue; self.symbols = symbols
    }
    deinit {
        let p = SendableOpaquePtr(raw: ptr); let s = symbols
        queue.async { s.destroyOnlineRec(p.raw) }
    }
}

private final class ManagedVad: @unchecked Sendable {
    let ptr: OpaquePointer
    private let queue: DispatchQueue
    private let symbols: SherpaSymbols
    init(ptr: OpaquePointer, queue: DispatchQueue, symbols: SherpaSymbols) {
        self.ptr = ptr; self.queue = queue; self.symbols = symbols
    }
    deinit {
        let p = SendableOpaquePtr(raw: ptr); let s = symbols
        queue.async { s.destroyVad(p.raw) }
    }
}

/// Native macOS ASR engine backed by `sherpa-onnx` C API + Silero VAD v5.
public final class SherpaAsrEngine: AsrEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.murmur.murmac.asr", qos: .userInitiated)
    private let symbols: SherpaSymbols?

    private var loadedAsrSpec: LoadSpec?
    private var loadedVadSpec: LoadSpec?
    private var loadedVadMaxSpeechSec: Float = 19.5
    private var offlineRec: ManagedOfflineRec?
    private var onlineRec: ManagedOnlineRec?
    private var vadHandle: ManagedVad?

    public init() {
        self.symbols = SherpaSymbols.shared
    }

    public func probe() async -> EngineProbe {
        await withCheckedContinuation { cont in
            queue.async {
                guard let s = self.symbols else {
                    cont.resume(returning: EngineProbe(availableUnits: [], runtimes: [], facts: ["native": "missing"]))
                    return
                }
                let ver = s.version().map { String(cString: $0) } ?? "unknown"
                let rts = RuntimeKeys.offlineAsr.union(RuntimeKeys.onlineAsr).union([RuntimeKeys.ortSileroVadV5])
                cont.resume(returning: EngineProbe(availableUnits: [.cpu], runtimes: rts, facts: ["sherpa.version": ver]))
            }
        }
    }

    public func load(asr: LoadSpec, vad: LoadSpec?) async throws -> LoadInfo {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let s = self.symbols else {
                    cont.resume(throwing: MurmurError.engineRuntimeMissing(asr.runtime))
                    return
                }
                let t0 = DispatchTime.now().uptimeNanoseconds

                // Derive Silero VAD max speech duration from ASR model's max_window_sec (default 19.5s, cap 29.5s).
                let maxWinSec = asr.options["max_window_sec"].flatMap(Double.init) ?? 20.0
                let vadMaxSpeech = Float(min(29.5, max(5.0, maxWinSec - 0.5)))

                // Load, update, or clear VAD
                if let vad {
                    if self.loadedVadSpec != vad || self.vadHandle == nil || abs(self.loadedVadMaxSpeechSec - vadMaxSpeech) > 0.1 {
                        self.vadHandle = nil
                        guard let vadModelPath = self.rolePath(spec: vad, role: "model"),
                              FileManager.default.fileExists(atPath: vadModelPath) else {
                            cont.resume(throwing: MurmurError.engineLoadFailed(.vad, "vad_file_missing"))
                            return
                        }
                        let vh: OpaquePointer? = CStringArena.withArena { arena in
                            var cfg = SherpaOnnxVadModelConfig()
                            cfg.silero_vad.model = arena.dup(vadModelPath)
                            cfg.silero_vad.threshold = 0.5
                            cfg.silero_vad.min_silence_duration = 0.5
                            cfg.silero_vad.min_speech_duration = 0.25
                            cfg.silero_vad.window_size = 512
                            cfg.silero_vad.max_speech_duration = vadMaxSpeech
                            cfg.sample_rate = Int32(PcmFormat.sampleRate)
                            cfg.num_threads = 1
                            cfg.provider = arena.dup("cpu")
                            cfg.debug = 0
                            return s.createVad(&cfg, 60.0)
                        }
                        guard let vh else {
                            cont.resume(throwing: MurmurError.engineLoadFailed(.vad, "sherpa_vad_create_failed"))
                            return
                        }
                        self.vadHandle = ManagedVad(ptr: vh, queue: self.queue, symbols: s)
                        self.loadedVadSpec = vad
                        self.loadedVadMaxSpeechSec = vadMaxSpeech
                    }
                } else {
                    self.vadHandle = nil
                    self.loadedVadSpec = nil
                }

                // Reuse loaded ASR if identical
                if self.loadedAsrSpec == asr && (self.offlineRec != nil || self.onlineRec != nil) {
                    cont.resume(returning: LoadInfo(unit: .cpu, loadMs: 0, deviceName: "Apple Silicon CPU"))
                    return
                }

                // Drop old recognizer references (deinit safely destroys on queue once live sessions finish)
                self.offlineRec = nil
                self.onlineRec = nil
                self.loadedAsrSpec = nil

                let threads = Int32(min(8, max(1, asr.options["threads"].flatMap(Int.init) ?? 4)))

                if RuntimeKeys.offlineAsr.contains(asr.runtime) {
                    let created: Result<OpaquePointer, MurmurError> = CStringArena.withArena { arena in
                        var cfg = SherpaOnnxOfflineRecognizerConfig()
                        cfg.feat_config.sample_rate = Int32(PcmFormat.sampleRate)
                        cfg.feat_config.feature_dim = 80
                        cfg.model_config.num_threads = threads
                        cfg.model_config.provider = arena.dup("cpu")
                        cfg.model_config.debug = 0
                        cfg.model_config.model_type = arena.dup(asr.options["model_type"] ?? "")
                        cfg.decoding_method = arena.dup("greedy_search")

                        switch asr.runtime {
                        case RuntimeKeys.sherpaOfflineTransducer:
                            guard let enc = self.rolePath(spec: asr, role: "encoder"),
                                  let dec = self.rolePath(spec: asr, role: "decoder"),
                                  let join = self.rolePath(spec: asr, role: "joiner"),
                                  let tok = self.rolePath(spec: asr, role: "tokens") else {
                                return .failure(.engineLoadFailed(.asr, "missing_transducer_files"))
                            }
                            cfg.model_config.transducer.encoder = arena.dup(enc)
                            cfg.model_config.transducer.decoder = arena.dup(dec)
                            cfg.model_config.transducer.joiner = arena.dup(join)
                            cfg.model_config.tokens = arena.dup(tok)
                        case RuntimeKeys.sherpaOfflineCtc:
                            guard let mod = self.rolePath(spec: asr, role: "model"),
                                  let tok = self.rolePath(spec: asr, role: "tokens") else {
                                return .failure(.engineLoadFailed(.asr, "missing_ctc_files"))
                            }
                            cfg.model_config.nemo_ctc.model = arena.dup(mod)
                            cfg.model_config.tokens = arena.dup(tok)
                        case RuntimeKeys.sherpaOfflineWhisper:
                            guard let enc = self.rolePath(spec: asr, role: "encoder"),
                                  let dec = self.rolePath(spec: asr, role: "decoder"),
                                  let tok = self.rolePath(spec: asr, role: "tokens") else {
                                return .failure(.engineLoadFailed(.asr, "missing_whisper_files"))
                            }
                            cfg.model_config.whisper.encoder = arena.dup(enc)
                            cfg.model_config.whisper.decoder = arena.dup(dec)
                            cfg.model_config.whisper.language = arena.dup(asr.options["language"] ?? "")
                            cfg.model_config.whisper.task = arena.dup("transcribe")
                            cfg.model_config.whisper.tail_paddings = -1
                            cfg.model_config.tokens = arena.dup(tok)
                        case RuntimeKeys.sherpaOfflineQwen3Asr:
                            guard let fe = self.rolePath(spec: asr, role: "frontend"),
                                  let enc = self.rolePath(spec: asr, role: "encoder"),
                                  let dec = self.rolePath(spec: asr, role: "decoder"),
                                  let vocab = self.rolePath(spec: asr, role: "vocab") else {
                                return .failure(.engineLoadFailed(.asr, "missing_qwen3_asr_files"))
                            }
                            cfg.model_config.qwen3_asr.conv_frontend = arena.dup(fe)
                            cfg.model_config.qwen3_asr.encoder = arena.dup(enc)
                            cfg.model_config.qwen3_asr.decoder = arena.dup(dec)
                            cfg.model_config.qwen3_asr.tokenizer = arena.dup((vocab as NSString).deletingLastPathComponent)
                            cfg.model_config.qwen3_asr.max_total_len = 1024
                            cfg.model_config.qwen3_asr.max_new_tokens = 512
                        default:
                            return .failure(.engineRuntimeMissing(asr.runtime))
                        }

                        guard let rec = s.createOfflineRec(&cfg) else {
                            return .failure(.engineLoadFailed(.asr, "sherpa_offline_create_failed"))
                        }
                        return .success(rec)
                    }
                    switch created {
                    case .success(let rec):
                        self.offlineRec = ManagedOfflineRec(ptr: rec, queue: self.queue, symbols: s)
                    case .failure(let err):
                        cont.resume(throwing: err)
                        return
                    }
                } else if RuntimeKeys.onlineAsr.contains(asr.runtime) {
                    let created: Result<OpaquePointer, MurmurError> = CStringArena.withArena { arena in
                        var cfg = SherpaOnnxOnlineRecognizerConfig()
                        cfg.feat_config.sample_rate = Int32(PcmFormat.sampleRate)
                        cfg.feat_config.feature_dim = 80
                        cfg.model_config.num_threads = threads
                        cfg.model_config.provider = arena.dup("cpu")
                        cfg.model_config.debug = 0
                        cfg.decoding_method = arena.dup("greedy_search")
                        cfg.enable_endpoint = 0

                        switch asr.runtime {
                        case RuntimeKeys.sherpaOnlineTransducer:
                            guard let enc = self.rolePath(spec: asr, role: "encoder"),
                                  let dec = self.rolePath(spec: asr, role: "decoder"),
                                  let join = self.rolePath(spec: asr, role: "joiner"),
                                  let tok = self.rolePath(spec: asr, role: "tokens") else {
                                return .failure(.engineLoadFailed(.asr, "missing_online_transducer"))
                            }
                            cfg.model_config.transducer.encoder = arena.dup(enc)
                            cfg.model_config.transducer.decoder = arena.dup(dec)
                            cfg.model_config.transducer.joiner = arena.dup(join)
                            cfg.model_config.tokens = arena.dup(tok)
                        case RuntimeKeys.sherpaOnlineTOne:
                            guard let mod = self.rolePath(spec: asr, role: "model"),
                                  let tok = self.rolePath(spec: asr, role: "tokens") else {
                                return .failure(.engineLoadFailed(.asr, "missing_tone_files"))
                            }
                            cfg.feat_config.sample_rate = 8000
                            cfg.model_config.t_one_ctc.model = arena.dup(mod)
                            cfg.model_config.tokens = arena.dup(tok)
                        default:
                            return .failure(.engineRuntimeMissing(asr.runtime))
                        }

                        guard let rec = s.createOnlineRec(&cfg) else {
                            return .failure(.engineLoadFailed(.asr, "sherpa_online_create_failed"))
                        }
                        return .success(rec)
                    }
                    switch created {
                    case .success(let rec):
                        self.onlineRec = ManagedOnlineRec(ptr: rec, queue: self.queue, symbols: s)
                    case .failure(let err):
                        cont.resume(throwing: err)
                        return
                    }
                } else {
                    cont.resume(throwing: MurmurError.engineRuntimeMissing(asr.runtime))
                    return
                }

                self.loadedAsrSpec = asr
                let loadMs = Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                cont.resume(returning: LoadInfo(unit: .cpu, loadMs: loadMs, deviceName: "Apple Silicon CPU"))
            }
        }
    }

    public func startSession(options: AsrSessionOptions) async throws -> AsrSession {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let s = self.symbols else {
                    cont.resume(throwing: MurmurError.engineRuntimeMissing("sherpa"))
                    return
                }
                if let off = self.offlineRec {
                    if let vh = self.vadHandle { s.vadReset(vh.ptr) }
                    cont.resume(returning: OfflineSherpaSession(queue: self.queue, symbols: s, rec: off, vad: self.vadHandle, options: options))
                } else if let onl = self.onlineRec {
                    cont.resume(returning: OnlineSherpaSession(queue: self.queue, symbols: s, rec: onl, options: options))
                } else {
                    cont.resume(throwing: MurmurError.asrFailed("not_loaded"))
                }
            }
        }
    }

    public func unload() async {
        await withCheckedContinuation { cont in
            queue.async {
                self.offlineRec = nil
                self.onlineRec = nil
                self.vadHandle = nil
                self.loadedAsrSpec = nil
                self.loadedVadSpec = nil
                cont.resume()
            }
        }
    }

    private func rolePath(spec: LoadSpec, role: String) -> String? {
        guard let rel = spec.layout[role] else { return nil }
        let path = (spec.dir as NSString).appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

private final class OfflineSherpaSession: AsrSession, @unchecked Sendable {
    private let queue: DispatchQueue
    private let symbols: SherpaSymbols
    private let rec: ManagedOfflineRec
    private let vad: ManagedVad?
    private let options: AsrSessionOptions

    private var cancelled = false
    private var vadPending: [Float] = []
    private var fallbackAllSamples: [Float] = []
    private var decodedPieces: [String] = []
    private var detectedLanguage: String?
    private var totalSpeechSamples: Int64 = 0
    private var totalDecodeMs: Int64 = 0
    private var segmentCount: Int = 0

    init(queue: DispatchQueue, symbols: SherpaSymbols, rec: ManagedOfflineRec, vad: ManagedVad?, options: AsrSessionOptions) {
        self.queue = queue
        self.symbols = symbols
        self.rec = rec
        self.vad = vad
        self.options = options
    }

    func feed(_ chunk: PcmChunk) async {
        await withCheckedContinuation { cont in
            queue.async {
                guard !self.cancelled else { cont.resume(); return }
                let floats = chunk.samples.map { Float($0) / 32768.0 }
                if let vad = self.vad {
                    self.vadPending.append(contentsOf: floats)
                    let win = 512
                    var offset = 0
                    while offset + win <= self.vadPending.count {
                        self.vadPending.withUnsafeBufferPointer { buf in
                            self.symbols.acceptVad(vad.ptr, buf.baseAddress!.advanced(by: offset), Int32(win))
                        }
                        offset += win
                    }
                    if offset > 0 { self.vadPending.removeFirst(offset) }
                    self.drainVadSegments(vad.ptr)
                } else {
                    self.fallbackAllSamples.append(contentsOf: floats)
                }
                cont.resume()
            }
        }
    }

    func finish() async throws -> Transcript {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard !self.cancelled else {
                    cont.resume(throwing: MurmurError.cancelled)
                    return
                }
                if let vad = self.vad {
                    if !self.vadPending.isEmpty {
                        var padded = self.vadPending
                        if padded.count < 512 {
                            padded.append(contentsOf: repeatElement(Float(0), count: 512 - padded.count))
                        }
                        padded.withUnsafeBufferPointer { buf in
                            self.symbols.acceptVad(vad.ptr, buf.baseAddress, Int32(padded.count))
                        }
                        self.vadPending.removeAll()
                    }
                    self.symbols.vadFlush(vad.ptr)
                    self.drainVadSegments(vad.ptr)
                } else if !self.fallbackAllSamples.isEmpty {
                    self.decodeSegment(self.fallbackAllSamples)
                    self.totalSpeechSamples = Int64(self.fallbackAllSamples.count)
                    self.fallbackAllSamples.removeAll()
                }
                let joined = self.decodedPieces
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let speechMs = self.totalSpeechSamples * 1000 / Int64(PcmFormat.sampleRate)
                cont.resume(returning: Transcript(
                    text: joined,
                    speechMs: speechMs,
                    decodeMs: self.totalDecodeMs,
                    language: self.detectedLanguage ?? self.options.language,
                    segmentCount: self.segmentCount
                ))
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { cont in
            queue.async {
                self.cancelled = true
                self.vadPending.removeAll()
                self.fallbackAllSamples.removeAll()
                cont.resume()
            }
        }
    }

    private func drainVadSegments(_ vadPtr: OpaquePointer) {
        while symbols.vadEmpty(vadPtr) == 0 {
            guard let segPtr = symbols.vadFront(vadPtr) else {
                symbols.vadPop(vadPtr)
                continue
            }
            let n = Int(segPtr.pointee.n)
            if n > 0, let samplesPtr = segPtr.pointee.samples {
                let samples = Array(UnsafeBufferPointer(start: samplesPtr, count: n))
                totalSpeechSamples += Int64(n)
                decodeSegment(samples)
            }
            symbols.destroySegment(segPtr)
            symbols.vadPop(vadPtr)
        }
    }

    private func decodeSegment(_ samples: [Float]) {
        guard let stream = symbols.createOfflineStream(rec.ptr) else { return }
        defer { symbols.destroyOfflineStream(stream) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        samples.withUnsafeBufferPointer { buf in
            symbols.acceptOffline(stream, Int32(PcmFormat.sampleRate), buf.baseAddress, Int32(samples.count))
        }
        symbols.decodeOffline(rec.ptr, stream)
        if let res = symbols.getOfflineResult(stream) {
            if let cText = res.pointee.text {
                let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { decodedPieces.append(text) }
            }
            if detectedLanguage == nil, let cLang = res.pointee.lang {
                let lang = String(cString: cLang).trimmingCharacters(in: .whitespacesAndNewlines)
                if !lang.isEmpty { detectedLanguage = lang }
            }
            symbols.destroyOfflineResult(res)
        }
        totalDecodeMs += Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        segmentCount += 1
    }
}

private final class OnlineSherpaSession: AsrSession, @unchecked Sendable {
    private let queue: DispatchQueue
    private let symbols: SherpaSymbols
    private let rec: ManagedOnlineRec
    private let options: AsrSessionOptions
    private var stream: OpaquePointer?
    private var totalSamples: Int64 = 0
    private var decodeMs: Int64 = 0

    init(queue: DispatchQueue, symbols: SherpaSymbols, rec: ManagedOnlineRec, options: AsrSessionOptions) {
        self.queue = queue
        self.symbols = symbols
        self.rec = rec
        self.options = options
        self.stream = symbols.createOnlineStream(rec.ptr)
    }

    deinit {
        if let st = stream {
            let p = SendableOpaquePtr(raw: st)
            let s = symbols
            let r = rec // keep recognizer alive until stream is destroyed on queue
            queue.async {
                withExtendedLifetime(r) {
                    s.destroyOnlineStream(p.raw)
                }
            }
        }
    }

    func feed(_ chunk: PcmChunk) async {
        await withCheckedContinuation { cont in
            queue.async {
                guard let st = self.stream else { cont.resume(); return }
                let floats = chunk.samples.map { Float($0) / 32768.0 }
                self.totalSamples += Int64(floats.count)
                let t0 = DispatchTime.now().uptimeNanoseconds
                floats.withUnsafeBufferPointer { buf in
                    self.symbols.acceptOnline(st, Int32(PcmFormat.sampleRate), buf.baseAddress, Int32(floats.count))
                }
                while self.symbols.isOnlineReady(self.rec.ptr, st) != 0 {
                    self.symbols.decodeOnline(self.rec.ptr, st)
                }
                self.decodeMs += Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                cont.resume()
            }
        }
    }

    func finish() async throws -> Transcript {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let st = self.stream else {
                    cont.resume(throwing: MurmurError.cancelled)
                    return
                }
                let t0 = DispatchTime.now().uptimeNanoseconds
                let tail = [Float](repeating: 0, count: PcmFormat.sampleRate / 2)
                tail.withUnsafeBufferPointer { buf in
                    self.symbols.acceptOnline(st, Int32(PcmFormat.sampleRate), buf.baseAddress, Int32(tail.count))
                }
                self.symbols.finishOnline(st)
                while self.symbols.isOnlineReady(self.rec.ptr, st) != 0 {
                    self.symbols.decodeOnline(self.rec.ptr, st)
                }
                var text = ""
                if let res = self.symbols.getOnlineResult(self.rec.ptr, st) {
                    if let cText = res.pointee.text {
                        text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    self.symbols.destroyOnlineResult(res)
                }
                self.decodeMs += Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                self.symbols.destroyOnlineStream(st)
                self.stream = nil
                let durMs = self.totalSamples * 1000 / Int64(PcmFormat.sampleRate)
                cont.resume(returning: Transcript(text: text, speechMs: durMs, decodeMs: self.decodeMs, language: self.options.language, segmentCount: 1))
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { cont in
            queue.async {
                if let st = self.stream {
                    self.symbols.destroyOnlineStream(st)
                    self.stream = nil
                }
                cont.resume()
            }
        }
    }
}
