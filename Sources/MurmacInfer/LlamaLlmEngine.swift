import CMurmurLlm
import Darwin
import Foundation
import MurmacCore

/// Process-wide singleton for dynamically loaded `libmurmur_llm.dylib` C API symbols (avoids dlopen refcount leaks).
private final class MurmurLlmSymbols: @unchecked Sendable {
    static let shared: MurmurLlmSymbols? = MurmurLlmSymbols()

    typealias GlobalInitFn = @convention(c) (UnsafePointer<mllm_init_params>?) -> Int32
    typealias BuildInfoFn = @convention(c) () -> UnsafePointer<CChar>?
    typealias RuntimeInfoFn = @convention(c) (UnsafeMutablePointer<CChar>?, Int32) -> Int32
    typealias DevicesFn = @convention(c) (UnsafeMutablePointer<CChar>?, Int32) -> Int32
    typealias LoadFn = @convention(c) (UnsafePointer<mllm_load_params>?, UnsafeMutablePointer<OpaquePointer?>?, UnsafeMutablePointer<mllm_load_info>?) -> Int32
    typealias PrefixSetFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<mllm_prefix_info>?) -> Int32
    typealias PrefixSaveFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias PrefixLoadFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<mllm_prefix_info>?) -> Int32
    typealias GenerateFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<mllm_gen_params>?, mllm_token_cb?, UnsafeMutableRawPointer?, UnsafeMutablePointer<mllm_gen_stats>?) -> Int32
    typealias CancelFn = @convention(c) (OpaquePointer?) -> Void
    typealias CancelClearFn = @convention(c) (OpaquePointer?) -> Void
    typealias TokenizeCountFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias LastErrorFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    typealias DeviceNameFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    typealias UnloadFn = @convention(c) (OpaquePointer?) -> Void
    typealias BenchFn = @convention(c) (OpaquePointer?, Int32, Int32, Int32, UnsafeMutablePointer<mllm_bench_result>?) -> Int32

    let handle: UnsafeMutableRawPointer
    let backendDir: String
    let globalInit: GlobalInitFn
    let buildInfo: BuildInfoFn
    let runtimeInfo: RuntimeInfoFn
    let devices: DevicesFn
    let load: LoadFn
    let prefixSet: PrefixSetFn
    let prefixSave: PrefixSaveFn
    let prefixLoad: PrefixLoadFn
    let generate: GenerateFn
    let cancel: CancelFn
    let cancelClear: CancelClearFn
    let tokenizeCount: TokenizeCountFn
    let lastError: LastErrorFn
    let deviceName: DeviceNameFn
    let unload: UnloadFn
    let bench: BenchFn

    private init?() {
        guard let loc = NativeLibraryLocator.locate(filename: "libmurmur_llm.dylib") else { return nil }
        guard let h = dlopen(loc.path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(h, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        guard let globalInit: GlobalInitFn = sym("mllm_global_init"),
              let buildInfo: BuildInfoFn = sym("mllm_build_info"),
              let runtimeInfo: RuntimeInfoFn = sym("mllm_runtime_info"),
              let devices: DevicesFn = sym("mllm_devices"),
              let load: LoadFn = sym("mllm_load"),
              let prefixSet: PrefixSetFn = sym("mllm_prefix_set"),
              let prefixSave: PrefixSaveFn = sym("mllm_prefix_save"),
              let prefixLoad: PrefixLoadFn = sym("mllm_prefix_load"),
              let generate: GenerateFn = sym("mllm_generate"),
              let cancel: CancelFn = sym("mllm_cancel"),
              let cancelClear: CancelClearFn = sym("mllm_cancel_clear"),
              let tokenizeCount: TokenizeCountFn = sym("mllm_tokenize_count"),
              let lastError: LastErrorFn = sym("mllm_last_error"),
              let deviceName: DeviceNameFn = sym("mllm_device_name"),
              let unload: UnloadFn = sym("mllm_unload"),
              let bench: BenchFn = sym("mllm_bench")
        else {
            dlclose(h)
            return nil
        }
        self.handle = h
        self.backendDir = loc.dir
        self.globalInit = globalInit
        self.buildInfo = buildInfo
        self.runtimeInfo = runtimeInfo
        self.devices = devices
        self.load = load
        self.prefixSet = prefixSet
        self.prefixSave = prefixSave
        self.prefixLoad = prefixLoad
        self.generate = generate
        self.cancel = cancel
        self.cancelClear = cancelClear
        self.tokenizeCount = tokenizeCount
        self.lastError = lastError
        self.deviceName = deviceName
        self.unload = unload
        self.bench = bench
    }
}

private final class TokenCallbackBox {
    let onPiece: @Sendable (String) -> Void
    var accumulated: String = ""
    init(onPiece: @escaping @Sendable (String) -> Void) { self.onPiece = onPiece }
}

private let swiftMllmTokenCallback: mllm_token_cb = { user, piecePtr, len in
    guard let user, let piecePtr, len > 0 else { return 0 }
    let box = Unmanaged<TokenCallbackBox>.fromOpaque(user).takeUnretainedValue()
    let data = Data(bytes: piecePtr, count: Int(len))
    if let s = String(data: data, encoding: .utf8) {
        box.accumulated += s
        box.onPiece(s)
    }
    return 0
}

/// Native macOS LLM engine backed by `murmur_llm` (`llama.cpp` + Metal GPU + prefix KV-cache).
public final class LlamaLlmEngine: LlmEngine, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.murmur.murmac.llm", qos: .userInitiated)
    private let handleLock = NSLock()
    private let symbols: MurmurLlmSymbols?

    private var initialized = false
    private var engineHandle: OpaquePointer?
    private var loadedSpec: LoadSpec?
    private var loadedNCtx: Int = 7168
    private var loadedPrefixTokens: Int = 0
    private var loadedPrefixCacheKey: String?
    private var loadedDir: String = ""

    public init() {
        self.symbols = MurmurLlmSymbols.shared
    }

    deinit {
        let h: OpaquePointer? = handleLock.withLock {
            let cur = engineHandle
            engineHandle = nil
            return cur
        }
        if let h, let s = symbols {
            s.unload(h)
        }
    }

    private func ensureInitialized(_ s: MurmurLlmSymbols) -> Int32 {
        if initialized { return MLLM_OK }
        let rc = s.backendDir.withCString { dirPtr -> Int32 in
            var p = mllm_init_params(backend_dir: dirPtr, htp_lib_dir: nil, hex_power_mode: nil, verbose: 0)
            return s.globalInit(&p)
        }
        if rc == MLLM_OK { initialized = true }
        return rc
    }

    public func probe() async -> EngineProbe {
        await withCheckedContinuation { cont in
            queue.async {
                guard let s = self.symbols else {
                    cont.resume(returning: EngineProbe(availableUnits: [], runtimes: [], facts: ["native": "missing"]))
                    return
                }
                let rc = self.ensureInitialized(s)
                let build = s.buildInfo().map { String(cString: $0) } ?? "unknown"
                var facts: [String: String] = ["native.build": build]
                if rc != MLLM_OK {
                    facts["native"] = "init_failed:\(rc)"
                    cont.resume(returning: EngineProbe(availableUnits: [], runtimes: [], facts: facts))
                    return
                }
                let devLen = Int(s.devices(nil, 0))
                var devBuf = [CChar](repeating: 0, count: max(1, devLen + 1))
                _ = s.devices(&devBuf, Int32(devBuf.count))
                let devStr = devBuf.withUnsafeBufferPointer { buf -> String in
                    let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    return String(decoding: bytes, as: UTF8.self)
                }
                facts["devices"] = devStr
                var units: Set<ComputeUnit> = []
                for item in devStr.split(separator: ";") {
                    let cols = item.split(separator: "|")
                    if cols.count >= 3 {
                        if cols[2] == "gpu" { units.insert(.gpu) }
                        if cols[2] == "cpu" { units.insert(.cpu) }
                    }
                }
                cont.resume(returning: EngineProbe(availableUnits: units, runtimes: [RuntimeKeys.llamaGguf], facts: facts))
            }
        }
    }

    public func load(spec: LoadSpec) async throws -> LoadInfo {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard spec.runtime == RuntimeKeys.llamaGguf else {
                    cont.resume(throwing: MurmurError.engineRuntimeMissing(spec.runtime))
                    return
                }
                guard let s = self.symbols else {
                    cont.resume(throwing: MurmurError.engineRuntimeMissing(RuntimeKeys.llamaGguf))
                    return
                }
                if let current = self.loadedSpec, current == spec, let h = self.engineHandle {
                    let devName = s.deviceName(h).map { String(cString: $0) } ?? spec.unit.displayName
                    cont.resume(returning: LoadInfo(unit: spec.unit, loadMs: 0, deviceName: devName))
                    return
                }
                guard let modelRel = spec.layout["model"] else {
                    cont.resume(throwing: MurmurError.engineLoadFailed(.llm, "layout_missing_model"))
                    return
                }
                let modelPath = (spec.dir as NSString).appendingPathComponent(modelRel)
                guard FileManager.default.fileExists(atPath: modelPath) else {
                    cont.resume(throwing: MurmurError.engineLoadFailed(.llm, "model_missing"))
                    return
                }
                let initRc = self.ensureInitialized(s)
                guard initRc == MLLM_OK else {
                    cont.resume(throwing: MurmurError.engineLoadFailed(.llm, "init_rc_\(initRc)"))
                    return
                }

                self.unloadLocked()

                let nCtx = Int32(spec.options["n_ctx"].flatMap(Int.init) ?? 7168)
                let threads = Int32(spec.options["threads"].flatMap(Int.init) ?? 4)
                let device: mllm_device = (spec.unit == .gpu) ? MLLM_DEV_GPU : MLLM_DEV_CPU
                let t0 = DispatchTime.now().uptimeNanoseconds

                var outHandle: OpaquePointer?
                var info = mllm_load_info()
                let rc: Int32 = modelPath.withCString { pathPtr in
                    var lp = mllm_load_params(
                        model_path: pathPtr,
                        device: device,
                        n_ctx: nCtx,
                        n_batch: 512,
                        n_threads: threads,
                        n_threads_batch: threads,
                        use_mmap: 1,
                        prefix_mode: MLLM_PREFIX_RAM,
                        kv_type: MLLM_KV_F16
                    )
                    return s.load(&lp, &outHandle, &info)
                }
                let loadMs = Int64((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)

                if rc != MLLM_OK || outHandle == nil {
                    let err: MurmurError
                    switch rc {
                    case MLLM_E_DEVICE: err = .unitUnavailable(spec.unit)
                    case MLLM_E_NOMEM: err = .outOfMemory(.llm)
                    default: err = .engineLoadFailed(.llm, "rc=\(rc)")
                    }
                    cont.resume(throwing: err)
                    return
                }

                self.handleLock.withLock {
                    self.engineHandle = outHandle
                }

                self.loadedSpec = spec
                self.loadedNCtx = Int(nCtx)
                self.loadedPrefixTokens = 0
                self.loadedPrefixCacheKey = nil
                self.loadedDir = spec.dir

                let devName = s.deviceName(outHandle).map { String(cString: $0) } ?? spec.unit.displayName
                cont.resume(returning: LoadInfo(unit: spec.unit, loadMs: loadMs, deviceName: devName))
            }
        }
    }

    public func setPrefix(_ spec: PrefixSpec) async throws -> PrefixInfo {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let s = self.symbols, let h = self.engineHandle else {
                    cont.resume(throwing: MurmurError.llmFailed("not_loaded"))
                    return
                }
                if self.loadedPrefixCacheKey == spec.cacheKey && self.loadedPrefixTokens > 0 {
                    cont.resume(returning: PrefixInfo(tokens: self.loadedPrefixTokens, prefillMs: 0, restoredFromDisk: false, bytes: 0))
                    return
                }
                s.cancelClear(h)
                let statePath = (self.loadedDir as NSString).appendingPathComponent("prefix-\(spec.cacheKey).state")
                var pInfo = mllm_prefix_info()

                if FileManager.default.fileExists(atPath: statePath) {
                    let loadRc: Int32 = statePath.withCString { pPtr in
                        spec.text.withCString { tPtr in
                            s.prefixLoad(h, pPtr, tPtr, &pInfo)
                        }
                    }
                    if loadRc == MLLM_OK {
                        self.loadedPrefixTokens = Int(pInfo.n_tokens)
                        self.loadedPrefixCacheKey = spec.cacheKey
                        cont.resume(returning: PrefixInfo(
                            tokens: Int(pInfo.n_tokens),
                            prefillMs: Int64(pInfo.prefill_ms),
                            restoredFromDisk: true,
                            bytes: Int(pInfo.snapshot_bytes)
                        ))
                        return
                    }
                    try? FileManager.default.removeItem(atPath: statePath)
                }

                let setRc: Int32 = spec.text.withCString { tPtr in
                    s.prefixSet(h, tPtr, &pInfo)
                }
                guard setRc == MLLM_OK else {
                    cont.resume(throwing: setRc == MLLM_E_CANCELLED ? MurmurError.cancelled : MurmurError.llmFailed("prefix_rc_\(setRc)"))
                    return
                }

                // Persist snapshot atomically (temp file -> rename so mmap invariants hold)
                let tmpPath = "\(statePath).tmp-\(UUID().uuidString)"
                let saveRc = tmpPath.withCString { s.prefixSave(h, $0) }
                if saveRc == MLLM_OK {
                    if rename(tmpPath, statePath) != 0 {
                        try? FileManager.default.removeItem(atPath: tmpPath)
                    }
                } else {
                    try? FileManager.default.removeItem(atPath: tmpPath)
                }

                self.loadedPrefixTokens = Int(pInfo.n_tokens)
                self.loadedPrefixCacheKey = spec.cacheKey
                cont.resume(returning: PrefixInfo(
                    tokens: Int(pInfo.n_tokens),
                    prefillMs: Int64(pInfo.prefill_ms),
                    restoredFromDisk: false,
                    bytes: Int(pInfo.snapshot_bytes)
                ))
            }
        }
    }

    public func generate(request: LlmRequest, onPiece: (@Sendable (String) -> Void)?) async throws -> LlmGenerationResult {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let s = self.symbols, let h = self.engineHandle else {
                    cont.resume(throwing: MurmurError.llmFailed("not_loaded"))
                    return
                }
                s.cancelClear(h)
                let suffixTokens = Int(request.suffix.withCString { s.tokenizeCount(h, $0) })
                let room = self.loadedNCtx - self.loadedPrefixTokens - max(0, suffixTokens)
                if room < request.minTokens {
                    cont.resume(throwing: MurmurError.llmContextOverflow)
                    return
                }
                let cappedMax = Int32(min(request.maxTokens, room))
                guard cappedMax > 0 else {
                    cont.resume(throwing: MurmurError.llmContextOverflow)
                    return
                }
                let box = TokenCallbackBox(onPiece: onPiece ?? { _ in })
                var stats = mllm_gen_stats()

                let cStops: [UnsafeMutablePointer<CChar>] = request.stops
                    .filter { !$0.isEmpty }
                    .compactMap { strdup($0) }
                defer { for p in cStops { free(p) } }
                let constStops: [UnsafePointer<CChar>?] = cStops.map { UnsafePointer($0) }

                let rc: Int32 = withExtendedLifetime(box) {
                    let opaque = Unmanaged.passUnretained(box).toOpaque()
                    return constStops.withUnsafeBufferPointer { stopBuf in
                        var gp = mllm_gen_params(
                            max_tokens: cappedMax,
                            temperature: request.temperature,
                            top_k: 40,
                            top_p: 0.95,
                            repeat_penalty: request.repeatPenalty,
                            seed: 42,
                            stop: stopBuf.baseAddress,
                            n_stop: Int32(constStops.count)
                        )
                        return request.suffix.withCString { sPtr in
                            s.generate(h, sPtr, &gp, swiftMllmTokenCallback, opaque, &stats)
                        }
                    }
                }

                if rc == MLLM_E_CANCELLED {
                    cont.resume(throwing: MurmurError.cancelled)
                    return
                }
                if rc == MLLM_E_OVERFLOW {
                    cont.resume(throwing: MurmurError.llmContextOverflow)
                    return
                }
                guard rc == MLLM_OK else {
                    let msg = s.lastError(h).map { String(cString: $0) } ?? "rc=\(rc)"
                    cont.resume(throwing: MurmurError.llmFailed(msg))
                    return
                }

                let llmStats = LlmStats(
                    promptTokens: Int(stats.n_prompt),
                    generatedTokens: Int(stats.n_gen),
                    restoreMs: stats.restore_ms,
                    prefillMs: stats.prefill_ms,
                    ttftMs: stats.ttft_ms,
                    decodeMs: stats.decode_ms,
                    totalMs: stats.total_ms,
                    truncated: stats.stop_reason == 1
                )
                cont.resume(returning: LlmGenerationResult(text: box.accumulated, stats: llmStats))
            }
        }
    }

    public func bench(nPrompt: Int, nGen: Int, reps: Int) async throws -> SyntheticBench {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let s = self.symbols, let h = self.engineHandle else {
                    cont.resume(throwing: MurmurError.llmFailed("not_loaded"))
                    return
                }
                s.cancelClear(h)
                var res = mllm_bench_result()
                let rc = s.bench(h, Int32(nPrompt), Int32(nGen), Int32(reps), &res)
                guard rc == MLLM_OK else {
                    cont.resume(throwing: rc == MLLM_E_CANCELLED ? MurmurError.cancelled : MurmurError.llmFailed("bench_rc_\(rc)"))
                    return
                }
                cont.resume(returning: SyntheticBench(prefillTps: res.pp_tps, decodeTps: res.tg_tps, prefillMs: res.pp_ms, decodeMs: res.tg_ms))
            }
        }
    }

    /// Thread-safe cancellation: invokes `mllm_cancel` (O(1) atomic store) WHILE holding `handleLock`
    /// so `unloadLocked()` cannot free the native engine concurrently.
    public func cancel() {
        handleLock.withLock {
            if let h = engineHandle, let s = symbols {
                s.cancel(h)
            }
        }
    }

    public func unload() async {
        await withCheckedContinuation { cont in
            queue.async {
                self.unloadLocked()
                cont.resume()
            }
        }
    }

    private func unloadLocked() {
        let h: OpaquePointer? = handleLock.withLock {
            let cur = engineHandle
            engineHandle = nil
            return cur
        }
        if let h, let s = symbols {
            s.unload(h)
        }
        loadedSpec = nil
        loadedPrefixTokens = 0
        loadedPrefixCacheKey = nil
    }
}
