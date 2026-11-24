import Foundation

public enum ComputeUnit: String, Codable, Hashable, Sendable, CaseIterable {
    case gpu
    case cpu
    case ane

    public var displayName: String {
        switch self {
        case .gpu: return "Metal GPU"
        case .cpu: return "CPU"
        case .ane: return "Neural Engine"
        }
    }
}

public enum UnitPreference: String, Codable, Hashable, Sendable, CaseIterable {
    case auto
    case gpu
    case cpu

    public var displayName: String {
        switch self {
        case .auto: return "Auto (Metal preferred)"
        case .gpu: return "Metal GPU"
        case .cpu: return "CPU"
        }
    }
}

public enum ModelKind: String, Codable, Hashable, Sendable, CaseIterable {
    case asr
    case vad
    case llm
    case ocr
}

public enum DictationLanguage: String, Codable, Hashable, Sendable, CaseIterable {
    case auto = "ru+en"
    case ru = "ru"
    case en = "en"

    public var displayName: String {
        switch self {
        case .auto: return "Russian + English"
        case .ru: return "Russian"
        case .en: return "English"
        }
    }

    public var asrHint: String? {
        switch self {
        case .auto: return nil
        case .ru: return "ru"
        case .en: return "en"
        }
    }
}

public enum InsertMethod: String, Codable, Hashable, Sendable {
    case accessibility
    case paste
    case copiedOnly
    case inApp
}

public enum AppTone: String, Codable, Hashable, Sendable, CaseIterable {
    case categoryDefault = "default"
    case casual
    case neutral
    case formal
    case verbatim
}

public enum MurmurError: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    case noAsrModel
    case noVadModel
    case engineRuntimeMissing(String)
    case engineLoadFailed(ModelKind, String)
    case unitUnavailable(ComputeUnit)
    case outOfMemory(ModelKind)
    case micPermissionDenied
    case accessibilityPermissionDenied
    case screenRecordingPermissionDenied
    case micBusy
    case micStartFailed(String)
    case micLost(String)
    case noSpeech
    case passwordField
    case appExcluded
    case noEditableField
    case targetChanged
    case insertRejected
    case secureWindow
    case asrFailed(String)
    case llmFailed(String)
    case llmContextOverflow
    case ocrFailed(String)
    case timeout(String)
    case lowStorage
    case storageFailed(String)
    case downloadFailed(String)
    case catalogInvalid(String)
    case cancelled
    case internalError(String)

    public var code: String {
        switch self {
        case .noAsrModel: return "no_asr_model"
        case .noVadModel: return "no_vad_model"
        case .engineRuntimeMissing(let rt): return "runtime_missing:\(rt)"
        case .engineLoadFailed(let k, let detail): return "load_failed:\(k.rawValue):\(detail)"
        case .unitUnavailable(let u): return "unit_unavailable:\(u.rawValue)"
        case .outOfMemory(let k): return "oom:\(k.rawValue)"
        case .micPermissionDenied: return "perm.mic"
        case .accessibilityPermissionDenied: return "perm.a11y"
        case .screenRecordingPermissionDenied: return "perm.screen"
        case .micBusy: return "mic_busy"
        case .micStartFailed(let m): return "mic_start:\(m)"
        case .micLost(let m): return "mic_lost:\(m)"
        case .noSpeech: return "no_speech"
        case .passwordField: return "password_field"
        case .appExcluded: return "app_excluded"
        case .noEditableField: return "no_editable_field"
        case .targetChanged: return "target_changed"
        case .insertRejected: return "insert_rejected"
        case .secureWindow: return "secure_window"
        case .asrFailed(let m): return "asr_failed:\(m)"
        case .llmFailed(let m): return "llm_failed:\(m)"
        case .llmContextOverflow: return "llm_context_overflow"
        case .ocrFailed(let m): return "ocr_failed:\(m)"
        case .timeout(let s): return "timeout:\(s)"
        case .lowStorage: return "low_storage"
        case .storageFailed(let m): return "storage:\(m)"
        case .downloadFailed(let m): return "download:\(m)"
        case .catalogInvalid(let m): return "catalog:\(m)"
        case .cancelled: return "cancelled"
        case .internalError(let m): return "internal:\(m)"
        }
    }

    public var description: String { code }
}

public protocol MurmurClock: Sendable {
    func nowMs() -> Int64
    func monotonicMs() -> Int64
}

public struct SystemMurmurClock: MurmurClock {
    public init() {}
    public func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000.0) }
    public func monotonicMs() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000.0) }
}

public struct AudioKey: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }

    public static func of(createdAtMs: Int64, sessionId: String) -> AudioKey {
        AudioKey("\(createdAtMs)-\(sessionId)")
    }
}
