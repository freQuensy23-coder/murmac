import Foundation
import SQLite3

public enum HotkeyMode: String, Codable, Hashable, Sendable, CaseIterable {
    case toggle
    case hold
}

/// Configurable global hotkey (default: Right Command + Right Option in toggle mode).
public struct HotkeyConfig: Codable, Equatable, Hashable, Sendable {
    public var mode: HotkeyMode
    /// Modifier-only shortcut: Right Command (0x10) + Right Option (0x40).
    public var useRightCommandOption: Bool
    /// Optional custom keyCode + modifierFlags when user rebinds in Settings.
    public var customKeyCode: UInt16?
    public var customModifierMask: UInt64?

    public init(
        mode: HotkeyMode = .toggle,
        useRightCommandOption: Bool = true,
        customKeyCode: UInt16? = nil,
        customModifierMask: UInt64? = nil
    ) {
        self.mode = mode
        self.useRightCommandOption = useRightCommandOption
        self.customKeyCode = customKeyCode
        self.customModifierMask = customModifierMask
    }

    public var displayLabel: String {
        if useRightCommandOption {
            return "Right ⌘ + Right ⌥"
        }
        return Self.formatCustom(keyCode: customKeyCode, mask: customModifierMask)
    }

    public static func formatCustom(keyCode: UInt16?, mask: UInt64?) -> String {
        var parts: [String] = []
        let m = mask ?? 0
        if (m & (1 << 18)) != 0 { parts.append("⌃") }
        if (m & (1 << 19)) != 0 { parts.append("⌥") }
        if (m & (1 << 17)) != 0 { parts.append("⇧") }
        if (m & (1 << 20)) != 0 { parts.append("⌘") }
        if let code = keyCode {
            parts.append(keyCodeName(code))
        }
        return parts.isEmpty ? "Right ⌘ + Right ⌥" : parts.joined(separator: " + ")
    }

    private static func keyCodeName(_ code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
        case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
        case 45: return "N"; case 46: return "M"
        default: return "Key(\(code))"
        }
    }
}

public enum UiLanguage: String, Codable, Hashable, Sendable, CaseIterable {
    case system
    case en
    case ru

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: DictationLanguage
    public var selectedAsrModelId: String
    public var selectedLlmModelId: String? // nil = speech only (no cleanup)
    public var llmUnitPreference: UnitPreference
    public var cleanupEnabled: Bool
    public var useScreenContext: Bool
    public var excludedBundleIds: [String]
    public var perAppTones: [String: AppTone]
    public var userPreferences: String
    public var systemPromptOverride: String?
    public var systemPromptOverrideProfile: String?
    public var hotkey: HotkeyConfig
    public var showHud: Bool
    public var playSounds: Bool
    public var restoreClipboard: Bool
    public var keepAudioHistory: Bool
    public var historyRetentionDays: Int // 0 = don't keep, 1, 7, 30, 365
    public var idleUnloadSeconds: Int
    public var typingSpeedWpm: Int
    public var onboardingCompleted: Bool
    public var uiLanguage: UiLanguage

    public init(
        language: DictationLanguage = .auto,
        selectedAsrModelId: String = "parakeet-tdt-0.6b-v3",
        selectedLlmModelId: String? = "murmur-cleanup-qwen3.5-2b",
        llmUnitPreference: UnitPreference = .auto,
        cleanupEnabled: Bool = true,
        useScreenContext: Bool = true,
        excludedBundleIds: [String] = [],
        perAppTones: [String: AppTone] = [:],
        userPreferences: String = "",
        systemPromptOverride: String? = nil,
        systemPromptOverrideProfile: String? = nil,
        hotkey: HotkeyConfig = HotkeyConfig(),
        showHud: Bool = true,
        playSounds: Bool = true,
        restoreClipboard: Bool = true,
        keepAudioHistory: Bool = true,
        historyRetentionDays: Int = 30,
        idleUnloadSeconds: Int = 60,
        typingSpeedWpm: Int = 45,
        onboardingCompleted: Bool = false,
        uiLanguage: UiLanguage = .system
    ) {
        self.language = language
        self.selectedAsrModelId = selectedAsrModelId
        self.selectedLlmModelId = selectedLlmModelId
        self.llmUnitPreference = llmUnitPreference
        self.cleanupEnabled = cleanupEnabled
        self.useScreenContext = useScreenContext
        self.excludedBundleIds = excludedBundleIds
        self.perAppTones = perAppTones
        self.userPreferences = userPreferences
        self.systemPromptOverride = systemPromptOverride
        self.systemPromptOverrideProfile = systemPromptOverrideProfile
        self.hotkey = hotkey
        self.showHud = showHud
        self.playSounds = playSounds
        self.restoreClipboard = restoreClipboard
        self.keepAudioHistory = keepAudioHistory
        self.historyRetentionDays = historyRetentionDays
        self.idleUnloadSeconds = idleUnloadSeconds
        self.typingSpeedWpm = typingSpeedWpm
        self.onboardingCompleted = onboardingCompleted
        self.uiLanguage = uiLanguage
    }
}

public enum HistoryStatus: String, Codable, Equatable, Sendable {
    case inserted
    case copied
    case failed
}

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let sessionId: String
    public let createdAtMs: Int64
    public let appBundleId: String
    public let appName: String
    public let windowTitle: String?
    public let rawText: String
    public let finalText: String
    public let cleaned: Bool
    public let cleanupOutcome: String
    public let status: HistoryStatus
    public let errorCode: String?
    public let durationMs: Int64
    public let speechMs: Int64
    public let asrMs: Int64
    public let llmMs: Int64
    public let ocrMs: Int64
    public let totalLatencyMs: Int64
    public let wordsCount: Int
    public let fillersRemoved: Int
    public let asrModelId: String
    public let llmModelId: String?
    public let audioPath: String?

    public init(
        id: Int64 = 0,
        sessionId: String,
        createdAtMs: Int64,
        appBundleId: String,
        appName: String,
        windowTitle: String? = nil,
        rawText: String,
        finalText: String,
        cleaned: Bool,
        cleanupOutcome: String,
        status: HistoryStatus,
        errorCode: String? = nil,
        durationMs: Int64,
        speechMs: Int64,
        asrMs: Int64,
        llmMs: Int64,
        ocrMs: Int64,
        totalLatencyMs: Int64,
        wordsCount: Int,
        fillersRemoved: Int,
        asrModelId: String,
        llmModelId: String?,
        audioPath: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.createdAtMs = createdAtMs
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.rawText = rawText
        self.finalText = finalText
        self.cleaned = cleaned
        self.cleanupOutcome = cleanupOutcome
        self.status = status
        self.errorCode = errorCode
        self.durationMs = durationMs
        self.speechMs = speechMs
        self.asrMs = asrMs
        self.llmMs = llmMs
        self.ocrMs = ocrMs
        self.totalLatencyMs = totalLatencyMs
        self.wordsCount = wordsCount
        self.fillersRemoved = fillersRemoved
        self.asrModelId = asrModelId
        self.llmModelId = llmModelId
        self.audioPath = audioPath
    }
}

public struct BenchmarkRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String // "\(artifactId)@\(unit.rawValue)"
    public let artifactId: String
    public let kind: ModelKind
    public let unit: ComputeUnit
    public let measuredAtMs: Int64
    public let loadMs: Int64
    public let prefillTps: Double?
    public let decodeTps: Double?
    public let asrRtf: Double?
    public let wer: Double?
    public let deviceName: String

    public init(
        artifactId: String,
        kind: ModelKind,
        unit: ComputeUnit,
        measuredAtMs: Int64,
        loadMs: Int64,
        prefillTps: Double? = nil,
        decodeTps: Double? = nil,
        asrRtf: Double? = nil,
        wer: Double? = nil,
        deviceName: String
    ) {
        self.id = "\(artifactId)@\(unit.rawValue)"
        self.artifactId = artifactId
        self.kind = kind
        self.unit = unit
        self.measuredAtMs = measuredAtMs
        self.loadMs = loadMs
        self.prefillTps = prefillTps
        self.decodeTps = decodeTps
        self.asrRtf = asrRtf
        self.wer = wer
        self.deviceName = deviceName
    }
}

public struct DailyWordCount: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let words: Int

    public init(id: String, label: String, words: Int) {
        self.id = id
        self.label = label
        self.words = words
    }
}

public struct DashboardStats: Equatable, Sendable {
    public let todayWords: Int
    public let totalWords: Int
    public let totalDictations: Int
    public let speakingMinutes: Double
    public let timeSavedMinutes: Double
    public let averageWpm: Int
    public let fillersRemoved: Int
    public let dailyWords: [DailyWordCount]

    public static func compute(entries: [HistoryEntry], typingSpeedWpm: Int, nowMs: Int64) -> DashboardStats {
        let valid = entries.filter { $0.status != .failed }
        let cal = Calendar.current
        let nowDate = Date(timeIntervalSince1970: Double(nowMs) / 1000.0)
        let startOfToday = cal.startOfDay(for: nowDate)

        var todayWords = 0
        var totalWords = 0
        var totalSpeechMs: Int64 = 0
        var fillers = 0

        for e in valid {
            totalWords += e.wordsCount
            totalSpeechMs += e.speechMs > 0 ? e.speechMs : e.durationMs
            fillers += e.fillersRemoved
            let d = Date(timeIntervalSince1970: Double(e.createdAtMs) / 1000.0)
            if d >= startOfToday {
                todayWords += e.wordsCount
            }
        }

        let speakingMinutes = Double(totalSpeechMs) / 60_000.0
        let typingMinutes = Double(totalWords) / Double(max(10, typingSpeedWpm))
        let timeSaved = max(0.0, typingMinutes - speakingMinutes)
        let avgWpm = speakingMinutes > 0.05 ? Int(round(Double(totalWords) / speakingMinutes)) : 0

        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        var daily: [DailyWordCount] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: startOfToday),
                  let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayWords = valid.reduce(0) { acc, e in
                let d = Date(timeIntervalSince1970: Double(e.createdAtMs) / 1000.0)
                return (d >= day && d < nextDay) ? (acc + e.wordsCount) : acc
            }
            let lbl = fmt.string(from: day)
            daily.append(DailyWordCount(id: "\(offset)-\(lbl)", label: lbl, words: dayWords))
        }

        return DashboardStats(
            todayWords: todayWords,
            totalWords: totalWords,
            totalDictations: valid.count,
            speakingMinutes: speakingMinutes,
            timeSavedMinutes: timeSaved,
            averageWpm: avgWpm,
            fillersRemoved: fillers,
            dailyWords: daily
        )
    }
}

/// JSON-backed Settings store in `~/Library/Application Support/Murmac/settings.json`.
public final class SettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var current: AppSettings

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Murmac", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("settings.json")
        }
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.current = decoded
        } else {
            self.current = AppSettings()
        }
    }

    public func load() -> AppSettings {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func save(_ settings: AppSettings) {
        lock.lock()
        current = settings
        let url = fileURL
        lock.unlock()
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult
    public func update(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        lock.lock()
        mutate(&current)
        let copy = current
        let url = fileURL
        lock.unlock()
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: url, options: .atomic)
        }
        return copy
    }
}

/// Native SQLite3 persistence for History, Benchmarks, and Custom GGUF models.
public final class SqliteStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let path: String

    public init(path: String? = nil) throws {
        if let path {
            self.path = path
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Murmac", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.path = dir.appendingPathComponent("murmac.sqlite").path
        }
        guard sqlite3_open(self.path, &db) == SQLITE_OK else {
            throw MurmurError.storageFailed("sqlite_open_failed")
        }
        sqlite3_busy_timeout(db, 5_000)
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "rc=\(rc)"
            sqlite3_free(errMsg)
            throw MurmurError.storageFailed("sqlite_exec:\(msg)")
        }
    }

    private func migrate() throws {
        try exec("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            app_bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            window_title TEXT,
            raw_text TEXT NOT NULL,
            final_text TEXT NOT NULL,
            cleaned INTEGER NOT NULL,
            cleanup_outcome TEXT NOT NULL,
            status TEXT NOT NULL,
            error_code TEXT,
            duration_ms INTEGER NOT NULL,
            speech_ms INTEGER NOT NULL,
            asr_ms INTEGER NOT NULL,
            llm_ms INTEGER NOT NULL,
            ocr_ms INTEGER NOT NULL,
            total_latency_ms INTEGER NOT NULL,
            words_count INTEGER NOT NULL,
            fillers_removed INTEGER NOT NULL,
            asr_model_id TEXT NOT NULL,
            llm_model_id TEXT,
            audio_path TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_history_created ON history(created_at_ms DESC);

        CREATE TABLE IF NOT EXISTS benchmarks (
            id TEXT PRIMARY KEY,
            artifact_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            unit TEXT NOT NULL,
            measured_at_ms INTEGER NOT NULL,
            load_ms INTEGER NOT NULL,
            prefill_tps REAL,
            decode_tps REAL,
            asr_rtf REAL,
            wer REAL,
            device_name TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS custom_models (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            sha256 TEXT NOT NULL,
            template TEXT NOT NULL,
            prompt_profile TEXT NOT NULL,
            n_ctx INTEGER NOT NULL,
            size_bytes INTEGER NOT NULL,
            added_at_ms INTEGER NOT NULL
        );
        """)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func colText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard sqlite3_column_type(stmt, idx) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: ptr)
    }

    @discardableResult
    public func insertHistory(_ entry: HistoryEntry) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        INSERT INTO history (
            session_id, created_at_ms, app_bundle_id, app_name, window_title,
            raw_text, final_text, cleaned, cleanup_outcome, status, error_code,
            duration_ms, speech_ms, asr_ms, llm_ms, ocr_ms, total_latency_ms,
            words_count, fillers_removed, asr_model_id, llm_model_id, audio_path
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_insert_history")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entry.sessionId)
        sqlite3_bind_int64(stmt, 2, entry.createdAtMs)
        bindText(stmt, 3, entry.appBundleId)
        bindText(stmt, 4, entry.appName)
        bindText(stmt, 5, entry.windowTitle)
        bindText(stmt, 6, entry.rawText)
        bindText(stmt, 7, entry.finalText)
        sqlite3_bind_int(stmt, 8, entry.cleaned ? 1 : 0)
        bindText(stmt, 9, entry.cleanupOutcome)
        bindText(stmt, 10, entry.status.rawValue)
        bindText(stmt, 11, entry.errorCode)
        sqlite3_bind_int64(stmt, 12, entry.durationMs)
        sqlite3_bind_int64(stmt, 13, entry.speechMs)
        sqlite3_bind_int64(stmt, 14, entry.asrMs)
        sqlite3_bind_int64(stmt, 15, entry.llmMs)
        sqlite3_bind_int64(stmt, 16, entry.ocrMs)
        sqlite3_bind_int64(stmt, 17, entry.totalLatencyMs)
        sqlite3_bind_int(stmt, 18, Int32(entry.wordsCount))
        sqlite3_bind_int(stmt, 19, Int32(entry.fillersRemoved))
        bindText(stmt, 20, entry.asrModelId)
        bindText(stmt, 21, entry.llmModelId)
        bindText(stmt, 22, entry.audioPath)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MurmurError.storageFailed("step_insert_history")
        }
        return sqlite3_last_insert_rowid(db)
    }

    public func updateHistory(_ entry: HistoryEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        UPDATE history SET
            raw_text = ?, final_text = ?, cleaned = ?, cleanup_outcome = ?,
            status = ?, error_code = ?, asr_ms = ?, llm_ms = ?, total_latency_ms = ?,
            words_count = ?, fillers_removed = ?
        WHERE id = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_update_history")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, entry.rawText)
        bindText(stmt, 2, entry.finalText)
        sqlite3_bind_int(stmt, 3, entry.cleaned ? 1 : 0)
        bindText(stmt, 4, entry.cleanupOutcome)
        bindText(stmt, 5, entry.status.rawValue)
        bindText(stmt, 6, entry.errorCode)
        sqlite3_bind_int64(stmt, 7, entry.asrMs)
        sqlite3_bind_int64(stmt, 8, entry.llmMs)
        sqlite3_bind_int64(stmt, 9, entry.totalLatencyMs)
        sqlite3_bind_int(stmt, 10, Int32(entry.wordsCount))
        sqlite3_bind_int(stmt, 11, Int32(entry.fillersRemoved))
        sqlite3_bind_int64(stmt, 12, entry.id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MurmurError.storageFailed("step_update_history")
        }
    }

    private static func escapeLike(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    public func fetchHistory(search: String? = nil, limit: Int = 500) throws -> [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        let hasQuery = search.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let sql = hasQuery
            ? "SELECT * FROM history WHERE final_text LIKE ? ESCAPE '\\' OR raw_text LIKE ? ESCAPE '\\' OR app_name LIKE ? ESCAPE '\\' ORDER BY created_at_ms DESC LIMIT ?;"
            : "SELECT * FROM history ORDER BY created_at_ms DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_fetch_history")
        }
        defer { sqlite3_finalize(stmt) }
        if hasQuery {
            let escaped = Self.escapeLike(search!.trimmingCharacters(in: .whitespacesAndNewlines))
            let pat = "%\(escaped)%"
            bindText(stmt, 1, pat)
            bindText(stmt, 2, pat)
            bindText(stmt, 3, pat)
            sqlite3_bind_int(stmt, 4, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }
        var out: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(HistoryEntry(
                id: sqlite3_column_int64(stmt, 0),
                sessionId: colText(stmt, 1) ?? "",
                createdAtMs: sqlite3_column_int64(stmt, 2),
                appBundleId: colText(stmt, 3) ?? "",
                appName: colText(stmt, 4) ?? "",
                windowTitle: colText(stmt, 5),
                rawText: colText(stmt, 6) ?? "",
                finalText: colText(stmt, 7) ?? "",
                cleaned: sqlite3_column_int(stmt, 8) != 0,
                cleanupOutcome: colText(stmt, 9) ?? "",
                status: HistoryStatus(rawValue: colText(stmt, 10) ?? "") ?? .copied,
                errorCode: colText(stmt, 11),
                durationMs: sqlite3_column_int64(stmt, 12),
                speechMs: sqlite3_column_int64(stmt, 13),
                asrMs: sqlite3_column_int64(stmt, 14),
                llmMs: sqlite3_column_int64(stmt, 15),
                ocrMs: sqlite3_column_int64(stmt, 16),
                totalLatencyMs: sqlite3_column_int64(stmt, 17),
                wordsCount: Int(sqlite3_column_int(stmt, 18)),
                fillersRemoved: Int(sqlite3_column_int(stmt, 19)),
                asrModelId: colText(stmt, 20) ?? "",
                llmModelId: colText(stmt, 21),
                audioPath: colText(stmt, 22)
            ))
        }
        return out
    }

    public func deleteHistory(ids: [Int64]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE;")
        do {
            var audioPaths: [String] = []
            // Chunk into batches of <= 500 to stay well under SQLITE_MAX_VARIABLE_NUMBER (999)
            for start in stride(from: 0, to: ids.count, by: 500) {
                let batch = Array(ids[start..<min(start + 500, ids.count)])
                let placeholders = batch.map { _ in "?" }.joined(separator: ",")
                var sel: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT audio_path FROM history WHERE id IN (\(placeholders));", -1, &sel, nil) == SQLITE_OK else {
                    throw MurmurError.storageFailed("prepare_select_delete_history")
                }
                defer { sqlite3_finalize(sel) }
                for (i, id) in batch.enumerated() { sqlite3_bind_int64(sel, Int32(i + 1), id) }
                while sqlite3_step(sel) == SQLITE_ROW {
                    if let p = colText(sel, 0) { audioPaths.append(p) }
                }

                var del: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM history WHERE id IN (\(placeholders));", -1, &del, nil) == SQLITE_OK else {
                    throw MurmurError.storageFailed("prepare_delete_history")
                }
                defer { sqlite3_finalize(del) }
                for (i, id) in batch.enumerated() { sqlite3_bind_int64(del, Int32(i + 1), id) }
                guard sqlite3_step(del) == SQLITE_DONE else {
                    throw MurmurError.storageFailed("step_delete_history")
                }
            }
            try exec("COMMIT;")
            return audioPaths
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func pruneHistory(olderThanMs cutoffMs: Int64) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE;")
        do {
            var paths: [String] = []
            var sel: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT audio_path FROM history WHERE created_at_ms < ?;", -1, &sel, nil) == SQLITE_OK else {
                throw MurmurError.storageFailed("prepare_select_prune")
            }
            defer { sqlite3_finalize(sel) }
            sqlite3_bind_int64(sel, 1, cutoffMs)
            while sqlite3_step(sel) == SQLITE_ROW {
                if let p = colText(sel, 0) { paths.append(p) }
            }

            var del: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM history WHERE created_at_ms < ?;", -1, &del, nil) == SQLITE_OK else {
                throw MurmurError.storageFailed("prepare_prune")
            }
            defer { sqlite3_finalize(del) }
            sqlite3_bind_int64(del, 1, cutoffMs)
            guard sqlite3_step(del) == SQLITE_DONE else {
                throw MurmurError.storageFailed("step_prune")
            }
            try exec("COMMIT;")
            return paths
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func saveBenchmark(_ rec: BenchmarkRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        INSERT OR REPLACE INTO benchmarks (
            id, artifact_id, kind, unit, measured_at_ms, load_ms, prefill_tps, decode_tps, asr_rtf, wer, device_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_save_bench")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, rec.id)
        bindText(stmt, 2, rec.artifactId)
        bindText(stmt, 3, rec.kind.rawValue)
        bindText(stmt, 4, rec.unit.rawValue)
        sqlite3_bind_int64(stmt, 5, rec.measuredAtMs)
        sqlite3_bind_int64(stmt, 6, rec.loadMs)
        if let v = rec.prefillTps { sqlite3_bind_double(stmt, 7, v) } else { sqlite3_bind_null(stmt, 7) }
        if let v = rec.decodeTps { sqlite3_bind_double(stmt, 8, v) } else { sqlite3_bind_null(stmt, 8) }
        if let v = rec.asrRtf { sqlite3_bind_double(stmt, 9, v) } else { sqlite3_bind_null(stmt, 9) }
        if let v = rec.wer { sqlite3_bind_double(stmt, 10, v) } else { sqlite3_bind_null(stmt, 10) }
        bindText(stmt, 11, rec.deviceName)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MurmurError.storageFailed("step_save_bench")
        }
    }

    public func fetchBenchmarks() throws -> [BenchmarkRecord] {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM benchmarks ORDER BY measured_at_ms DESC;", -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_fetch_bench")
        }
        defer { sqlite3_finalize(stmt) }
        var out: [BenchmarkRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let kind = ModelKind(rawValue: colText(stmt, 2) ?? "") ?? .llm
            let unit = ComputeUnit(rawValue: colText(stmt, 3) ?? "") ?? .cpu
            let pp: Double? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6)
            let tg: Double? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 7)
            let rtf: Double? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 8)
            let wer: Double? = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9)
            out.append(BenchmarkRecord(
                artifactId: colText(stmt, 1) ?? "",
                kind: kind,
                unit: unit,
                measuredAtMs: sqlite3_column_int64(stmt, 4),
                loadMs: sqlite3_column_int64(stmt, 5),
                prefillTps: pp,
                decodeTps: tg,
                asrRtf: rtf,
                wer: wer,
                deviceName: colText(stmt, 10) ?? ""
            ))
        }
        return out
    }

    public func saveCustomModel(_ m: CustomLlmModel) throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        INSERT OR REPLACE INTO custom_models (
            id, display_name, file_path, sha256, template, prompt_profile, n_ctx, size_bytes, added_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_save_custom")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, m.id)
        bindText(stmt, 2, m.displayName)
        bindText(stmt, 3, m.filePath)
        bindText(stmt, 4, m.sha256)
        bindText(stmt, 5, m.template)
        bindText(stmt, 6, m.promptProfile)
        sqlite3_bind_int(stmt, 7, Int32(m.nCtx))
        sqlite3_bind_int64(stmt, 8, m.sizeBytes)
        sqlite3_bind_int64(stmt, 9, m.addedAtMs)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MurmurError.storageFailed("step_save_custom")
        }
    }

    public func fetchCustomModels() throws -> [CustomLlmModel] {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM custom_models ORDER BY added_at_ms DESC;", -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_fetch_custom")
        }
        defer { sqlite3_finalize(stmt) }
        var out: [CustomLlmModel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CustomLlmModel(
                id: colText(stmt, 0) ?? "",
                displayName: colText(stmt, 1) ?? "",
                filePath: colText(stmt, 2) ?? "",
                sha256: colText(stmt, 3) ?? "",
                template: colText(stmt, 4) ?? "qwen3.5",
                promptProfile: colText(stmt, 5) ?? "default.v1",
                nCtx: Int(sqlite3_column_int(stmt, 6)),
                sizeBytes: sqlite3_column_int64(stmt, 7),
                addedAtMs: sqlite3_column_int64(stmt, 8)
            ))
        }
        return out
    }

    public func deleteCustomModel(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM custom_models WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            throw MurmurError.storageFailed("prepare_delete_custom")
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MurmurError.storageFailed("step_delete_custom")
        }
    }
}
