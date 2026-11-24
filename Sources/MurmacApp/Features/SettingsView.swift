import AppKit
import MurmacCore
import MurmacPlatform
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case cleanup
    case privacy
    case permissions

    var id: String { rawValue }
}

public struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var category: SettingsCategory = .general
    @State private var installedApps: [InstalledAppInfo] = []
    @State private var appSearchQuery: String = ""
    @State private var showPromptEditor = false

    public var body: some View {
        let l10n = state.l10n
        HStack(spacing: 0) {
            // Left categories pane
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("Settings", "Настройки"))
                    .font(MurmacFonts.sans(22, weight: .semibold))
                    .foregroundColor(MurmacColor.ink)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                categoryRow(.general, icon: "slider.horizontal.3", title: l10n.t("General & Hotkey", "Общие и хоткей"))
                categoryRow(.cleanup, icon: "sparkles", title: l10n.t("Cleanup & Prompt", "Очистка и промпт"))
                categoryRow(.privacy, icon: "eye.slash", title: l10n.t("Screen Context & Privacy", "Контекст и приватность"))
                categoryRow(.permissions, icon: "checkmark.shield", title: l10n.t("Permissions & About", "Права и о программе"))

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(width: 240)
            .background(MurmacColor.bg)

            Divider().background(MurmacColor.line)

            // Right detail pane
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch category {
                    case .general: generalPane(l10n: l10n)
                    case .cleanup: cleanupPane(l10n: l10n)
                    case .privacy: privacyPane(l10n: l10n)
                    case .permissions: permissionsPane(l10n: l10n)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MurmacColor.surface)
        }
        .onAppear {
            state.refreshPermissions()
        }
        .task {
            if installedApps.isEmpty {
                let apps = await Task.detached(priority: .userInitiated) {
                    MacAppInfo.runningAndCommonApps()
                }.value
                installedApps = apps
            }
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorSheet(state: state)
        }
    }

    private func categoryRow(_ cat: SettingsCategory, icon: String, title: String) -> some View {
        let active = category == cat
        return Button {
            category = cat
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(active ? MurmacColor.accentInk : MurmacColor.ink2)
                Text(title)
                    .font(MurmacFonts.sans(14, weight: active ? .semibold : .medium))
                    .foregroundColor(active ? MurmacColor.ink : MurmacColor.ink2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(active ? MurmacColor.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func generalPane(l10n: L10n) -> some View {
        Text(l10n.t("General & Hotkey", "Общие и хоткей"))
            .font(MurmacFonts.sans(22, weight: .semibold))
            .foregroundColor(MurmacColor.ink)

        MurmacCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Dictation Hotkey", "Сочетание клавиш диктовки"))
                            .font(MurmacFonts.sans(14, weight: .semibold))
                        Text(l10n.t("Press once to start recording, press again to stop. Press Esc to cancel.",
                                    "Нажмите один раз для старта, ещё раз — для остановки. Esc — отмена."))
                            .font(MurmacFonts.sans(12))
                            .foregroundColor(MurmacColor.ink3)
                    }
                    Spacer()
                    MurmacBadge(state.settings.hotkey.displayLabel)
                }

                Picker(l10n.t("Trigger mode", "Режим хоткея"), selection: Binding(
                    get: { state.settings.hotkey.mode },
                    set: { m in state.updateSettings { $0.hotkey.mode = m } }
                )) {
                    Text(l10n.t("Toggle (press to start / stop)", "Переключатель (нажал — стоп)")).tag(HotkeyMode.toggle)
                    Text(l10n.t("Hold to talk", "Удержание (Hold to talk)")).tag(HotkeyMode.hold)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button(l10n.t("Reset to Right ⌘ + Right ⌥", "Сбросить на Right ⌘ + Right ⌥")) {
                        state.updateSettings {
                            $0.hotkey.useRightCommandOption = true
                            $0.hotkey.customKeyCode = nil
                            $0.hotkey.customModifierMask = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.settings.hotkey.useRightCommandOption)

                    Button(l10n.t("Use ⌥ + Space instead", "Использовать ⌥ + Space")) {
                        state.updateSettings {
                            $0.hotkey.useRightCommandOption = false
                            $0.hotkey.customKeyCode = 49 // Space
                            $0.hotkey.customModifierMask = (1 << 19) // Option
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        MurmacCard {
            VStack(alignment: .leading, spacing: 14) {
                Picker(l10n.t("Dictation language", "Язык диктовки"), selection: Binding(
                    get: { state.settings.language },
                    set: { lang in state.updateSettings { $0.language = lang } }
                )) {
                    ForEach(DictationLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                Picker(l10n.t("Interface language", "Язык интерфейса"), selection: Binding(
                    get: { state.settings.uiLanguage },
                    set: { lang in state.updateSettings { $0.uiLanguage = lang } }
                )) {
                    ForEach(UiLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                Toggle(l10n.t("Show floating HUD indicator during dictation", "Показывать плавающий HUD-индикатор во время записи"), isOn: Binding(
                    get: { state.settings.showHud },
                    set: { v in state.updateSettings { $0.showHud = v } }
                ))

                Toggle(l10n.t("Play subtle sound cues", "Воспроизводить тихие звуки старта/стопа"), isOn: Binding(
                    get: { state.settings.playSounds },
                    set: { v in state.updateSettings { $0.playSounds = v } }
                ))

                Toggle(l10n.t("Restore previous clipboard after pasting (Wispr Flow style)", "Восстанавливать буфер обмена после вставки (как в Wispr Flow)"), isOn: Binding(
                    get: { state.settings.restoreClipboard },
                    set: { v in state.updateSettings { $0.restoreClipboard = v } }
                ))
            }
        }
    }

    @ViewBuilder
    private func cleanupPane(l10n: L10n) -> some View {
        Text(l10n.t("Cleanup & Prompt", "Очистка и промпт"))
            .font(MurmacFonts.sans(22, weight: .semibold))
            .foregroundColor(MurmacColor.ink)

        MurmacCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(l10n.t("Enable local LLM cleanup", "Включить локальную LLM-очистку"), isOn: Binding(
                    get: { state.settings.cleanupEnabled },
                    set: { v in state.updateSettings { $0.cleanupEnabled = v } }
                ))

                Picker(l10n.t("Compute backend", "Вычислительный бэкенд"), selection: Binding(
                    get: { state.settings.llmUnitPreference },
                    set: { u in state.updateSettings { $0.llmUnitPreference = u } }
                )) {
                    ForEach(UnitPreference.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .pickerStyle(.segmented)

                Picker(l10n.t("Unload idle models after", "Выгружать неактивные модели через"), selection: Binding(
                    get: { state.settings.idleUnloadSeconds },
                    set: { sec in state.updateSettings { $0.idleUnloadSeconds = sec } }
                )) {
                    Text("30 s").tag(30)
                    Text("60 s").tag(60)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                }
            }
        }

        MurmacCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Cleanup prompt & My preferences", "Промпт очистки и «Мои предпочтения»"))
                            .font(MurmacFonts.sans(14, weight: .semibold))
                        Text(l10n.t("Customize cleanup instructions or add vocabulary / style rules.",
                                    "Настройте системный промпт или добавьте словарь терминов и предпочтения."))
                            .font(MurmacFonts.sans(12))
                            .foregroundColor(MurmacColor.ink3)
                    }
                    Spacer()
                    Button(l10n.t("Edit prompt…", "Редактировать…")) {
                        showPromptEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurmacColor.accent)
                }

                Text(l10n.t("MY PREFERENCES", "МОИ ПРЕДПОЧТЕНИЯ"))
                    .font(MurmacFonts.sans(11, weight: .semibold))
                    .foregroundColor(MurmacColor.ink3)
                    .tracking(0.8)

                TextEditor(text: Binding(
                    get: { state.settings.userPreferences },
                    set: { txt in
                        let clipped = String(txt.prefix(PromptEditRules.maxPreferencesChars))
                        state.updateSettings { $0.userPreferences = clipped }
                    }
                ))
                .font(MurmacFonts.mono(12))
                .frame(height: 90)
                .padding(6)
                .background(MurmacColor.surface2, in: RoundedRectangle(cornerRadius: 10))
                Text("\(state.settings.userPreferences.count) / \(PromptEditRules.maxPreferencesChars)")
                    .font(MurmacFonts.mono(11))
                    .foregroundColor(MurmacColor.ink3)
            }
        }
    }

    @ViewBuilder
    private func privacyPane(l10n: L10n) -> some View {
        Text(l10n.t("Screen Context & Privacy", "Контекст и приватность"))
            .font(MurmacFonts.sans(22, weight: .semibold))
            .foregroundColor(MurmacColor.ink)

        MurmacCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(l10n.t("Use what's on screen (Apple Vision OCR)", "Использовать контекст экрана (Apple Vision OCR)"), isOn: Binding(
                    get: { state.settings.useScreenContext },
                    set: { v in state.updateSettings { $0.useScreenContext = v } }
                ))
                Text(l10n.t(
                    "Captures only the active window in RAM ~0.5 s after start, reads text on Neural Engine, and discards it immediately after cleanup. Never saved to disk or sent over network.",
                    "Снимает только активное окно в RAM через ~0.5 с после старта, распознаёт текст на Neural Engine и сразу удаляет из памяти. Никогда не сохраняется на диск и не уходит в сеть."
                ))
                .font(MurmacFonts.sans(12))
                .foregroundColor(MurmacColor.ink3)

                Divider()

                Picker(l10n.t("Keep dictation history", "Хранить историю диктовок"), selection: Binding(
                    get: { state.settings.historyRetentionDays },
                    set: { d in state.updateSettings { $0.historyRetentionDays = d } }
                )) {
                    Text(l10n.t("Don't keep", "Не хранить")).tag(0)
                    Text(l10n.t("1 day", "1 день")).tag(1)
                    Text(l10n.t("7 days", "7 дней")).tag(7)
                    Text(l10n.t("30 days", "30 дней")).tag(30)
                    Text(l10n.t("1 year", "1 год")).tag(365)
                }

                Toggle(l10n.t("Save audio recordings for playback & Retry", "Сохранять аудиозаписи для прослушивания и Retry"), isOn: Binding(
                    get: { state.settings.keepAudioHistory },
                    set: { v in state.updateSettings { $0.keepAudioHistory = v } }
                ))
            }
        }

        MurmacCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.t("EXCLUDED APPS (NO DICTATION OR SCREEN CAPTURE)", "ИСКЛЮЧЁННЫЕ ПРИЛОЖЕНИЯ"))
                    .font(MurmacFonts.sans(11, weight: .semibold))
                    .foregroundColor(MurmacColor.ink3)
                    .tracking(0.8)
                Text(l10n.t("Password managers (1Password, Keychain, Bitwarden, Passwords) and password fields are always excluded automatically.",
                            "Менеджеры паролей (1Password, Связка ключей, Bitwarden, Passwords) и поля паролей исключены всегда автоматически."))
                    .font(MurmacFonts.sans(12))
                    .foregroundColor(MurmacColor.ink3)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(MurmacColor.ink3)
                    TextField(l10n.t("Filter apps…", "Поиск приложений…"), text: $appSearchQuery)
                        .textFieldStyle(.plain)
                        .font(MurmacFonts.sans(13))
                    if !appSearchQuery.isEmpty {
                        Button(action: { appSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(MurmacColor.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MurmacColor.surface2, in: Capsule())

                let filteredApps: [InstalledAppInfo] = {
                    let knownIds = Set(installedApps.map(\.id))
                    let extraExcluded = state.settings.excludedBundleIds
                        .filter { !knownIds.contains($0) }
                        .map { InstalledAppInfo(bundleId: $0, name: $0, path: "") }
                    let all = extraExcluded + installedApps
                    let q = appSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !q.isEmpty else { return all }
                    return all.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
                }()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            let excluded = state.settings.excludedBundleIds.contains(app.id)
                            HStack {
                                if let icon = MacAppInfo.icon(for: app.id) {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name).font(MurmacFonts.sans(13)).foregroundColor(MurmacColor.ink)
                                    Text(app.id).font(MurmacFonts.mono(10)).foregroundColor(MurmacColor.ink3)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { excluded },
                                    set: { on in
                                        state.updateSettings { s in
                                            if on {
                                                if !s.excludedBundleIds.contains(app.id) { s.excludedBundleIds.append(app.id) }
                                            } else {
                                                s.excludedBundleIds.removeAll { $0 == app.id }
                                            }
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    @ViewBuilder
    private func permissionsPane(l10n: L10n) -> some View {
        HStack {
            Text(l10n.t("Permissions & About", "Права и о программе"))
                .font(MurmacFonts.sans(22, weight: .semibold))
                .foregroundColor(MurmacColor.ink)
            Spacer()
            Button(l10n.t("Restart Murmac", "Перезапустить")) { state.relaunchApp() }
                .buttonStyle(.bordered)
            Button(l10n.t("Refresh", "Обновить")) { state.refreshPermissions() }
                .buttonStyle(.bordered)
        }

        MurmacCard {
            VStack(spacing: 14) {
                permRow(
                    title: l10n.t("Microphone", "Микрофон"),
                    desc: l10n.t("Required to record speech locally.", "Нужен для локальной записи речи."),
                    granted: state.permissionSnapshot.microphone,
                    actionLabel: l10n.t("Grant / Open", "Открыть")
                ) {
                    Task {
                        _ = await state.permissions.requestMicrophone()
                        state.refreshPermissions()
                        if !state.permissionSnapshot.microphone {
                            state.permissions.openSystemSettings(.microphone)
                        }
                    }
                }
                Divider()
                permRow(
                    title: l10n.t("Accessibility", "Универсальный доступ"),
                    desc: l10n.t("Required for global hotkey (\(state.settings.hotkey.displayLabel)), focused field detection, and pasting.",
                                 "Нужен для глобального хоткея (\(state.settings.hotkey.displayLabel)), определения активного поля и вставки текста."),
                    granted: state.permissionSnapshot.accessibility,
                    actionLabel: l10n.t("Open Settings", "Открыть настройки")
                ) {
                    state.permissions.requestAccessibilityPrompt()
                    state.permissions.openSystemSettings(.accessibility)
                }
                Divider()
                permRow(
                    title: l10n.t("Screen Recording", "Запись экрана"),
                    desc: l10n.t("Optional: lets Apple Vision OCR read context from the active window.",
                                 "Опционально: позволяет Apple Vision OCR читать контекст из активного окна."),
                    granted: state.permissionSnapshot.screenRecording,
                    actionLabel: l10n.t("Open Settings", "Открыть настройки")
                ) {
                    state.permissions.requestScreenRecordingPrompt()
                    state.permissions.openSystemSettings(.screenRecording)
                }
            }
        }

        MurmacCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Murmac").font(MurmacFonts.sans(16, weight: .semibold))
                Text(l10n.t("Local on-device dictation for macOS. Ported from Murmur. Apache-2.0.",
                            "Локальная диктовка на устройстве для macOS. Порт Murmur. Apache-2.0."))
                    .font(MurmacFonts.sans(13))
                    .foregroundColor(MurmacColor.ink3)
                Button(l10n.t("Run Onboarding Again", "Запустить онбординг снова")) {
                    state.showOnboarding = true
                }
                .buttonStyle(.bordered)
                .padding(.top, 6)
            }
        }
    }

    private func permRow(title: String, desc: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(MurmacFonts.sans(14, weight: .semibold)).foregroundColor(MurmacColor.ink)
                    MurmacBadge(granted ? "Granted" : "Needed", fg: granted ? MurmacColor.ok : MurmacColor.warn, bg: granted ? MurmacColor.okSoft : MurmacColor.warnSoft)
                }
                Text(desc).font(MurmacFonts.sans(12)).foregroundColor(MurmacColor.ink3)
            }
            Spacer()
            if !granted {
                Button(actionLabel, action: action).buttonStyle(.bordered)
            }
        }
    }
}

private struct PromptEditorSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var profileName: String = "default.v1"
    @State private var isEditable: Bool = true
    @State private var problems: [String] = []

    var body: some View {
        let l10n = state.l10n
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l10n.t("System Prompt (\(profileName))", "Системный промпт (\(profileName))"))
                    .font(MurmacFonts.sans(18, weight: .semibold))
                Spacer()
                if !isEditable {
                    MurmacBadge(l10n.t("Read-only (fine-tune)", "Только чтение (файнтюн)"), fg: MurmacColor.warn, bg: MurmacColor.warnSoft)
                }
            }

            if !isEditable {
                Text(l10n.t("Fine-tuned Murmur Cleanup models use the exact system prompt they were trained on.",
                            "Дообученные модели Murmur Cleanup используют фиксированный системный промпт, на котором они обучались."))
                    .font(MurmacFonts.sans(12))
                    .foregroundColor(MurmacColor.ink3)
            }

            TextEditor(text: $draft)
                .font(MurmacFonts.mono(12))
                .disabled(!isEditable)
                .padding(8)
                .background(MurmacColor.surface2, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: draft) { _, val in
                    problems = PromptEditRules.validateSystem(val)
                }

            if !problems.isEmpty {
                Text("Validation issues: \(problems.joined(separator: ", "))")
                    .font(MurmacFonts.mono(12))
                    .foregroundColor(MurmacColor.err)
            }

            HStack {
                if isEditable {
                    Button(l10n.t("Reset to default", "Сбросить по умолчанию")) {
                        state.updateSettings {
                            $0.systemPromptOverride = nil
                            $0.systemPromptOverrideProfile = nil
                        }
                        loadCurrent()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(l10n.t("Cancel", "Отмена")) { dismiss() }
                    .buttonStyle(.bordered)
                if isEditable {
                    Button(l10n.t("Save", "Сохранить")) {
                        state.updateSettings {
                            $0.systemPromptOverride = draft
                            $0.systemPromptOverrideProfile = profileName
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurmacColor.accent)
                    .disabled(!problems.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 480)
        .onAppear { loadCurrent() }
    }

    private func loadCurrent() {
        let model = state.catalog.models.first { $0.id == state.settings.selectedLlmModelId }
        let pName = model?.llm?.promptProfile ?? "default.v1"
        profileName = pName
        if let profile = try? state.promptAssets.profile(name: pName) {
            isEditable = PromptEditRules.editable(profile: profile)
            if PromptEditRules.overrideApplies(profile: profile, overrideBaseProfile: state.settings.systemPromptOverrideProfile),
               let ov = state.settings.systemPromptOverride {
                draft = ov
            } else {
                draft = (try? state.promptAssets.systemPrompt(stem: RenderPy.versioned(profile.system))) ?? ""
            }
        }
    }
}
