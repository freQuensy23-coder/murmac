import AppKit
import Combine
import MurmacCore
import SwiftUI

/// Non-activating floating HUD pill (`NSPanel` with `.nonactivatingPanel`) so it NEVER steals focus
/// from the user's active text field while displaying Listening waveform, Transcribing, Polishing, or Done status.
@MainActor
public final class HudPanelController {
    private let state: AppState
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    public init(state: AppState) {
        self.state = state
        self.cancellable = state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.updateVisibility(for: phase)
            }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: HudPillView(state: state))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = hosting
        self.panel = p
        return p
    }

    private func updateVisibility(for phase: DictationPhase) {
        guard state.settings.showHud else {
            panel?.orderOut(nil)
            return
        }
        switch phase {
        case .idle:
            panel?.orderOut(nil)
        case .listening, .transcribing, .polishing, .done:
            let p = ensurePanel()
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let frame = screen.visibleFrame
                let w: CGFloat = 290
                let h: CGFloat = 52
                let x = frame.midX - w / 2
                let y = frame.minY + 34
                p.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            }
            p.orderFrontRegardless()
        }
    }
}

private struct HudPillView: View {
    @ObservedObject var state: AppState
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let l10n = state.l10n
        HStack(spacing: 12) {
            switch state.phase {
            case .idle:
                EmptyView()
            case .listening(let startedAtMs, let warn):
                Circle()
                    .fill(warn ? MurmacColor.warn : Color.white)
                    .frame(width: 8, height: 8)
                WaveformBars(levels: state.levels)
                Text(elapsedString(startedAtMs: startedAtMs))
                    .font(MurmacFonts.mono(13, weight: .medium))
                    .foregroundColor(.white)
                Spacer(minLength: 4)
                Button(action: { state.cancelDictation() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                    .tint(MurmacColor.onInverse)
                Text(l10n.t("Transcribing…", "Распознаю…"))
                    .font(MurmacFonts.sans(13, weight: .semibold))
                    .foregroundColor(MurmacColor.onInverse)
            case .polishing:
                ProgressView()
                    .controlSize(.small)
                    .tint(MurmacColor.onInverse)
                Text(l10n.t("Polishing…", "Улучшаю текст…"))
                    .font(MurmacFonts.sans(13, weight: .semibold))
                    .foregroundColor(MurmacColor.onInverse)
            case .done(let outcome):
                doneContent(outcome, l10n: l10n)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(pillBackground, in: Capsule())
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 6)
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private func doneContent(_ outcome: DictationOutcome, l10n: L10n) -> some View {
        switch outcome {
        case .inserted(let cleaned, _):
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(MurmacColor.ok)
            Text(cleaned ? l10n.t("Inserted", "Вставлено") : l10n.t("Inserted (raw)", "Вставлено (без LLM)"))
                .font(MurmacFonts.sans(13, weight: .semibold))
                .foregroundColor(MurmacColor.onInverse)
        case .copied:
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(MurmacColor.accent)
            Text(l10n.t("Copied · Press ⌘V", "Скопировано · ⌘V"))
                .font(MurmacFonts.sans(13, weight: .semibold))
                .foregroundColor(MurmacColor.onInverse)
        case .discarded:
            Image(systemName: "lock.fill")
                .foregroundColor(MurmacColor.warn)
            Text(l10n.t("Discarded (password)", "Отменено (пароль)"))
                .font(MurmacFonts.sans(13, weight: .semibold))
                .foregroundColor(MurmacColor.onInverse)
        case .failed(let err):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(MurmacColor.err)
            Text(l10n.errorText(err))
                .font(MurmacFonts.sans(13, weight: .semibold))
                .foregroundColor(MurmacColor.onInverse)
                .lineLimit(1)
        }
    }

    private var pillBackground: Color {
        switch state.phase {
        case .listening(_, let warn):
            return warn ? Color(red: 0.72, green: 0.42, blue: 0.05) : Color(red: 0.184, green: 0.294, blue: 0.910)
        default:
            return MurmacColor.inverse
        }
    }

    private func elapsedString(startedAtMs: Int64) -> String {
        let nowMono = Int64(ProcessInfo.processInfo.systemUptime * 1000.0)
        let sec = max(0, Int((nowMono - startedAtMs) / 1000))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

private struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(7, levels.count), id: \.self) { i in
                let h = max(4.0, CGFloat(levels[i]) * 20.0 + 4.0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: h)
                    .animation(.linear(duration: 0.05), value: levels[i])
            }
        }
        .frame(height: 24)
    }
}
