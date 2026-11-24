import Foundation

/// Byte-exact Swift port of Murmur's `prompts/guard.py` (GUARD_VERSION = guard.v1.1) and `GuardPyPort.kt`.
public final class GuardPyPort: OutputGuard, Sendable {
    public static let guardVersion = "guard.v1.1"

    public static let defaultFillers: Set<String> = Set(
        "э ээ эээ э-э э-э-э м мм ммм м-м хм гм а-а ну эм ам um uh uhm uh-huh erm er hmm hm mm mmm ah eh"
            .split(separator: " ").map(String.init)
    )

    public var fillers: Set<String> { Self.defaultFillers }

    private static let growK = 1.5
    private static let growAdd = 4.0
    private static let charGrowK = 2.5
    private static let charGrowAdd = 40.0
    private static let shrinkK = 0.3
    private static let shrinkMinIn = 8
    private static let novelMin = 3
    private static let novelShare = 0.5
    private static let novelSim = 0.75
    private static let scriptMinLetters = 8
    private static let distractorSim = 0.6
    private static let rivalMargin = 0.15
    private static let noScriptCheck: Set<String> = ["code", "address"]
    private static let spanLostMin = 1
    private static let spanSim = 0.5
    private static let spanKeepSim = 0.7

    private static let W = "[\(Py.W)]"
    private static let S = "[\(Py.S)]"
    private static let NS = "[^\(Py.S)]"
    private static let B = "(?!\(W))"

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Force UNIX lines behavior: `.` matches anything except `\n` (unless dotMatchesLineSeparators is set).
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func ci(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        compile(Py.ignoreCase(pattern), options: options)
    }

    private static let halluFull = ci(
        "^(?:\\[?\(S)*(?:blank_audio|silence|music|музыка|тишина|аплодисменты|смех)\(S)*\\]?|" +
        "\\(?\(S)*(?:music|музыка)\(S)*\\)?|" +
        "thanks? (?:you )?for watching!?|thank you for watching!?|please subscribe.*|" +
        "продолжение следует\\.*|спасибо за просмотр!?|подписывайтесь на канал.*|" +
        "субтитры (?:сделал|делал|создавал|подготовил)\(W)*\(S).*|редактор субтитров\(S).*|" +
        "корректор\(S)+\(NS)+\\.\(S)*\(NS)+|dimatorzok)$"
    )
    private static let halluTail = ci(
        "(?:(?<=[.!?…])\(S)*|\(S)+)(?:продолжение следует\\.*|субтитры (?:сделал|делал|создавал|подготовил)\(W)*\(S).*|" +
        "редактор субтитров\(S).*|thanks? for watching!?|thank you for watching!?|\\[blank_audio\\])\(S)*$"
    )
    private static let thinkRegex = compile("<think>.*?</think>\(S)*|^.*?</think>\(S)*", options: [.dotMatchesLineSeparators])
    private static let chatTokensRegex = compile("<\\|[a-z_]+\\|>|<\\|im_end\\|>|<\\|endoftext\\|>")
    private static let labelRegex = ci(
        "^\(S)*(?:output|edited text|edited|result|corrected text|text|вывод|результат|текст|" +
        "исправленный текст|отредактированный текст)\(S)*:\(S)*"
    )
    private static let leakRegex = ci(
        "</?(?:context|transcript|preferences)>|^\(S)*Style:|<\\|im_|<think|Names and terms on screen|" +
        "Dictation language:|Text already in the field",
        options: [.anchorsMatchLines]
    )
    private static let preambleRegex = ci(
        "^\(S)*(?:sure\(B)|certainly\(B)|of course\(B)|here is\(B)|here's\(B)|here are\(B)|okay, here\(B)|i'm sorry\(B)|i cannot\(B)|" +
        "as an ai\(B)|конечно[,!]|вот (?:исправленный|ваш|отредактированный|готовый)|исправленный текст|" +
        "отредактированный текст|извините, (?:я|но)|я не могу\(B))"
    )
    private static let charLoopRegex = compile("(.{1,6}?)\\1{7,}", options: [.dotMatchesLineSeparators])
    private static let fenceRegex = compile("^```\(W)*\\n?|\\n?```$")
    private static let spanSplitRegex = compile("[-_'’]")

    private static let quotePairs: [Unicode.Scalar: Unicode.Scalar] = [
        "\"": "\"", "«": "»", "“": "”", "'": "'", "`": "`",
    ]

    private static let tr: [UInt32: String] = {
        let src = Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя".unicodeScalars)
        let dst = ["a","b","v","g","d","e","e","zh","z","i","i","k","l","m","n","o","p","r","s",
                   "t","u","f","h","ts","ch","sh","sch","","y","","e","yu","ya"]
        var m: [UInt32: String] = [:]
        for i in 0..<src.count { m[src[i].value] = dst[i] }
        return m
    }()

    private static let phon: [(String, String)] = [
        ("sch", "sh"), ("ph", "f"), ("ck", "k"), ("qu", "kv"), ("w", "v"), ("th", "t"),
        ("x", "ks"), ("c", "k"), ("y", "i"), ("j", "dj"), ("q", "k"), ("ou", "au"), ("ee", "i"), ("oo", "u"), ("h", ""),
    ]

    public init() {}

    private static func matches(_ rx: NSRegularExpression, in s: String) -> Bool {
        let ns = s as NSString
        return rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func firstMatchString(_ rx: NSRegularExpression, in s: String) -> String? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    private static func replaceAll(_ rx: NSRegularExpression, in s: String, with template: String) -> String {
        let ns = s as NSString
        return rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    private static func replaceFirst(_ rx: NSRegularExpression, in s: String, with template: String) -> String {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return s }
        return ns.replacingCharacters(in: m.range, with: template)
    }

    public func precheck(_ transcript: String) -> Precheck {
        let t = Py.strip(transcript.precomposedStringWithCanonicalMapping)
        let bare = Py.strip(t, chars: " .,!?…-—\"'«»()[]")
        if content(words(bare)).isEmpty {
            return Precheck(skip: true, transcript: "", reason: bare.isEmpty ? "empty" : "filler_only")
        }
        if Self.matches(Self.halluFull, in: bare) {
            return Precheck(skip: true, transcript: "", reason: "asr_hallucination")
        }
        let cut = Py.rstrip(Self.replaceAll(Self.halluTail, in: t, with: ""))
        if cut != t && !cut.isEmpty {
            return Precheck(skip: false, transcript: cut, reason: "tail_removed")
        }
        return Precheck(skip: false, transcript: t, reason: "ok")
    }

    public func fallbackText(transcript: String, ctx: CtxV2?) -> String {
        var t = Py.strip(transcript)
        let cat = ctx?.app.category
        let before = Py.rstrip(ctx?.field?.beforeCursor ?? "")
        let mid = !before.isEmpty && !".!?…:\n".contains(Py.last(before))
        if !t.isEmpty && cat != "search" && cat != "address" && cat != "code" && !mid {
            t = Py.upperFirst(t)
        }
        return t
    }

    public func repair(output: String, transcript: String, ctx: CtxV2?) -> String {
        var o = Self.replaceAll(Self.thinkRegex, in: output, with: "")
        o = Py.strip(Self.replaceAll(Self.chatTokensRegex, in: o, with: ""))
        o = Py.strip(Self.replaceFirst(Self.labelRegex, in: o, with: ""))
        let t = Py.strip(transcript)
        if o.hasPrefix("```") && o.hasSuffix("```") && Py.len(o) > 6 && !t.hasPrefix("```") {
            o = Py.strip(Self.replaceAll(Self.fenceRegex, in: o, with: ""))
        }
        while Py.len(o) >= 2 {
            guard let q = o.unicodeScalars.first, let close = Self.quotePairs[q] else { break }
            let lastSc = o.unicodeScalars.last
            let tFirst = t.unicodeScalars.first
            let qCount = o.unicodeScalars.reduce(0) { $0 + ($1 == q ? 1 : 0) }
            let expected = (q == close) ? 2 : 1
            if lastSc != close || tFirst == q || qCount != expected { break }
            let inner = String(o.unicodeScalars.dropFirst().dropLast())
            o = Py.strip(inner)
        }
        let before = Py.strip(ctx?.field?.beforeCursor ?? "")
        if Py.len(before) >= 15 && o.hasPrefix(before) {
            o = Py.lstrip(String(o.dropFirst(before.count)))
        }
        return o
    }

    public func guardOutput(transcript: String, output: String, ctx: CtxV2?) -> GuardVerdict {
        let pre = precheck(transcript)
        if pre.skip { return GuardVerdict(text: "", action: .empty, reason: pre.reason) }
        let tr = pre.transcript
        let fb = fallbackText(transcript: tr, ctx: ctx)
        let o = repair(output: output, transcript: tr, ctx: ctx)
        let cat = ctx?.app.category
        let tw = content(words(tr))
        let ow = content(words(o))
        func fallback(_ reason: String) -> GuardVerdict {
            GuardVerdict(text: fb, action: .fallback, reason: reason)
        }

        if o.isEmpty { return fallback("R1_empty") }
        if Self.matches(Self.leakRegex, in: o) { return fallback("R2_leaked_tags") }
        if Self.matches(Self.preambleRegex, in: o) && !Self.matches(Self.preambleRegex, in: tr) {
            return fallback("R3_preamble")
        }
        let grams = trigrams(ow)
        let tgrams = trigrams(tw)
        for (g, n) in grams where n >= 4 && (tgrams[g] ?? 0) < 2 {
            return fallback("R4_loop")
        }
        if let m = Self.firstMatchString(Self.charLoopRegex, in: o), !tr.contains(m) {
            return fallback("R4_loop")
        }
        if Double(Py.len(o)) > Self.charGrowK * Double(Py.len(tr)) + Self.charGrowAdd {
            return fallback("R4_length")
        }
        if Double(ow.count) > Self.growK * Double(tw.count) + Self.growAdd ||
            (tw.count >= Self.shrinkMinIn && Double(ow.count) < Self.shrinkK * Double(tw.count)) {
            return fallback("R4_length")
        }
        if cat == nil || !Self.noScriptCheck.contains(cat!) {
            let (tl, tc) = letters(tr)
            let (ol, oc) = letters(o)
            let tn = tl + tc
            let on = ol + oc
            if tn >= Self.scriptMinLetters && on != 0 {
                for (ts, os) in [(tl, ol), (tc, oc)] {
                    if ts >= Self.scriptMinLetters && Double(ts) / Double(tn) >= 0.2 && Double(os) / Double(on) < 0.05 {
                        return fallback("R5_script")
                    }
                }
                if Double(tc) / Double(tn) >= 0.7 && Double(oc) / Double(on) < 0.3 {
                    return fallback("R5_script")
                }
            }
            if translatedSpan(transcript: tr, output: o) {
                return fallback("R5b_translated_span")
            }
        }
        var allowed = Set(words(tr).map { Py.head($0, 5) })
        allowed.formUnion(screenWords(ctx))
        let contentWords = ow.filter { Py.len($0) >= 4 && !Py.isDigitString($0) }
        let novel = contentWords.filter { !allowed.contains(Py.head($0, 5)) && bestSim(term: $0, transcript: tr) < Self.novelSim }
        if novel.count >= Self.novelMin && !contentWords.isEmpty && Double(novel.count) / Double(contentWords.count) > Self.novelShare {
            return fallback("R6_novel")
        }
        let oFold = Py.casefold(o)
        let tFold = Py.casefold(tr)
        let terms = screenTerms(ctx)
        for term in terms {
            let f = Py.casefold(term)
            if !oFold.contains(f) || tFold.contains(f) { continue }
            let sTerm = bestSim(term: term, transcript: tr)
            let rivals = terms
                .filter { $0 != term && !oFold.contains(Py.casefold($0)) }
                .map { bestSim(term: $0, transcript: tr) }
            if sTerm < Self.distractorSim || rivals.contains(where: { $0 >= sTerm + Self.rivalMargin }) {
                return fallback("R7_distractor")
            }
        }
        return GuardVerdict(text: o, action: .accept, reason: o == Py.strip(output) ? "ok" : "repaired")
    }

    public func wordTokens(_ s: String) -> [String] {
        let c = Py.cps(s)
        var out: [String] = []
        var k = 0
        while k < c.count {
            if !Py.isWord(c[k]) { k += 1; continue }
            let start = k
            while k < c.count && Py.isWord(c[k]) { k += 1 }
            while k + 1 < c.count && (c[k] == 0x2D || c[k] == 0x27 || c[k] == 0x2019) && Py.isWord(c[k + 1]) {
                k += 1
                while k < c.count && Py.isWord(c[k]) { k += 1 }
            }
            out.append(Py.str(c, from: start, to: k))
        }
        return out
    }

    public func words(_ s: String) -> [String] {
        wordTokens(s).map { Py.casefold($0).replacingOccurrences(of: "ё", with: "е") }
    }

    private func content(_ ws: [String]) -> [String] {
        ws.filter { !Self.defaultFillers.contains($0) }
    }

    private func trigrams(_ ws: [String]) -> [String: Int] {
        guard ws.count >= 3 else { return [:] }
        var m: [String: Int] = [:]
        for i in 0..<(ws.count - 2) {
            let key = "\(ws[i]) \(ws[i + 1]) \(ws[i + 2])"
            m[key, default: 0] += 1
        }
        return m
    }

    private func letters(_ s: String) -> (Int, Int) {
        var lat = 0
        var cyr = 0
        for sc in s.unicodeScalars {
            if Py.lowerIsAsciiLetter(sc.value) { lat += 1 }
            if Py.isCyrillic(sc.value) { cyr += 1 }
        }
        return (lat, cyr)
    }

    public func phoneticKey(_ s: String) -> String {
        let nfkd = Py.casefold(s).decomposedStringWithCompatibilityMapping
        var b = ""
        b.reserveCapacity(nfkd.count)
        for sc in nfkd.unicodeScalars {
            let cp = sc.value
            if let rep = Self.tr[cp] {
                b += rep
            } else if (cp >= 0x61 && cp <= 0x7A) || (cp >= 0x30 && cp <= 0x39) {
                b.append(Character(sc))
            }
        }
        var k = b
        for (x, y) in Self.phon {
            k = k.replacingOccurrences(of: x, with: y)
        }
        var v = ""
        v.reserveCapacity(k.count)
        var prevVowel = false
        for ch in k {
            let isV = ch == "a" || ch == "e" || ch == "i" || ch == "o" || ch == "u"
            if isV {
                if !prevVowel { v.append("a") }
            } else {
                v.append(ch)
            }
            prevVowel = isV
        }
        var d = ""
        d.reserveCapacity(v.count)
        var prev: Character? = nil
        for ch in v {
            if prev != ch {
                d.append(ch)
                prev = ch
            }
        }
        return d
    }

    private func lev(_ a: String, _ b: String) -> Int {
        let aa = Array(a.utf8)
        let bb = Array(b.utf8)
        var prev = Array(0...bb.count)
        for i in 1...max(1, aa.count) {
            if i > aa.count { break }
            var cur = Array(repeating: 0, count: bb.count + 1)
            cur[0] = i
            for j in 1...max(1, bb.count) {
                if j > bb.count { break }
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, min(cur[j - 1] + 1, prev[j - 1] + cost))
            }
            prev = cur
        }
        return prev[bb.count]
    }

    private func sim(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0.0 }
        return 1.0 - Double(lev(a, b)) / Double(max(a.count, b.count))
    }

    public func bestSim(term: String, transcript: String) -> Double {
        let tk = phoneticKey(term)
        if tk.isEmpty { return 1.0 }
        let keys = wordTokens(transcript).map { phoneticKey($0) }
        var best = 0.0
        for i in 0..<keys.count {
            var span = ""
            for n in 1...4 {
                if i + n > keys.count { break }
                span += keys[i + n - 1]
                best = max(best, sim(tk, span))
            }
        }
        return best
    }

    public func spoken(term: String, transcript: String) -> Bool {
        bestSim(term: term, transcript: transcript) >= Self.distractorSim
    }

    public func screenTerms(_ ctx: CtxV2?) -> [String] {
        guard let ctx, ctx.v == 2 else { return [] }
        let texts = (ctx.screen?.lines ?? []).map(\.text)
        return RenderPy.ocrTerms(texts, limit: 60).filter { Py.len(Py.strip($0)) >= 3 }
    }

    private func screenWords(_ ctx: CtxV2?) -> Set<String> {
        var parts: [String] = []
        if let ctx, ctx.v == 2 {
            parts.append(contentsOf: (ctx.screen?.lines ?? []).map(\.text))
            parts.append(ctx.field?.beforeCursor ?? "")
            parts.append(ctx.field?.hint ?? "")
        } else {
            parts.append(ctx?.field?.beforeCursor ?? "")
        }
        var out: Set<String> = []
        for p in parts {
            for w in words(p) { out.insert(Py.head(w, 5)) }
        }
        return out
    }

    private func scriptOf(_ w: String) -> String {
        let (lat, cyr) = letters(w)
        if lat > cyr { return "lat" }
        if cyr > lat { return "cyr" }
        return ""
    }

    private func translatedSpan(transcript: String, output: String) -> Bool {
        let flatT = Self.replaceAll(Self.spanSplitRegex, in: transcript, with: " ")
        let flatO = Self.replaceAll(Self.spanSplitRegex, in: output, with: " ")
        let tw = content(words(flatT)).filter { Py.len($0) >= 3 }
        let ow = content(words(flatO)).filter { Py.len($0) >= 3 }
        let tset = Set(tw)
        let oset = Set(ow)
        let ok1 = ow.map { phoneticKey($0) }
        var okeys = ok1
        if ok1.count >= 2 {
            for i in 0..<(ok1.count - 1) { okeys.append(ok1[i] + ok1[i + 1]) }
        }
        for (src, dst) in [("lat", "cyr"), ("cyr", "lat")] {
            let lost = tw.filter { w in
                if scriptOf(w) != src || oset.contains(w) { return false }
                let wk = phoneticKey(w)
                let best = okeys.map { sim(wk, $0) }.max() ?? 0.0
                return best < Self.spanKeepSim
            }
            let added = ow.filter { w in
                scriptOf(w) == dst && !tset.contains(w) && bestSim(term: w, transcript: flatT) < Self.spanSim
            }
            if Set(lost).count >= Self.spanLostMin && !added.isEmpty { return true }
        }
        return false
    }
}
