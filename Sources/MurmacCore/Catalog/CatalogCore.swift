import CryptoKit
import Foundation

public enum RuntimeKeys {
    public static let sherpaOfflineTransducer = "sherpa/offline-transducer"
    public static let sherpaOfflineCtc = "sherpa/offline-ctc"
    public static let sherpaOfflineWhisper = "sherpa/offline-whisper"
    public static let sherpaOfflineQwen3Asr = "sherpa/offline-qwen3-asr"
    public static let sherpaOnlineTransducer = "sherpa/online-transducer"
    public static let sherpaOnlineTOne = "sherpa/online-t-one"
    public static let ortSileroVadV5 = "ort/silero-vad-v5"
    public static let llamaGguf = "llama/gguf"

    public static let offlineAsr: Set<String> = [
        sherpaOfflineTransducer, sherpaOfflineCtc, sherpaOfflineWhisper, sherpaOfflineQwen3Asr,
    ]
    public static let onlineAsr: Set<String> = [
        sherpaOnlineTransducer, sherpaOnlineTOne,
    ]
}

public struct CatalogDocument: Codable, Equatable, Sendable {
    public let schema: Int
    public let catalogVersion: String
    public let generated: String?
    public let defaults: CatalogDefaults
    public let packs: [ModelPack]
    public let models: [CatalogModel]

    public init(schema: Int, catalogVersion: String, generated: String?, defaults: CatalogDefaults, packs: [ModelPack], models: [CatalogModel]) {
        self.schema = schema
        self.catalogVersion = catalogVersion
        self.generated = generated
        self.defaults = defaults
        self.packs = packs
        self.models = models
    }
}

public struct CatalogDefaults: Codable, Equatable, Sendable {
    public let asr: [String: String]
    public let vad: String

    public init(asr: [String: String], vad: String) {
        self.asr = asr
        self.vad = vad
    }
}

public struct ModelPack: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let recommended: Bool?
    public let description: String
    public let items: [String]
}

public struct CatalogLanguages: Codable, Equatable, Sendable {
    public let codes: [String]?
    public let count: Int?
    public let mode: String?
    public let note: String?
}

public struct CatalogLicense: Codable, Equatable, Sendable {
    public let id: String
    public let url: String?
    public let note: String?
}

public struct AsrTraits: Codable, Equatable, Sendable {
    public let streaming: Bool
    public let punctuation: Bool
    public let casing: Bool

    public init(streaming: Bool = false, punctuation: Bool = true, casing: Bool = true) {
        self.streaming = streaming
        self.punctuation = punctuation
        self.casing = casing
    }
}

public struct LlmTraits: Codable, Equatable, Sendable {
    public let template: String
    public let promptProfile: String
    public let nCtx: Int
    public let prefixTokens: Int?
    public let kvBytesPerToken: Int?
    public let note: String?

    public init(
        template: String,
        promptProfile: String = "default.v1",
        nCtx: Int = 7168,
        prefixTokens: Int? = nil,
        kvBytesPerToken: Int? = nil,
        note: String? = nil
    ) {
        self.template = template
        self.promptProfile = promptProfile
        self.nCtx = nCtx
        self.prefixTokens = prefixTokens
        self.kvBytesPerToken = kvBytesPerToken
        self.note = note
    }
}

public struct ArtifactFileSpec: Codable, Equatable, Sendable {
    public let name: String
    public let url: String
    public let bytes: Int64
    public let sha256: String?
    public let archive: String?
}

public struct CatalogArtifact: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let runtime: String
    public let format: String
    public let units: [ComputeUnit]
    public let files: [ArtifactFileSpec]
    public let layout: [String: String]
    public let quant: String?
    public let maxWindowSec: Double?
    public let memoryMb: [String: Int]?
    public let notes: String?

    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.bytes }
    }
}

public struct CatalogModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ModelKind
    public let displayName: String
    public let publisher: String?
    public let family: String?
    public let baseRepo: String?
    public let description: String?
    public let params: Int64?
    public let paramsLabel: String?
    public let languages: CatalogLanguages?
    public let license: CatalogLicense?
    public let tier: String?
    public let status: String?
    public let previewOnly: Bool?
    public let asr: AsrTraits?
    public let llm: LlmTraits?
    public let artifacts: [CatalogArtifact]

    public var isSelectable: Bool { !(previewOnly ?? false) }
    public var preferredArtifact: CatalogArtifact? { artifacts.first }
}

public enum CatalogLoader {
    public static func loadBundled() throws -> CatalogDocument {
        guard let url = MurmacCoreResources.bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "catalog") else {
            throw MurmurError.catalogInvalid("bundled catalog.json missing")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogDocument.self, from: data)
    }
}

/// Custom user-imported GGUF model (local file or Hugging Face repo).
public struct CustomLlmModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let filePath: String
    public let sha256: String
    public let template: String
    public let promptProfile: String
    public let nCtx: Int
    public let sizeBytes: Int64
    public let addedAtMs: Int64

    public init(
        id: String,
        displayName: String,
        filePath: String,
        sha256: String,
        template: String,
        promptProfile: String,
        nCtx: Int,
        sizeBytes: Int64,
        addedAtMs: Int64
    ) {
        self.id = id
        self.displayName = displayName
        self.filePath = filePath
        self.sha256 = sha256
        self.template = template
        self.promptProfile = promptProfile
        self.nCtx = nCtx
        self.sizeBytes = sizeBytes
        self.addedAtMs = addedAtMs
    }
}

/// Maps GGUF `general.architecture` to Murmur's supported chat templates.
public enum GgufTemplates {
    public static func templateForArchitecture(_ arch: String?) -> String {
        guard let a = arch?.lowercased() else { return "qwen3.5" }
        if a.contains("lfm3") { return "lfm3" }
        if a.contains("lfm2") || a.contains("lfm") { return "lfm2.5" }
        if a.contains("qwen35") || a.contains("qwen3.5") { return "qwen3.5" }
        if a.contains("qwen") { return "qwen3" }
        return "qwen3.5"
    }

    public static func promptProfile(from meta: GgufHeader.Meta) -> String {
        if let p = meta.string("murmur.prompt_profile"), !p.isEmpty { return p }
        return "default.v1"
    }
}

/// Exact Swift port of Murmur's GgufHeader (v2/v3 metadata parser without loading tensor weights).
public enum GgufHeader {
    public static let magic: UInt32 = 0x46554747 // "GGUF" little-endian
    public static let maxNumericArray = 4_096

    public enum Value: Equatable, Sendable {
        case int(Int64)
        case double(Double)
        case bool(Bool)
        case string(String)
        case intArray([Int64])
    }

    public struct Meta: Equatable, Sendable {
        public let version: Int
        public let kvCount: UInt64
        public let values: [String: Value]
        public let complete: Bool
        public let bytesUsed: Int

        public func string(_ key: String) -> String? {
            if case .string(let s) = values[key] { return s }
            return nil
        }

        public func int(_ key: String) -> Int64? {
            if case .int(let n) = values[key] { return n }
            return nil
        }

        public func ints(_ key: String) -> [Int64]? {
            if case .intArray(let a) = values[key] { return a }
            return nil
        }
    }

    public enum ParseError: Error, Equatable {
        case badMagic
        case unsupportedVersion(Int)
        case invalidData(String)
        case underflow
    }

    public static func parse(_ data: Data) throws -> Meta {
        var pos = 0
        let count = data.count

        func readU8() throws -> UInt8 {
            guard pos + 1 <= count else { throw ParseError.underflow }
            let v = data[data.startIndex + pos]
            pos += 1
            return v
        }
        func readU16() throws -> UInt16 {
            guard pos + 2 <= count else { throw ParseError.underflow }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pos, as: UInt16.self) }
            pos += 2
            return UInt16(littleEndian: v)
        }
        func readU32() throws -> UInt32 {
            guard pos + 4 <= count else { throw ParseError.underflow }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pos, as: UInt32.self) }
            pos += 4
            return UInt32(littleEndian: v)
        }
        func readU64() throws -> UInt64 {
            guard pos + 8 <= count else { throw ParseError.underflow }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pos, as: UInt64.self) }
            pos += 8
            return UInt64(littleEndian: v)
        }
        func readF32() throws -> Float { Float(bitPattern: try readU32()) }
        func readF64() throws -> Double { Double(bitPattern: try readU64()) }
        func readStr() throws -> String {
            let n = try readU64()
            guard n <= (1 << 24) else { throw ParseError.invalidData("string too long") }
            let len = Int(n)
            guard pos + len <= count else { throw ParseError.underflow }
            let slice = data[(data.startIndex + pos)..<(data.startIndex + pos + len)]
            pos += len
            return String(decoding: slice, as: UTF8.self)
        }
        func readValue(type: UInt32) throws -> Value? {
            switch type {
            case 0: return .int(Int64(try readU8()))
            case 1: return .int(Int64(Int8(bitPattern: try readU8())))
            case 2: return .int(Int64(try readU16()))
            case 3: return .int(Int64(Int16(bitPattern: try readU16())))
            case 4: return .int(Int64(try readU32()))
            case 5: return .int(Int64(Int32(bitPattern: try readU32())))
            case 6: return .double(Double(try readF32()))
            case 7: return .bool(try readU8() != 0)
            case 8: return .string(try readStr())
            case 9:
                let itemType = try readU32()
                let n = try readU64()
                guard n <= (1 << 32) else { throw ParseError.invalidData("array too long") }
                let fixed: Int
                switch itemType {
                case 0, 1, 7: fixed = 1
                case 2, 3: fixed = 2
                case 4, 5, 6: fixed = 4
                case 10, 11, 12: fixed = 8
                default: fixed = 0
                }
                if fixed > 0 && n > UInt64(maxNumericArray) {
                    let skip = Int(n) * fixed
                    guard pos + skip <= count else { throw ParseError.underflow }
                    pos += skip
                    return nil
                }
                if itemType == 8 {
                    for _ in 0..<n { _ = try readStr() }
                    return nil
                }
                if itemType == 9 { throw ParseError.invalidData("nested arrays") }
                var ints: [Int64] = []
                ints.reserveCapacity(Int(n))
                for _ in 0..<n {
                    if let v = try readValue(type: itemType), case .int(let x) = v {
                        ints.append(x)
                    }
                }
                return ints.isEmpty ? nil : .intArray(ints)
            case 10: return .int(Int64(bitPattern: try readU64()))
            case 11: return .int(Int64(bitPattern: try readU64()))
            case 12: return .double(try readF64())
            default: throw ParseError.invalidData("unknown value type \(type)")
            }
        }

        guard count >= 24 else { throw ParseError.badMagic }
        let m = try readU32()
        guard m == magic else { throw ParseError.badMagic }
        let version = Int(try readU32())
        guard version == 2 || version == 3 else { throw ParseError.unsupportedVersion(version) }
        _ = try readU64() // tensor count
        let kvCount = try readU64()
        guard kvCount <= 100_000 else { throw ParseError.invalidData("implausible kvCount") }

        var values: [String: Value] = [:]
        var lastGood = pos
        do {
            for _ in 0..<kvCount {
                let key = try readStr()
                let type = try readU32()
                if let val = try readValue(type: type) {
                    values[key] = val
                }
                lastGood = pos
            }
        } catch ParseError.underflow {
            return Meta(version: version, kvCount: kvCount, values: values, complete: false, bytesUsed: lastGood)
        }
        return Meta(version: version, kvCount: kvCount, values: values, complete: true, bytesUsed: lastGood)
    }

    public static func kvBytesPerToken(_ meta: Meta) -> Int? {
        guard let arch = meta.string("general.architecture"),
              let layers = meta.int("\(arch).block_count"),
              let embd = meta.int("\(arch).embedding_length"),
              layers > 0
        else { return nil }
        let heads = meta.int("\(arch).attention.head_count") ?? meta.ints("\(arch).attention.head_count")?.max()
        guard let h = heads, h > 0 else { return nil }
        let k = meta.int("\(arch).attention.key_length") ?? (embd / h)
        let v = meta.int("\(arch).attention.value_length") ?? (embd / h)
        let interval = meta.int("\(arch).full_attention_interval")
        let attnLayers = (interval ?? 0) > 0 ? (layers / interval!) : layers
        let kvHeadsTotal: Int64
        if let arr = meta.ints("\(arch).attention.head_count_kv") {
            kvHeadsTotal = arr.reduce(0, +)
        } else if let single = meta.int("\(arch).attention.head_count_kv") {
            kvHeadsTotal = single * attnLayers
        } else {
            kvHeadsTotal = h * attnLayers
        }
        let bytes = kvHeadsTotal * (k + v) * 2
        return bytes > 0 && bytes <= Int64(Int.max) ? Int(bytes) : nil
    }
}

public enum InstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double, bytesReceived: Int64, totalBytes: Int64)
    case verifying
    case installed(dir: String)
    case failed(String)

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

/// Manages local model files under `~/Library/Application Support/Murmac/models/<artifactId>/`.
public final class ModelStorage: @unchecked Sendable {
    public let rootURL: URL
    private let fm = FileManager.default

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = appSupport.appendingPathComponent("Murmac/models", isDirectory: true)
        }
        try? fm.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    public func artifactDir(_ artifactId: String) -> URL {
        let safe = artifactId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let name = safe.isEmpty ? "artifact" : safe
        return rootURL.appendingPathComponent(name, isDirectory: true)
    }

    public func isInstalled(_ artifact: CatalogArtifact) -> Bool {
        let dir = artifactDir(artifact.id)
        let marker = dir.appendingPathComponent(".installed")
        guard fm.fileExists(atPath: marker.path) else { return false }
        for (role, rel) in artifact.layout where role != "dir" {
            let base = artifact.layout["dir"].map { dir.appendingPathComponent($0) } ?? dir
            if !fm.fileExists(atPath: base.appendingPathComponent(rel).path) {
                return false
            }
        }
        return true
    }

    public func delete(_ artifactId: String) throws {
        let dir = artifactDir(artifactId)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    public func installedSizeBytes(_ artifactId: String) -> Int64 {
        let dir = artifactDir(artifactId)
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let sz = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(sz)
            }
        }
        return total
    }

    public func loadSpec(for model: CatalogModel, artifact: CatalogArtifact, unit: ComputeUnit, threads: Int = 4, languageHint: String? = nil) -> LoadSpec {
        let dir = artifactDir(artifact.id)
        let baseDir = artifact.layout["dir"].map { dir.appendingPathComponent($0).path } ?? dir.path
        var opts: [String: String] = ["threads": "\(threads)"]
        if let llm = model.llm {
            opts["n_ctx"] = "\(llm.nCtx)"
            opts["template"] = llm.template
            opts["profile"] = llm.promptProfile
        }
        if let maxWin = artifact.maxWindowSec {
            opts["max_window_sec"] = "\(maxWin)"
        }
        if artifact.runtime == RuntimeKeys.sherpaOfflineWhisper {
            // Fixed-English Distil-Whisper needs "en"; multilingual Whisper accepts hint or "" for auto-detect.
            if model.languages?.codes == ["en"] {
                opts["language"] = "en"
            } else {
                opts["language"] = languageHint ?? ""
            }
        }
        return LoadSpec(
            artifactId: artifact.id,
            kind: model.kind,
            runtime: artifact.runtime,
            unit: unit,
            dir: baseDir,
            layout: artifact.layout,
            options: opts
        )
    }
}

/// High-throughput URLSessionDownloadDelegate bridge: streams directly to disk with throttled progress callbacks.
private final class DownloadBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let onBytes: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var cancelledEarly = false
    private var lastReport = Date.distantPast

    init(onBytes: @escaping @Sendable (Int64) -> Void) {
        self.onBytes = onBytes
    }

    func start(url: URL) async throws -> URL {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                enum Action { case resumeTask, finishNow(Result<URL, Error>) }
                let action: Action = self.lock.withLock {
                    if let res = self.pendingResult {
                        self.pendingResult = nil
                        return .finishNow(res)
                    }
                    if self.cancelledEarly {
                        return .finishNow(.failure(MurmurError.cancelled))
                    }
                    self.continuation = cont
                    return .resumeTask
                }
                switch action {
                case .resumeTask:
                    task.resume()
                case .finishNow(let res):
                    session.invalidateAndCancel()
                    cont.resume(with: res)
                }
            }
        } onCancel: {
            self.lock.withLock { self.cancelledEarly = true }
            task.cancel()
            session.invalidateAndCancel()
            self.finish(with: .failure(MurmurError.cancelled))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let shouldReport: Bool = lock.withLock {
            let now = Date()
            if now.timeIntervalSince(lastReport) >= 0.15 {
                lastReport = now
                return true
            }
            return false
        }
        if shouldReport { onBytes(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finish(with: .failure(MurmurError.downloadFailed("http_\(http.statusCode)")))
            session.finishTasksAndInvalidate()
            return
        }
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent("murmac-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: tempCopy)
            finish(with: .success(tempCopy))
        } catch {
            finish(with: .failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            session.finishTasksAndInvalidate()
        }
    }

    private func finish(with result: Result<URL, Error>) {
        let cont: CheckedContinuation<URL, Error>? = lock.withLock {
            if let c = continuation {
                continuation = nil
                return c
            }
            if pendingResult == nil {
                pendingResult = result
            }
            return nil
        }
        cont?.resume(with: result)
    }
}

/// Downloads artifacts from Hugging Face / GitHub Releases using native URLSessionDownloadTask streaming,
/// coalescing duplicate requests, verifying SHA-256 in 256 KiB chunks, validating tar entries, and swapping atomically.
public actor ModelDownloader {
    private let storage: ModelStorage
    private var activeTasks: [String: Task<URL, Error>] = [:]

    public init(storage: ModelStorage) {
        self.storage = storage
    }

    public func cancel(artifactId: String) {
        activeTasks[artifactId]?.cancel()
        activeTasks[artifactId] = nil
    }

    public func download(
        artifact: CatalogArtifact,
        onProgress: @escaping @Sendable (InstallState) -> Void
    ) async throws -> URL {
        if storage.isInstalled(artifact) {
            let dir = storage.artifactDir(artifact.id)
            onProgress(.installed(dir: dir.path))
            return dir
        }

        // Coalesce concurrent downloads for the same artifact ID
        if let existing = activeTasks[artifact.id] {
            return try await existing.value
        }

        let storage = self.storage
        let task = Task<URL, Error> {
            let fm = FileManager.default
            let finalDir = storage.artifactDir(artifact.id)
            let stagingDir = storage.rootURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingDir) }

            let totalBytes = max(1, artifact.totalBytes)
            var completedBefore: Int64 = 0

            for fileSpec in artifact.files {
                try Task.checkCancellation()
                guard let url = URL(string: fileSpec.url) else {
                    throw MurmurError.downloadFailed("invalid_url:\(fileSpec.name)")
                }
                let destFile = try Self.safePath(base: stagingDir, relative: fileSpec.name)
                try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)

                let baseCompleted = completedBefore
                let bridge = DownloadBridge { fileReceived in
                    let got = baseCompleted + fileReceived
                    let prog = min(0.99, Double(got) / Double(totalBytes))
                    onProgress(.downloading(progress: prog, bytesReceived: got, totalBytes: totalBytes))
                }
                let tmpDownloaded = try await bridge.start(url: url)
                defer { try? fm.removeItem(at: tmpDownloaded) }

                onProgress(.verifying)
                if let expectedSha = fileSpec.sha256, !expectedSha.isEmpty {
                    let actual = try Self.sha256File(url: tmpDownloaded)
                    guard actual.lowercased() == expectedSha.lowercased() else {
                        throw MurmurError.downloadFailed("sha256_mismatch:\(fileSpec.name)")
                    }
                }

                if fm.fileExists(atPath: destFile.path) { try fm.removeItem(at: destFile) }
                try fm.moveItem(at: tmpDownloaded, to: destFile)

                if fileSpec.archive == "tar.bz2" || fileSpec.name.hasSuffix(".tar.bz2") {
                    try await Self.extractTarBz2Safely(archive: destFile, into: stagingDir)
                    try? fm.removeItem(at: destFile)
                }

                completedBefore += fileSpec.bytes
            }

            try Data("ok".utf8).write(to: stagingDir.appendingPathComponent(".installed"))
            if fm.fileExists(atPath: finalDir.path) {
                _ = try fm.replaceItemAt(finalDir, withItemAt: stagingDir)
            } else {
                try fm.moveItem(at: stagingDir, to: finalDir)
            }
            onProgress(.installed(dir: finalDir.path))
            return finalDir
        }

        activeTasks[artifact.id] = task
        defer { activeTasks[artifact.id] = nil }
        do {
            return try await task.value
        } catch is CancellationError {
            onProgress(.notInstalled)
            throw MurmurError.cancelled
        } catch {
            onProgress(.failed(error.localizedDescription))
            throw error
        }
    }

    private static func safePath(base: URL, relative: String) throws -> URL {
        let baseStd = base.standardizedFileURL.path
        let candidate = base.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(baseStd + "/") else {
            throw MurmurError.downloadFailed("unsafe_path:\(relative)")
        }
        return candidate
    }

    private static func sha256File(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func extractTarBz2Safely(archive: URL, into dir: URL) async throws {
        // 1a. Verbose listing to reject symlinks/hardlinks
        let verboseOut = try await runProcess(executable: "/usr/bin/tar", arguments: ["-tvjf", archive.path])
        for line in verboseOut.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.hasPrefix("l") || s.hasPrefix("h") {
                throw MurmurError.downloadFailed("tar_contains_link")
            }
        }
        // 1b. Plain listing (unsplit paths) to reject absolute paths or `..` traversal even with spaces
        let namesOut = try await runProcess(executable: "/usr/bin/tar", arguments: ["-tjf", archive.path])
        for line in namesOut.split(whereSeparator: \.isNewline) {
            let pathStr = String(line)
            if pathStr.hasPrefix("/") || pathStr.split(separator: "/").contains("..") {
                throw MurmurError.downloadFailed("tar_unsafe_member:\(pathStr)")
            }
        }
        // 2. Extract cleanly with task cancellation support
        _ = try await runProcess(executable: "/usr/bin/tar", arguments: ["-xjf", archive.path, "-C", dir.path])
    }

    private static func runProcess(executable: String, arguments: [String]) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try proc.run()
                        // Drain stdout & stderr concurrently while process runs to avoid 64 KiB pipe deadlock
                        let group = DispatchGroup()
                        final class DataBox: @unchecked Sendable { var data = Data() }
                        let outBox = DataBox()
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        group.enter()
                        DispatchQueue.global(qos: .utility).async {
                            _ = errPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        proc.waitUntilExit()
                        group.wait()
                        if proc.terminationStatus == 0 {
                            cont.resume(returning: String(decoding: outBox.data, as: UTF8.self))
                        } else {
                            cont.resume(throwing: MurmurError.downloadFailed("tar_failed:\(proc.terminationStatus)"))
                        }
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            if proc.isRunning { proc.terminate() }
        }
    }
}
