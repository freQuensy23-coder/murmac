import Foundation
import Testing
@testable import MurmacCore

@Suite("Murmur Golden Parity")
struct GoldenParityTests {
    private func goldensRoot() throws -> URL {
        try #require(Bundle.module.url(forResource: "goldens", withExtension: nil))
    }

    @Test("Bundled macOS catalog loads cleanly without QNN artifacts")
    func catalogLoadsCleanly() throws {
        let catalog = try CatalogLoader.loadBundled()
        #expect(catalog.models.count >= 20)
        #expect(catalog.packs.count == 3)
        #expect(catalog.models.contains { $0.id == "parakeet-tdt-0.6b-v3" })
        #expect(catalog.models.contains { $0.id == "murmur-cleanup-qwen3.5-2b" })
        #expect(catalog.models.contains { $0.id == "silero-vad-v5" })
        #expect(catalog.models.allSatisfy { $0.kind != .ocr })
        for m in catalog.models {
            for a in m.artifacts {
                #expect(!a.runtime.contains("qnn"))
            }
        }
    }

    @Test("All 16 plain prefixes match Python goldens byte-for-byte")
    func plainPrefixesMatchGoldens() throws {
        let root = try goldensRoot()
        let assets = BundlePromptAssets()
        let renderer = RenderPyPort(assets: assets)

        let indexData = try Data(contentsOf: root.appendingPathComponent("index.json"))
        let indexObj = try JSONDecoder().decode(JSONValue.self, from: indexData).objectValue ?? [:]
        let expectedHashes = indexObj["prefix_sha256"]?.objectValue ?? [:]
        let profiles = ["default.v1", "default.v4", "default.v4s", "finetuned.v1"]
        let templates = ["qwen3.5", "qwen3", "lfm3", "lfm2.5"]

        for pName in profiles {
            let profile = try assets.profile(name: pName)
            for tpl in templates {
                let actual = try renderer.cachePrefix(profile: profile, template: tpl, preferences: nil, systemOverride: nil)
                let goldenURL = root.appendingPathComponent("prefix/\(pName).\(tpl).plain.txt")
                let expected = try String(contentsOf: goldenURL, encoding: .utf8)
                #expect(actual == expected, "Prefix mismatch for \(pName)/\(tpl)")
                if let sha = expectedHashes[pName]?.objectValue?[tpl]?.stringValue {
                    #expect(RenderPyPort.sha256Hex(actual) == sha, "SHA256 mismatch for \(pName)/\(tpl)")
                }
            }
        }
    }

    @Test("Prefix preferences & override variants match goldens")
    func prefixVariantsMatchGoldens() throws {
        let root = try goldensRoot()
        let assets = BundlePromptAssets()
        let renderer = RenderPyPort(assets: assets)
        let profile = try assets.profile(name: "default.v1")
        let tpl = "qwen3.5"

        let plain = try renderer.cachePrefix(profile: profile, template: tpl, preferences: nil, systemOverride: nil)
        let plainExpected = try String(contentsOf: root.appendingPathComponent("prefix/default.v1.qwen3.5.plain.txt"), encoding: .utf8)
        #expect(plain == plainExpected)

        let blank = try renderer.cachePrefix(profile: profile, template: tpl, preferences: "   \n\t ", systemOverride: nil)
        let blankExpected = try String(contentsOf: root.appendingPathComponent("prefix/default.v1.qwen3.5.prefs_blank.txt"), encoding: .utf8)
        #expect(blank == blankExpected)
    }

    @Test("Full suffix corpus across all 4 chat templates matches Python goldens byte-for-byte")
    func suffixCorpusMatchesGoldens() throws {
        struct CaseRow: Decodable {
            let id: String
            let ctx: CtxV2?
            let transcript: String
            let styleOverride: String?
            enum CodingKeys: String, CodingKey {
                case id, ctx, transcript
                case styleOverride = "style_override"
            }
        }

        let root = try goldensRoot()
        let assets = BundlePromptAssets()
        let renderer = RenderPyPort(assets: assets)

        let rawCases = try String(contentsOf: root.appendingPathComponent("cases.jsonl"), encoding: .utf8)
        let decoder = JSONDecoder()
        let cases: [CaseRow] = try rawCases.split(whereSeparator: \.isNewline).compactMap { line in
            let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, let d = s.data(using: .utf8) else { return nil }
            return try decoder.decode(CaseRow.self, from: d)
        }
        #expect(cases.count > 100)

        let profile = try assets.profile(name: "default.v1")
        let templates = ["qwen3.5", "qwen3", "lfm3", "lfm2.5"]
        var checked = 0

        for tpl in templates {
            for row in cases {
                let goldenURL = root.appendingPathComponent("suffix/\(tpl)/\(row.id).txt")
                guard FileManager.default.fileExists(atPath: goldenURL.path) else { continue }
                let expected = try String(contentsOf: goldenURL, encoding: .utf8)
                let rendered = try renderer.render(RenderInput(
                    profile: profile,
                    template: tpl,
                    ctx: row.ctx,
                    transcript: row.transcript,
                    styleOverride: row.styleOverride
                ))
                #expect(rendered.suffix == expected, "Suffix mismatch for \(tpl)/\(row.id)")
                if rendered.suffix != expected { return }
                checked += 1
            }
        }
        #expect(checked > 400)
    }

    @Test("OutputGuard matches guard.json golden corpus 100%")
    func guardCorpusMatchesGoldens() throws {
        let root = try goldensRoot()
        let guardPort = GuardPyPort()

        let data = try Data(contentsOf: root.appendingPathComponent("guard.json"))
        let rootObj = try JSONDecoder().decode(JSONValue.self, from: data).objectValue ?? [:]
        #expect(rootObj["guard_version"]?.stringValue == GuardPyPort.guardVersion)

        if case .array(let fArr) = rootObj["fillers"] {
            let expectedFillers = Set(fArr.compactMap(\.stringValue))
            #expect(guardPort.fillers == expectedFillers)
        }

        let decoder = JSONDecoder()
        func decodeCtx(_ val: JSONValue?) throws -> CtxV2? {
            guard let val, val != .null else { return nil }
            let encoded = try JSONEncoder().encode(val)
            return try decoder.decode(CtxV2.self, from: encoded)
        }

        var count = 0
        for section in ["test_guard", "test_render_v2"] {
            guard case .array(let rows) = rootObj[section] else { continue }
            for rowVal in rows {
                guard let row = rowVal.objectValue,
                      let fn = row["fn"]?.stringValue,
                      let args = row["args"]?.objectValue,
                      let res = row["result"] else { continue }
                switch fn {
                case "fallback_text":
                    let tr = args["transcript"]?.stringValue ?? ""
                    let ctx = try decodeCtx(args["ctx"])
                    #expect(guardPort.fallbackText(transcript: tr, ctx: ctx) == res.stringValue, "fallback_text(\(tr))")
                case "phonetic_key":
                    let s = args["s"]?.stringValue ?? ""
                    #expect(guardPort.phoneticKey(s) == res.stringValue, "phonetic_key(\(s))")
                case "spoken":
                    let term = args["term"]?.stringValue ?? ""
                    let tr = args["transcript"]?.stringValue ?? ""
                    #expect(guardPort.spoken(term: term, transcript: tr) == res.boolValue, "spoken(\(term), \(tr))")
                case "precheck":
                    let tr = args["transcript"]?.stringValue ?? ""
                    let actual = guardPort.precheck(tr)
                    let r = res.objectValue ?? [:]
                    #expect(actual.skip == r["skip"]?.boolValue, "precheck.skip(\(tr))")
                    #expect(actual.transcript == r["transcript"]?.stringValue, "precheck.transcript(\(tr))")
                    #expect(actual.reason == r["reason"]?.stringValue, "precheck.reason(\(tr))")
                case "repair":
                    let out = args["output"]?.stringValue ?? ""
                    let tr = args["transcript"]?.stringValue ?? ""
                    let ctx = try decodeCtx(args["ctx"])
                    #expect(guardPort.repair(output: out, transcript: tr, ctx: ctx) == res.stringValue, "repair(\(out))")
                case "screen_terms":
                    let ctx = try decodeCtx(args["ctx"])
                    if case .array(let arr) = res {
                        #expect(guardPort.screenTerms(ctx) == arr.compactMap(\.stringValue))
                    }
                case "guard":
                    let tr = args["transcript"]?.stringValue ?? ""
                    let out = args["output"]?.stringValue ?? ""
                    let ctx = try decodeCtx(args["ctx"])
                    let actual = guardPort.guardOutput(transcript: tr, output: out, ctx: ctx)
                    let r = res.objectValue ?? [:]
                    #expect(actual.text == r["text"]?.stringValue, "guard.text(\(tr) -> \(out))")
                    #expect(actual.action.rawValue.lowercased() == r["action"]?.stringValue, "guard.action(\(tr) -> \(out))")
                    #expect(actual.reason == r["reason"]?.stringValue, "guard.reason(\(tr) -> \(out))")
                default:
                    break
                }
                count += 1
            }
        }
        #expect(count > 70)

        if case .array(let preRows) = rootObj["eval_precheck"] {
            for rowVal in preRows {
                guard let row = rowVal.objectValue,
                      let tr = row["transcript"]?.stringValue,
                      let r = row["result"]?.objectValue else { continue }
                let actual = guardPort.precheck(tr)
                #expect(actual.skip == r["skip"]?.boolValue)
                #expect(actual.transcript == r["transcript"]?.stringValue)
                #expect(actual.reason == r["reason"]?.stringValue)
            }
        }
    }
}
