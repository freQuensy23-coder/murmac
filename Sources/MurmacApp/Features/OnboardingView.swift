import MurmacCore
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var state: AppState
    @State private var step = 0

    public var body: some View {
        let l10n = state.l10n
        VStack(spacing: 0) {
            // Top step indicator (clears macOS traffic lights / titlebar)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? MurmacColor.accent : MurmacColor.surface3)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 12)

            ScrollView {
                VStack {
                    Spacer(minLength: 24)
                    Group {
                        switch step {
                        case 0: welcomeStep(l10n: l10n)
                        case 1: permissionsStep(l10n: l10n)
                        case 2: modelsStep(l10n: l10n)
                        default: practiceStep(l10n: l10n)
                        }
                    }
                    .frame(maxWidth: 580)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .padding(.horizontal, 32)
            }

            Divider().background(MurmacColor.line)

            HStack {
                if step > 0 {
                    Button(l10n.t("Back", "Назад")) { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < 3 {
                    Button(l10n.t("Continue", "Продолжить")) { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
                } else {
                    Button(l10n.t("Finish Setup", "Завершить настройку")) {
                        state.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurmacColor.accent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .background(MurmacColor.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MurmacColor.bg)
    }

    @ViewBuilder
    private func welcomeStep(l10n: L10n) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(MurmacColor.accent)
            Text(l10n.t("Welcome to Murmac", "Добро пожаловать в Murmac"))
                .font(MurmacFonts.sans(30, weight: .semibold))
                .foregroundColor(MurmacColor.ink)
            Text(l10n.t(
                "Private, on-device dictation for macOS. Press \(state.settings.hotkey.displayLabel) anywhere to dictate, clean up with a local Metal LLM using on-screen context, and insert straight into your cursor.",
                "Приватная локальная диктовка для macOS. Нажмите \(state.settings.hotkey.displayLabel) в любом приложении — Murmac распознает речь, улучшит текст локальной LLM на Metal с учётом контекста экрана и вставит прямо под курсор."
            ))
            .font(MurmacFonts.sans(15))
            .foregroundColor(MurmacColor.ink2)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func permissionsStep(l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.t("macOS Permissions", "Разрешения macOS"))
                .font(MurmacFonts.sans(24, weight: .semibold))
                .foregroundColor(MurmacColor.ink)
            MurmacCard {
                VStack(spacing: 14) {
                    permLine(
                        title: l10n.t("Microphone", "Микрофон"),
                        granted: state.permissionSnapshot.microphone
                    ) {
                        Task {
                            _ = await state.permissions.requestMicrophone()
                            state.refreshPermissions()
                        }
                    }
                    Divider()
                    permLine(
                        title: l10n.t("Accessibility (Global Hotkey & Paste)", "Универсальный доступ (Хоткей и вставка)"),
                        granted: state.permissionSnapshot.accessibility
                    ) {
                        state.refreshPermissions()
                        if !state.permissionSnapshot.accessibility {
                            state.permissions.requestAccessibilityPrompt()
                            state.permissions.openSystemSettings(.accessibility)
                        }
                    }
                    Divider()
                    permLine(
                        title: l10n.t("Screen Recording (Optional · Apple Vision OCR)", "Запись экрана (Опционально · Vision OCR)"),
                        granted: state.permissionSnapshot.screenRecording
                    ) {
                        state.refreshPermissions()
                        if !state.permissionSnapshot.screenRecording {
                            state.permissions.requestScreenRecordingPrompt()
                            state.permissions.openSystemSettings(.screenRecording)
                        }
                    }
                }
            }

            Text(l10n.t(
                "Status updates automatically. Note: macOS requires restarting Murmac after enabling Screen Recording (and sometimes Accessibility after a fresh build).",
                "Статус обновляется автоматически. Важно: после включения «Записи экрана» (и иногда «Универсального доступа») macOS требует перезапустить Murmac."
            ))
            .font(MurmacFonts.sans(12))
            .foregroundColor(MurmacColor.ink3)

            HStack {
                Button(l10n.t("Restart Murmac", "Перезапустить Murmac")) {
                    state.relaunchApp()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(l10n.t("Refresh status", "Проверить снова")) { state.refreshPermissions() }
                    .buttonStyle(.bordered)
            }
        }
        .onAppear { state.refreshPermissions() }
        .task {
            // Auto-poll permissions every second while on the Permissions step
            while !Task.isCancelled {
                state.refreshPermissions()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func permLine(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? MurmacColor.ok : MurmacColor.ink4)
            Text(title).font(MurmacFonts.sans(14, weight: .medium)).foregroundColor(MurmacColor.ink)
            Spacer()
            if !granted {
                Button("Grant", action: action).buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func modelsStep(l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("Choose a local model pack", "Выберите набор локальных моделей"))
                .font(MurmacFonts.sans(24, weight: .semibold))
                .foregroundColor(MurmacColor.ink)
            Text(l10n.t("Everything runs offline on your Mac once downloaded.", "После загрузки всё работает полностью офлайн на вашем Mac."))
                .font(MurmacFonts.sans(13))
                .foregroundColor(MurmacColor.ink3)

            ForEach(state.catalog.packs) { pack in
                let packArtifacts = pack.items.compactMap { id in
                    state.catalog.models.first(where: { $0.id == id })?.preferredArtifact
                }
                let allInstalled = !packArtifacts.isEmpty && packArtifacts.allSatisfy {
                    if case .installed = state.installStates[$0.id] { return true }
                    return false
                }
                let downloadingProgress: Double? = {
                    var anyDownloading = false
                    var total: Int64 = 0
                    var received: Int64 = 0
                    for a in packArtifacts {
                        total += max(1, a.totalBytes)
                        switch state.installStates[a.id] {
                        case .installed:
                            received += max(1, a.totalBytes)
                        case .downloading(_, let rx, let tot):
                            anyDownloading = true
                            received += min(rx, max(1, tot))
                        default:
                            break
                        }
                    }
                    return anyDownloading ? Double(received) / Double(max(1, total)) : nil
                }()
                let totalSize = packArtifacts.reduce(Int64(0)) { $0 + $1.totalBytes }
                let isSelectedPack: Bool = {
                    let asrId = pack.items.first { id in state.catalog.models.first(where: { $0.id == id })?.kind == .asr }
                    let llmId = pack.items.first { id in state.catalog.models.first(where: { $0.id == id })?.kind == .llm }
                    if pack.id == "speech-only" {
                        return state.settings.selectedAsrModelId == asrId && !state.settings.cleanupEnabled
                    }
                    return state.settings.selectedAsrModelId == asrId && state.settings.selectedLlmModelId == llmId && state.settings.cleanupEnabled
                }()

                MurmacCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(pack.title).font(MurmacFonts.sans(15, weight: .semibold)).foregroundColor(MurmacColor.ink)
                                    if pack.recommended == true {
                                        MurmacBadge(l10n.t("Recommended", "Рекомендуем"))
                                    }
                                    if allInstalled {
                                        MurmacBadge(l10n.t("Installed", "Установлен"), fg: MurmacColor.ok, bg: MurmacColor.okSoft)
                                    }
                                }
                                Text("\(pack.description) · \(formatBytes(totalSize))")
                                    .font(MurmacFonts.sans(12))
                                    .foregroundColor(MurmacColor.ink3)
                            }
                            Spacer()
                            if let pct = downloadingProgress {
                                Text("\(Int(pct * 100))%")
                                    .font(MurmacFonts.mono(13, weight: .medium))
                                    .foregroundColor(MurmacColor.accentInk)
                            } else if allInstalled && isSelectedPack {
                                Label(l10n.t("Active", "Активен"), systemImage: "checkmark.circle.fill")
                                    .font(MurmacFonts.sans(13, weight: .semibold))
                                    .foregroundColor(MurmacColor.ok)
                            } else if allInstalled {
                                Button(l10n.t("Use Pack", "Выбрать")) {
                                    state.downloadPack(pack)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(MurmacColor.accent)
                            } else {
                                Button(l10n.t("Download Pack", "Скачать")) {
                                    state.downloadPack(pack)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(MurmacColor.accent)
                            }
                        }
                        if let pct = downloadingProgress {
                            ProgressView(value: pct)
                                .tint(MurmacColor.accent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func practiceStep(l10n: L10n) -> some View {
        PracticeView(state: state)
    }
}

public struct PracticeView: View {
    @ObservedObject var state: AppState

    public var body: some View {
        let l10n = state.l10n
        let isRecording: Bool = {
            if case .listening = state.phase { return true }
            return false
        }()

        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("Practice Dictation", "Пробная диктовка"))
                .font(MurmacFonts.sans(22, weight: .semibold))
                .foregroundColor(MurmacColor.ink)
            Text(l10n.t(
                "Click the button below or press \(state.settings.hotkey.displayLabel), say a sentence, then stop.",
                "Нажмите кнопку ниже или \(state.settings.hotkey.displayLabel), произнесите фразу и остановите запись."
            ))
            .font(MurmacFonts.sans(13))
            .foregroundColor(MurmacColor.ink3)

            TextEditor(text: $state.practiceText)
                .font(MurmacFonts.sans(16))
                .frame(height: 140)
                .padding(10)
                .background(MurmacColor.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(MurmacColor.line, lineWidth: 1))

            HStack {
                Button {
                    state.toggleDictation(mode: .inAppPractice)
                } label: {
                    Label(
                        isRecording ? l10n.t("Stop Recording", "Остановить запись") : l10n.t("Start Practice Dictation", "Начать диктовку"),
                        systemImage: isRecording ? "stop.circle.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? MurmacColor.err : MurmacColor.accent)

                if !state.practiceText.isEmpty {
                    Button(l10n.t("Clear", "Очистить")) { state.practiceText = "" }
                        .buttonStyle(.bordered)
                }
                Spacer()
                practicePhaseLabel(l10n: l10n)
            }
        }
    }

    @ViewBuilder
    private func practicePhaseLabel(l10n: L10n) -> some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .listening:
            MurmacBadge(l10n.t("Listening…", "Слушаю…"), fg: MurmacColor.err, bg: MurmacColor.errSoft)
        case .transcribing:
            MurmacBadge(l10n.t("Transcribing…", "Распознаю…"), fg: MurmacColor.accentInk, bg: MurmacColor.accentSoft)
        case .polishing:
            MurmacBadge(l10n.t("Cleaning up…", "Очищаю…"), fg: MurmacColor.accentInk, bg: MurmacColor.accentSoft)
        case .done(let outcome):
            switch outcome {
            case .inserted, .copied:
                MurmacBadge(l10n.t("Done", "Готово"), fg: MurmacColor.ok, bg: MurmacColor.okSoft)
            case .discarded:
                EmptyView()
            case .failed(let err):
                MurmacBadge(l10n.errorText(err), fg: MurmacColor.err, bg: MurmacColor.errSoft)
            }
        }
    }
}
