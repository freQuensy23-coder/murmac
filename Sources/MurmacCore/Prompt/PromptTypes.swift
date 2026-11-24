import Foundation

/// Untyped JSON value for `PromptProfile.ctx2` and `tones.v1.json`.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSONValue")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}

public struct PromptProfile: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let system: String
    public let shots: String?
    public let answerPrefix: String
    public let ctx2: [String: JSONValue]?
    public let preferencesBlock: String

    enum CodingKeys: String, CodingKey {
        case name, system, shots
        case answerPrefix = "answer_prefix"
        case ctx2
        case preferencesBlock = "preferences_block"
    }

    public init(
        name: String,
        system: String,
        shots: String? = nil,
        answerPrefix: String = "",
        ctx2: [String: JSONValue]? = nil,
        preferencesBlock: String = "preferences_block"
    ) {
        self.name = name
        self.system = system
        self.shots = shots
        self.answerPrefix = answerPrefix
        self.ctx2 = ctx2
        self.preferencesBlock = preferencesBlock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.system = try c.decode(String.self, forKey: .system)
        self.shots = try c.decodeIfPresent(String.self, forKey: .shots)
        self.answerPrefix = try c.decodeIfPresent(String.self, forKey: .answerPrefix) ?? ""
        self.ctx2 = try c.decodeIfPresent([String: JSONValue].self, forKey: .ctx2)
        self.preferencesBlock = try c.decodeIfPresent(String.self, forKey: .preferencesBlock) ?? "preferences_block"
    }
}

public struct Shot: Codable, Equatable, Sendable {
    public let ctx: CtxV2?
    public let transcript: String
    public let target: String

    public init(ctx: CtxV2? = nil, transcript: String, target: String) {
        self.ctx = ctx
        self.transcript = transcript
        self.target = target
    }
}

public struct RenderInput: Sendable {
    public let profile: PromptProfile
    public let template: String
    public let ctx: CtxV2?
    public let transcript: String
    public let preferences: String?
    public let styleOverride: String?
    public let systemOverride: String?

    public init(
        profile: PromptProfile,
        template: String,
        ctx: CtxV2?,
        transcript: String,
        preferences: String? = nil,
        styleOverride: String? = nil,
        systemOverride: String? = nil
    ) {
        self.profile = profile
        self.template = template
        self.ctx = ctx
        self.transcript = transcript
        self.preferences = preferences
        self.styleOverride = styleOverride
        self.systemOverride = systemOverride
    }
}

public struct RenderedPrompt: Equatable, Sendable {
    public let prefix: String
    public let suffix: String
    public let prefixKey: String

    public init(prefix: String, suffix: String, prefixKey: String) {
        self.prefix = prefix
        self.suffix = suffix
        self.prefixKey = prefixKey
    }

    public var full: String { prefix + suffix }
}

public enum GuardAction: String, Codable, Equatable, Sendable {
    case accept = "ACCEPT"
    case fallback = "FALLBACK"
    case empty = "EMPTY"
}

public struct GuardVerdict: Equatable, Sendable {
    public let text: String
    public let action: GuardAction
    public let reason: String

    public init(text: String, action: GuardAction, reason: String) {
        self.text = text
        self.action = action
        self.reason = reason
    }
}

public struct Precheck: Equatable, Sendable {
    public let skip: Bool
    public let transcript: String
    public let reason: String

    public init(skip: Bool, transcript: String, reason: String) {
        self.skip = skip
        self.transcript = transcript
        self.reason = reason
    }
}

public protocol PromptAssets: Sendable {
    func systemPrompt(stem: String) throws -> String
    func profile(name: String) throws -> PromptProfile
    func shots(path: String) throws -> [Shot]
    func text(path: String) throws -> String
}

public protocol PromptRenderer: Sendable {
    func render(_ input: RenderInput) throws -> RenderedPrompt
    func renderContext(_ ctx: CtxV2, ctx2: [String: JSONValue]?) throws -> String
    func cachePrefix(profile: PromptProfile, template: String, preferences: String?, systemOverride: String?) throws -> String
    func toneText(_ tone: String) -> String?
}

public protocol OutputGuard: Sendable {
    func precheck(_ transcript: String) -> Precheck
    func guardOutput(transcript: String, output: String, ctx: CtxV2?) -> GuardVerdict
    var fillers: Set<String> { get }
}

public enum PromptEditState: Equatable, Sendable {
    case `default`
    case edited
    case madeForOlderPrompt
    case notEditable
}

public enum PromptEditRules {
    public static let maxSystemChars = 8_000
    public static let maxPreferencesChars = 1_000
    private static let forbidden = ["<|im_", "<|startoftext|>", "<|endoftext|>", "<think>", "</think>"]

    public static func overrideApplies(profile: PromptProfile, overrideBaseProfile: String?) -> Bool {
        overrideBaseProfile != nil && !profile.system.hasPrefix("finetuned") && profile.name == overrideBaseProfile
    }

    public static func editable(profile: PromptProfile) -> Bool {
        !profile.system.hasPrefix("finetuned")
    }

    public static func editState(profile: PromptProfile, overrideBaseProfile: String?) -> PromptEditState {
        guard let base = overrideBaseProfile else {
            return editable(profile: profile) ? .default : .notEditable
        }
        return overrideApplies(profile: profile, overrideBaseProfile: base) ? .edited : .madeForOlderPrompt
    }

    public static func validateSystem(_ text: String) -> [String] {
        var problems: [String] = []
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("empty") }
        if text.count > maxSystemChars { problems.append("too_long") }
        if forbidden.contains(where: { text.contains($0) }) { problems.append("markup") }
        return problems
    }
}

/// Reads packaged prompts from Bundle.module (`Resources/prompts/...`).
public struct BundlePromptAssets: PromptAssets {
    private let rootURL: URL

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else if let bundled = MurmacCoreResources.bundle.url(forResource: "prompts", withExtension: nil) {
            self.rootURL = bundled
        } else {
            self.rootURL = URL(fileURLWithPath: "Resources/prompts")
        }
    }

    public func text(path: String) throws -> String {
        let url = rootURL.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func systemPrompt(stem: String) throws -> String {
        try text(path: "system/\(stem).md")
    }

    public func profile(name: String) throws -> PromptProfile {
        let direct = rootURL.appendingPathComponent("profiles/\(name).json")
        guard FileManager.default.fileExists(atPath: direct.path) else {
            return PromptProfile(name: name, system: name, shots: nil)
        }
        let data = try Data(contentsOf: direct)
        let p = try JSONDecoder().decode(PromptProfile.self, from: data)
        if p.name.isEmpty {
            return PromptProfile(
                name: name, system: p.system, shots: p.shots,
                answerPrefix: p.answerPrefix, ctx2: p.ctx2, preferencesBlock: p.preferencesBlock
            )
        }
        return p
    }

    public func shots(path: String) throws -> [Shot] {
        let raw = try text(path: path)
        let decoder = JSONDecoder()
        var out: [Shot] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            out.append(try decoder.decode(Shot.self, from: data))
        }
        return out
    }
}
