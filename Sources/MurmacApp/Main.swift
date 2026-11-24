import AppKit
import Foundation
import MurmacCore
import MurmacInfer
import SwiftUI

@main
struct MurmacApplication {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-check") {
            let requireNative = args.contains("--require-native")
            let rc = SelfCheck.run(requireNative: requireNative)
            exit(rc)
        }
        let app = NSApplication.shared
        let delegate = MurmacAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

private enum SelfCheck {
    static func run(requireNative: Bool) -> Int32 {
        do {
            let catalog = try CatalogLoader.loadBundled()
            guard catalog.models.count >= 10 else {
                fputs("SELF_CHECK_FAIL: catalog has too few models (\(catalog.models.count))\n", stderr)
                return 1
            }

            let assets = BundlePromptAssets()
            for profileName in ["default.v1", "finetuned.v1"] {
                let profile = try assets.profile(name: profileName)
                let sys = try assets.systemPrompt(stem: RenderPy.versioned(profile.system))
                guard !sys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fputs("SELF_CHECK_FAIL: empty system prompt for \(profileName)\n", stderr)
                    return 1
                }
            }

            guard MurmacAppResources.bundle.url(forResource: "onest_variable", withExtension: "ttf", subdirectory: "fonts") != nil else {
                fputs("SELF_CHECK_FAIL: missing bundled font onest_variable.ttf\n", stderr)
                return 1
            }
            guard MurmacAppResources.bundle.url(forResource: "tokens", withExtension: "json") != nil else {
                fputs("SELF_CHECK_FAIL: missing bundled tokens.json\n", stderr)
                return 1
            }

            var nativeSummary = "skipped"
            if requireNative {
                final class Box: @unchecked Sendable {
                    var llm: EngineProbe?
                    var asr: EngineProbe?
                }
                let box = Box()
                let sem = DispatchSemaphore(value: 0)
                Task.detached {
                    box.llm = await LlamaLlmEngine().probe()
                    box.asr = await SherpaAsrEngine().probe()
                    sem.signal()
                }
                sem.wait()

                guard let llm = box.llm, !llm.availableUnits.isEmpty else {
                    fputs("SELF_CHECK_FAIL: LLM native runtime unavailable: \(box.llm?.facts ?? [:])\n", stderr)
                    return 1
                }
                guard let asr = box.asr, !asr.availableUnits.isEmpty else {
                    fputs("SELF_CHECK_FAIL: ASR native runtime unavailable: \(box.asr?.facts ?? [:])\n", stderr)
                    return 1
                }
                let llmUnits = llm.availableUnits.map(\.rawValue).joined(separator: ",")
                let asrVer = asr.facts["sherpa.version"] ?? "unknown"
                nativeSummary = "llm=[\(llmUnits)] asr=[v\(asrVer)]"
            }

            print("SELF_CHECK_OK catalog=\(catalog.catalogVersion) models=\(catalog.models.count) native=\(nativeSummary)")
            return 0
        } catch {
            fputs("SELF_CHECK_FAIL: \(error)\n", stderr)
            return 1
        }
    }
}

@MainActor
final class MurmacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var hudController: HudPanelController!
    private var menuBarController: MenuBarController!
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        hudController = HudPanelController(state: state)
        menuBarController = MenuBarController(state: state) { [weak self] in
            self?.showMainWindow()
        }
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the Menu Bar with the global hotkey active!
        return false
    }

    func showMainWindow() {
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmac"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AppShellView(state: state))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }
}

struct AppShellView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let l10n = state.l10n
        Group {
            if state.showOnboarding {
                OnboardingView(state: state)
            } else {
                HStack(spacing: 0) {
                    // Navigation Rail (88 pt wide, matching Murmur's inner display rail)
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(MurmacColor.accent)
                            .frame(width: 44, height: 44)
                            .background(MurmacColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 18)
                            .padding(.bottom, 12)

                        railItem(.history, icon: "clock.arrow.circlepath", label: l10n.t("History", "История"))
                        railItem(.dashboard, icon: "chart.bar", label: l10n.t("Overview", "Обзор"))
                        railItem(.models, icon: "cpu", label: l10n.t("Models", "Модели"))
                        railItem(.settings, icon: "slider.horizontal.3", label: l10n.t("Settings", "Настройки"))

                        Spacer()

                        Button {
                            state.toggleDictation(mode: .menuBar)
                        } label: {
                            let active: Bool = {
                                if case .listening = state.phase { return true }
                                return false
                            }()
                            Image(systemName: active ? "stop.fill" : "mic.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(active ? MurmacColor.err : MurmacColor.accent, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(state.settings.hotkey.displayLabel)
                        .padding(.bottom, 18)
                    }
                    .frame(width: 84)
                    .background(MurmacColor.surface)

                    Divider().background(MurmacColor.line)

                    // Active Tab Content
                    Group {
                        switch state.selectedTab {
                        case .history: HistoryView(state: state)
                        case .dashboard: DashboardView(state: state)
                        case .models: ModelsView(state: state)
                        case .settings: SettingsView(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $state.showPracticeSheet) {
            VStack(spacing: 16) {
                PracticeView(state: state)
                HStack {
                    Spacer()
                    Button(l10n.t("Close", "Закрыть")) { state.showPracticeSheet = false }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
                }
            }
            .padding(24)
            .frame(width: 540)
        }
    }

    private func railItem(_ tab: AppTab, icon: String, label: String) -> some View {
        let selected = state.selectedTab == tab
        return Button {
            state.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? MurmacColor.onAccent : MurmacColor.ink2)
                    .frame(width: 52, height: 30)
                    .background(selected ? MurmacColor.ink : Color.clear, in: Capsule())
                Text(label)
                    .font(MurmacFonts.sans(11, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? MurmacColor.ink : MurmacColor.ink3)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
