import Darwin
import Foundation

/// Locates prebuilt macOS native libraries (`libmurmur_llm.dylib`, `libsherpa-onnx-c-api.dylib`).
/// When running inside a `.app` bundle, `Contents/Frameworks` is checked exclusively first to prevent dylib hijacking.
/// In non-bundled dev/test runs, `MURMAC_NATIVE_LIBS_DIR` and `.cache/native/macos-arm64` are searched.
public enum NativeLibraryLocator {
    private static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public static func searchDirectories() -> [String] {
        var dirs: [String] = []
        if let fw = Bundle.main.privateFrameworksPath {
            dirs.append(fw)
        }
        // In a packaged .app bundle, never trust untrusted env vars or CWD for native library loading.
        if isAppBundle {
            return dirs
        }
        if let env = ProcessInfo.processInfo.environment["MURMAC_NATIVE_LIBS_DIR"], !env.isEmpty {
            dirs.append(env)
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent().path
        dirs.append(execDir)
        let cwd = FileManager.default.currentDirectoryPath
        dirs.append("\(cwd)/.cache/native/macos-arm64")
        for base in [cwd, execDir] {
            var u = URL(fileURLWithPath: base)
            for _ in 0..<5 {
                let candidate = u.appendingPathComponent(".cache/native/macos-arm64").path
                if FileManager.default.fileExists(atPath: candidate) {
                    dirs.append(candidate)
                    break
                }
                u.deleteLastPathComponent()
            }
        }
        var seen: Set<String> = []
        return dirs.filter { seen.insert($0).inserted }
    }

    public static func locate(filename: String) -> (path: String, dir: String)? {
        let fm = FileManager.default
        for dir in searchDirectories() {
            let full = (dir as NSString).appendingPathComponent(filename)
            if fm.fileExists(atPath: full) {
                return (full, dir)
            }
        }
        return nil
    }
}
