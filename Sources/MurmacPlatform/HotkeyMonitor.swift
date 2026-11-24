import AppKit
import CoreGraphics
import Foundation
import MurmacCore

/// Pure state machine for hotkey detection (unit-testable without CGEventTap).
public struct HotkeyDetector: Sendable {
    // Device-dependent macOS IOKit modifier masks (IOKit/hidsystem/IOLLEvent.h)
    public static let rightCommandMask: UInt64 = 0x0000_0010
    public static let rightOptionMask: UInt64  = 0x0000_0040
    public static let leftCommandMask: UInt64  = 0x0000_0008
    public static let leftOptionMask: UInt64   = 0x0000_0020

    public enum Action: Equatable, Sendable {
        case none
        case toggle
        case holdStart
        case holdStop
        case cancel
    }

    private var config: HotkeyConfig
    private var chordActive = false
    private var holding = false

    public init(config: HotkeyConfig = HotkeyConfig()) {
        self.config = config
    }

    public mutating func updateConfig(_ newConfig: HotkeyConfig) {
        self.config = newConfig
        reset()
    }

    public mutating func reset() {
        chordActive = false
        holding = false
    }

    public mutating func handleFlagsChanged(rawFlags: UInt64) -> Action {
        guard config.useRightCommandOption else { return .none }
        let rightCmd = (rawFlags & Self.rightCommandMask) != 0
        let rightOpt = (rawFlags & Self.rightOptionMask) != 0
        let bothDown = rightCmd && rightOpt

        if bothDown && !chordActive {
            chordActive = true
            switch config.mode {
            case .toggle:
                return .toggle
            case .hold:
                holding = true
                return .holdStart
            }
        } else if !bothDown && chordActive {
            chordActive = false
            if config.mode == .hold && holding {
                holding = false
                return .holdStop
            }
        }
        return .none
    }

    public mutating func handleKeyDown(keyCode: UInt16, flags: UInt64, isRecording: Bool, isAutorepeat: Bool = false) -> Action {
        if keyCode == 53 && isRecording { // Escape cancels active recording
            holding = false
            return .cancel
        }
        if isAutorepeat { return .none }
        guard !config.useRightCommandOption,
              let targetCode = config.customKeyCode,
              keyCode == targetCode else { return .none }
        let relevantMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        let expected = (config.customModifierMask ?? 0) & relevantMask
        let actual = flags & relevantMask
        guard actual == expected else { return .none }
        switch config.mode {
        case .toggle:
            return .toggle
        case .hold:
            if !holding {
                holding = true
                return .holdStart
            }
            return .none
        }
    }

    public mutating func handleKeyUp(keyCode: UInt16) -> Action {
        guard !config.useRightCommandOption,
              config.mode == .hold,
              holding,
              let targetCode = config.customKeyCode,
              keyCode == targetCode else { return .none }
        holding = false
        return .holdStop
    }
}

/// Retained weak-box wrapper for CGEventTap refcon so callbacks never UAF on stop/deinit.
private final class TapRefBox {
    weak var monitor: HotkeyMonitor?
    init(_ monitor: HotkeyMonitor) { self.monitor = monitor }
}

/// Global macOS hotkey monitor using `CGEventTap` on the main RunLoop (safe tap invalidation,
/// no external callback invocation under lock, ignores key autorepeat, resets latch on tap timeout).
public final class HotkeyMonitor: @unchecked Sendable {
    public struct Callbacks: Sendable {
        public let onToggle: @Sendable () -> Void
        public let onHoldStart: @Sendable () -> Void
        public let onHoldStop: @Sendable () -> Void
        public let onCancel: @Sendable () -> Void
        public let isRecording: @Sendable () -> Bool

        public init(
            onToggle: @escaping @Sendable () -> Void,
            onHoldStart: @escaping @Sendable () -> Void,
            onHoldStop: @escaping @Sendable () -> Void,
            onCancel: @escaping @Sendable () -> Void,
            isRecording: @escaping @Sendable () -> Bool
        ) {
            self.onToggle = onToggle
            self.onHoldStart = onHoldStart
            self.onHoldStop = onHoldStop
            self.onCancel = onCancel
            self.isRecording = isRecording
        }
    }

    private let lock = NSLock()
    private var detector: HotkeyDetector
    private let callbacks: Callbacks
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refBoxPtr: UnsafeMutableRawPointer?
    private var running = false

    public init(config: HotkeyConfig, callbacks: Callbacks) {
        self.detector = HotkeyDetector(config: config)
        self.callbacks = callbacks
    }

    deinit {
        let (tap, source, boxPtr): (CFMachPort?, CFRunLoopSource?, UnsafeMutableRawPointer?) = lock.withLock {
            let res = (eventTap, runLoopSource, refBoxPtr)
            eventTap = nil
            runLoopSource = nil
            refBoxPtr = nil
            running = false
            return res
        }
        Self.teardownOnMain(tap: tap, source: source, boxPtr: boxPtr)
    }

    public func updateConfig(_ config: HotkeyConfig) {
        lock.withLock {
            detector.updateConfig(config)
        }
    }

    @MainActor
    @discardableResult
    public func start() -> Bool {
        let alreadyRunning = lock.withLock { running }
        if alreadyRunning { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let box = TapRefBox(self)
        let retainedPtr = Unmanaged.passRetained(box).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<TapRefBox>.fromOpaque(refcon).takeUnretainedValue()
                box.monitor?.process(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: retainedPtr
        ) else {
            Unmanaged<TapRefBox>.fromOpaque(retainedPtr).release()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.withLock {
            eventTap = tap
            runLoopSource = source
            refBoxPtr = retainedPtr
            running = true
        }
        return true
    }

    public func stop() {
        let (tap, source, boxPtr): (CFMachPort?, CFRunLoopSource?, UnsafeMutableRawPointer?) = lock.withLock {
            let res = (eventTap, runLoopSource, refBoxPtr)
            eventTap = nil
            runLoopSource = nil
            refBoxPtr = nil
            running = false
            detector.reset()
            return res
        }
        Self.teardownOnMain(tap: tap, source: source, boxPtr: boxPtr)
    }

    private final class TeardownPayload: @unchecked Sendable {
        let tap: CFMachPort?
        let source: CFRunLoopSource?
        let boxPtr: UnsafeMutableRawPointer?
        init(tap: CFMachPort?, source: CFRunLoopSource?, boxPtr: UnsafeMutableRawPointer?) {
            self.tap = tap
            self.source = source
            self.boxPtr = boxPtr
        }
    }

    private static func teardownOnMain(tap: CFMachPort?, source: CFRunLoopSource?, boxPtr: UnsafeMutableRawPointer?) {
        guard tap != nil || source != nil || boxPtr != nil else { return }
        let payload = TeardownPayload(tap: tap, source: source, boxPtr: boxPtr)
        let cleanup: @Sendable () -> Void = {
            if let tap = payload.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            if let source = payload.source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            if let boxPtr = payload.boxPtr {
                Unmanaged<TapRefBox>.fromOpaque(boxPtr).release()
            }
        }
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }

    public var isRunning: Bool {
        lock.withLock { running }
    }

    private func process(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap: CFMachPort? = lock.withLock {
                detector.reset()
                return eventTap
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        // Read external recording state OUTSIDE self.lock to avoid any lock-inversion deadlock
        let recording = (type == .keyDown) ? callbacks.isRecording() : false
        let action: HotkeyDetector.Action = lock.withLock {
            switch type {
            case .flagsChanged:
                return detector.handleFlagsChanged(rawFlags: event.flags.rawValue)
            case .keyDown:
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                return detector.handleKeyDown(keyCode: code, flags: event.flags.rawValue, isRecording: recording, isAutorepeat: isRepeat)
            case .keyUp:
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                return detector.handleKeyUp(keyCode: code)
            default:
                return .none
            }
        }

        switch action {
        case .none: break
        case .toggle: callbacks.onToggle()
        case .holdStart: callbacks.onHoldStart()
        case .holdStop: callbacks.onHoldStop()
        case .cancel: callbacks.onCancel()
        }
    }
}
