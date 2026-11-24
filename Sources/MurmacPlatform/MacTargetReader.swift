import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MurmacCore
import ScreenCaptureKit

/// Reads active app/window/focused text field via macOS Accessibility (`AXUIElement`) on a dedicated
/// utility queue (with a 300ms AX messaging timeout and strict CFTypeID validation)
/// and captures the active window screenshot in RAM via `ScreenCaptureKit`.
public final class MacTargetReader: TargetReaderPort, @unchecked Sendable {
    private let axQueue = DispatchQueue(label: "app.murmur.murmac.ax", qos: .userInitiated)

    public init() {}

    public func snapshot() async -> A11ySnapshot? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let frontInfo: (bundleId: String, appName: String?, pid: pid_t)? = await MainActor.run {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
            return (frontApp.bundleIdentifier ?? "unknown", frontApp.localizedName, frontApp.processIdentifier)
        }
        guard let info = frontInfo else { return nil }

        guard AXIsProcessTrusted() else {
            return A11ySnapshot(bundleId: info.bundleId, appName: info.appName, capturedAtMs: nowMs)
        }

        return await withCheckedContinuation { cont in
            axQueue.async {
                let appElem = AXUIElementCreateApplication(info.pid)
                // Bound every AX IPC call to 300 ms so beachballing apps never wedge dictation
                AXUIElementSetMessagingTimeout(appElem, 0.3)

                var windowTitle: String? = nil
                var windowBounds: Rect? = nil
                var windowNumber: Int? = nil

                if let axWin = self.axElement(appElem, kAXFocusedWindowAttribute) {
                    AXUIElementSetMessagingTimeout(axWin, 0.3)
                    windowTitle = self.axString(axWin, kAXTitleAttribute)
                    windowBounds = self.axFrame(axWin)
                    windowNumber = self.findWindowNumber(pid: info.pid, title: windowTitle, bounds: windowBounds)
                }

                var fieldSnap: FieldSnapshot? = nil
                if let axField = self.axElement(appElem, kAXFocusedUIElementAttribute) {
                    AXUIElementSetMessagingTimeout(axField, 0.3)
                    let role = self.axString(axField, kAXRoleAttribute)
                    let subrole = self.axString(axField, kAXSubroleAttribute)
                    let isPassword = (subrole == "AXSecureTextField")
                    let hint = self.axString(axField, kAXPlaceholderValueAttribute) ?? self.axString(axField, kAXDescriptionAttribute)
                    let bounds = self.axFrame(axField)
                    let isMultiline = (role == "AXTextArea" || role == "AXWebArea")
                    let isEditable = self.isEditableRole(role: role, element: axField)

                    var beforeCursor: String? = nil
                    if !isPassword {
                        beforeCursor = self.readBeforeCursor(axField)
                    }

                    fieldSnap = FieldSnapshot(
                        role: role,
                        subrole: subrole,
                        hint: hint,
                        beforeCursor: beforeCursor,
                        boundsInScreen: bounds,
                        isPassword: isPassword,
                        isMultiline: isMultiline,
                        isEditable: isEditable
                    )
                }

                cont.resume(returning: A11ySnapshot(
                    bundleId: info.bundleId,
                    appName: info.appName,
                    windowTitle: windowTitle,
                    windowNumber: windowNumber,
                    field: fieldSnap,
                    windowBoundsInScreen: windowBounds,
                    capturedAtMs: nowMs
                ))
            }
        }
    }

    public func screenshot(target: A11ySnapshot) async throws -> ScreenImageData {
        // Defense-in-depth: never capture a password field or denylisted password manager
        if target.field?.isPassword == true || MacBuiltInDenylist.bundleIds.contains(target.bundleId) {
            throw MurmurError.secureWindow
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw MurmurError.screenRecordingPermissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let matchingWindow: SCWindow?
        if let wid = target.windowNumber {
            matchingWindow = content.windows.first { Int($0.windowID) == wid }
        } else {
            matchingWindow = content.windows.first {
                $0.owningApplication?.bundleIdentifier == target.bundleId && $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100
            }
        }
        guard let window = matchingWindow else {
            throw MurmurError.ocrFailed("window_not_found")
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        // Cap BOTH width and height so tall/narrow windows also stay bounded for fast Vision OCR
        let maxDim = max(1.0, max(window.frame.width, window.frame.height))
        let scale = min(2.0, 1920.0 / maxDim)
        cfg.width = max(1, Int(window.frame.width * scale))
        cfg.height = max(1, Int(window.frame.height * scale))
        cfg.showsCursor = false
        cfg.capturesAudio = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return ScreenImageData(width: cgImage.width, height: cgImage.height, cgImageBox: { cgImage })
    }

    // MARK: - Safe AX helpers (strict CFTypeID checks before every cast)

    private func axElement(_ elem: AXUIElement, _ attr: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &ref) == .success,
              let val = ref,
              CFGetTypeID(val) == AXUIElementGetTypeID() else { return nil }
        return (val as! AXUIElement)
    }

    private func axValue(_ elem: AXUIElement, _ attr: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &ref) == .success,
              let val = ref,
              CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
        return (val as! AXValue)
    }

    private func axString(_ elem: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func axFrame(_ elem: AXUIElement) -> Rect? {
        guard let pVal = axValue(elem, kAXPositionAttribute),
              let sVal = axValue(elem, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(pVal, .cgPoint, &pt),
              AXValueGetValue(sVal, .cgSize, &sz) else { return nil }
        return Rect(x0: Int(pt.x), y0: Int(pt.y), x1: Int(pt.x + sz.width), y1: Int(pt.y + sz.height))
    }

    private func axSelectedRange(_ elem: AXUIElement) -> CFRange? {
        guard let val = axValue(elem, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange(location: 0, length: 0)
        return AXValueGetValue(val, .cfRange, &range) ? range : nil
    }

    /// Reads up to 1000 chars before the caret using parameterized range queries first (avoiding multi-MB full-document copies).
    private func readBeforeCursor(_ axField: AXUIElement) -> String? {
        if let range = axSelectedRange(axField), range.location >= 0 {
            let start = max(0, range.location - 1000)
            let len = range.location - start
            if len == 0 { return "" }
            var sliceRange = CFRange(location: start, length: len)
            if let axRange = AXValueCreate(.cfRange, &sliceRange) {
                var strRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(axField, kAXStringForRangeParameterizedAttribute as CFString, axRange, &strRef) == .success,
                   let s = strRef as? String {
                    return s
                }
            }
            // Fallback to kAXValueAttribute if parameterized query isn't supported by the app
            if let val = axString(axField, kAXValueAttribute) {
                let ns = val as NSString
                let loc = min(range.location, ns.length)
                let st = max(0, loc - 1000)
                return ns.substring(with: NSRange(location: st, length: loc - st))
            }
        } else if let val = axString(axField, kAXValueAttribute) {
            return String(val.suffix(1000))
        }
        return nil
    }

    private func isEditableRole(role: String?, element: AXUIElement) -> Bool {
        if let r = role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"].contains(r) {
            return true
        }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue {
            return true
        }
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue {
            return true
        }
        return false
    }

    private func findWindowNumber(pid: pid_t, title: String?, bounds: Rect?) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = info[kCGWindowNumber as String] as? Int else { continue }
            if let title, !title.isEmpty, let name = info[kCGWindowName as String] as? String, name == title {
                return num
            }
            if let bounds, let dict = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict as CFDictionary),
               abs(Int(rect.origin.x) - bounds.x0) <= 4 && abs(Int(rect.origin.y) - bounds.y0) <= 4 {
                return num
            }
        }
        for info in list {
            if let ownerPid = info[kCGWindowOwnerPID as String] as? pid_t, ownerPid == pid,
               let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
               let num = info[kCGWindowNumber as String] as? Int {
                return num
            }
        }
        return nil
    }
}
