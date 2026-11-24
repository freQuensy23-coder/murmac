import Foundation

public struct LoadSpec: Codable, Equatable, Hashable, Sendable {
    public let artifactId: String
    public let kind: ModelKind
    public let runtime: String
    public let unit: ComputeUnit
    public let dir: String
    public let layout: [String: String]
    public let options: [String: String]

    public init(
        artifactId: String,
        kind: ModelKind,
        runtime: String,
        unit: ComputeUnit,
        dir: String,
        layout: [String: String],
        options: [String: String] = [:]
    ) {
        self.artifactId = artifactId
        self.kind = kind
        self.runtime = runtime
        self.unit = unit
        self.dir = dir
        self.layout = layout
        self.options = options
    }
}

public struct LoadInfo: Codable, Equatable, Hashable, Sendable {
    public let unit: ComputeUnit
    public let loadMs: Int64
    public let deviceName: String

    public init(unit: ComputeUnit, loadMs: Int64, deviceName: String) {
        self.unit = unit
        self.loadMs = loadMs
        self.deviceName = deviceName
    }
}

public struct AsrSessionOptions: Equatable, Sendable {
    public let language: String?
    public let maxWindowSec: Double?

    public init(language: String? = nil, maxWindowSec: Double? = nil) {
        self.language = language
        self.maxWindowSec = maxWindowSec
    }
}

public struct Transcript: Equatable, Sendable {
    public let text: String
    public let speechMs: Int64
    public let decodeMs: Int64
    public let language: String?
    public let segmentCount: Int

    public init(text: String, speechMs: Int64, decodeMs: Int64, language: String? = nil, segmentCount: Int = 1) {
        self.text = text
        self.speechMs = speechMs
        self.decodeMs = decodeMs
        self.language = language
        self.segmentCount = segmentCount
    }
}

public struct PrefixSpec: Equatable, Sendable {
    public let text: String
    public let cacheKey: String

    public init(text: String, cacheKey: String) {
        self.text = text
        self.cacheKey = cacheKey
    }
}

public struct PrefixInfo: Equatable, Sendable {
    public let tokens: Int
    public let prefillMs: Int64
    public let restoredFromDisk: Bool
    public let bytes: Int

    public init(tokens: Int, prefillMs: Int64, restoredFromDisk: Bool, bytes: Int) {
        self.tokens = tokens
        self.prefillMs = prefillMs
        self.restoredFromDisk = restoredFromDisk
        self.bytes = bytes
    }
}

public struct LlmRequest: Equatable, Sendable {
    public let suffix: String
    public let maxTokens: Int
    public let minTokens: Int
    public let temperature: Float
    public let repeatPenalty: Float
    public let stops: [String]

    public init(
        suffix: String,
        maxTokens: Int,
        minTokens: Int = 16,
        temperature: Float = 0.0,
        repeatPenalty: Float = 1.0,
        stops: [String] = ["<|im_end|>", "<|endoftext|>"]
    ) {
        self.suffix = suffix
        self.maxTokens = maxTokens
        self.minTokens = minTokens
        self.temperature = temperature
        self.repeatPenalty = repeatPenalty
        self.stops = stops
    }
}

public struct LlmStats: Equatable, Sendable {
    public let promptTokens: Int
    public let generatedTokens: Int
    public let restoreMs: Double
    public let prefillMs: Double
    public let ttftMs: Double
    public let decodeMs: Double
    public let totalMs: Double
    public let truncated: Bool

    public init(
        promptTokens: Int,
        generatedTokens: Int,
        restoreMs: Double,
        prefillMs: Double,
        ttftMs: Double,
        decodeMs: Double,
        totalMs: Double,
        truncated: Bool
    ) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.restoreMs = restoreMs
        self.prefillMs = prefillMs
        self.ttftMs = ttftMs
        self.decodeMs = decodeMs
        self.totalMs = totalMs
        self.truncated = truncated
    }
}

public struct LlmGenerationResult: Equatable, Sendable {
    public let text: String
    public let stats: LlmStats

    public init(text: String, stats: LlmStats) {
        self.text = text
        self.stats = stats
    }
}

public struct SyntheticBench: Codable, Equatable, Sendable {
    public let prefillTps: Double
    public let decodeTps: Double
    public let prefillMs: Double
    public let decodeMs: Double

    public init(prefillTps: Double, decodeTps: Double, prefillMs: Double, decodeMs: Double) {
        self.prefillTps = prefillTps
        self.decodeTps = decodeTps
        self.prefillMs = prefillMs
        self.decodeMs = decodeMs
    }
}

public struct EngineProbe: Equatable, Sendable {
    public let availableUnits: Set<ComputeUnit>
    public let runtimes: Set<String>
    public let facts: [String: String]

    public init(availableUnits: Set<ComputeUnit>, runtimes: Set<String>, facts: [String: String] = [:]) {
        self.availableUnits = availableUnits
        self.runtimes = runtimes
        self.facts = facts
    }
}

public protocol AsrSession: AnyObject, Sendable {
    func feed(_ chunk: PcmChunk) async
    func finish() async throws -> Transcript
    func cancel() async
}

public protocol AsrEngine: AnyObject, Sendable {
    func probe() async -> EngineProbe
    func load(asr: LoadSpec, vad: LoadSpec?) async throws -> LoadInfo
    func startSession(options: AsrSessionOptions) async throws -> AsrSession
    func unload() async
}

public protocol LlmEngine: AnyObject, Sendable {
    func probe() async -> EngineProbe
    func load(spec: LoadSpec) async throws -> LoadInfo
    func setPrefix(_ spec: PrefixSpec) async throws -> PrefixInfo
    func generate(request: LlmRequest, onPiece: (@Sendable (String) -> Void)?) async throws -> LlmGenerationResult
    func bench(nPrompt: Int, nGen: Int, reps: Int) async throws -> SyntheticBench
    func cancel()
    func unload() async
}

/// Pluggable screen OCR backend (default on macOS: Apple Vision ANE).
public struct ScreenImageData: Sendable {
    public let width: Int
    public let height: Int
    public let pngData: Data?
    /// Raw CGImage boxed as AnyObject (Sendable-safe immutable CGImage on macOS).
    public let cgImageBox: (@Sendable () -> AnyObject?)?

    public init(width: Int, height: Int, pngData: Data? = nil, cgImageBox: (@Sendable () -> AnyObject?)? = nil) {
        self.width = width
        self.height = height
        self.pngData = pngData
        self.cgImageBox = cgImageBox
    }
}

public protocol ScreenOcrEngine: AnyObject, Sendable {
    func recognize(image: ScreenImageData) async throws -> ScreenText
}

public protocol Engines: AnyObject, Sendable {
    var asr: AsrEngine { get }
    var llm: LlmEngine { get }
    var ocr: ScreenOcrEngine { get }
    func scheduleIdleUnload(afterMs: Int64)
    func holdActive()
    func unloadAll() async
}
