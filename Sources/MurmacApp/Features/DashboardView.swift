import MurmacCore
import SwiftUI

public struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var showTypingSheet = false

    public var body: some View {
        let l10n = state.l10n
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let stats = DashboardStats.compute(entries: state.history, typingSpeedWpm: state.settings.typingSpeedWpm, nowMs: nowMs)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(l10n.t("Dashboard", "Обзор"))
                        .font(MurmacFonts.sans(26, weight: .semibold))
                        .foregroundColor(MurmacColor.ink)
                    Spacer()
                    Button {
                        state.showPracticeSheet = true
                    } label: {
                        Label(l10n.t("Try a dictation", "Попробовать диктовку"), systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MurmacColor.accent)
                }

                // Permissions warning banner
                if !state.permissionSnapshot.allCoreGranted {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundColor(MurmacColor.err)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t("Permissions needed for global dictation", "Нужны права macOS для глобальной диктовки"))
                                .font(MurmacFonts.sans(14, weight: .semibold))
                                .foregroundColor(MurmacColor.ink)
                            Text(l10n.t(
                                "Enable Microphone & Accessibility in System Settings so \(state.settings.hotkey.displayLabel) works in any app.",
                                "Включите Микрофон и Универсальный доступ в Настройках системы, чтобы \(state.settings.hotkey.displayLabel) работал в любом окне."
                            ))
                            .font(MurmacFonts.sans(12))
                            .foregroundColor(MurmacColor.ink2)
                        }
                        Spacer()
                        Button(l10n.t("Settings", "Настройки")) {
                            state.selectedTab = .settings
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(MurmacColor.errSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Hero "Today" card + 7-day chart
                MurmacCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t("TODAY", "СЕГОДНЯ"))
                                    .font(MurmacFonts.sans(11, weight: .semibold))
                                    .foregroundColor(MurmacColor.ink3)
                                    .tracking(0.8)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(stats.todayWords)")
                                        .font(MurmacFonts.sans(44, weight: .semibold))
                                        .foregroundColor(MurmacColor.ink)
                                    Text(l10n.t("words dictated", "слов продиктовано"))
                                        .font(MurmacFonts.sans(15))
                                        .foregroundColor(MurmacColor.ink3)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                MurmacBadge(state.settings.hotkey.displayLabel)
                                Text(state.hotkeyActive
                                     ? l10n.t("Hotkey active", "Хоткей активен")
                                     : l10n.t("Hotkey inactive (check Accessibility)", "Хоткей неактивен (нужен Accessibility)"))
                                    .font(MurmacFonts.sans(11))
                                    .foregroundColor(state.hotkeyActive ? MurmacColor.ok : MurmacColor.warn)
                            }
                        }

                        // 7-day bar chart
                        let maxDay = max(1, stats.dailyWords.map(\.words).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(stats.dailyWords) { item in
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(item.words > 0 ? MurmacColor.accent : MurmacColor.surface3)
                                        .frame(height: max(6, CGFloat(item.words) / CGFloat(maxDay) * 80))
                                    Text(item.label)
                                        .font(MurmacFonts.mono(11))
                                        .foregroundColor(MurmacColor.ink3)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 104, alignment: .bottom)
                    }
                }

                // Metric grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    statCard(
                        title: l10n.t("Time saved", "Сэкономлено"),
                        value: String(format: "%.1f min", stats.timeSavedMinutes),
                        sub: l10n.t("vs \(state.settings.typingSpeedWpm) WPM typing", "против \(state.settings.typingSpeedWpm) сл/мин"),
                        actionTitle: l10n.t("Edit", "Изм.")
                    ) {
                        showTypingSheet = true
                    }
                    statCard(
                        title: l10n.t("Speaking speed", "Скорость речи"),
                        value: stats.averageWpm > 0 ? "\(stats.averageWpm) WPM" : "—",
                        sub: l10n.t("\(String(format: "%.1f", stats.speakingMinutes)) min spoken", "\(String(format: "%.1f", stats.speakingMinutes)) мин речи")
                    )
                    statCard(
                        title: l10n.t("Total dictations", "Всего диктовок"),
                        value: "\(stats.totalDictations)",
                        sub: l10n.t("\(stats.totalWords) words total", "\(stats.totalWords) слов всего")
                    )
                    statCard(
                        title: l10n.t("Fillers removed", "Убрано слов-паразитов"),
                        value: "\(stats.fillersRemoved)",
                        sub: l10n.t("by local cleanup", "локальной очисткой")
                    )
                }

                // Local engine hardware status
                MurmacCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t("LOCAL ENGINE BACKENDS", "ЛОКАЛЬНЫЕ ДВИЖКИ MACOS"))
                            .font(MurmacFonts.sans(11, weight: .semibold))
                            .foregroundColor(MurmacColor.ink3)
                            .tracking(0.8)
                        HStack(spacing: 12) {
                            backendPill(
                                title: "LLM (llama.cpp)",
                                detail: state.llmProbe?.availableUnits.contains(.gpu) == true
                                    ? "Metal GPU"
                                    : (state.llmProbe?.availableUnits.contains(.cpu) == true ? "CPU" : l10n.t("Not built", "Не собран")),
                                ok: !(state.llmProbe?.availableUnits.isEmpty ?? true)
                            )
                            backendPill(
                                title: "ASR (sherpa-onnx)",
                                detail: state.asrProbe?.facts["sherpa.version"].map { "v\($0) · Apple Silicon" } ?? l10n.t("Not built", "Не собран"),
                                ok: !(state.asrProbe?.availableUnits.isEmpty ?? true)
                            )
                            backendPill(
                                title: "OCR (Apple Vision)",
                                detail: state.permissionSnapshot.screenRecording ? "Neural Engine (ANE)" : l10n.t("Needs Screen Recording", "Нужен Screen Recording"),
                                ok: state.permissionSnapshot.screenRecording
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(MurmacColor.bg)
        .sheet(isPresented: $showTypingSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(l10n.t("Your typing speed", "Ваша скорость печати"))
                    .font(MurmacFonts.sans(18, weight: .semibold))
                Text(l10n.t("Used only to estimate how much time dictation saves you.", "Используется только для оценки сэкономленного времени."))
                    .font(MurmacFonts.sans(13))
                    .foregroundColor(MurmacColor.ink3)
                Stepper(
                    "\(state.settings.typingSpeedWpm) WPM",
                    value: Binding(
                        get: { state.settings.typingSpeedWpm },
                        set: { val in state.updateSettings { $0.typingSpeedWpm = max(15, min(150, val)) } }
                    ),
                    in: 15...150,
                    step: 5
                )
                HStack {
                    Spacer()
                    Button(l10n.t("Done", "Готово")) { showTypingSheet = false }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
                }
            }
            .padding(24)
            .frame(width: 340)
        }
    }

    private func statCard(title: String, value: String, sub: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        MurmacCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(MurmacFonts.sans(12, weight: .medium))
                        .foregroundColor(MurmacColor.ink3)
                    Spacer()
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderless)
                            .font(MurmacFonts.sans(12, weight: .medium))
                            .foregroundColor(MurmacColor.accentInk)
                    }
                }
                Text(value)
                    .font(MurmacFonts.sans(26, weight: .semibold))
                    .foregroundColor(MurmacColor.ink)
                Text(sub)
                    .font(MurmacFonts.sans(12))
                    .foregroundColor(MurmacColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func backendPill(title: String, detail: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(ok ? MurmacColor.ok : MurmacColor.warn).frame(width: 8, height: 8)
                Text(title).font(MurmacFonts.sans(13, weight: .semibold)).foregroundColor(MurmacColor.ink)
            }
            Text(detail).font(MurmacFonts.mono(11)).foregroundColor(MurmacColor.ink3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MurmacColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
