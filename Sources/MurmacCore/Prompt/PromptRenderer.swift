import CryptoKit
import Foundation

/// Byte-exact Swift port of Murmur's `prompts/render.py` (and `RenderPy.kt` / `RenderPyPort.kt`).
public enum RenderPy {
    public static let maxBeforeCursor = 300

    public static let langNames: [String: String] = [
        "ru": "Russian", "en": "English", "uk": "Ukrainian",
        "de": "German", "fr": "French", "es": "Spanish",
    ]

    public static let fieldPhrases: [String: String] = [
        "message": "message field",
        "email_body": "email body",
        "email_subject": "email subject",
        "search": "search field",
        "address": "address field",
        "note": "note",
        "code": "code or terminal input",
        "generic": "text field",
        "none": "no text field focused",
    ]

    public static let emptyContext = "<context>\nApp: unknown app — text field\n</context>"

    private static func isCtrl(_ cp: UInt32) -> Bool {
        (cp <= 0x08) || (cp >= 0x0B && cp <= 0x1F) || (cp >= 0x7F && cp <= 0x9F) ||
            (cp >= 0x200B && cp <= 0x200F) || (cp >= 0x202A && cp <= 0x202E) ||
            (cp >= 0x2066 && cp <= 0x2069) || cp == 0xFEFF
    }

    private static func collapseWs(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var inRun = false
        for sc in s.unicodeScalars {
            if sc.value == 0x20 || sc.value == 0x09 || sc.value == 0xA0 {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(Character(sc))
                inRun = false
            }
        }
        return out
    }

    private static func collapseBlankLines(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var run = 0
        for sc in s.unicodeScalars {
            if sc.value == 0x0A {
                run += 1
                if run <= 2 { out.append("\n") }
            } else {
                run = 0
                out.append(Character(sc))
            }
        }
        return out
    }

    public static func clean(_ s: String?, keepNewlines: Bool = false) -> String {
        guard let s, !s.isEmpty else { return "" }
        var t = s.precomposedStringWithCanonicalMapping // Unicode NFC
        if t.unicodeScalars.contains(where: { isCtrl($0.value) }) {
            var filtered = String.UnicodeScalarView()
            for sc in t.unicodeScalars where !isCtrl(sc.value) { filtered.append(sc) }
            t = String(filtered)
        }
        t = t.replacingOccurrences(of: "<", with: "‹").replacingOccurrences(of: ">", with: "›")
        if keepNewlines {
            let lines = Py.splitlines(t).map { Py.strip(collapseWs($0)) }.joined(separator: "\n")
            return Py.strip(collapseBlankLines(lines))
        } else {
            let flat = t.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            return Py.strip(collapseWs(flat))
        }
    }

    public static func clipEnd(_ s: String, _ n: Int) -> String {
        let c = Py.cps(s)
        if c.count <= n { return s }
        var end = Py.sliceEnd(size: c.count, n: n)
        var sp = -1
        if end > 0 {
            for k in stride(from: end - 1, through: 0, by: -1) {
                if c[k] == 0x20 { sp = k; break }
            }
        }
        if Double(sp) > Double(n) * 0.6 { end = sp }
        return Py.rstrip(Py.str(c, from: 0, to: end)) + "…"
    }

    public static func clipStart(_ s: String, _ n: Int) -> String {
        let c = Py.cps(s)
        if c.count <= n { return s }
        var start = Py.sliceStartFromEnd(size: c.count, n: n)
        var sp = -1
        for k in start..<c.count {
            if c[k] == 0x20 { sp = k - start; break }
        }
        if sp >= 0 && Double(sp) < Double(n) * 0.4 { start += sp + 1 }
        return "…" + Py.lstrip(Py.str(c, from: start, to: c.count))
    }

    public struct Ctx2Options {
        public let budget: Double
        public let order: String?
        public let minConf: Double
        public let minChars: Double
        public let dropClock: Bool
        public let dedup: Bool
        public let merge: Bool
        public let side: Bool
        public let terms: Bool
        public let lineMax: Int

        public init(_ o: [String: JSONValue]?) throws {
            self.budget = try Self.num(o?["budget"], default: 1400.0)
            if let ord = o?["order"] {
                self.order = ord.stringValue
            } else {
                self.order = "near"
            }
            self.minConf = try Self.num(o?["min_conf"], default: 0.5)
            self.minChars = try Self.num(o?["min_chars"], default: 2.0)
            self.dropClock = Self.truthy(o?["drop_clock"], default: true)
            self.dedup = Self.truthy(o?["dedup"], default: true)
            self.merge = Self.truthy(o?["merge"], default: true)
            self.side = Self.truthy(o?["side"], default: false)
            self.terms = Self.truthy(o?["terms"], default: false)
            if let lm = o?["line_max"] {
                let d = try Self.num(lm, default: 240.0)
                guard d == floor(d) else { throw MurmurError.internalError("ctx2.line_max must be an integer") }
                self.lineMax = Int(d)
            } else {
                self.lineMax = 240
            }
        }

        private static func num(_ e: JSONValue?, default def: Double) throws -> Double {
            guard let e else { return def }
            switch e {
            case .bool(let b): return b ? 1.0 : 0.0
            case .number(let n): return n
            default: throw MurmurError.internalError("ctx2 option must be a number")
            }
        }

        private static func truthy(_ e: JSONValue?, default def: Bool) -> Bool {
            guard let e else { return def }
            switch e {
            case .null: return false
            case .bool(let b): return b
            case .number(let n): return n != 0.0
            case .string(let s): return !s.isEmpty
            case .array(let a): return !a.isEmpty
            case .object(let o): return !o.isEmpty
            }
        }
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        let r = a % b
        return (r != 0 && ((a < 0) != (b < 0))) ? (q - 1) : q
    }

    private static func screenSize(_ ctx: CtxV2) -> (Int, Int) {
        if let s = ctx.screen?.size, s.count >= 2 { return (s[0], s[1]) }
        return (1080, 2520)
    }

    private static func alnumCount(_ t: String) -> Int {
        var count = 0
        for sc in t.unicodeScalars {
            if sc.value != 0x5F && Py.isWord(sc.value) { count += 1 }
        }
        return count
    }

    private static let clockPunct: Set<UInt32> = Set(":.,/%+-–—()|·•".unicodeScalars.map(\.value))

    public static func isClock(_ text: String) -> Bool {
        let c = Py.cps(text)
        let n = c.count
        func inA(_ cp: UInt32) -> Bool { Py.isDecimal(cp) || Py.isSpace(cp) || clockPunct.contains(cp) }
        func eq(_ cp: UInt32, _ ch: Unicode.Scalar) -> Bool { Py.ignoreCaseEquals(cp, ch) }

        var suffixOk = Array(repeating: false, count: n + 1)
        suffixOk[n] = true
        if n > 0 {
            for k in stride(from: n - 1, through: 0, by: -1) {
                suffixOk[k] = suffixOk[k + 1] && inA(c[k])
            }
        }
        var k = 0
        while true {
            if suffixOk[k] { return true }
            var ends: [Int] = []
            if k < n && (eq(c[k], "a") || eq(c[k], "p")) {
                var p = k + 1
                if p < n && c[p] == 0x2E { p += 1 }
                if p < n && eq(c[p], "m") {
                    p += 1
                    ends.append(p)
                    if p < n && c[p] == 0x2E { ends.append(p + 1) }
                }
            }
            if k < n && eq(c[k], "ч") { ends.append(k + 1) }
            if k + 2 < n && eq(c[k], "м") && eq(c[k + 1], "и") && eq(c[k + 2], "н") { ends.append(k + 3) }
            if k + 2 < n && eq(c[k], "l") && eq(c[k + 1], "t") && eq(c[k + 2], "e") { ends.append(k + 3) }
            if k < n && eq(c[k], "g") { ends.append(k + 1) }
            if ends.contains(where: { suffixOk[$0] }) { return true }
            if k < n && inA(c[k]) { k += 1 } else { return false }
        }
    }

    public struct Block2 {
        public let i: Int
        public let text: String
        public let box: [Int]
        public let right: Bool
    }

    private final class MutableBlock {
        var text: String
        var box: [Int]
        var last: [Int]
        init(text: String, box: [Int], last: [Int]) {
            self.text = text; self.box = box; self.last = last
        }
    }

    public static func ocrBlocks(_ ctx: CtxV2, _ o: Ctx2Options) -> [Block2] {
        let w = screenSize(ctx).0
        let fbox = (ctx.field?.box?.isEmpty == false) ? ctx.field?.box : nil
        let hint = Py.casefold(clean(ctx.field?.hint))
        var kept: [(String, [Int])] = []
        var seen: Set<String> = []

        for ln in ctx.screen?.lines ?? [] {
            let t = clean(ln.text)
            let box = ln.box
            if t.isEmpty || ln.conf < o.minConf || Double(alnumCount(t)) < o.minChars { continue }
            if let fbox, fbox.count >= 4, box.count >= 4 {
                let cx = floorDiv(box[0] + box[2], 2)
                let cy = floorDiv(box[1] + box[3], 2)
                if fbox[0] <= cx && cx <= fbox[2] && fbox[1] <= cy && cy <= fbox[3] { continue }
            }
            let tf = Py.casefold(t)
            if !hint.isEmpty && tf == hint { continue }
            if o.dedup {
                if !seen.insert(tf).inserted { continue }
            }
            kept.append((t, box))
        }

        var blocks: [MutableBlock] = []
        for (text, box) in kept {
            let lh = box[3] - box[1]
            if let b = blocks.last {
                let bh = b.last[3] - b.last[1]
                if o.merge && abs(box[0] - b.last[0]) * 50 <= w && abs(lh - bh) * 10 <= bh &&
                    0 <= box[1] - b.last[3] && (box[1] - b.last[3]) * 2 < max(1, bh) {
                    b.text += " \(text)"
                    b.box = [min(b.box[0], box[0]), b.box[1], max(b.box[2], box[2]), box[3]]
                    b.last = box
                    continue
                }
            }
            blocks.append(MutableBlock(text: text, box: box, last: box))
        }

        if o.dropClock {
            blocks = blocks.filter { !(Py.len($0.text) <= 12 && isClock($0.text)) }
        }
        return blocks.enumerated().map { idx, b in
            let isRight = b.box[0] * 100 >= 15 * w && (w - b.box[2]) * 10 < w
            return Block2(i: idx, text: clipEnd(b.text, o.lineMax), box: b.box, right: isRight)
        }
    }

    private static func fieldAnchorY(_ ctx: CtxV2) -> Int {
        if let fbox = ctx.field?.box, fbox.count >= 4 {
            return floorDiv(fbox[1] + fbox[3], 2)
        }
        return screenSize(ctx).1
    }

    private static let termStrip = ".,;:!?()«»\"“”‹›'’-–—…"
    private static let specialJoin: Set<UInt32> = Set("#@_./-".unicodeScalars.map(\.value))

    private static func isCamelLower(_ cp: UInt32) -> Bool {
        (cp >= 0x61 && cp <= 0x7A) || (cp >= 0x430 && cp <= 0x44F) || cp == 0x451
    }
    private static func isCamelUpper(_ cp: UInt32) -> Bool {
        (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x410 && cp <= 0x42F) || cp == 0x401
    }
    private static func isAlnumNotDecimal(_ cp: UInt32) -> Bool {
        cp != 0x5F && Py.isWord(cp) && !Py.isDecimal(cp)
    }

    private static func hasSpecial(_ c: [UInt32]) -> Bool {
        for k in 0..<c.count {
            if k + 2 < c.count && Py.isWord(c[k]) && specialJoin.contains(c[k + 1]) && Py.isWord(c[k + 2]) { return true }
            if k + 1 < c.count && isAlnumNotDecimal(c[k]) && Py.isDecimal(c[k + 1]) { return true }
            if k + 1 < c.count && Py.isDecimal(c[k]) && isAlnumNotDecimal(c[k + 1]) { return true }
        }
        return false
    }

    public static func ocrTerms(_ texts: [String], limit: Int = 20) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        func add(_ x: String) {
            if Py.len(x) >= 3 && seen.insert(Py.casefold(x)).inserted { out.append(x) }
        }
        for t in texts {
            let tc = Py.cps(t)
            let cyrCount = tc.reduce(0) { $0 + (Py.isCyrillic($1) ? 1 : 0) }
            let latCount = tc.reduce(0) { $0 + (Py.lowerIsAsciiLetter($1) ? 1 : 0) }
            let cyrLine = cyrCount > latCount
            let toks = Py.split(t)
            var run: [String] = []
            var runStart = false
            func flush() {
                if !run.isEmpty && (run.count >= 2 || !runStart) {
                    add(run.joined(separator: " "))
                }
                run.removeAll(keepingCapacity: true)
            }
            for (j, tok) in toks.enumerated() {
                let core = Py.strip(tok, chars: termStrip)
                let cc = Py.cps(core)
                let sentStart = j == 0 || ".!?…".contains(Py.last(toks[j - 1]))
                let letters = cc.filter { Py.isAlpha($0) }
                let spec = hasSpecial(cc)
                let camel = cc.count >= 2 && (0..<(cc.count - 1)).contains { isCamelLower(cc[$0]) && isCamelUpper(cc[$0 + 1]) }
                let caps = letters.count >= 2 && letters.allSatisfy { Py.isUpper($0) }
                let latin = cyrLine && letters.count >= 4 && letters.allSatisfy { Py.lowerIsAsciiLetter($0) }
                if cc.isEmpty {
                    flush()
                } else if spec || camel || caps {
                    flush()
                    add(core)
                } else if Py.isUpper(cc[0]) && cc.count >= 2 && Py.isLower(cc[1]) {
                    if run.isEmpty { runStart = sentStart }
                    run.append(core)
                    if ",.!?…;:".contains(Py.last(tok)) { flush() }
                } else {
                    flush()
                    if latin { add(core) }
                }
            }
            flush()
        }
        return Array(out.prefix(Py.sliceEnd(size: out.count, n: limit)))
    }

    public static func renderContextV2(_ ctx: CtxV2, _ ctx2: [String: JSONValue]?) throws -> String {
        let o = try Ctx2Options(ctx2)
        let privacy = ctx.privacy?.level ?? "full"
        let field = ctx.field
        var label = clean(ctx.app.label)
        if label.isEmpty { label = "unknown app" }
        if privacy == "none" { label = "unknown app" }
        let kind: String
        if let k = field?.kind, !k.isEmpty {
            kind = k
        } else if field == nil || field?.isEmptyObject == true {
            kind = "none"
        } else {
            kind = "generic"
        }
        var out: [String] = []
        out.append("App: \(label) — \(fieldPhrases[kind] ?? "text field")")
        let hint = clipEnd(clean(field?.hint), 60)
        if !hint.isEmpty && privacy != "none" { out.append("Field hint: «\(hint)»") }
        if let lang = ctx.language?.asr, !lang.isEmpty {
            out.append("Dictation language: \(langNames[lang] ?? lang)")
        }
        if privacy == "app_only" || privacy == "none" {
            return "<context>\n" + out.joined(separator: "\n") + "\n</context>"
        }
        let before = clipStart(clean(field?.beforeCursor), maxBeforeCursor)
        if !before.isEmpty { out.append("Text already in the field before the cursor: «\(before)»") }
        let blocks = ocrBlocks(ctx, o)
        let ranked: [Block2]
        if o.order == "reading" {
            ranked = blocks
        } else {
            let ay = fieldAnchorY(ctx)
            ranked = blocks.sorted { a, b in
                let da = abs(floorDiv(a.box[1] + a.box[3], 2) - ay)
                let db = abs(floorDiv(b.box[1] + b.box[3], 2) - ay)
                return da != db ? da < db : a.i < b.i
            }
        }
        var shown: [(Int, String)] = []
        var used = 0
        for b in ranked {
            let s = (o.side && b.right ? "» " : "") + b.text
            let l = Py.len(s)
            if Double(used + l + 1) > o.budget { break }
            shown.append((b.i, s))
            used += l + 1
        }
        if o.order == "near_reading" {
            shown.sort { $0.0 < $1.0 }
        }
        if !shown.isEmpty {
            let head: String
            switch o.order {
            case "near": head = "Screen text (OCR, nearest to the field first):"
            case "near_reading", "reading": head = "Screen text (OCR, top to bottom):"
            default: throw MurmurError.internalError("ctx2.order must be near, near_reading or reading")
            }
            out.append(head)
            for (_, s) in shown { out.append(s) }
            if o.terms {
                let terms = ocrTerms(shown.sorted { $0.0 < $1.0 }.map(\.1))
                if !terms.isEmpty { out.append("Terms on screen: " + terms.joined(separator: "; ")) }
            }
        }
        return "<context>\n" + out.joined(separator: "\n") + "\n</context>"
    }

    public static func renderContext(_ ctx: CtxV2?, _ ctx2: [String: JSONValue]?) throws -> String {
        guard let ctx else { return emptyContext }
        guard ctx.v == 2 else { throw MurmurError.internalError("only ctx v2 is rendered") }
        return try renderContextV2(ctx, ctx2)
    }

    public static func styleLine(_ ctx: CtxV2?, tones: [String: JSONValue], override: String?) -> String {
        if let override, !override.isEmpty { return "Style: " + clean(override) }
        var cat = (ctx?.app.category?.isEmpty == false) ? ctx!.app.category! : "default"
        if let variation = ctx?.field?.inputTypeVariation, !variation.isEmpty,
           let fo = tones["field_overrides"]?.objectValue,
           let mapped = fo[variation]?.stringValue {
            cat = mapped
        }
        let cats = tones["categories"]?.objectValue ?? [:]
        let entry: [String: JSONValue]
        if let e = cats[cat]?.objectValue, !e.isEmpty {
            entry = e
        } else {
            entry = cats["default"]?.objectValue ?? [:]
        }
        return "Style: " + (entry["text"]?.stringValue ?? "")
    }

    public static func versioned(_ name: String) -> String {
        let n = name.hasSuffix("\n") ? String(name.dropLast()) : name
        let c = Py.cps(n)
        var k = c.count
        while k > 0 && Py.isDecimal(c[k - 1]) { k -= 1 }
        let ok = k < c.count && k >= 2 && c[k - 1] == 0x76 && c[k - 2] == 0x2E // ".v"
        return ok ? name : "\(name).v1"
    }

    public static func userMessage(
        ctx: CtxV2?,
        transcript: String,
        styleOverride: String?,
        ctx2: [String: JSONValue]?,
        tones: [String: JSONValue]
    ) throws -> String {
        let style = styleLine(ctx, tones: tones, override: styleOverride)
        let place = ctx2?["place"]?.stringValue
        if let ctx, ctx.v == 2, place == "after" {
            return "\(style)\n<transcript>\n\(clean(transcript))\n</transcript>\n\(try renderContext(ctx, ctx2))"
        } else {
            return "\(style)\n\(try renderContext(ctx, ctx2))\n<transcript>\n\(clean(transcript))\n</transcript>"
        }
    }

    public struct ChatTemplate: Sendable {
        public let bos: String
        public let prior: String
        public let finalOpener: String
    }

    public static let templates: [String: ChatTemplate] = [
        "qwen3.5": ChatTemplate(bos: "", prior: "<|im_start|>assistant\n", finalOpener: "<|im_start|>assistant\n<think>\n\n</think>\n\n"),
        "qwen3": ChatTemplate(bos: "", prior: "<|im_start|>assistant\n", finalOpener: "<|im_start|>assistant\n<think>\n\n</think>\n\n"),
        "lfm3": ChatTemplate(bos: "<|startoftext|>", prior: "<|im_start|>assistant\n<think></think>", finalOpener: "<|im_start|>assistant\n<think></think>"),
        "lfm2.5": ChatTemplate(bos: "<|startoftext|>", prior: "<|im_start|>assistant\n", finalOpener: "<|im_start|>assistant\n"),
    ]

    public static func template(_ name: String) throws -> ChatTemplate {
        guard let t = templates[name] else {
            throw MurmurError.internalError("unknown chat template: \(name)")
        }
        return t
    }

    public static func prefix(system: String, turns: [(String, String)], tpl: ChatTemplate) -> String {
        var out = "\(tpl.bos)<|im_start|>system\n\(system)<|im_end|>\n"
        for (u, a) in turns {
            out += "<|im_start|>user\n\(u)<|im_end|>\n\(tpl.prior)\(a)<|im_end|>\n"
        }
        out += "<|im_start|>user\n"
        return out
    }

    public static func suffix(user: String, tpl: ChatTemplate, answerPrefix: String) -> String {
        "\(user)<|im_end|>\n\(tpl.finalOpener)\(answerPrefix)"
    }
}

public final class RenderPyPort: PromptRenderer, @unchecked Sendable {
    private let assets: PromptAssets
    private let lock = NSLock()
    private lazy var tones: [String: JSONValue] = {
        guard let raw = try? assets.text(path: "tones/tones.v1.json"),
              let data = raw.data(using: .utf8),
              let val = try? JSONDecoder().decode(JSONValue.self, from: data),
              let obj = val.objectValue
        else { return [:] }
        return obj
    }()

    private struct PrefixKey: Hashable {
        let profile: PromptProfile
        let template: String
        let preferences: String?
        let systemOverride: String?
    }

    private var turnsCache: [PromptProfile: [(String, String)]] = [:]
    private var prefixCache: [PrefixKey: (text: String, key: String)] = [:]

    public init(assets: PromptAssets = BundlePromptAssets()) {
        self.assets = assets
    }

    public func render(_ input: RenderInput) throws -> RenderedPrompt {
        let tpl = try RenderPy.template(input.template)
        let p = try cachedPrefix(
            profile: input.profile,
            template: input.template,
            preferences: input.preferences,
            systemOverride: input.systemOverride
        )
        let user = try RenderPy.userMessage(
            ctx: input.ctx,
            transcript: input.transcript,
            styleOverride: input.styleOverride,
            ctx2: input.profile.ctx2,
            tones: getTones()
        )
        return RenderedPrompt(
            prefix: p.text,
            suffix: RenderPy.suffix(user: user, tpl: tpl, answerPrefix: input.profile.answerPrefix),
            prefixKey: p.key
        )
    }

    public func renderContext(_ ctx: CtxV2, ctx2: [String: JSONValue]? = nil) throws -> String {
        try RenderPy.renderContext(ctx, ctx2)
    }

    public func cachePrefix(profile: PromptProfile, template: String, preferences: String?, systemOverride: String?) throws -> String {
        try cachedPrefix(profile: profile, template: template, preferences: preferences, systemOverride: systemOverride).text
    }

    public func systemPrompt(profile: PromptProfile, preferences: String?, systemOverride: String?) throws -> String {
        let base: String
        if let ov = systemOverride {
            base = trimEndNewlines(ov.replacingOccurrences(of: "\r\n", with: "\n"))
        } else {
            base = try systemFile(profile.system)
        }
        let prefs = (preferences?.isEmpty == false) ? RenderPy.clean(preferences, keepNewlines: true) : ""
        if prefs.isEmpty { return base }
        let block = try systemFile(profile.preferencesBlock)
        return base + block.replacingOccurrences(of: "{{PREFERENCES}}", with: Py.head(prefs, PromptEditRules.maxPreferencesChars))
    }

    public func styleLine(_ ctx: CtxV2?, styleOverride: String?) -> String {
        RenderPy.styleLine(ctx, tones: getTones(), override: styleOverride)
    }

    public func toneText(_ tone: String) -> String? {
        let t = getTones()
        guard let named = t["named"]?.objectValue,
              let entry = named[tone.lowercased()]?.objectValue,
              let txt = entry["text"]?.stringValue,
              !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return txt
    }

    private func getTones() -> [String: JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return tones
    }

    private func systemFile(_ stem: String) throws -> String {
        let raw = try assets.systemPrompt(stem: RenderPy.versioned(stem))
        let norm = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return trimEndNewlines(norm)
    }

    private func trimEndNewlines(_ s: String) -> String {
        var idx = s.unicodeScalars.endIndex
        while idx > s.unicodeScalars.startIndex {
            let prev = s.unicodeScalars.index(before: idx)
            if s.unicodeScalars[prev].value != 0x0A { break }
            idx = prev
        }
        return String(s.unicodeScalars[..<idx])
    }

    private func profileTurns(_ profile: PromptProfile) throws -> [(String, String)] {
        lock.lock()
        if let hit = turnsCache[profile] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let result: [(String, String)]
        if let path = profile.shots, !path.isEmpty {
            let shots = try assets.shots(path: path)
            let t = getTones()
            result = try shots.map { shot in
                let u = try RenderPy.userMessage(ctx: shot.ctx, transcript: shot.transcript, styleOverride: nil, ctx2: profile.ctx2, tones: t)
                return (u, shot.target)
            }
        } else {
            result = []
        }

        lock.lock()
        if turnsCache.count >= 8 { turnsCache.removeAll() }
        turnsCache[profile] = result
        lock.unlock()
        return result
    }

    private func cachedPrefix(profile: PromptProfile, template: String, preferences: String?, systemOverride: String?) throws -> (text: String, key: String) {
        let key = PrefixKey(profile: profile, template: template, preferences: preferences, systemOverride: systemOverride)
        lock.lock()
        if let hit = prefixCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let sys = try systemPrompt(profile: profile, preferences: preferences, systemOverride: systemOverride)
        let turns = try profileTurns(profile)
        let tpl = try RenderPy.template(template)
        let text = RenderPy.prefix(system: sys, turns: turns, tpl: tpl)
        let hash = Self.sha256Hex(text)

        lock.lock()
        if prefixCache.count >= 16 { prefixCache.removeAll() }
        prefixCache[key] = (text, hash)
        lock.unlock()
        return (text, hash)
    }

    public static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
