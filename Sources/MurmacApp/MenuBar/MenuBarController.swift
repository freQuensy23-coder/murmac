import AppKit
import Combine
import MurmacCore

/// macOS Menu Bar status item (`NSStatusItem`) showing live dictation state and quick controls.
@MainActor
public final class MenuBarController: NSObject {
    private let state: AppState
    private let onOpenWindow: () -> Void
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    public init(state: AppState, onOpenWindow: @escaping () -> Void) {
        self.state = state
        self.onOpenWindow = onOpenWindow
        super.init()
        setupStatusItem()
        observe()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        updateIcon(for: state.phase)
        rebuildMenu()
    }

    private func observe() {
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.updateIcon(for: phase)
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        state.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for phase: DictationPhase) {
        guard let btn = statusItem?.button else { return }
        let symbol: String
        switch phase {
        case .idle, .done:
            symbol = "waveform"
        case .listening:
            symbol = "waveform.circle.fill"
        case .transcribing, .polishing:
            symbol = "ellipsis.circle"
        }
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Murmac")
        btn.image?.isTemplate = true
    }

    private func rebuildMenu() {
        let l10n = state.l10n
        let menu = NSMenu()

        let isRecording: Bool
        if case .listening = state.phase { isRecording = true } else { isRecording = false }

        let dictTitle = isRecording
            ? l10n.t("Stop Dictation (\(state.settings.hotkey.displayLabel))", "Остановить диктовку (\(state.settings.hotkey.displayLabel))")
            : l10n.t("Start Dictation (\(state.settings.hotkey.displayLabel))", "Начать диктовку (\(state.settings.hotkey.displayLabel))")
        let toggleItem = NSMenuItem(title: dictTitle, action: #selector(handleToggleDictation), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let cleanupItem = NSMenuItem(
            title: l10n.t("Local LLM Cleanup", "Локальная очистка LLM"),
            action: #selector(handleToggleCleanup),
            keyEquivalent: ""
        )
        cleanupItem.target = self
        cleanupItem.state = state.settings.cleanupEnabled ? .on : .off
        menu.addItem(cleanupItem)

        let screenItem = NSMenuItem(
            title: l10n.t("Screen Context (Vision OCR)", "Контекст экрана (Vision OCR)"),
            action: #selector(handleToggleScreen),
            keyEquivalent: ""
        )
        screenItem.target = self
        screenItem.state = state.settings.useScreenContext ? .on : .off
        menu.addItem(screenItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: l10n.t("Open Murmac…", "Открыть Murmac…"), action: #selector(handleOpen), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: l10n.t("Quit Murmac", "Выйти из Murmac"), action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func handleToggleDictation() { state.toggleDictation(mode: .menuBar) }
    @objc private func handleToggleCleanup() { state.updateSettings { $0.cleanupEnabled.toggle() } }
    @objc private func handleToggleScreen() { state.updateSettings { $0.useScreenContext.toggle() } }
    @objc private func handleOpen() { onOpenWindow() }
    @objc private func handleQuit() { NSApp.terminate(nil) }
}
