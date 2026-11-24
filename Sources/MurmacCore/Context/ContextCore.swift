import Foundation

public struct Rect: Codable, Equatable, Hashable, Sendable {
    public let x0: Int
    public let y0: Int
    public let x1: Int
    public let y1: Int

    public init(x0: Int, y0: Int, x1: Int, y1: Int) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public var width: Int { max(0, x1 - x0) }
    public var height: Int { max(0, y1 - y0) }
    public var asList: [Int] { [x0, y0, x1, y1] }
}

public struct OcrLine: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let conf: Double
    public let box: [Int]

    public init(text: String, conf: Double, box: [Int]) {
        self.text = text
        self.conf = conf
        self.box = box
    }
}

public struct ScreenText: Codable, Equatable, Hashable, Sendable {
    public let size: [Int]
    public let lines: [OcrLine]

    public init(size: [Int], lines: [OcrLine]) {
        self.size = size
        self.lines = lines
    }
}

public struct AppInfo: Codable, Equatable, Hashable, Sendable {
    public let pkg: String
    public let label: String?
    public let category: String?

    enum CodingKeys: String, CodingKey {
        case pkg = "package"
        case label
        case category
    }

    public init(pkg: String, label: String? = nil, category: String? = nil) {
        self.pkg = pkg
        self.label = label
        self.category = category
    }
}

public struct FieldInfo: Codable, Equatable, Hashable, Sendable {
    public let kind: String?
    public let hint: String?
    public let beforeCursor: String?
    public let box: [Int]?
    public let inputTypeVariation: String?
    public let password: Bool?

    enum CodingKeys: String, CodingKey {
        case kind
        case hint
        case beforeCursor = "before_cursor"
        case box
        case inputTypeVariation = "input_type_variation"
        case password
    }

    public init(
        kind: String? = nil,
        hint: String? = nil,
        beforeCursor: String? = nil,
        box: [Int]? = nil,
        inputTypeVariation: String? = nil,
        password: Bool? = nil
    ) {
        self.kind = kind
        self.hint = hint
        self.beforeCursor = beforeCursor
        self.box = box
        self.inputTypeVariation = inputTypeVariation
        self.password = password
    }

    public var isEmptyObject: Bool {
        kind == nil && hint == nil && beforeCursor == nil && box == nil && inputTypeVariation == nil && password == nil
    }
}

public struct Screen: Codable, Equatable, Hashable, Sendable {
    public let size: [Int]
    public let lines: [OcrLine]

    public init(size: [Int], lines: [OcrLine]) {
        self.size = size
        self.lines = lines
    }
}

public struct LanguageInfo: Codable, Equatable, Hashable, Sendable {
    public let asr: String?

    public init(asr: String? = nil) {
        self.asr = asr
    }
}

public enum PrivacyLevel {
    public static let full = "full"
    public static let appOnly = "app_only"
    public static let none = "none"
}

public enum PrivacyReason {
    public static let secureWindow = "secure_window"
    public static let denylistedApp = "denylisted_app"
    public static let passwordField = "password_field"
    public static let screenshotError = "screenshot_error"
    public static let ocrEmpty = "ocr_empty"
    public static let userSetting = "user_setting"

    public static func noScreenLevel(_ reason: String) -> String {
        switch reason {
        case passwordField: return PrivacyLevel.none
        case secureWindow, denylistedApp, userSetting: return PrivacyLevel.appOnly
        default: return PrivacyLevel.full
        }
    }
}

/// `privacy` writes explicit null for `reason` when nil, matching prompts/context.schema.v2.json.
public struct Privacy: Codable, Equatable, Hashable, Sendable {
    public let level: String
    public let reason: String?

    public init(level: String = PrivacyLevel.full, reason: String? = nil) {
        self.level = level
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey { case level, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.level = try c.decodeIfPresent(String.self, forKey: .level) ?? PrivacyLevel.full
        self.reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(level, forKey: .level)
        if let reason {
            try c.encode(reason, forKey: .reason)
        } else {
            try c.encodeNil(forKey: .reason)
        }
    }
}

public struct CtxV2: Codable, Equatable, Hashable, Sendable {
    public let v: Int
    public let app: AppInfo
    public let field: FieldInfo?
    public let screen: Screen?
    public let language: LanguageInfo?
    public let privacy: Privacy?

    public init(
        v: Int = 2,
        app: AppInfo,
        field: FieldInfo? = nil,
        screen: Screen? = nil,
        language: LanguageInfo? = nil,
        privacy: Privacy? = nil
    ) {
        self.v = v
        self.app = app
        self.field = field
        self.screen = screen
        self.language = language
        self.privacy = privacy
    }

    enum CodingKeys: String, CodingKey {
        case v, app, field, screen, language, privacy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 2
        self.app = try c.decode(AppInfo.self, forKey: .app)
        self.field = try c.decodeIfPresent(FieldInfo.self, forKey: .field)
        self.screen = try c.decodeIfPresent(Screen.self, forKey: .screen)
        self.language = try c.decodeIfPresent(LanguageInfo.self, forKey: .language)
        self.privacy = try c.decodeIfPresent(Privacy.self, forKey: .privacy)
    }
}

/// Snapshot captured via macOS Accessibility (AXUIElement) at hotkey press.
public struct FieldSnapshot: Equatable, Hashable, Sendable {
    public let role: String?
    public let subrole: String?
    public let hint: String?
    public let beforeCursor: String?
    public let boundsInScreen: Rect?
    public let isPassword: Bool
    public let isMultiline: Bool
    public let isEditable: Bool

    public init(
        role: String? = nil,
        subrole: String? = nil,
        hint: String? = nil,
        beforeCursor: String? = nil,
        boundsInScreen: Rect? = nil,
        isPassword: Bool = false,
        isMultiline: Bool = false,
        isEditable: Bool = true
    ) {
        self.role = role
        self.subrole = subrole
        self.hint = hint
        self.beforeCursor = beforeCursor
        self.boundsInScreen = boundsInScreen
        self.isPassword = isPassword
        self.isMultiline = isMultiline
        self.isEditable = isEditable
    }
}

public struct A11ySnapshot: Equatable, Hashable, Sendable {
    public let bundleId: String
    public let appName: String?
    public let windowTitle: String?
    public let windowNumber: Int?
    public let field: FieldSnapshot?
    public let windowBoundsInScreen: Rect?
    public let capturedAtMs: Int64

    public init(
        bundleId: String,
        appName: String? = nil,
        windowTitle: String? = nil,
        windowNumber: Int? = nil,
        field: FieldSnapshot? = nil,
        windowBoundsInScreen: Rect? = nil,
        capturedAtMs: Int64 = 0
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowNumber = windowNumber
        self.field = field
        self.windowBoundsInScreen = windowBoundsInScreen
        self.capturedAtMs = capturedAtMs
    }
}

public struct ContextSettings: Equatable, Sendable {
    public let useScreen: Bool
    public let excludedBundleIds: Set<String>
    public let inAppPractice: Bool

    public init(useScreen: Bool = true, excludedBundleIds: Set<String> = [], inAppPractice: Bool = false) {
        self.useScreen = useScreen
        self.excludedBundleIds = excludedBundleIds
        self.inAppPractice = inAppPractice
    }
}

public struct PrivacyDecision: Equatable, Sendable {
    public let level: String
    public let takeScreenshot: Bool
    public let reason: String?
    public let skipLlm: Bool
    public let dictationAllowed: Bool

    public init(level: String, takeScreenshot: Bool, reason: String?, skipLlm: Bool, dictationAllowed: Bool = true) {
        self.level = level
        self.takeScreenshot = takeScreenshot
        self.reason = reason
        self.skipLlm = skipLlm
        self.dictationAllowed = dictationAllowed
    }
}

public enum ScreenOutcome: Equatable, Sendable {
    case text(ScreenText)
    case notTaken
    case secureWindow
    case failed
}

public enum MacBuiltInDenylist {
    public static let bundleIds: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.SecurityAgent",
    ]
}

public enum AppCategories {
    /// Built-in macOS bundle IDs -> tone category (aligned with prompts/tones/tones.v1.json).
    public static let macDefaults: [String: String] = [
        // Messaging
        "ru.keepcoder.Telegram": "messaging",
        "org.telegram.desktop": "messaging",
        "com.apple.MobileSMS": "messaging",
        "net.whatsapp.WhatsApp": "messaging",
        "org.whispersystems.signal-desktop": "messaging",
        "com.hnc.Discord": "messaging",
        "com.facebook.archon": "messaging",
        // Work chat
        "com.tinyspeck.slackmacgap": "work_chat",
        "com.microsoft.teams2": "work_chat",
        "com.microsoft.teams": "work_chat",
        "us.zoom.xos": "work_chat",
        "com.mattermost.Desktop": "work_chat",
        // Email
        "com.apple.mail": "email",
        "com.microsoft.Outlook": "email",
        "com.readdle.smartemail-Mac": "email",
        "org.mozilla.thunderbird": "email",
        // Notes / docs
        "com.apple.Notes": "notes",
        "md.obsidian": "notes",
        "notion.id": "notes",
        "com.apple.iWork.Pages": "notes",
        "net.shinyfrog.bear": "notes",
        "com.linear": "work_chat",
        // Code / terminals
        "com.apple.dt.Xcode": "code",
        "com.microsoft.VSCode": "code",
        "com.todesktop.230313mzl4w4u92": "code", // Cursor
        "com.jetbrains.pycharm": "code",
        "com.jetbrains.intellij": "code",
        "com.jetbrains.goland": "code",
        "com.jetbrains.WebStorm": "code",
        "dev.zed.Zed": "code",
        "com.apple.Terminal": "code",
        "com.googlecode.iterm2": "code",
        "com.mitchellh.ghostty": "code",
        "dev.warp.Warp-Stable": "code",
        "net.kovidgoyal.kitty": "code",
        // Browsers
        "com.apple.Safari": "browser",
        "com.google.Chrome": "browser",
        "company.thebrowser.Browser": "browser", // Arc
        "org.mozilla.firefox": "browser",
        "com.brave.Browser": "browser",
    ]

    public static func category(for bundleId: String, extra: [String: String] = [:]) -> String? {
        if let c = extra[bundleId] { return c }
        if let c = macDefaults[bundleId] { return c }
        let lower = bundleId.lowercased()
        if lower.contains("jetbrains") || lower.contains("vscode") || lower.contains("terminal") { return "code" }
        if lower.contains("telegram") || lower.contains("whatsapp") || lower.contains("discord") { return "messaging" }
        if lower.contains("slack") || lower.contains("teams") { return "work_chat" }
        if lower.contains("mail") || lower.contains("outlook") { return "email" }
        return nil
    }
}

public protocol ContextAssembler: Sendable {
    func decide(snapshot: A11ySnapshot, settings: ContextSettings) -> PrivacyDecision
    func assemble(snapshot: A11ySnapshot, decision: PrivacyDecision, screen: ScreenOutcome, asrLanguage: String?) -> CtxV2
}

public struct DefaultContextAssembler: ContextAssembler {
    public static let ownBundleId = "app.murmur.murmac"
    public static let maxPackage = 200
    public static let maxLabel = 100
    public static let maxCategory = 40
    public static let maxHint = 200
    public static let maxBeforeCursor = 4000
    public static let maxLanguage = 8
    public static let maxLines = 400
    public static let maxLineText = 1000

    private let extraCategories: [String: String]
    private let ownBundleId: String

    public init(extraCategories: [String: String] = [:], ownBundleId: String = DefaultContextAssembler.ownBundleId) {
        self.extraCategories = extraCategories
        self.ownBundleId = ownBundleId
    }

    public func decide(snapshot: A11ySnapshot, settings: ContextSettings) -> PrivacyDecision {
        if let f = snapshot.field, f.isPassword || f.subrole == "AXSecureTextField" {
            return PrivacyDecision(level: PrivacyLevel.none, takeScreenshot: false, reason: PrivacyReason.passwordField, skipLlm: true, dictationAllowed: false)
        }
        if MacBuiltInDenylist.bundleIds.contains(snapshot.bundleId) || settings.excludedBundleIds.contains(snapshot.bundleId) {
            return PrivacyDecision(level: PrivacyLevel.appOnly, takeScreenshot: false, reason: PrivacyReason.denylistedApp, skipLlm: false, dictationAllowed: false)
        }
        if snapshot.bundleId == ownBundleId {
            return PrivacyDecision(level: PrivacyLevel.appOnly, takeScreenshot: false, reason: PrivacyReason.denylistedApp, skipLlm: false, dictationAllowed: settings.inAppPractice)
        }
        if !settings.useScreen {
            return PrivacyDecision(level: PrivacyLevel.appOnly, takeScreenshot: false, reason: PrivacyReason.userSetting, skipLlm: false, dictationAllowed: true)
        }
        return PrivacyDecision(level: PrivacyLevel.full, takeScreenshot: true, reason: nil, skipLlm: false, dictationAllowed: true)
    }

    public func assemble(snapshot: A11ySnapshot, decision: PrivacyDecision, screen: ScreenOutcome, asrLanguage: String?) -> CtxV2 {
        let fieldSnap = snapshot.field
        let isPassword = fieldSnap.map { $0.isPassword || $0.subrole == "AXSecureTextField" } ?? false

        var validScreen: ScreenText? = nil
        if case .text(let st) = screen, st.size.count == 2, st.size.allSatisfy({ $0 > 0 }) {
            validScreen = st
        }
        let lines = (validScreen?.lines ?? [])
            .filter { $0.conf.isFinite && $0.box.count == 4 }
            .prefix(Self.maxLines)
            .map { OcrLine(text: clipStart($0.text, max: Self.maxLineText), conf: min(1.0, max(0.0, $0.conf)), box: $0.box) }

        let privacy: Privacy
        if isPassword {
            privacy = Privacy(level: PrivacyLevel.none, reason: PrivacyReason.passwordField)
        } else if decision.level != PrivacyLevel.full {
            privacy = Privacy(level: decision.level, reason: decision.reason)
        } else if !lines.isEmpty {
            privacy = Privacy(level: PrivacyLevel.full, reason: nil)
        } else {
            let reason: String
            switch screen {
            case .secureWindow: reason = PrivacyReason.secureWindow
            case .text where validScreen != nil: reason = PrivacyReason.ocrEmpty
            default: reason = PrivacyReason.screenshotError
            }
            privacy = Privacy(level: PrivacyReason.noScreenLevel(reason), reason: reason)
        }

        let level = privacy.level
        let withScreen = !isPassword && decision.level == PrivacyLevel.full && !lines.isEmpty
        let category = AppCategories.category(for: snapshot.bundleId, extra: extraCategories)
            .flatMap { $0.isEmpty || $0.unicodeScalars.count > Self.maxCategory ? nil : $0 }

        let appLabel: String?
        if level != PrivacyLevel.none, let lbl = snapshot.appName, !lbl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appLabel = clipStart(lbl, max: Self.maxLabel)
        } else {
            appLabel = nil
        }

        let app = AppInfo(
            pkg: clipStart(snapshot.bundleId, max: Self.maxPackage),
            label: appLabel,
            category: category
        )

        let field: FieldInfo? = fieldSnap.map { f in
            let kind = inferFieldKind(f, category: category)
            let boxInShot: [Int]? = f.boundsInScreen.flatMap { b in
                guard let wb = snapshot.windowBoundsInScreen, wb.width > 0, wb.height > 0 else {
                    return nil
                }
                let scaleX: Double
                let scaleY: Double
                if let sz = validScreen?.size {
                    scaleX = Double(sz[0]) / Double(wb.width)
                    scaleY = Double(sz[1]) / Double(wb.height)
                } else {
                    scaleX = 1.0
                    scaleY = 1.0
                }
                return [
                    Int(Double(b.x0 - wb.x0) * scaleX),
                    Int(Double(b.y0 - wb.y0) * scaleY),
                    Int(Double(b.x1 - wb.x0) * scaleX),
                    Int(Double(b.y1 - wb.y0) * scaleY),
                ]
            }
            return FieldInfo(
                kind: kind,
                hint: (level != PrivacyLevel.none ? f.hint : nil).map { clipStart($0, max: Self.maxHint) },
                beforeCursor: (level == PrivacyLevel.full && !isPassword ? f.beforeCursor : nil).map { clipEnd($0, max: Self.maxBeforeCursor) },
                box: boxInShot,
                inputTypeVariation: nil,
                password: isPassword ? true : nil
            )
        }

        let langInfo: LanguageInfo?
        if let lang = asrLanguage, !lang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           lang.unicodeScalars.count <= Self.maxLanguage {
            langInfo = LanguageInfo(asr: lang)
        } else {
            langInfo = nil
        }

        return CtxV2(
            v: 2,
            app: app,
            field: field,
            screen: withScreen ? Screen(size: validScreen!.size, lines: lines) : nil,
            language: langInfo,
            privacy: privacy
        )
    }

    private func inferFieldKind(_ f: FieldSnapshot, category: String?) -> String {
        if f.subrole == "AXSearchField" { return "search" }
        let hintLower = (f.hint ?? "").lowercased()
        if hintLower.contains("search") || hintLower.contains("поиск") { return "search" }
        if hintLower.contains("subject") || hintLower.contains("тема") { return "email_subject" }
        if hintLower.contains("url") || hintLower.contains("address") || hintLower.contains("адрес") { return "address" }
        switch category {
        case "messaging", "work_chat": return "message"
        case "email": return "email_body"
        case "notes": return "note"
        case "code": return "code"
        default: return "generic"
        }
    }

    private func clipStart(_ s: String, max: Int) -> String {
        let scalars = s.unicodeScalars
        guard scalars.count > max else { return s }
        return String(scalars.prefix(max))
    }

    private func clipEnd(_ s: String, max: Int) -> String {
        let scalars = s.unicodeScalars
        guard scalars.count > max else { return s }
        return String(scalars.suffix(max))
    }
}
