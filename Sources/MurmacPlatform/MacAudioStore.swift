import AVFoundation
import Foundation
import MurmacCore

/// Stores dictation audio recordings locally as 16 kHz mono WAV under `~/Library/Application Support/Murmac/audio/`.
public final class MacAudioStore: AudioStorePort, @unchecked Sendable {
    public let rootURL: URL

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = appSupport.appendingPathComponent("Murmac/audio", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    public func save(samples: [Int16], key: AudioKey) throws -> String {
        let url = rootURL.appendingPathComponent("\(key.value).wav")
        let data = WavCodec.encode(samples: samples)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    public func load(path: String) throws -> [Int16] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try WavCodec.decode(data: data)
    }

    public func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

private final class TimerBox {
    var timer: Timer?
    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
    deinit {
        invalidate()
    }
}

/// Lightweight audio playback controller for History detail recordings (guarantees Timer invalidation in deinit).
@MainActor
public final class MacAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private let timerBox = TimerBox()

    public func load(path: String) {
        stop()
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let p = try? AVAudioPlayer(contentsOf: url) else {
            player = nil
            duration = 0
            return
        }
        p.delegate = self
        p.prepareToPlay()
        player = p
        duration = p.duration
        currentTime = 0
    }

    public func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
            timerBox.invalidate()
        } else {
            p.play()
            isPlaying = true
            timerBox.invalidate()
            timerBox.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let p = self.player else { return }
                    self.currentTime = p.currentTime
                }
            }
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = max(0, min(p.duration, seconds))
        currentTime = p.currentTime
    }

    public func stop() {
        timerBox.invalidate()
        player?.stop()
        isPlaying = false
        currentTime = 0
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.timerBox.invalidate()
        }
    }
}
