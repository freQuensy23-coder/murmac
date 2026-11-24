import Foundation

/// Python `str` semantics reproduced for byte-exact parity with Murmur's prompts/render.py & prompts/guard.py.
public enum Py {
    public static func len(_ s: String) -> Int { s.unicodeScalars.count }

    public static func cps(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

    public static func str(_ cp: UInt32) -> String {
        guard let sc = Unicode.Scalar(cp) else { return "" }
        return String(sc)
    }

    public static func str(_ cps: [UInt32], from: Int, to: Int) -> String {
        guard to > from else { return "" }
        var view = String.UnicodeScalarView()
        view.reserveCapacity(to - from)
        for i in from..<to {
            if let sc = Unicode.Scalar(cps[i]) { view.append(sc) }
        }
        return String(view)
    }

    public static func head(_ s: String, _ n: Int) -> String {
        guard n > 0 else { return "" }
        let scalars = s.unicodeScalars
        guard scalars.count > n else { return s }
        return String(scalars.prefix(n))
    }

    public static func tail(_ s: String, _ n: Int) -> String {
        guard n > 0 else { return s }
        let scalars = s.unicodeScalars
        guard scalars.count > n else { return s }
        return String(scalars.suffix(n))
    }

    public static func sliceEnd(size: Int, n: Int) -> Int {
        n >= 0 ? min(n, size) : max(size + n, 0)
    }

    public static func sliceStartFromEnd(size: Int, n: Int) -> Int {
        if n > 0 { return max(size - n, 0) }
        if n == 0 { return 0 }
        return min(-n, size)
    }

    public static func isSpace(_ cp: UInt32) -> Bool {
        switch cp {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    public static func isAlpha(_ cp: UInt32) -> Bool {
        guard let sc = Unicode.Scalar(cp) else { return false }
        switch sc.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    public static func isDecimal(_ cp: UInt32) -> Bool {
        guard let sc = Unicode.Scalar(cp) else { return false }
        return sc.properties.generalCategory == .decimalNumber
    }

    public static func isWord(_ cp: UInt32) -> Bool {
        if cp == 0x5F { return true } // '_'
        guard let sc = Unicode.Scalar(cp) else { return false }
        switch sc.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static let digitNotDecimal: [(UInt32, UInt32)] = [
        (0xB2, 0xB3), (0xB9, 0xB9), (0x1369, 0x1371), (0x19DA, 0x19DA), (0x2070, 0x2070), (0x2074, 0x2079),
        (0x2080, 0x2089), (0x2460, 0x2468), (0x2474, 0x247C), (0x2488, 0x2490), (0x24EA, 0x24EA), (0x24F5, 0x24FD),
        (0x24FF, 0x24FF), (0x2776, 0x277E), (0x2780, 0x2788), (0x278A, 0x2792), (0x10A40, 0x10A43), (0x10E60, 0x10E68),
        (0x11052, 0x1105A), (0x1F100, 0x1F10A),
    ]

    private static let otherUppercase: [(UInt32, UInt32)] = [
        (0x2160, 0x216F), (0x24B6, 0x24CF), (0x1F130, 0x1F149), (0x1F150, 0x1F169), (0x1F170, 0x1F189),
    ]

    private static let otherLowercase: [(UInt32, UInt32)] = [
        (0xAA, 0xAA), (0xBA, 0xBA), (0x2B0, 0x2B8), (0x2C0, 0x2C1), (0x2E0, 0x2E4), (0x345, 0x345), (0x37A, 0x37A),
        (0x10FC, 0x10FC), (0x1D2C, 0x1D6A), (0x1D78, 0x1D78), (0x1D9B, 0x1DBF), (0x2071, 0x2071), (0x207F, 0x207F),
        (0x2090, 0x209C), (0x2170, 0x217F), (0x24D0, 0x24E9), (0x2C7C, 0x2C7D), (0xA69C, 0xA69D), (0xA770, 0xA770),
        (0xA7F2, 0xA7F4), (0xA7F8, 0xA7F9), (0xAB5C, 0xAB5F), (0xAB69, 0xAB69), (0x10780, 0x10780), (0x10783, 0x10785),
        (0x10787, 0x107B0), (0x107B2, 0x107BA), (0x1E030, 0x1E06D),
    ]

    private static func inRanges(_ ranges: [(UInt32, UInt32)], _ cp: UInt32) -> Bool {
        for (lo, hi) in ranges where cp >= lo && cp <= hi { return true }
        return false
    }

    public static func isDigit(_ cp: UInt32) -> Bool { isDecimal(cp) || inRanges(digitNotDecimal, cp) }

    public static func isUpper(_ cp: UInt32) -> Bool {
        guard let sc = Unicode.Scalar(cp) else { return false }
        return sc.properties.generalCategory == .uppercaseLetter || inRanges(otherUppercase, cp)
    }

    public static func isLower(_ cp: UInt32) -> Bool {
        guard let sc = Unicode.Scalar(cp) else { return false }
        return sc.properties.generalCategory == .lowercaseLetter || inRanges(otherLowercase, cp)
    }

    public static func isDigitString(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { isDigit($0.value) }
    }

    public static func lower(_ cp: UInt32) -> String {
        if cp < 0x80 {
            if cp >= 0x41 && cp <= 0x5A { return str(cp + 32) }
            return str(cp)
        }
        guard let sc = Unicode.Scalar(cp) else { return "" }
        return sc.properties.lowercaseMapping
    }

    public static func upper(_ cp: UInt32) -> String {
        if cp < 0x80 {
            if cp >= 0x61 && cp <= 0x7A { return str(cp - 32) }
            return str(cp)
        }
        guard let sc = Unicode.Scalar(cp) else { return "" }
        return sc.properties.uppercaseMapping
    }

    public static func casefold(_ cp: UInt32) -> String {
        if cp < 0x80 {
            if cp >= 0x41 && cp <= 0x5A { return str(cp + 32) }
            return str(cp)
        }
        if cp == 0x131 { return "\u{0131}" }
        if cp == 0x1E9E { return "ss" }
        if cp >= 0x13A0 && cp <= 0x13F5 { return str(cp) }
        if cp >= 0x13F8 && cp <= 0x13FD { return str(cp - 8) }
        if cp >= 0xAB70 && cp <= 0xABBF { return str(cp - 0xAB70 + 0x13A0) }
        // Exact Python casefold via uppercase->lowercase + special Swift scalar mapping
        if let sc = Unicode.Scalar(cp) {
            let up = sc.properties.uppercaseMapping
            var res = ""
            for u in up.unicodeScalars {
                res += u.properties.lowercaseMapping
            }
            return res
        }
        return ""
    }

    public static func casefold(_ s: String) -> String {
        var needsFold = false
        for sc in s.unicodeScalars {
            if sc.value >= 0x80 || (sc.value >= 0x41 && sc.value <= 0x5A) {
                needsFold = true
                break
            }
        }
        if !needsFold { return s }
        var out = ""
        out.reserveCapacity(s.count)
        for sc in s.unicodeScalars {
            out += casefold(sc.value)
        }
        return out
    }

    public static func upperFirst(_ s: String) -> String {
        guard let first = s.unicodeScalars.first else { return s }
        let rest = s.unicodeScalars.dropFirst()
        return upper(first.value) + String(rest)
    }

    public static func lowerIsAsciiLetter(_ cp: UInt32) -> Bool {
        let l = lower(cp)
        return cmp("a", l) <= 0 && cmp(l, "z") <= 0
    }

    public static func cmp(_ a: String, _ b: String) -> Int {
        var ia = a.unicodeScalars.makeIterator()
        var ib = b.unicodeScalars.makeIterator()
        while true {
            let ca = ia.next()?.value
            let cb = ib.next()?.value
            switch (ca, cb) {
            case (nil, nil): return 0
            case (nil, _): return -1
            case (_, nil): return 1
            case (let x?, let y?):
                if x != y { return x < y ? -1 : 1 }
            }
        }
    }

    public static func isCyrillic(_ cp: UInt32) -> Bool { cp >= 0x0400 && cp <= 0x04FF }

    public static func strip(_ s: String) -> String { rstrip(lstrip(s)) }

    public static func lstrip(_ s: String) -> String {
        let scalars = s.unicodeScalars
        var idx = scalars.startIndex
        while idx < scalars.endIndex && isSpace(scalars[idx].value) {
            idx = scalars.index(after: idx)
        }
        return String(scalars[idx...])
    }

    public static func rstrip(_ s: String) -> String {
        let scalars = s.unicodeScalars
        var idx = scalars.endIndex
        while idx > scalars.startIndex {
            let prev = scalars.index(before: idx)
            if !isSpace(scalars[prev].value) { break }
            idx = prev
        }
        return String(scalars[..<idx])
    }

    public static func strip(_ s: String, chars: String) -> String {
        let set = Set(chars.unicodeScalars)
        let scalars = s.unicodeScalars
        var i = scalars.startIndex
        var j = scalars.endIndex
        while i < j && set.contains(scalars[i]) { i = scalars.index(after: i) }
        while j > i {
            let prev = scalars.index(before: j)
            if !set.contains(scalars[prev]) { break }
            j = prev
        }
        return String(scalars[i..<j])
    }

    public static func split(_ s: String) -> [String] {
        var out: [String] = []
        let scalars = s.unicodeScalars
        var idx = scalars.startIndex
        var start: String.UnicodeScalarView.Index? = nil
        while idx < scalars.endIndex {
            if isSpace(scalars[idx].value) {
                if let st = start {
                    out.append(String(scalars[st..<idx]))
                    start = nil
                }
            } else if start == nil {
                start = idx
            }
            idx = scalars.index(after: idx)
        }
        if let st = start { out.append(String(scalars[st...])) }
        return out
    }

    public static func splitlines(_ s: String) -> [String] {
        var out: [String] = []
        let scalars = Array(s.unicodeScalars)
        var start = 0
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            let brk = v == 0x0A || v == 0x0D || v == 0x0B || v == 0x0C || (v >= 0x1C && v <= 0x1E)
                || v == 0x85 || v == 0x2028 || v == 0x2029
            if brk {
                out.append(String(String.UnicodeScalarView(scalars[start..<i])))
                if v == 0x0D && i + 1 < scalars.count && scalars[i + 1].value == 0x0A {
                    i += 2
                } else {
                    i += 1
                }
                start = i
            } else {
                i += 1
            }
        }
        if start < scalars.count {
            out.append(String(String.UnicodeScalarView(scalars[start..<scalars.count])))
        }
        return out
    }

    public static func last(_ s: String) -> String {
        guard let sc = s.unicodeScalars.last else { return "" }
        return String(sc)
    }

    // ICU regex character class bodies with exact Python semantics
    public static let W = "\\p{L}\\p{Nd}\\p{Nl}\\p{No}_"
    public static let S = "\\t\\n\\x0B\\f\\r\\x1C-\\x20\\x85\\xA0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"

    private static let ignoreCaseExtra: [UInt32: String] = [
        0x69: "\u{0130}\u{0131}", // i -> İı
        0x6B: "\u{212A}",         // k -> K
        0x73: "\u{017F}",         // s -> ſ
        0x432: "\u{1C80}",        // в -> ᲀ
        0x434: "\u{1C81}",        // д -> ᲁ
        0x43E: "\u{1C82}",        // о -> ᲂ
        0x441: "\u{1C83}",        // с -> ᲃ
        0x442: "\u{1C84}\u{1C85}",// т -> ᲄᲅ
        0x44A: "\u{1C86}",        // ъ -> ᲆ
    ]

    private static let ignoreCaseTable: [UInt32: String] = {
        var m: [UInt32: String] = [:]
        var lowers: [UInt32] = Array(0x61...0x7A) + Array(0x430...0x44F) + [0x451]
        for lo in lowers {
            let up: UInt32 = (lo == 0x451) ? 0x401 : (lo - 32)
            let v = str(lo) + str(up) + (ignoreCaseExtra[lo] ?? "")
            m[lo] = v
            m[up] = v
        }
        return m
    }()

    public static func ignoreCaseVariants(_ sc: Unicode.Scalar) -> String {
        guard let v = ignoreCaseTable[sc.value] else {
            preconditionFailure("No re.I class for U+\(String(sc.value, radix: 16))")
        }
        return v
    }

    public static func ignoreCaseEquals(_ cp: UInt32, _ letter: Unicode.Scalar) -> Bool {
        guard cp <= 0xFFFF, let sc = Unicode.Scalar(cp) else { return false }
        return ignoreCaseVariants(letter).unicodeScalars.contains(sc)
    }

    public static func ignoreCase(_ pattern: String) -> String {
        let scalars = Array(pattern.unicodeScalars)
        var out = ""
        out.reserveCapacity(pattern.count * 3)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "\\" {
                guard i + 1 < scalars.count else {
                    out.append("\\")
                    i += 1
                    continue
                }
                let n = scalars[i + 1]
                out.append(Character(c))
                out.append(Character(n))
                i += 2
            } else if c == "[" {
                let end = classEnd(scalars, start: i)
                for k in i..<end { out.append(Character(scalars[k])) }
                i = end
            } else if isAlpha(c.value) {
                out.append("[")
                out.append(ignoreCaseVariants(c))
                out.append("]")
                i += 1
            } else {
                out.append(Character(c))
                i += 1
            }
        }
        return out
    }

    private static func classEnd(_ p: [Unicode.Scalar], start: Int) -> Int {
        var j = start + 1
        if j < p.count && p[j] == "^" { j += 1 }
        while j < p.count && p[j] != "]" {
            if p[j] == "\\" && j + 1 < p.count {
                let nxt = p[j + 1]
                if nxt == "p" || nxt == "P" {
                    while j < p.count && p[j] != "}" { j += 1 }
                    j = min(p.count, j + 1)
                } else if nxt == "x" {
                    j = min(p.count, j + 4)
                } else if nxt == "u" {
                    j = min(p.count, j + 6)
                } else {
                    j = min(p.count, j + 2)
                }
            } else {
                j += 1
            }
        }
        return min(p.count, j + 1)
    }
}
