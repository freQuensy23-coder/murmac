import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import MurmacCore

public final class MacPermissions: PermissionMonitorPort, @unchecked Sendable {
    public init() {}

    public func check() -> PermissionSnapshot {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let a11y = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        return PermissionSnapshot(microphone: mic, accessibility: a11y, screenRecording: screen)
    }

    public func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func requestAccessibilityPrompt() {
        guard !AXIsProcessTrusted() else { return }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    public func requestScreenRecordingPrompt() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    public func openSystemSettings(_ pane: PermissionPane) {
        let urlStr: String
        switch pane {
        case .microphone:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}

public final class MacFeedback: FeedbackPort, @unchecked Sendable {
    public init() {}

    private func play(_ name: String) {
        DispatchQueue.main.async {
            if let s = NSSound(named: NSSound.Name(name)) {
                s.volume = 0.35
                s.play()
            }
        }
    }

    public func playStart() { play("Tink") }
    public func playStop()  { play("Pop") }
    public func playDone()  { play("Glass") }
    public func playError() { play("Basso") }
}

public struct InstalledAppInfo: Identifiable, Hashable, Sendable {
    public let id: String // bundleId
    public let name: String
    public let path: String

    public init(bundleId: String, name: String, path: String) {
        self.id = bundleId
        self.name = name
        self.path = path
    }
}

public enum MacAppInfo {
    public static func icon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    public static func runningAndCommonApps() -> [InstalledAppInfo] {
        var seen: Set<String> = []
        var list: [InstalledAppInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, let name = app.localizedName,
                  seen.insert(bid).inserted else { continue }
            list.append(InstalledAppInfo(bundleId: bid, name: name, path: app.bundleURL?.path ?? ""))
        }
        let appDirs = ["/Applications", "/System/Applications"]
        let fm = FileManager.default
        for dir in appDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let full = (dir as NSString).appendingPathComponent(item)
                guard let bundle = Bundle(path: full),
                      let bid = bundle.bundleIdentifier,
                      seen.insert(bid).inserted else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? (item as NSString).deletingPathExtension
                list.append(InstalledAppInfo(bundleId: bid, name: name, path: full))
            }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
