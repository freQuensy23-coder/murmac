import MurmacCore
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var state: AppState
    @State private var step = 0

    public var body: some View {
        let l10n = state.l10n
        VStack(spacing: 0) {
            // Top step indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? MurmacColor.accent : MurmacColor.surface3)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)

            Spacer()

            Group {
                switch step {
                case 0: welcomeStep(l10n: l10n)
                case 1: permissionsStep(l10n: l10n)
                case 2: modelsStep(l10n: l10n)
                default: practiceStep(l10n: l10n)
                }
            }
            .frame(maxWidth: 560)

            Spacer()

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
            .padding(.bottom, 28)
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
                        state.permissions.requestAccessibilityPrompt()
                        state.permissions.openSystemSettings(.accessibility)
                    }
                    Divider()
                    permLine(
                        title: l10n.t("Screen Recording (Optional · Apple Vision OCR)", "Запись экрана (Опционально · Vision OCR)"),
                        granted: state.permissionSnapshot.screenRecording
                    ) {
                        state.permissions.requestScreenRecordingPrompt()
                        state.permissions.openSystemSettings(.screenRecording)
                    }
                }
            }
            HStack {
                Spacer()
                Button(l10n.t("Refresh status", "Проверить снова")) { state.refreshPermissions() }
                    .buttonStyle(.bordered)
            }
        }
        .onAppear { state.refreshPermissions() }
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
                MurmacCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(pack.title).font(MurmacFonts.sans(15, weight: .semibold)).foregroundColor(MurmacColor.ink)
                                if pack.recommended == true {
                                    MurmacBadge(l10n.t("Recommended", "Рекомендуем"))
                                }
                            }
                            Text(pack.description).font(MurmacFonts.sans(12)).foregroundColor(MurmacColor.ink3)
                        }
                        Spacer()
                        Button(l10n.t("Download Pack", "Скачать")) {
                            state.downloadPack(pack)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
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
            }
        }
    }
}
