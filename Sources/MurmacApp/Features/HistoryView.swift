import AppKit
import MurmacCore
import MurmacPlatform
import SwiftUI

public struct HistoryView: View {
    @ObservedObject var state: AppState
    @State private var searchText = ""
    @State private var selectedEntryId: Int64?
    @State private var multiSelectMode = false
    @State private var selectedForDelete: Set<Int64> = []

    public var body: some View {
        let l10n = state.l10n
        HStack(spacing: 0) {
            // Left list pane (320 pt, matching Murmur inner display)
            VStack(spacing: 0) {
                HStack {
                    Text(l10n.t("History", "История"))
                        .font(MurmacFonts.sans(22, weight: .semibold))
                        .foregroundColor(MurmacColor.ink)
                    Spacer()
                    if !state.history.isEmpty {
                        Button(multiSelectMode ? l10n.t("Done", "Готово") : l10n.t("Select", "Выбрать")) {
                            multiSelectMode.toggle()
                            if !multiSelectMode { selectedForDelete.removeAll() }
                        }
                        .buttonStyle(.borderless)
                        .font(MurmacFonts.sans(13, weight: .medium))
                        .foregroundColor(MurmacColor.accentInk)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(MurmacColor.ink3)
                    TextField(l10n.t("Search dictations…", "Поиск по диктовкам…"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(MurmacFonts.sans(14))
                        .onChange(of: searchText) { _, val in
                            state.reloadHistory(search: val)
                        }
                    if !searchText.isEmpty {
                        Button(action: { searchText = ""; state.reloadHistory(search: "") }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(MurmacColor.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MurmacColor.surface2, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if multiSelectMode && !selectedForDelete.isEmpty {
                    HStack {
                        Text(l10n.t("\(selectedForDelete.count) selected", "Выбрано: \(selectedForDelete.count)"))
                            .font(MurmacFonts.sans(13, weight: .medium))
                            .foregroundColor(MurmacColor.ink2)
                        Spacer()
                        Button(role: .destructive) {
                            let ids = Array(selectedForDelete)
                            if let sel = selectedEntryId, selectedForDelete.contains(sel) {
                                selectedEntryId = nil
                            }
                            state.deleteHistory(ids: ids)
                            selectedForDelete.removeAll()
                            multiSelectMode = false
                        } label: {
                            Label(l10n.t("Delete", "Удалить"), systemImage: "trash")
                                .font(MurmacFonts.sans(13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.err)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Divider().background(MurmacColor.line)

                if state.history.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "waveform")
                            .font(.system(size: 32))
                            .foregroundColor(MurmacColor.ink4)
                        Text(l10n.t("No dictations yet", "Диктовок пока нет"))
                            .font(MurmacFonts.sans(17, weight: .semibold))
                            .foregroundColor(MurmacColor.ink)
                        Text(l10n.t(
                            "Press \(state.settings.hotkey.displayLabel) anywhere to start dictating.",
                            "Нажмите \(state.settings.hotkey.displayLabel) в любом окне, чтобы начать диктовку."
                        ))
                        .font(MurmacFonts.sans(13))
                        .foregroundColor(MurmacColor.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        Button(l10n.t("Try a dictation", "Попробовать диктовку")) {
                            state.showPracticeSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
                        .padding(.top, 4)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(state.history) { entry in
                                HistoryListRow(
                                    entry: entry,
                                    isSelected: multiSelectMode ? selectedForDelete.contains(entry.id) : selectedEntryId == entry.id,
                                    multiSelectMode: multiSelectMode,
                                    l10n: l10n
                                )
                                .onTapGesture {
                                    if multiSelectMode {
                                        if selectedForDelete.contains(entry.id) {
                                            selectedForDelete.remove(entry.id)
                                        } else {
                                            selectedForDelete.insert(entry.id)
                                        }
                                    } else {
                                        selectedEntryId = entry.id
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(width: 320)
            .background(MurmacColor.bg)

            Divider().background(MurmacColor.line)

            // Right detail pane
            if let entry = state.history.first(where: { $0.id == selectedEntryId }) ?? state.history.first {
                HistoryDetailPane(entry: entry, state: state)
                    .id(entry.id)
            } else {
                VStack(spacing: 8) {
                    Text(l10n.t("Select a dictation", "Выберите запись"))
                        .font(MurmacFonts.sans(15, weight: .medium))
                        .foregroundColor(MurmacColor.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MurmacColor.surface)
            }
        }
    }
}

private struct HistoryListRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let multiSelectMode: Bool
    let l10n: L10n

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if multiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? MurmacColor.accent : MurmacColor.ink3)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.appName)
                        .font(MurmacFonts.sans(12, weight: .medium))
                        .foregroundColor(MurmacColor.ink3)
                    Spacer()
                    Text(relativeTime(entry.createdAtMs))
                        .font(MurmacFonts.mono(11))
                        .foregroundColor(MurmacColor.ink3)
                }
                if entry.status == .failed {
                    Text(l10n.t("Failed: \(entry.errorCode ?? "error")", "Ошибка: \(entry.errorCode ?? "error")"))
                        .font(MurmacFonts.sans(14, weight: .medium))
                        .foregroundColor(MurmacColor.err)
                } else {
                    Text(entry.finalText)
                        .font(MurmacFonts.sans(14))
                        .foregroundColor(MurmacColor.ink)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    if entry.cleaned {
                        MurmacBadge(l10n.t("Cleaned", "Очищено"), fg: MurmacColor.ok, bg: MurmacColor.okSoft)
                    } else if entry.status != .failed {
                        MurmacBadge(l10n.t("Raw", "Без LLM"), fg: MurmacColor.ink2, bg: MurmacColor.surface2)
                    }
                    if entry.totalLatencyMs > 0 {
                        Text("\(entry.totalLatencyMs) ms")
                            .font(MurmacFonts.mono(11))
                            .foregroundColor(MurmacColor.ink3)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MurmacColor.accentSoft : MurmacColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? MurmacColor.accent.opacity(0.4) : MurmacColor.line, lineWidth: 1))
    }

    private func relativeTime(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(d) ? .none : .short
        return f.string(from: d)
    }
}

private enum DetailTab: String, CaseIterable {
    case finalText
    case original
    case changes
}

private struct HistoryDetailPane: View {
    let entry: HistoryEntry
    @ObservedObject var state: AppState
    @StateObject private var player = MacAudioPlayer()
    @State private var tab: DetailTab = .finalText
    @State private var copiedToast = false

    var body: some View {
        let l10n = state.l10n
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    if let img = MacAppInfo.icon(for: entry.appBundleId) {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.appName)
                            .font(MurmacFonts.sans(16, weight: .semibold))
                            .foregroundColor(MurmacColor.ink)
                        Text([entry.windowTitle, formatDate(entry.createdAtMs)].compactMap { $0 }.joined(separator: " · "))
                            .font(MurmacFonts.sans(12))
                            .foregroundColor(MurmacColor.ink3)
                    }
                    Spacer()
                    if entry.audioPath != nil {
                        Button {
                            state.retry(entry: entry)
                        } label: {
                            Label(l10n.t("Retry", "Повторить"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    if !entry.finalText.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.finalText, forType: .string)
                            copiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedToast = false }
                        } label: {
                            Label(copiedToast ? l10n.t("Copied", "Скопировано") : l10n.t("Copy", "Копировать"),
                                  systemImage: copiedToast ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MurmacColor.accent)
                    }
                    Button(role: .destructive) {
                        state.deleteHistory(ids: [entry.id])
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                // Segmented switcher: Final / Original / Changes
                if entry.status != .failed {
                    Picker("", selection: $tab) {
                        Text(l10n.t("Final", "Итог")).tag(DetailTab.finalText)
                        Text(l10n.t("Original", "Оригинал")).tag(DetailTab.original)
                        Text(l10n.t("Changes", "Изменения")).tag(DetailTab.changes)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    MurmacCard {
                        Group {
                            switch tab {
                            case .finalText:
                                Text(entry.finalText)
                                    .font(MurmacFonts.sans(17))
                                    .foregroundColor(MurmacColor.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            case .original:
                                Text(entry.rawText.isEmpty ? "—" : entry.rawText)
                                    .font(MurmacFonts.sans(17))
                                    .foregroundColor(MurmacColor.ink2)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            case .changes:
                                WordDiffView(raw: entry.rawText, final: entry.finalText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    MurmacCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(MurmacColor.err)
                            Text(l10n.t("Dictation failed (\(entry.errorCode ?? "unknown")). You can replay or retry the saved recording below.",
                                        "Диктовка не удалась (\(entry.errorCode ?? "unknown")). Вы можете прослушать запись или повторить обработку."))
                                .font(MurmacFonts.sans(14))
                                .foregroundColor(MurmacColor.ink)
                        }
                    }
                }

                // Audio Player
                if let path = entry.audioPath, FileManager.default.fileExists(atPath: path) {
                    HStack(spacing: 12) {
                        Button(action: { player.togglePlayPause() }) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MurmacColor.onAccent)
                                .frame(width: 34, height: 34)
                                .background(MurmacColor.accent, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ), in: 0...max(0.1, player.duration))
                        .tint(MurmacColor.accent)

                        Text("\(formatSec(player.currentTime)) / \(formatSec(player.duration))")
                            .font(MurmacFonts.mono(12))
                            .foregroundColor(MurmacColor.ink3)
                    }
                    .padding(14)
                    .background(MurmacColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onAppear { player.load(path: path) }
                    .onDisappear { player.stop() }
                }

                // Pipeline metrics
                MurmacCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.t("PIPELINE DETAILS", "ДЕТАЛИ ПАЙПЛАЙНА"))
                            .font(MurmacFonts.sans(11, weight: .semibold))
                            .foregroundColor(MurmacColor.ink3)
                            .tracking(0.8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 10) {
                            metricCell(l10n.t("Speech model", "Модель речи"), entry.asrModelId)
                            metricCell(l10n.t("Cleanup model", "Модель очистки"), entry.llmModelId ?? l10n.t("None", "Нет"))
                            metricCell(l10n.t("Cleanup outcome", "Статус очистки"), entry.cleanupOutcome)
                            metricCell(l10n.t("ASR / OCR / LLM", "ASR / OCR / LLM"), "\(entry.asrMs) / \(entry.ocrMs) / \(entry.llmMs) ms")
                            metricCell(l10n.t("Total latency", "Общая задержка"), "\(entry.totalLatencyMs) ms")
                            metricCell(l10n.t("Words / Fillers cut", "Слова / Паразиты"), "\(entry.wordsCount) / \(entry.fillersRemoved)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(MurmacColor.surface)
    }

    private func metricCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MurmacFonts.sans(11))
                .foregroundColor(MurmacColor.ink3)
            Text(value)
                .font(MurmacFonts.mono(12, weight: .medium))
                .foregroundColor(MurmacColor.ink)
                .lineLimit(1)
        }
    }

    private func formatDate(_ ms: Int64) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }

    private func formatSec(_ s: TimeInterval) -> String {
        let total = max(0, Int(s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct WordDiffView: View {
    let raw: String
    let final: String

    var body: some View {
        let rawWords = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let finalWords = final.split(whereSeparator: \.isWhitespace).map(String.init)
        let diff = finalWords.difference(from: rawWords)

        var removedIdx: Set<Int> = []
        var insertedIdx: Set<Int> = []
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedIdx.insert(offset)
            case .insert(let offset, _, _): insertedIdx.insert(offset)
            }
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text(buildAttributed(words: rawWords, highlighted: removedIdx, color: MurmacColor.err, strikethrough: true))
                .font(MurmacFonts.sans(15))
            Divider()
            Text(buildAttributed(words: finalWords, highlighted: insertedIdx, color: MurmacColor.ok, strikethrough: false))
                .font(MurmacFonts.sans(16))
        }
    }

    private func buildAttributed(words: [String], highlighted: Set<Int>, color: Color, strikethrough: Bool) -> AttributedString {
        var result = AttributedString()
        for (i, w) in words.enumerated() {
            var part = AttributedString((i > 0 ? " " : "") + w)
            if highlighted.contains(i) {
                part.foregroundColor = color
                if strikethrough { part.strikethroughStyle = .single }
            } else {
                part.foregroundColor = MurmacColor.ink
            }
            result.append(part)
        }
        return result
    }
}
