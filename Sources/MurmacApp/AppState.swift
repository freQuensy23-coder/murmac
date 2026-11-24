import AppKit
import Combine
import CryptoKit
import Foundation
import MurmacCore
import MurmacInfer
import MurmacPlatform
import SwiftUI

public enum AppTab: String, CaseIterable, Identifiable {
    case history
    case dashboard
    case models
    case settings

    public var id: String { rawValue }
}

@MainActor
public final class AppState: ObservableObject {
    // Dependencies
    public let catalog: CatalogDocument
    public let storage: ModelStorage
    public let downloader: ModelDownloader
    public let settingsStore: SettingsStore
    public let db: SqliteStore
    public let engines: LocalEngines
    public let audioStore: MacAudioStore
    public let permissions: MacPermissions
    public let benchmarkRunner: BenchmarkRunner
    public let promptAssets: BundlePromptAssets
    public let promptRenderer: RenderPyPort
    public private(set) var orchestrator: DictationOrchestrator!
    public private(set) var hotkeyMonitor: HotkeyMonitor!

    // Published UI state
    @Published public var selectedTab: AppTab = .history
    @Published public var showOnboarding: Bool
    @Published public var showPracticeSheet: Bool = false
    @Published public var practiceText: String = ""

    @Published public var settings: AppSettings
    @Published public var phase: DictationPhase = .idle
    @Published public var levels: [Float] = Array(repeating: 0, count: 7)
    @Published public var permissionSnapshot: PermissionSnapshot
    @Published public var history: [HistoryEntry] = []
    @Published public var benchmarks: [BenchmarkRecord] = []
    @Published public var customModels: [CustomLlmModel] = []
    @Published public var installStates: [String: InstallState] = [:]
    @Published public var asrProbe: EngineProbe?
    @Published public var llmProbe: EngineProbe?
    @Published public var hotkeyActive: Bool = false
    @Published public var runningBenchmarkId: String?

    public var l10n: L10n { L10n(uiLanguage: settings.uiLanguage) }

    private let recordingFlag = RecordingFlag()
    private var currentSearchQuery: String = ""
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        MurmacFonts.registerIfNeeded()
        self.catalog = (try? CatalogLoader.loadBundled()) ?? CatalogDocument(
            schema: 1, catalogVersion: "fallback", generated: nil,
            defaults: CatalogDefaults(asr: [:], vad: "silero-vad-v5"), packs: [], models: []
        )
        self.storage = ModelStorage()
        self.downloader = ModelDownloader(storage: storage)
        self.settingsStore = SettingsStore()
        self.db = (try? SqliteStore()) ?? (try! SqliteStore(path: ":memory:"))
        self.engines = LocalEngines()
        self.audioStore = MacAudioStore()
        self.permissions = MacPermissions()
        self.benchmarkRunner = BenchmarkRunner(engines: engines, storage: storage, db: db)
        self.promptAssets = BundlePromptAssets()
        self.promptRenderer = RenderPyPort(assets: promptAssets)

        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.showOnboarding = !loadedSettings.onboardingCompleted
        self.permissionSnapshot = permissions.check()

        let resolver = DefaultModelResolver(catalog: catalog, storage: storage, db: db)
        self.orchestrator = DictationOrchestrator(
            engines: engines,
            audioCapture: MacAudioCapture(),
            targetReader: MacTargetReader(),
            inserter: MacTextInserter(),
            audioStore: audioStore,
            permissions: permissions,
            feedback: MacFeedback(),
            resolver: resolver,
            settingsStore: settingsStore,
            db: db,
            promptAssets: promptAssets,
            promptRenderer: promptRenderer,
            observer: .init(
                onPhase: { [weak self] newPhase in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.phase = newPhase
                        if case .listening = newPhase {
                            self.recordingFlag.set(true)
                        } else {
                            self.recordingFlag.set(false)
                        }
                    }
                },
                onLevels: { [weak self] bars in
                    Task { @MainActor [weak self] in
                        self?.levels = bars
                    }
                },
                onHistoryUpdated: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.reloadHistory()
                    }
                },
                onInAppDelivery: { [weak self] text in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.practiceText.isEmpty {
                            self.practiceText = text
                        } else {
                            self.practiceText += (self.practiceText.hasSuffix(" ") || self.practiceText.hasSuffix("\n") ? "" : " ") + text
                        }
                    }
                }
            )
        )

        self.hotkeyMonitor = HotkeyMonitor(
            config: loadedSettings.hotkey,
            callbacks: .init(
                onToggle: { [weak self] in
                    Task { [weak self] in await self?.orchestrator.toggle(mode: .hotkey) }
                },
                onHoldStart: { [weak self] in
                    Task { [weak self] in await self?.orchestrator.start(mode: .hotkey) }
                },
                onHoldStop: { [weak self] in
                    Task { [weak self] in await self?.orchestrator.stopAndProcess() }
                },
                onCancel: { [weak self] in
                    Task { [weak self] in await self?.orchestrator.cancel() }
                },
                isRecording: { [recordingFlag] in recordingFlag.get() }
            )
        )

        refreshInstallStates()
        autoSelectInstalledModelsIfUnset()
        reloadHistory()
        reloadBenchmarks()
        reloadCustomModels()
        applyRetentionIfNeeded()

        // Only create the global CGEventTap once Accessibility is granted;
        // otherwise macOS pops an unrelated "Input Monitoring" dialog during onboarding.
        if permissionSnapshot.accessibility {
            startHotkeyIfPossible()
        }

        // Automatically refresh permission status whenever the user returns from System Settings.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
            .store(in: &cancellables)

        Task {
            await probeEngines()
        }
    }

    private func autoSelectInstalledModelsIfUnset() {
        var changed = false
        var updated = settings
        let selectedAsrInstalled: Bool = {
            guard let m = catalog.models.first(where: { $0.id == updated.selectedAsrModelId }),
                  let art = m.preferredArtifact else { return false }
            return storage.isInstalled(art)
        }()
        if !selectedAsrInstalled {
            if let asr = catalog.models.first(where: { $0.kind == .asr && ($0.preferredArtifact.map { storage.isInstalled($0) } ?? false) }) {
                updated.selectedAsrModelId = asr.id
                changed = true
            }
        }
        let selectedLlmInstalled: Bool = {
            guard let lid = updated.selectedLlmModelId,
                  let m = catalog.models.first(where: { $0.id == lid }),
                  let art = m.preferredArtifact else { return false }
            return storage.isInstalled(art)
        }()
        if !selectedLlmInstalled && updated.cleanupEnabled {
            if let llm = catalog.models.first(where: { $0.kind == .llm && ($0.preferredArtifact.map { storage.isInstalled($0) } ?? false) }) {
                updated.selectedLlmModelId = llm.id
                changed = true
            }
        }
        if changed {
            settingsStore.save(updated)
            settings = updated
        }
    }

    public func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", bundleURL.path]
        try? proc.run()
        NSApp.terminate(nil)
    }

    public func probeEngines() async {
        asrProbe = await engines.asr.probe()
        llmProbe = await engines.llm.probe()
    }

    public func refreshPermissions() {
        permissionSnapshot = permissions.check()
        if permissionSnapshot.accessibility && !hotkeyActive {
            startHotkeyIfPossible()
        }
    }

    public func startHotkeyIfPossible() {
        guard permissions.check().accessibility else {
            hotkeyActive = false
            return
        }
        hotkeyActive = hotkeyMonitor.start()
    }

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        let updated = settingsStore.update(mutate)
        self.settings = updated
        hotkeyMonitor.updateConfig(updated.hotkey)
        applyRetentionIfNeeded()
    }

    public func toggleDictation(mode: StartMode = .menuBar) {
        Task {
            await orchestrator.toggle(mode: mode)
        }
    }

    public func cancelDictation() {
        Task {
            await orchestrator.cancel()
        }
    }

    public func retry(entry: HistoryEntry) {
        Task {
            await orchestrator.retry(entry: entry)
        }
    }

    public func reloadHistory(search: String? = nil) {
        if let search {
            currentSearchQuery = search
        }
        let q = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        history = (try? db.fetchHistory(search: q.isEmpty ? nil : q)) ?? []
    }

    public func deleteHistory(ids: [Int64]) {
        if let paths = try? db.deleteHistory(ids: ids) {
            for p in paths { audioStore.delete(path: p) }
        }
        reloadHistory()
    }

    public func reloadBenchmarks() {
        benchmarks = (try? db.fetchBenchmarks()) ?? []
    }

    public func reloadCustomModels() {
        customModels = (try? db.fetchCustomModels()) ?? []
    }

    public func applyRetentionIfNeeded() {
        let days = settings.historyRetentionDays
        guard days >= 0 else { return }
        let cutoffMs: Int64
        if days == 0 {
            cutoffMs = Int64.max
        } else {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            cutoffMs = nowMs - Int64(days) * 86_400_000
        }
        if let paths = try? db.pruneHistory(olderThanMs: cutoffMs) {
            for p in paths { audioStore.delete(path: p) }
            if !paths.isEmpty { reloadHistory() }
        }
    }

    public func refreshInstallStates() {
        var map: [String: InstallState] = [:]
        for m in catalog.models {
            for a in m.artifacts {
                if case .downloading = installStates[a.id] {
                    map[a.id] = installStates[a.id]
                } else if storage.isInstalled(a) {
                    map[a.id] = .installed(dir: storage.artifactDir(a.id).path)
                } else {
                    map[a.id] = .notInstalled
                }
            }
        }
        installStates = map
    }

    public func download(artifact: CatalogArtifact) {
        installStates[artifact.id] = .downloading(progress: 0, bytesReceived: 0, totalBytes: artifact.totalBytes)
        Task {
            do {
                _ = try await downloader.download(artifact: artifact) { [weak self] st in
                    Task { @MainActor [weak self] in
                        self?.installStates[artifact.id] = st
                    }
                }
                refreshInstallStates()
            } catch {
                if case MurmurError.cancelled = error {
                    installStates[artifact.id] = .notInstalled
                } else {
                    installStates[artifact.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func cancelDownload(artifactId: String) {
        Task {
            await downloader.cancel(artifactId: artifactId)
            installStates[artifactId] = .notInstalled
        }
    }

    public func deleteArtifact(_ artifact: CatalogArtifact) {
        try? storage.delete(artifact.id)
        refreshInstallStates()
    }

    public func downloadPack(_ pack: ModelPack) {
        for modelId in pack.items {
            guard let model = catalog.models.first(where: { $0.id == modelId }),
                  let art = model.preferredArtifact else { continue }
            if !storage.isInstalled(art) {
                download(artifact: art)
            }
            if model.kind == .asr {
                updateSettings { $0.selectedAsrModelId = model.id }
            } else if model.kind == .llm {
                updateSettings {
                    $0.selectedLlmModelId = model.id
                    $0.cleanupEnabled = true
                }
            }
        }
        if pack.id == "speech-only" {
            updateSettings {
                $0.selectedLlmModelId = nil
                $0.cleanupEnabled = false
            }
        }
    }

    public func runBenchmark(model: CatalogModel, artifact: CatalogArtifact) {
        guard runningBenchmarkId == nil else { return }
        runningBenchmarkId = artifact.id
        Task {
            defer { Task { @MainActor in self.runningBenchmarkId = nil } }
            do {
                if model.kind == .llm {
                    let unit: ComputeUnit = settings.llmUnitPreference == .cpu ? .cpu : .gpu
                    _ = try await benchmarkRunner.benchmarkLlm(model: model, artifact: artifact, unit: unit)
                } else if model.kind == .asr {
                    let vadModel = catalog.models.first { $0.id == catalog.defaults.vad && $0.kind == .vad }
                    let vadSpec = vadModel.flatMap { vm -> LoadSpec? in
                        guard let va = vm.preferredArtifact, storage.isInstalled(va) else { return nil }
                        return storage.loadSpec(for: vm, artifact: va, unit: .cpu, threads: 1)
                    }
                    _ = try await benchmarkRunner.benchmarkAsr(model: model, artifact: artifact, vadSpec: vadSpec)
                }
                await MainActor.run { self.reloadBenchmarks() }
            } catch {
                // Handled silently or surfaced in UI
            }
        }
    }

    public func importCustomGguf(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let headerData = try handle.read(upToCount: 512 * 1024) ?? Data()
        let meta = try GgufHeader.parse(headerData)
        let arch = meta.string("general.architecture")
        let name = meta.string("general.name") ?? url.deletingPathExtension().lastPathComponent
        let tpl = GgufTemplates.templateForArchitecture(arch)
        let profile = GgufTemplates.promptProfile(from: meta)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var hasher = SHA256()
        hasher.update(data: headerData.prefix(64 * 1024))
        hasher.update(data: Data("\(size)|\(Int64(mtime))".utf8))
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let custom = CustomLlmModel(
            id: "custom:\(UUID().uuidString.prefix(8).lowercased())",
            displayName: name,
            filePath: url.path,
            sha256: digest,
            template: tpl,
            promptProfile: profile,
            nCtx: 7168,
            sizeBytes: size,
            addedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0)
        )
        try db.saveCustomModel(custom)
        reloadCustomModels()
        updateSettings {
            $0.selectedLlmModelId = custom.id
            $0.cleanupEnabled = true
        }
    }

    public func deleteCustomModel(id: String) {
        try? db.deleteCustomModel(id: id)
        if settings.selectedLlmModelId == id {
            updateSettings { $0.selectedLlmModelId = nil }
        }
        reloadCustomModels()
    }

    public func completeOnboarding() {
        updateSettings { $0.onboardingCompleted = true }
        showOnboarding = false
    }
}

private final class RecordingFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ v: Bool) { lock.withLock { value = v } }
    func get() -> Bool { lock.withLock { value } }
}
