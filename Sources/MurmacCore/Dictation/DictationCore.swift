import Foundation

public struct LlmSpeed: Equatable, Sendable {
    public let prefillTps: Double
    public let decodeTps: Double

    public init(prefillTps: Double, decodeTps: Double) {
        self.prefillTps = prefillTps
        self.decodeTps = decodeTps
    }
}

public struct DictationConfig: Sendable {
    public let screenshotDelayMs: Int64
    public let ocrBudgetMs: Int64
    public let contextWaitMs: Int64
    public let warnAtMs: Int64
    public let maxDurationMs: Int64
    public let minSpeechMs: Int64
    public let llmReadyWaitMs: Int64
    public let llmBaseMs: Int64
    public let llmSafety: Double
    public let llmHardCapMs: Int64
    public let llmMaxExpectedMs: Int64
    public let doubleTapGuardMs: Int64
    public let defaultSpeed: [ComputeUnit: LlmSpeed]
    public let insertedDismissMs: Int64
    public let copiedDismissMs: Int64
    public let errorDismissMs: Int64

    public init(
        screenshotDelayMs: Int64 = 450,
        ocrBudgetMs: Int64 = 4_000,
        contextWaitMs: Int64 = 800,
        warnAtMs: Int64 = 270_000,
        maxDurationMs: Int64 = 300_000,
        minSpeechMs: Int64 = 250,
        llmReadyWaitMs: Int64 = 10_000,
        llmBaseMs: Int64 = 4_000,
        llmSafety: Double = 1.5,
        llmHardCapMs: Int64 = 64_000,
        llmMaxExpectedMs: Int64 = 40_000,
        doubleTapGuardMs: Int64 = 300,
        defaultSpeed: [ComputeUnit: LlmSpeed] = [
            .gpu: LlmSpeed(prefillTps: 500.0, decodeTps: 60.0),
            .cpu: LlmSpeed(prefillTps: 120.0, decodeTps: 20.0),
            .ane: LlmSpeed(prefillTps: 400.0, decodeTps: 30.0),
        ],
        insertedDismissMs: Int64 = 1_400,
        copiedDismissMs: Int64 = 3_500,
        errorDismissMs: Int64 = 5_000
    ) {
        self.screenshotDelayMs = screenshotDelayMs
        self.ocrBudgetMs = ocrBudgetMs
        self.contextWaitMs = contextWaitMs
        self.warnAtMs = warnAtMs
        self.maxDurationMs = maxDurationMs
        self.minSpeechMs = minSpeechMs
        self.llmReadyWaitMs = llmReadyWaitMs
        self.llmBaseMs = llmBaseMs
        self.llmSafety = llmSafety
        self.llmHardCapMs = llmHardCapMs
        self.llmMaxExpectedMs = llmMaxExpectedMs
        self.doubleTapGuardMs = doubleTapGuardMs
        self.defaultSpeed = defaultSpeed
        self.insertedDismissMs = insertedDismissMs
        self.copiedDismissMs = copiedDismissMs
        self.errorDismissMs = errorDismissMs
    }

    public func llmTimeoutMs(expectedMs: Int64) -> Int64 {
        min(llmHardCapMs, Int64(Double(llmBaseMs) + Double(expectedMs) * llmSafety))
    }
}

public enum CleanupBudget {
    public static let tokensPerChar = 0.40
    public static let contextReserveChars = 1_850
    public static let outputFactor = 1.5
    public static let minOutputFactor = 1.1

    public struct Plan: Equatable, Sendable {
        public let fits: Bool
        public let skipReason: String?
        public let maxTokens: Int
        public let minTokens: Int
        public let expectedMs: Int64
        public let timeoutMs: Int64
    }

    public static func estTokens(chars: Int) -> Int {
        Int(ceil(Double(chars) * tokensPerChar))
    }

    public static func plan(
        transcriptChars: Int,
        prefixTokens: Int,
        nCtx: Int,
        speed: LlmSpeed,
        config: DictationConfig
    ) -> Plan {
        let tTok = estTokens(chars: transcriptChars)
        let suffixTok = tTok + estTokens(chars: contextReserveChars)
        let minTokens = Int(ceil(Double(tTok) * minOutputFactor)) + 16
        let room = nCtx - prefixTokens - suffixTok
        let maxTokens = min(Int(ceil(Double(tTok) * outputFactor)) + 64, room)
        let prefillMs = Double(suffixTok) / max(1.0, speed.prefillTps) * 1000.0
        let decodeMs = Double(minTokens) / max(1.0, speed.decodeTps) * 1000.0
        let expectedMs = Int64(prefillMs + decodeMs)
        let fits = room >= minTokens && expectedMs <= config.llmMaxExpectedMs
        return Plan(
            fits: fits,
            skipReason: fits ? nil : "too_long",
            maxTokens: max(0, maxTokens),
            minTokens: minTokens,
            expectedMs: expectedMs,
            timeoutMs: config.llmTimeoutMs(expectedMs: expectedMs)
        )
    }
}

public enum StartMode: Equatable, Sendable {
    case hotkey
    case menuBar
    case inAppPractice
    case retry(entryId: Int64)
}

public enum DictationOutcome: Equatable, Sendable {
    case inserted(cleaned: Bool, skipReason: String?)
    case copied(cleaned: Bool, skipReason: String?)
    case discarded
    case failed(MurmurError)
}

/// High-level observable UI state for HUD pill, Menu Bar icon, and Practice screen.
public enum DictationPhase: Equatable, Sendable {
    case idle
    case listening(startedAtMs: Int64, warn: Bool)
    case transcribing
    case polishing
    case done(DictationOutcome)
}

public struct PermissionSnapshot: Equatable, Sendable {
    public let microphone: Bool
    public let accessibility: Bool
    public let screenRecording: Bool

    public init(microphone: Bool, accessibility: Bool, screenRecording: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    public var allCoreGranted: Bool { microphone && accessibility }
}

// MARK: - Platform Ports

public protocol CaptureHandlePort: AnyObject, Sendable {
    var chunks: AsyncStream<PcmChunk> { get }
    func currentLevels() -> [Float]
    func stop() async -> (durationMs: Int64, samples: [Int16])
    func cancel()
}

public protocol AudioCapturePort: AnyObject, Sendable {
    func start(onLevels: @escaping @Sendable ([Float]) -> Void) async throws -> CaptureHandlePort
}

public protocol TargetReaderPort: AnyObject, Sendable {
    func snapshot() async -> A11ySnapshot?
    func screenshot(target: A11ySnapshot) async throws -> ScreenImageData
}

public enum InsertOutcome: Equatable, Sendable {
    case inserted(InsertMethod)
    case copiedOnly
    case failed(MurmurError)
}

public protocol TextInserterPort: AnyObject, Sendable {
    func insert(text: String, target: A11ySnapshot?, restoreClipboard: Bool) async -> InsertOutcome
    func copyToClipboard(_ text: String)
}

public protocol AudioStorePort: AnyObject, Sendable {
    func save(samples: [Int16], key: AudioKey) throws -> String
    func load(path: String) throws -> [Int16]
    func delete(path: String)
}

public protocol PermissionMonitorPort: AnyObject, Sendable {
    func check() -> PermissionSnapshot
    func requestMicrophone() async -> Bool
    func requestAccessibilityPrompt()
    func requestScreenRecordingPrompt()
    func openSystemSettings(_ pane: PermissionPane)
}

public enum PermissionPane: Sendable {
    case microphone
    case accessibility
    case screenRecording
}

public protocol FeedbackPort: AnyObject, Sendable {
    func playStart()
    func playStop()
    func playDone()
    func playError()
}

public struct ResolvedLlm: Sendable {
    public let spec: LoadSpec
    public let fallbackSpec: LoadSpec?
    public let modelId: String
    public let template: String
    public let profileName: String
    public let nCtx: Int
    public let prefixTokens: Int?
    public let modelSha256: String
    public let speed: LlmSpeed?

    public init(
        spec: LoadSpec,
        fallbackSpec: LoadSpec?,
        modelId: String,
        template: String,
        profileName: String,
        nCtx: Int,
        prefixTokens: Int?,
        modelSha256: String,
        speed: LlmSpeed?
    ) {
        self.spec = spec
        self.fallbackSpec = fallbackSpec
        self.modelId = modelId
        self.template = template
        self.profileName = profileName
        self.nCtx = nCtx
        self.prefixTokens = prefixTokens
        self.modelSha256 = modelSha256
        self.speed = speed
    }
}

public struct ResolvedModels: Sendable {
    public let asr: LoadSpec
    public let asrModelId: String
    public let asrTraits: AsrTraits
    public let vad: LoadSpec?
    public let llm: ResolvedLlm?
    public let llmUnavailableReason: String?

    public init(
        asr: LoadSpec,
        asrModelId: String,
        asrTraits: AsrTraits,
        vad: LoadSpec?,
        llm: ResolvedLlm?,
        llmUnavailableReason: String?
    ) {
        self.asr = asr
        self.asrModelId = asrModelId
        self.asrTraits = asrTraits
        self.vad = vad
        self.llm = llm
        self.llmUnavailableReason = llmUnavailableReason
    }
}

public protocol ModelResolverPort: Sendable {
    func resolve(settings: AppSettings) throws -> ResolvedModels
}

public struct DefaultModelResolver: ModelResolverPort {
    private let catalog: CatalogDocument
    private let storage: ModelStorage
    private let db: SqliteStore

    public init(catalog: CatalogDocument, storage: ModelStorage, db: SqliteStore) {
        self.catalog = catalog
        self.storage = storage
        self.db = db
    }

    public func resolve(settings: AppSettings) throws -> ResolvedModels {
        let asrModel = catalog.models.first { $0.id == settings.selectedAsrModelId && $0.kind == .asr }
            ?? catalog.models.first { $0.kind == .asr && $0.isSelectable && ($0.preferredArtifact.map(storage.isInstalled) ?? false) }
        guard let asrModel, let asrArtifact = asrModel.preferredArtifact, storage.isInstalled(asrArtifact) else {
            throw MurmurError.noAsrModel
        }
        let asrTraits = asrModel.asr ?? AsrTraits()
        let asrSpec = storage.loadSpec(
            for: asrModel,
            artifact: asrArtifact,
            unit: .cpu,
            threads: 4,
            languageHint: settings.language.asrHint
        )

        var vadSpec: LoadSpec? = nil
        if let vadModel = catalog.models.first(where: { $0.id == catalog.defaults.vad && $0.kind == .vad }),
           let vadArtifact = vadModel.preferredArtifact,
           storage.isInstalled(vadArtifact) {
            vadSpec = storage.loadSpec(for: vadModel, artifact: vadArtifact, unit: .cpu, threads: 1)
        }
        if !asrTraits.streaming && vadSpec == nil {
            throw MurmurError.noVadModel
        }

        guard settings.cleanupEnabled, let llmId = settings.selectedLlmModelId else {
            return ResolvedModels(
                asr: asrSpec,
                asrModelId: asrModel.id,
                asrTraits: asrTraits,
                vad: vadSpec,
                llm: nil,
                llmUnavailableReason: "none"
            )
        }

        let benchmarks = (try? db.fetchBenchmarks()) ?? []
        let primaryUnit: ComputeUnit = settings.llmUnitPreference == .cpu ? .cpu : .gpu
        let fallbackUnit: ComputeUnit? = primaryUnit == .gpu ? .cpu : nil

        // Check catalog LLMs first
        if let llmModel = catalog.models.first(where: { $0.id == llmId && $0.kind == .llm }),
           let llmArtifact = llmModel.preferredArtifact,
           storage.isInstalled(llmArtifact),
           let traits = llmModel.llm {
            let spec = storage.loadSpec(for: llmModel, artifact: llmArtifact, unit: primaryUnit, threads: 4)
            let fb = fallbackUnit.map { storage.loadSpec(for: llmModel, artifact: llmArtifact, unit: $0, threads: 4) }
            let bench = benchmarks.first { $0.artifactId == llmArtifact.id && $0.unit == primaryUnit }
            let speed = bench.flatMap { b -> LlmSpeed? in
                guard let pp = b.prefillTps, let tg = b.decodeTps, pp > 0, tg > 0 else { return nil }
                return LlmSpeed(prefillTps: pp, decodeTps: tg)
            }
            let sha = llmArtifact.files.first?.sha256 ?? llmArtifact.id
            let resolved = ResolvedLlm(
                spec: spec,
                fallbackSpec: fb,
                modelId: llmModel.id,
                template: traits.template,
                profileName: traits.promptProfile,
                nCtx: traits.nCtx,
                prefixTokens: traits.prefixTokens,
                modelSha256: sha,
                speed: speed
            )
            return ResolvedModels(
                asr: asrSpec,
                asrModelId: asrModel.id,
                asrTraits: asrTraits,
                vad: vadSpec,
                llm: resolved,
                llmUnavailableReason: nil
            )
        }

        // Check user custom GGUF models
        if let custom = (try? db.fetchCustomModels())?.first(where: { $0.id == llmId }),
           FileManager.default.fileExists(atPath: custom.filePath) {
            let url = URL(fileURLWithPath: custom.filePath)
            let dir = url.deletingLastPathComponent().path
            let fileName = url.lastPathComponent
            let opts = ["n_ctx": "\(custom.nCtx)", "threads": "4", "template": custom.template, "profile": custom.promptProfile]
            let spec = LoadSpec(artifactId: custom.id, kind: .llm, runtime: RuntimeKeys.llamaGguf, unit: primaryUnit, dir: dir, layout: ["model": fileName], options: opts)
            let fb = fallbackUnit.map { LoadSpec(artifactId: custom.id, kind: .llm, runtime: RuntimeKeys.llamaGguf, unit: $0, dir: dir, layout: ["model": fileName], options: opts) }
            let resolved = ResolvedLlm(
                spec: spec,
                fallbackSpec: fb,
                modelId: custom.id,
                template: custom.template,
                profileName: custom.promptProfile,
                nCtx: custom.nCtx,
                prefixTokens: nil,
                modelSha256: custom.sha256,
                speed: nil
            )
            return ResolvedModels(
                asr: asrSpec,
                asrModelId: asrModel.id,
                asrTraits: asrTraits,
                vad: vadSpec,
                llm: resolved,
                llmUnavailableReason: nil
            )
        }

        return ResolvedModels(
            asr: asrSpec,
            asrModelId: asrModel.id,
            asrTraits: asrTraits,
            vad: vadSpec,
            llm: nil,
            llmUnavailableReason: "no_model"
        )
    }
}

/// Serial actor orchestrating the full Murmur dictation pipeline on macOS.
public actor DictationOrchestrator {
    public struct Observer: Sendable {
        public let onPhase: @Sendable (DictationPhase) -> Void
        public let onLevels: @Sendable ([Float]) -> Void
        public let onHistoryUpdated: @Sendable () -> Void
        public let onInAppDelivery: @Sendable (String) -> Void

        public init(
            onPhase: @escaping @Sendable (DictationPhase) -> Void,
            onLevels: @escaping @Sendable ([Float]) -> Void,
            onHistoryUpdated: @escaping @Sendable () -> Void,
            onInAppDelivery: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.onPhase = onPhase
            self.onLevels = onLevels
            self.onHistoryUpdated = onHistoryUpdated
            self.onInAppDelivery = onInAppDelivery
        }
    }

    private let engines: Engines
    private let audioCapture: AudioCapturePort
    private let targetReader: TargetReaderPort
    private let inserter: TextInserterPort
    private let audioStore: AudioStorePort
    private let permissions: PermissionMonitorPort
    private let feedback: FeedbackPort
    private let resolver: ModelResolverPort
    private let settingsStore: SettingsStore
    private let db: SqliteStore
    private let contextAssembler: ContextAssembler
    private let promptAssets: PromptAssets
    private let promptRenderer: PromptRenderer
    private let outputGuard: OutputGuard
    private let clock: MurmurClock
    private let config: DictationConfig
    private let observer: Observer

    private var phase: DictationPhase = .idle
    private var startingInFlight: Bool = false
    private var pendingStopAfterStart: Bool = false
    private var pendingCancelAfterStart: Bool = false
    private var activeSession: ActiveRun?
    private var activeProcessingRun: ActiveRun?
    private var dismissTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?

    private final class ActiveRun {
        let sessionId: String
        let mode: StartMode
        let startedAtMs: Int64
        let settings: AppSettings
        let models: ResolvedModels
        let target: A11ySnapshot?
        let decision: PrivacyDecision
        var captureHandle: CaptureHandlePort?
        var asrSession: AsrSession?
        var asrLoadTask: Task<LoadInfo, Error>?
        var feedTask: Task<Void, Never>?
        var llmPrepareTask: Task<(LoadInfo, PrefixInfo, ResolvedLlm, PromptProfile, String), Error>?
        var ocrTask: Task<(ScreenOutcome, Int64), Never>?

        init(
            sessionId: String,
            mode: StartMode,
            startedAtMs: Int64,
            settings: AppSettings,
            models: ResolvedModels,
            target: A11ySnapshot?,
            decision: PrivacyDecision
        ) {
            self.sessionId = sessionId
            self.mode = mode
            self.startedAtMs = startedAtMs
            self.settings = settings
            self.models = models
            self.target = target
            self.decision = decision
        }
    }

    public init(
        engines: Engines,
        audioCapture: AudioCapturePort,
        targetReader: TargetReaderPort,
        inserter: TextInserterPort,
        audioStore: AudioStorePort,
        permissions: PermissionMonitorPort,
        feedback: FeedbackPort,
        resolver: ModelResolverPort,
        settingsStore: SettingsStore,
        db: SqliteStore,
        contextAssembler: ContextAssembler = DefaultContextAssembler(),
        promptAssets: PromptAssets = BundlePromptAssets(),
        promptRenderer: PromptRenderer? = nil,
        outputGuard: OutputGuard = GuardPyPort(),
        clock: MurmurClock = SystemMurmurClock(),
        config: DictationConfig = DictationConfig(),
        observer: Observer
    ) {
        self.engines = engines
        self.audioCapture = audioCapture
        self.targetReader = targetReader
        self.inserter = inserter
        self.audioStore = audioStore
        self.permissions = permissions
        self.feedback = feedback
        self.resolver = resolver
        self.settingsStore = settingsStore
        self.db = db
        self.contextAssembler = contextAssembler
        self.promptAssets = promptAssets
        self.promptRenderer = promptRenderer ?? RenderPyPort(assets: promptAssets)
        self.outputGuard = outputGuard
        self.clock = clock
        self.config = config
        self.observer = observer
    }

    public func currentPhase() -> DictationPhase { phase }

    public func toggle(mode: StartMode = .hotkey) async {
        if startingInFlight {
            pendingStopAfterStart = true
            return
        }
        switch phase {
        case .idle, .done:
            await start(mode: mode)
        case .listening(let startedAtMs, _):
            if clock.monotonicMs() - startedAtMs < config.doubleTapGuardMs {
                return // Double-tap guard (300 ms)
            }
            await stopAndProcess()
        case .transcribing, .polishing:
            break
        }
    }

    public func cancel() async {
        if startingInFlight {
            pendingCancelAfterStart = true
            return
        }
        maxDurationTask?.cancel()
        maxDurationTask = nil
        switch phase {
        case .listening:
            if let run = activeSession {
                await tearDownRun(run, cancelAsrSession: true)
                activeSession = nil
            }
            observer.onLevels(Array(repeating: 0, count: 7))
            setPhase(.idle)
            scheduleIdleUnload()
        case .transcribing, .polishing:
            engines.llm.cancel()
            if let run = activeProcessingRun {
                await tearDownRun(run, cancelAsrSession: true)
                activeProcessingRun = nil
            }
            setPhase(.idle)
            scheduleIdleUnload()
        case .idle, .done:
            break
        }
    }

    private func tearDownRun(_ run: ActiveRun, cancelAsrSession: Bool) async {
        run.captureHandle?.cancel()
        run.feedTask?.cancel()
        run.ocrTask?.cancel()
        run.asrLoadTask?.cancel()
        run.llmPrepareTask?.cancel()
        if cancelAsrSession {
            await run.asrSession?.cancel()
        }
    }

    public func retry(entry: HistoryEntry) async {
        guard !startingInFlight, let audioPath = entry.audioPath else { return }
        switch phase {
        case .idle, .done:
            dismissTask?.cancel()
            dismissTask = nil
        default:
            return
        }
        let samples: [Int16]
        do {
            samples = try audioStore.load(path: audioPath)
        } catch {
            finishWithError(.storageFailed("audio_read"))
            return
        }
        let settings = settingsStore.load()
        let models: ResolvedModels
        do {
            models = try resolver.resolve(settings: settings)
        } catch let e as MurmurError {
            finishWithError(e)
            return
        } catch {
            finishWithError(.internalError(error.localizedDescription))
            return
        }

        engines.holdActive()
        setPhase(.transcribing)
        let t0 = clock.monotonicMs()
        do {
            _ = try await engines.asr.load(asr: models.asr, vad: models.vad)
            let session = try await engines.asr.startSession(options: AsrSessionOptions(language: settings.language.asrHint))
            await session.feed(PcmChunk(samples: samples, startSample: 0))
            let transcript = try await session.finish()
            let asrMs = clock.monotonicMs() - t0
            let pre = outputGuard.precheck(transcript.text)
            if pre.skip {
                finishWithError(.noSpeech)
                return
            }

            var finalText = pre.transcript
            var cleaned = false
            var cleanupOutcome = "skipped:\(models.llmUnavailableReason ?? "none")"
            var llmMs: Int64 = 0

            if let llm = models.llm {
                setPhase(.polishing)
                let ctx = CtxV2(
                    app: AppInfo(pkg: entry.appBundleId, label: entry.appName, category: AppCategories.category(for: entry.appBundleId)),
                    privacy: Privacy(level: PrivacyLevel.appOnly, reason: PrivacyReason.userSetting)
                )
                let result = await runCleanup(
                    transcript: pre.transcript,
                    llm: llm,
                    prepTask: nil,
                    settings: settings,
                    targetBundleId: entry.appBundleId,
                    ctx: ctx
                )
                if result.empty {
                    finishWithError(.noSpeech)
                    scheduleIdleUnload()
                    return
                }
                finalText = result.text
                cleaned = result.cleaned
                cleanupOutcome = result.outcome
                llmMs = result.durationMs
            }

            let updated = HistoryEntry(
                id: entry.id,
                sessionId: entry.sessionId,
                createdAtMs: entry.createdAtMs,
                appBundleId: entry.appBundleId,
                appName: entry.appName,
                windowTitle: entry.windowTitle,
                rawText: transcript.text,
                finalText: finalText,
                cleaned: cleaned,
                cleanupOutcome: cleanupOutcome,
                status: .copied,
                errorCode: nil,
                durationMs: entry.durationMs,
                speechMs: transcript.speechMs,
                asrMs: asrMs,
                llmMs: llmMs,
                ocrMs: 0,
                totalLatencyMs: clock.monotonicMs() - t0,
                wordsCount: countWords(finalText),
                fillersRemoved: countFillersRemoved(raw: transcript.text, final: finalText),
                asrModelId: models.asrModelId,
                llmModelId: models.llm?.modelId,
                audioPath: entry.audioPath
            )
            try? db.updateHistory(updated)
            inserter.copyToClipboard(finalText)
            observer.onHistoryUpdated()
            if settings.playSounds { feedback.playDone() }
            showDone(.copied(cleaned: cleaned, skipReason: cleaned ? nil : cleanupOutcome), dismissMs: config.copiedDismissMs)
        } catch let e as MurmurError {
            finishWithError(e)
        } catch {
            finishWithError(.asrFailed(error.localizedDescription))
        }
        scheduleIdleUnload()
    }

    public func start(mode: StartMode = .hotkey) async {
        guard !startingInFlight else { return }
        switch phase {
        case .idle, .done:
            break
        case .listening, .transcribing, .polishing:
            return
        }
        startingInFlight = true
        pendingStopAfterStart = false
        pendingCancelAfterStart = false
        defer {
            startingInFlight = false
        }

        dismissTask?.cancel()
        dismissTask = nil
        let settings = settingsStore.load()
        let perms = permissions.check()
        if !perms.microphone {
            let granted = await permissions.requestMicrophone()
            if pendingCancelAfterStart { return }
            if !granted {
                finishWithError(.micPermissionDenied)
                return
            }
        }

        let target: A11ySnapshot?
        if mode == .inAppPractice {
            target = A11ySnapshot(
                bundleId: DefaultContextAssembler.ownBundleId,
                appName: "Murmac Practice",
                windowTitle: "Practice",
                field: FieldSnapshot(role: "AXTextArea", isEditable: true),
                capturedAtMs: clock.nowMs()
            )
        } else {
            target = await targetReader.snapshot()
        }
        if pendingCancelAfterStart { return }

        let ctxSettings = ContextSettings(
            useScreen: settings.useScreenContext && perms.screenRecording,
            excludedBundleIds: Set(settings.excludedBundleIds),
            inAppPractice: mode == .inAppPractice
        )
        let snapshotForDecision = target ?? A11ySnapshot(bundleId: "unknown", appName: nil, capturedAtMs: clock.nowMs())
        let decision = contextAssembler.decide(snapshot: snapshotForDecision, settings: ctxSettings)

        if !decision.dictationAllowed {
            if decision.reason == PrivacyReason.passwordField {
                finishWithError(.passwordField)
            } else {
                finishWithError(.appExcluded)
            }
            return
        }

        let models: ResolvedModels
        do {
            models = try resolver.resolve(settings: settings)
        } catch let e as MurmurError {
            finishWithError(e)
            return
        } catch {
            finishWithError(.internalError(error.localizedDescription))
            return
        }

        engines.holdActive()
        if settings.playSounds { feedback.playStart() }

        let handle: CaptureHandlePort
        do {
            handle = try await audioCapture.start { [observer] bars in
                observer.onLevels(bars)
            }
        } catch let e as MurmurError {
            finishWithError(e)
            return
        } catch {
            finishWithError(.micStartFailed(error.localizedDescription))
            return
        }

        if pendingCancelAfterStart {
            handle.cancel()
            scheduleIdleUnload()
            return
        }

        let nowMono = clock.monotonicMs()
        let sessionId = UUID().uuidString.lowercased()
        let run = ActiveRun(
            sessionId: sessionId,
            mode: mode,
            startedAtMs: nowMono,
            settings: settings,
            models: models,
            target: target,
            decision: decision
        )
        run.captureHandle = handle
        activeSession = run
        setPhase(.listening(startedAtMs: nowMono, warn: false))

        // 1. Load ASR + VAD in parallel and begin feeding captured audio
        run.asrLoadTask = Task {
            try await engines.asr.load(asr: models.asr, vad: models.vad)
        }
        run.feedTask = Task { [weak run] in
            guard let run else { return }
            do {
                _ = try await run.asrLoadTask?.value
                if Task.isCancelled { return }
                let session = try await engines.asr.startSession(options: AsrSessionOptions(language: settings.language.asrHint))
                if Task.isCancelled {
                    await session.cancel()
                    return
                }
                run.asrSession = session
                for await chunk in handle.chunks {
                    if Task.isCancelled { break }
                    await session.feed(chunk)
                }
            } catch {
                // Handled during stopAndProcess
            }
        }

        // 2. Warm/load LLM + prefix cache in parallel (when cleanup planned)
        if let llm = models.llm, !decision.skipLlm {
            run.llmPrepareTask = Task {
                try await self.prepareLlm(llm: llm, settings: settings)
            }
        }

        // 3. Delayed screen capture + Apple Vision OCR (~450 ms after press, in RAM only)
        if decision.takeScreenshot, let snap = target {
            let delayNs = UInt64(config.screenshotDelayMs) * 1_000_000
            run.ocrTask = Task {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return (.notTaken, 0) }
                let t0 = clock.monotonicMs()
                do {
                    let img = try await targetReader.screenshot(target: snap)
                    let text = try await engines.ocr.recognize(image: img)
                    return (.text(text), clock.monotonicMs() - t0)
                } catch MurmurError.secureWindow {
                    return (.secureWindow, clock.monotonicMs() - t0)
                } catch {
                    return (.failed, clock.monotonicMs() - t0)
                }
            }
        }

        // 4. Warn at 4:30, auto-stop at 5:00
        maxDurationTask?.cancel()
        let warnNs = UInt64(config.warnAtMs) * 1_000_000
        let remNs = UInt64(max(0, config.maxDurationMs - config.warnAtMs)) * 1_000_000
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: warnNs)
            guard !Task.isCancelled else { return }
            await self?.markWarn()
            try? await Task.sleep(nanoseconds: remNs)
            guard !Task.isCancelled else { return }
            await self?.stopAndProcess()
        }

        // Handle early Hold-to-Talk release that arrived while start() was awaiting permissions/snapshot/mic
        if pendingStopAfterStart {
            pendingStopAfterStart = false
            startingInFlight = false
            await stopAndProcess()
        }
    }

    private func markWarn() {
        if case .listening(let startedAt, false) = phase {
            setPhase(.listening(startedAtMs: startedAt, warn: true))
        }
    }

    public func stopAndProcess() async {
        if startingInFlight {
            pendingStopAfterStart = true
            return
        }
        guard case .listening = phase, let run = activeSession else { return }
        maxDurationTask?.cancel()
        maxDurationTask = nil
        activeSession = nil
        activeProcessingRun = run
        defer {
            if activeProcessingRun === run { activeProcessingRun = nil }
        }

        if run.settings.playSounds { feedback.playStop() }
        observer.onLevels(Array(repeating: 0, count: 7))

        let stoppedMono = clock.monotonicMs()
        setPhase(.transcribing)

        let captureResult: (durationMs: Int64, samples: [Int16])
        if let handle = run.captureHandle {
            captureResult = await handle.stop()
        } else {
            captureResult = (durationMs: 0, samples: [])
        }
        await run.feedTask?.value

        // If user cancelled while stopping/draining
        if case .idle = phase {
            await tearDownRun(run, cancelAsrSession: true)
            return
        }

        let createdAtMs = clock.nowMs()
        var savedAudioPath: String? = nil
        if run.settings.keepAudioHistory && run.settings.historyRetentionDays > 0 && run.mode != .inAppPractice && !captureResult.samples.isEmpty {
            let key = AudioKey.of(createdAtMs: createdAtMs, sessionId: run.sessionId)
            savedAudioPath = try? audioStore.save(samples: captureResult.samples, key: key)
        }

        let transcript: Transcript
        do {
            _ = try await run.asrLoadTask?.value
            let session: AsrSession
            if let existing = run.asrSession {
                session = existing
            } else {
                session = try await engines.asr.startSession(options: AsrSessionOptions(language: run.settings.language.asrHint))
                await session.feed(PcmChunk(samples: captureResult.samples, startSample: 0))
            }
            transcript = try await session.finish()
        } catch let e as MurmurError {
            run.ocrTask?.cancel()
            run.llmPrepareTask?.cancel()
            if e == .cancelled || phase == .idle {
                if let p = savedAudioPath { audioStore.delete(path: p) }
                scheduleIdleUnload()
                return
            }
            recordFailure(run: run, error: e, createdAtMs: createdAtMs, durationMs: captureResult.durationMs, audioPath: savedAudioPath)
            finishWithError(e)
            scheduleIdleUnload()
            return
        } catch {
            run.ocrTask?.cancel()
            run.llmPrepareTask?.cancel()
            if phase == .idle {
                if let p = savedAudioPath { audioStore.delete(path: p) }
                scheduleIdleUnload()
                return
            }
            let err = MurmurError.asrFailed(error.localizedDescription)
            recordFailure(run: run, error: err, createdAtMs: createdAtMs, durationMs: captureResult.durationMs, audioPath: savedAudioPath)
            finishWithError(err)
            scheduleIdleUnload()
            return
        }
        if phase == .idle {
            run.ocrTask?.cancel()
            run.llmPrepareTask?.cancel()
            if let p = savedAudioPath { audioStore.delete(path: p) }
            scheduleIdleUnload()
            return
        }
        let asrMs = clock.monotonicMs() - stoppedMono

        let pre = outputGuard.precheck(transcript.text)
        let tooShort = run.models.asrTraits.streaming == false && transcript.speechMs < config.minSpeechMs && transcript.speechMs > 0
        if pre.skip || tooShort || transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            run.ocrTask?.cancel()
            run.llmPrepareTask?.cancel()
            recordFailure(run: run, error: .noSpeech, createdAtMs: createdAtMs, durationMs: captureResult.durationMs, audioPath: savedAudioPath)
            finishWithError(.noSpeech)
            scheduleIdleUnload()
            return
        }

        // Wait briefly for OCR context (up to contextWaitMs = 800 ms)
        var screenOutcome: ScreenOutcome = run.decision.takeScreenshot ? .failed : .notTaken
        var ocrMs: Int64 = 0
        if let ocrTask = run.ocrTask {
            if let res = await withTimeout(ms: config.contextWaitMs, task: ocrTask) {
                screenOutcome = res.0
                ocrMs = res.1
            } else {
                ocrTask.cancel()
                screenOutcome = .failed
            }
        }

        let ctx = contextAssembler.assemble(
            snapshot: run.target ?? A11ySnapshot(bundleId: "unknown", capturedAtMs: createdAtMs),
            decision: run.decision,
            screen: screenOutcome,
            asrLanguage: transcript.language ?? run.settings.language.asrHint
        )

        var finalText = pre.transcript
        var cleaned = false
        var cleanupOutcome = "skipped:\(run.decision.skipLlm ? "password" : (run.models.llmUnavailableReason ?? "none"))"
        var llmMs: Int64 = 0

        if let llm = run.models.llm, !run.decision.skipLlm {
            setPhase(.polishing)
            let res = await runCleanup(
                transcript: pre.transcript,
                llm: llm,
                prepTask: run.llmPrepareTask,
                settings: run.settings,
                targetBundleId: run.target?.bundleId,
                ctx: ctx
            )
            if case .idle = phase {
                // User cancelled during polishing
                if let p = savedAudioPath { audioStore.delete(path: p) }
                return
            }
            if res.empty {
                recordFailure(run: run, error: .noSpeech, createdAtMs: createdAtMs, durationMs: captureResult.durationMs, audioPath: savedAudioPath)
                finishWithError(.noSpeech)
                scheduleIdleUnload()
                return
            }
            finalText = res.text
            cleaned = res.cleaned
            cleanupOutcome = res.outcome
            llmMs = res.durationMs
        }

        // Defense-in-depth privacy re-check right before delivery:
        // blocks BOTH password fields AND denylisted/excluded apps (e.g. switched to 1Password mid-dictation)
        var deliveryTarget = run.target
        if run.mode != .inAppPractice, let latest = await targetReader.snapshot() {
            let latestDecision = contextAssembler.decide(
                snapshot: latest,
                settings: ContextSettings(
                    useScreen: run.settings.useScreenContext,
                    excludedBundleIds: Set(run.settings.excludedBundleIds),
                    inAppPractice: false
                )
            )
            if !latestDecision.dictationAllowed {
                if let p = savedAudioPath { audioStore.delete(path: p) }
                showDone(.discarded, dismissMs: 400)
                scheduleIdleUnload()
                return
            }
            deliveryTarget = latest
        }

        let totalLatency = clock.monotonicMs() - stoppedMono

        if run.mode == .inAppPractice {
            observer.onInAppDelivery(finalText)
            if run.settings.playSounds { feedback.playDone() }
            showDone(.inserted(cleaned: cleaned, skipReason: cleaned ? nil : cleanupOutcome), dismissMs: config.insertedDismissMs)
            scheduleIdleUnload()
            return
        }

        let insertResult = await inserter.insert(
            text: finalText,
            target: deliveryTarget,
            restoreClipboard: run.settings.restoreClipboard
        )

        let historyStatus: HistoryStatus
        let outcome: DictationOutcome
        let dismissMs: Int64
        switch insertResult {
        case .inserted:
            historyStatus = .inserted
            outcome = .inserted(cleaned: cleaned, skipReason: cleaned ? nil : cleanupOutcome)
            dismissMs = config.insertedDismissMs
        case .copiedOnly:
            historyStatus = .copied
            outcome = .copied(cleaned: cleaned, skipReason: cleaned ? nil : cleanupOutcome)
            dismissMs = config.copiedDismissMs
        case .failed:
            inserter.copyToClipboard(finalText)
            historyStatus = .copied
            outcome = .copied(cleaned: cleaned, skipReason: cleaned ? nil : cleanupOutcome)
            dismissMs = config.copiedDismissMs
        }

        if run.settings.historyRetentionDays > 0 {
            let entry = HistoryEntry(
                sessionId: run.sessionId,
                createdAtMs: createdAtMs,
                appBundleId: deliveryTarget?.bundleId ?? "unknown",
                appName: deliveryTarget?.appName ?? "Unknown App",
                windowTitle: run.settings.useScreenContext ? deliveryTarget?.windowTitle : nil,
                rawText: transcript.text,
                finalText: finalText,
                cleaned: cleaned,
                cleanupOutcome: cleanupOutcome,
                status: historyStatus,
                errorCode: nil,
                durationMs: captureResult.durationMs,
                speechMs: transcript.speechMs,
                asrMs: asrMs,
                llmMs: llmMs,
                ocrMs: ocrMs,
                totalLatencyMs: totalLatency,
                wordsCount: countWords(finalText),
                fillersRemoved: countFillersRemoved(raw: transcript.text, final: finalText),
                asrModelId: run.models.asrModelId,
                llmModelId: run.models.llm?.modelId,
                audioPath: savedAudioPath
            )
            _ = try? db.insertHistory(entry)
            observer.onHistoryUpdated()
        }

        if run.settings.playSounds { feedback.playDone() }
        showDone(outcome, dismissMs: dismissMs)
        scheduleIdleUnload()
    }

    private struct CleanupRunResult {
        let text: String
        let cleaned: Bool
        let outcome: String
        let durationMs: Int64
        let empty: Bool
    }

    private func runCleanup(
        transcript: String,
        llm: ResolvedLlm,
        prepTask: Task<(LoadInfo, PrefixInfo, ResolvedLlm, PromptProfile, String), Error>?,
        settings: AppSettings,
        targetBundleId: String?,
        ctx: CtxV2
    ) async -> CleanupRunResult {
        let t0 = clock.monotonicMs()
        do {
            // 1. Wait for LLM load + prefix prefill up to config.llmReadyWaitMs
            let prepared: (LoadInfo, PrefixInfo, ResolvedLlm, PromptProfile, String)
            let pTask = prepTask ?? Task { try await self.prepareLlm(llm: llm, settings: settings) }
            guard let maybePrepared = try await withThrowingTimeout(ms: config.llmReadyWaitMs, onTimeout: { [engines] in
                engines.llm.cancel()
            }, task: pTask) else {
                return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:llm_not_ready", durationMs: clock.monotonicMs() - t0, empty: false)
            }
            prepared = maybePrepared

            let (loadInfo, prefixInfo, resolvedLlm, profile, sysOverrideApplied) = prepared
            let speed = resolvedLlm.speed ?? config.defaultSpeed[loadInfo.unit] ?? LlmSpeed(prefillTps: 120, decodeTps: 20)
            let plan = CleanupBudget.plan(
                transcriptChars: transcript.count,
                prefixTokens: prefixInfo.tokens,
                nCtx: resolvedLlm.nCtx,
                speed: speed,
                config: config
            )
            guard plan.fits else {
                return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:\(plan.skipReason ?? "too_long")", durationMs: clock.monotonicMs() - t0, empty: false)
            }

            let appTone = targetBundleId.flatMap { settings.perAppTones[$0] }
            let styleOverride = appTone.flatMap { $0 == .categoryDefault ? nil : promptRenderer.toneText($0.rawValue) }
            let rendered = try promptRenderer.render(RenderInput(
                profile: profile,
                template: resolvedLlm.template,
                ctx: ctx,
                transcript: transcript,
                preferences: settings.userPreferences.isEmpty ? nil : settings.userPreferences,
                styleOverride: styleOverride,
                systemOverride: sysOverrideApplied.isEmpty ? nil : sysOverrideApplied
            ))
            let req = LlmRequest(
                suffix: rendered.suffix,
                maxTokens: plan.maxTokens,
                minTokens: plan.minTokens,
                temperature: 0.0,
                repeatPenalty: resolvedLlm.template.hasPrefix("lfm") ? 1.05 : 1.0
            )

            // 2. Enforce adaptive cleanup timeout (plan.timeoutMs) and call engines.llm.cancel() on expiry
            let genTask = Task { try await self.engines.llm.generate(request: req, onPiece: nil) }
            guard let gen = try await withThrowingTimeout(ms: plan.timeoutMs, onTimeout: { [engines] in
                engines.llm.cancel()
            }, task: genTask) else {
                return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:timeout", durationMs: clock.monotonicMs() - t0, empty: false)
            }

            if gen.stats.truncated {
                return CleanupRunResult(text: transcript, cleaned: false, outcome: "fallback:truncated", durationMs: clock.monotonicMs() - t0, empty: false)
            }
            let verdict = outputGuard.guardOutput(transcript: transcript, output: gen.text, ctx: ctx)
            switch verdict.action {
            case .accept:
                return CleanupRunResult(text: verdict.text, cleaned: true, outcome: "accept:\(verdict.reason)", durationMs: clock.monotonicMs() - t0, empty: false)
            case .fallback:
                return CleanupRunResult(text: verdict.text, cleaned: false, outcome: "fallback:\(verdict.reason)", durationMs: clock.monotonicMs() - t0, empty: false)
            case .empty:
                return CleanupRunResult(text: "", cleaned: false, outcome: "empty:\(verdict.reason)", durationMs: clock.monotonicMs() - t0, empty: true)
            }
        } catch MurmurError.llmContextOverflow {
            return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:too_long", durationMs: clock.monotonicMs() - t0, empty: false)
        } catch MurmurError.cancelled {
            return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:timeout", durationMs: clock.monotonicMs() - t0, empty: false)
        } catch {
            return CleanupRunResult(text: transcript, cleaned: false, outcome: "skipped:llm_load", durationMs: clock.monotonicMs() - t0, empty: false)
        }
    }

    private func withThrowingTimeout<T: Sendable>(
        ms: Int64,
        onTimeout: @escaping @Sendable () -> Void,
        task: Task<T, Error>
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, ms)) * 1_000_000)
                onTimeout()
                task.cancel()
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func prepareLlm(llm: ResolvedLlm, settings: AppSettings) async throws -> (LoadInfo, PrefixInfo, ResolvedLlm, PromptProfile, String) {
        let loadInfo: LoadInfo
        do {
            loadInfo = try await engines.llm.load(spec: llm.spec)
        } catch {
            guard let fb = llm.fallbackSpec else { throw error }
            loadInfo = try await engines.llm.load(spec: fb)
        }
        let profile = try promptAssets.profile(name: llm.profileName)
        let sysOverride = PromptEditRules.overrideApplies(profile: profile, overrideBaseProfile: settings.systemPromptOverrideProfile)
            ? settings.systemPromptOverride
            : nil
        let prefixText = try promptRenderer.cachePrefix(
            profile: profile,
            template: llm.template,
            preferences: settings.userPreferences.isEmpty ? nil : settings.userPreferences,
            systemOverride: sysOverride
        )
        let cacheKey = RenderPyPort.sha256Hex("\(llm.modelSha256)|\(loadInfo.unit.rawValue)|\(llm.nCtx)|\(prefixText)")
        let prefixInfo = try await engines.llm.setPrefix(PrefixSpec(text: prefixText, cacheKey: cacheKey))
        return (loadInfo, prefixInfo, llm, profile, sysOverride ?? "")
    }

    private func recordFailure(run: ActiveRun, error: MurmurError, createdAtMs: Int64, durationMs: Int64, audioPath: String?) {
        guard run.settings.historyRetentionDays > 0, run.mode != .inAppPractice else { return }
        let entry = HistoryEntry(
            sessionId: run.sessionId,
            createdAtMs: createdAtMs,
            appBundleId: run.target?.bundleId ?? "unknown",
            appName: run.target?.appName ?? "Unknown App",
            windowTitle: run.settings.useScreenContext ? run.target?.windowTitle : nil,
            rawText: "",
            finalText: "",
            cleaned: false,
            cleanupOutcome: "failed",
            status: .failed,
            errorCode: error.code,
            durationMs: durationMs,
            speechMs: 0,
            asrMs: 0,
            llmMs: 0,
            ocrMs: 0,
            totalLatencyMs: 0,
            wordsCount: 0,
            fillersRemoved: 0,
            asrModelId: run.models.asrModelId,
            llmModelId: run.models.llm?.modelId,
            audioPath: audioPath
        )
        _ = try? db.insertHistory(entry)
        observer.onHistoryUpdated()
    }

    private func finishWithError(_ error: MurmurError) {
        if settingsStore.load().playSounds { feedback.playError() }
        showDone(.failed(error), dismissMs: config.errorDismissMs)
    }

    private func showDone(_ outcome: DictationOutcome, dismissMs: Int64) {
        setPhase(.done(outcome))
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(dismissMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.dismissIfDone()
        }
    }

    private func dismissIfDone() {
        if case .done = phase {
            setPhase(.idle)
        }
    }

    private func setPhase(_ newPhase: DictationPhase) {
        phase = newPhase
        observer.onPhase(newPhase)
    }

    private func scheduleIdleUnload() {
        let sec = max(10, settingsStore.load().idleUnloadSeconds)
        engines.scheduleIdleUnload(afterMs: Int64(sec) * 1000)
    }

    private func countWords(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func countFillersRemoved(raw: String, final: String) -> Int {
        let f = outputGuard.fillers
        let rawCount = raw.lowercased().split { !$0.isLetter && $0 != "-" }.filter { f.contains(String($0)) }.count
        let finalCount = final.lowercased().split { !$0.isLetter && $0 != "-" }.filter { f.contains(String($0)) }.count
        return max(0, rawCount - finalCount)
    }

    private func withTimeout<T: Sendable>(ms: Int64, task: Task<T, Never>) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    await task.value
                } onCancel: {
                    task.cancel()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(1, ms)) * 1_000_000)
                task.cancel()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
