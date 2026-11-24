import Foundation

/// Resolves SwiftPM resource bundles cleanly both inside packaged macOS `.app` bundles
/// (`Contents/Resources/<name>.bundle`) and during `swift test` / `swift run` (`Bundle.module`).
public enum MurmacCoreResources {
    public static let bundle: Bundle = {
        let name = "Murmac_MurmacCore.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
        ]
        for candidate in candidates {
            if let url = candidate, let b = Bundle(url: url) {
                return b
            }
        }
        return Bundle.module
    }()
}
