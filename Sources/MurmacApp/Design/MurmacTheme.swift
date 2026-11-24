import AppKit
import CoreText
import MurmacCore
import SwiftUI

/// Locates `Murmac_MurmacApp.bundle` in a packaged `.app` (`Contents/Resources/`)
/// before falling back to SwiftPM's build-tree `Bundle.module`.
public enum MurmacAppResources {
    private static let bundleName = "Murmac_MurmacApp.bundle"

    public static let bundle: Bundle = {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
        ]
        for case let url? in candidates {
            if let found = Bundle(url: url) {
                return found
            }
        }
        return Bundle.module
    }()
}

/// Registers bundled Onest & JetBrains Mono fonts at launch.
public enum MurmacFonts {
    private static let didRegister: Bool = {
        let files = ["onest_variable", "jetbrains_mono_regular", "jetbrains_mono_medium"]
        for name in files {
            if let url = MurmacAppResources.bundle.url(forResource: name, withExtension: "ttf", subdirectory: "fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }()

    public static func registerIfNeeded() {
        _ = didRegister
    }

    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        registerIfNeeded()
        return Font.custom("Onest", size: size).weight(weight)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        registerIfNeeded()
        let name = weight == .medium || weight == .semibold ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular"
        return Font.custom(name, size: size)
    }
}

/// Exact Murmur design palette from `tokens.json` (light & dark adaptive colors).
public enum MurmacColor {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        })
    }

    public static let bg           = dynamic(light: 0xF6F7F9, dark: 0x0F1013)
    public static let surface      = dynamic(light: 0xFFFFFF, dark: 0x17191D)
    public static let surface2     = dynamic(light: 0xEEF0F4, dark: 0x1F2227)
    public static let surface3     = dynamic(light: 0xE2E5EB, dark: 0x2A2E35)
    public static let ink          = dynamic(light: 0x14161B, dark: 0xECEEF2)
    public static let ink2         = dynamic(light: 0x464C59, dark: 0xB9BFCA)
    public static let ink3         = dynamic(light: 0x6B7280, dark: 0x9AA1AE)
    public static let ink4         = dynamic(light: 0xA3A9B5, dark: 0x646B78)
    public static let line         = dynamic(light: 0xE4E7EC, dark: 0x25282F)
    public static let line2        = dynamic(light: 0xD0D4DC, dark: 0x343843)
    public static let accent       = dynamic(light: 0x2F4BE8, dark: 0x8296FF)
    public static let onAccent     = dynamic(light: 0xFFFFFF, dark: 0x0B1033)
    public static let accentSoft   = dynamic(light: 0xE8ECFF, dark: 0x1D2347)
    public static let accentInk    = dynamic(light: 0x2238C9, dark: 0xB4C1FF)
    public static let ok           = dynamic(light: 0x167A49, dark: 0x5FD08F)
    public static let okSoft       = dynamic(light: 0xE3F4EA, dark: 0x13261B)
    public static let warn         = dynamic(light: 0x9A5B00, dark: 0xF2B54A)
    public static let warnSoft     = dynamic(light: 0xFFF1D6, dark: 0x2B2110)
    public static let err          = dynamic(light: 0xC2341F, dark: 0xFF8A75)
    public static let errSoft      = dynamic(light: 0xFDE9E5, dark: 0x2E1612)
    public static let inverse      = dynamic(light: 0x14161B, dark: 0xECEEF2)
    public static let onInverse    = dynamic(light: 0xF3F4F6, dark: 0x14161B)
}

/// Bilingual EN + RU localization helper matching Murmur's copy.
public struct L10n: Sendable {
    public let isRussian: Bool

    public init(uiLanguage: UiLanguage) {
        switch uiLanguage {
        case .ru: self.isRussian = true
        case .en: self.isRussian = false
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            self.isRussian = pref.hasPrefix("ru")
        }
    }

    public func t(_ en: String, _ ru: String) -> String {
        isRussian ? ru : en
    }

    public func errorText(_ error: MurmurError) -> String {
        switch error {
        case .noSpeech: return t("Didn't catch that", "Не удалось разобрать речь")
        case .noAsrModel: return t("Download a speech model first", "Сначала скачайте модель речи")
        case .noVadModel: return t("Download Silero VAD first", "Сначала скачайте Silero VAD")
        case .micPermissionDenied: return t("Microphone access needed", "Нужен доступ к микрофону")
        case .accessibilityPermissionDenied: return t("Accessibility access needed", "Нужен доступ к Универсальному доступу")
        case .passwordField: return t("Disabled in password fields", "Отключено в полях паролей")
        case .appExcluded: return t("Disabled in this app", "Отключено в этом приложении")
        case .engineRuntimeMissing: return t("Native engine library missing", "Не найдена нативная библиотека движка")
        case .micBusy, .micStartFailed: return t("Microphone unavailable", "Микрофон недоступен")
        default: return t("Dictation failed (\(error.code))", "Ошибка диктовки (\(error.code))")
        }
    }
}

public struct MurmacBadge: View {
    let text: String
    let fg: Color
    let bg: Color

    public init(_ text: String, fg: Color = MurmacColor.accentInk, bg: Color = MurmacColor.accentSoft) {
        self.text = text
        self.fg = fg
        self.bg = bg
    }

    public var body: some View {
        Text(text)
            .font(MurmacFonts.mono(11, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

public struct MurmacCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(MurmacColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MurmacColor.line, lineWidth: 1))
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
