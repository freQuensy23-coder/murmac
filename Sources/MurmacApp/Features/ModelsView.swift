import MurmacCore
import SwiftUI
import UniformTypeIdentifiers

private enum ModelsSegment: String, CaseIterable {
    case speech
    case cleanup
}

public struct ModelsView: View {
    @ObservedObject var state: AppState
    @State private var segment: ModelsSegment = .speech
    @State private var selectedModelId: String?
    @State private var showFileImporter = false
    @State private var importError: String?

    public var body: some View {
        let l10n = state.l10n
        let filteredModels = state.catalog.models.filter { m in
            segment == .speech ? (m.kind == .asr || m.kind == .vad) : (m.kind == .llm)
        }

        HStack(spacing: 0) {
            // Left catalog list
            VStack(spacing: 0) {
                HStack {
                    Text(l10n.t("Models", "Модели"))
                        .font(MurmacFonts.sans(22, weight: .semibold))
                        .foregroundColor(MurmacColor.ink)
                    Spacer()
                    if segment == .cleanup {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label(l10n.t("Add GGUF", "Добавить GGUF"), systemImage: "plus")
                                .font(MurmacFonts.sans(12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Picker("", selection: $segment) {
                    Text(l10n.t("Speech (ASR)", "Речь (ASR)")).tag(ModelsSegment.speech)
                    Text(l10n.t("Cleanup (LLM)", "Очистка (LLM)")).tag(ModelsSegment.cleanup)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                Divider().background(MurmacColor.line)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if segment == .cleanup {
                            // "None / Speech only" row
                            let isNone = !state.settings.cleanupEnabled || state.settings.selectedLlmModelId == nil
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l10n.t("None (Speech only)", "Нет (только распознавание)"))
                                        .font(MurmacFonts.sans(14, weight: .semibold))
                                        .foregroundColor(MurmacColor.ink)
                                    Text(l10n.t("Insert raw ASR transcript without LLM cleanup", "Вставлять сырой текст ASR без обработки LLM"))
                                        .font(MurmacFonts.sans(12))
                                        .foregroundColor(MurmacColor.ink3)
                                }
                                Spacer()
                                if isNone {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(MurmacColor.accent)
                                }
                            }
                            .padding(12)
                            .background(isNone ? MurmacColor.accentSoft : MurmacColor.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MurmacColor.line, lineWidth: 1))
                            .onTapGesture {
                                state.updateSettings {
                                    $0.cleanupEnabled = false
                                    $0.selectedLlmModelId = nil
                                }
                            }

                            // Custom imported GGUFs
                            ForEach(state.customModels) { cm in
                                let active = state.settings.cleanupEnabled && state.settings.selectedLlmModelId == cm.id
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cm.displayName).font(MurmacFonts.sans(14, weight: .semibold)).foregroundColor(MurmacColor.ink)
                                        Text("GGUF · \(cm.template) · \(formatBytes(cm.sizeBytes))")
                                            .font(MurmacFonts.mono(11)).foregroundColor(MurmacColor.ink3)
                                    }
                                    Spacer()
                                    if active {
                                        MurmacBadge(l10n.t("In use", "Активна"), fg: MurmacColor.ok, bg: MurmacColor.okSoft)
                                    }
                                    Button(role: .destructive) {
                                        state.deleteCustomModel(id: cm.id)
                                    } label: {
                                        Image(systemName: "trash").foregroundColor(MurmacColor.err)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(12)
                                .background(active ? MurmacColor.accentSoft : MurmacColor.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MurmacColor.line, lineWidth: 1))
                                .onTapGesture {
                                    state.updateSettings {
                                        $0.selectedLlmModelId = cm.id
                                        $0.cleanupEnabled = true
                                    }
                                }
                            }
                        }

                        ForEach(filteredModels) { model in
                            let art = model.preferredArtifact
                            let inst = art.flatMap { state.installStates[$0.id] } ?? .notInstalled
                            let isActive = (model.kind == .asr && state.settings.selectedAsrModelId == model.id) ||
                                (model.kind == .llm && state.settings.cleanupEnabled && state.settings.selectedLlmModelId == model.id)
                            let isSelected = selectedModelId == model.id

                            ModelListRow(
                                model: model,
                                artifact: art,
                                installState: inst,
                                isActive: isActive,
                                isSelected: isSelected,
                                l10n: l10n
                            )
                            .onTapGesture { selectedModelId = model.id }
                        }
                    }
                    .padding(12)
                }
            }
            .frame(width: 340)
            .background(MurmacColor.bg)

            Divider().background(MurmacColor.line)

            // Right detail pane
            if let model = filteredModels.first(where: { $0.id == selectedModelId }) ?? filteredModels.first {
                ModelDetailPane(model: model, state: state)
            } else {
                Spacer()
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            switch result {
            case .success(let url):
                do {
                    try state.importCustomGguf(url: url)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let err):
                importError = err.localizedDescription
            }
        }
        .alert("GGUF Import Error", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }
}

private struct ModelListRow: View {
    let model: CatalogModel
    let artifact: CatalogArtifact?
    let installState: InstallState
    let isActive: Bool
    let isSelected: Bool
    let l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.displayName)
                    .font(MurmacFonts.sans(14, weight: .semibold))
                    .foregroundColor(MurmacColor.ink)
                Spacer()
                if isActive {
                    MurmacBadge(l10n.t("Active", "Активна"), fg: MurmacColor.ok, bg: MurmacColor.okSoft)
                } else if model.tier == "recommended" {
                    MurmacBadge(l10n.t("Recommended", "Рекомендуем"))
                } else if model.kind == .vad {
                    MurmacBadge("VAD", fg: MurmacColor.ink2, bg: MurmacColor.surface2)
                }
            }
            HStack(spacing: 8) {
                if let art = artifact {
                    Text(formatBytes(art.totalBytes))
                        .font(MurmacFonts.mono(11))
                        .foregroundColor(MurmacColor.ink3)
                }
                if let q = artifact?.quant {
                    Text("· \(q)").font(MurmacFonts.mono(11)).foregroundColor(MurmacColor.ink3)
                }
                Spacer()
                statusLabel
            }
            if case .downloading(let prog, _, _) = installState {
                ProgressView(value: prog)
                    .tint(MurmacColor.accent)
            }
        }
        .padding(12)
        .background(isSelected ? MurmacColor.accentSoft : MurmacColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? MurmacColor.accent.opacity(0.45) : MurmacColor.line, lineWidth: 1))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch installState {
        case .installed:
            Label(l10n.t("Installed", "Установлена"), systemImage: "checkmark.circle.fill")
                .font(MurmacFonts.sans(11, weight: .medium))
                .foregroundColor(MurmacColor.ok)
        case .downloading(let p, _, _):
            Text("\(Int(p * 100))%")
                .font(MurmacFonts.mono(11, weight: .medium))
                .foregroundColor(MurmacColor.accentInk)
        case .verifying:
            Text(l10n.t("Verifying…", "Проверка…"))
                .font(MurmacFonts.mono(11))
                .foregroundColor(MurmacColor.warn)
        case .failed:
            Text(l10n.t("Failed", "Ошибка"))
                .font(MurmacFonts.sans(11, weight: .medium))
                .foregroundColor(MurmacColor.err)
        case .notInstalled:
            Text(l10n.t("Download", "Скачать"))
                .font(MurmacFonts.sans(11))
                .foregroundColor(MurmacColor.ink3)
        }
    }
}

private struct ModelDetailPane: View {
    let model: CatalogModel
    @ObservedObject var state: AppState

    var body: some View {
        let l10n = state.l10n
        let art = model.preferredArtifact
        let inst = art.flatMap { state.installStates[$0.id] } ?? .notInstalled
        let isActive = (model.kind == .asr && state.settings.selectedAsrModelId == model.id) ||
            (model.kind == .llm && state.settings.cleanupEnabled && state.settings.selectedLlmModelId == model.id)
        let bench = art.flatMap { a in state.benchmarks.first { $0.artifactId == a.id } }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.displayName)
                            .font(MurmacFonts.sans(24, weight: .semibold))
                            .foregroundColor(MurmacColor.ink)
                        Spacer()
                        if let pub = model.publisher {
                            MurmacBadge(pub, fg: MurmacColor.ink2, bg: MurmacColor.surface2)
                        }
                    }
                    if let desc = model.description {
                        Text(desc)
                            .font(MurmacFonts.sans(14))
                            .foregroundColor(MurmacColor.ink2)
                    }
                }

                // Action bar
                if let art {
                    HStack(spacing: 12) {
                        switch inst {
                        case .notInstalled, .failed:
                            Button {
                                state.download(artifact: art)
                            } label: {
                                Label(l10n.t("Download (\(formatBytes(art.totalBytes)))", "Скачать (\(formatBytes(art.totalBytes)))"),
                                      systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(MurmacColor.accent)
                        case .downloading(let p, let got, let total):
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: p).tint(MurmacColor.accent)
                                Text("\(formatBytes(got)) / \(formatBytes(total)) (\(Int(p * 100))%)")
                                    .font(MurmacFonts.mono(11)).foregroundColor(MurmacColor.ink3)
                            }
                            Button(l10n.t("Cancel", "Отмена")) { state.cancelDownload(artifactId: art.id) }
                                .buttonStyle(.bordered)
                        case .verifying:
                            ProgressView().controlSize(.small)
                            Text(l10n.t("Verifying SHA-256…", "Проверка SHA-256…")).font(MurmacFonts.sans(13))
                        case .installed:
                            if model.kind != .vad && model.isSelectable {
                                Button {
                                    state.updateSettings { s in
                                        if model.kind == .asr { s.selectedAsrModelId = model.id }
                                        if model.kind == .llm { s.selectedLlmModelId = model.id; s.cleanupEnabled = true }
                                    }
                                } label: {
                                    Label(isActive ? l10n.t("Selected", "Выбрана") : l10n.t("Use this model", "Выбрать модель"),
                                          systemImage: isActive ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(isActive ? MurmacColor.ok : MurmacColor.accent)
                                .disabled(isActive)
                            }
                            if model.kind == .llm || model.kind == .asr {
                                Button {
                                    state.runBenchmark(model: model, artifact: art)
                                } label: {
                                    if state.runningBenchmarkId == art.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label(l10n.t("Benchmark", "Тест скорости"), systemImage: "gauge.medium")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(state.runningBenchmarkId != nil)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                state.deleteArtifact(art)
                            } label: {
                                Label(l10n.t("Delete", "Удалить"), systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if case .failed(let msg) = inst {
                        Text(msg)
                            .font(MurmacFonts.mono(12))
                            .foregroundColor(MurmacColor.err)
                    }
                }

                // Specs card
                MurmacCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.t("SPECIFICATIONS", "ХАРАКТЕРИСТИКИ"))
                            .font(MurmacFonts.sans(11, weight: .semibold))
                            .foregroundColor(MurmacColor.ink3)
                            .tracking(0.8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 10) {
                            if let p = model.paramsLabel { spec("Parameters", p) }
                            if let art {
                                spec("Runtime", art.runtime)
                                spec("Backend", art.units.map(\.displayName).joined(separator: " / "))
                                spec("Size", formatBytes(art.totalBytes))
                            }
                            if let lic = model.license?.id { spec("License", lic) }
                            if let llm = model.llm {
                                spec("Context", "\(llm.nCtx) tokens")
                                spec("Prompt profile", llm.promptProfile)
                            }
                        }
                    }
                }

                // Benchmark result card
                if let bench {
                    MurmacCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(l10n.t("MEASURED ON THIS MAC", "ИЗМЕРЕНО НА ЭТОМ MAC"))
                                .font(MurmacFonts.sans(11, weight: .semibold))
                                .foregroundColor(MurmacColor.ink3)
                                .tracking(0.8)
                            HStack(spacing: 24) {
                                spec("Device", bench.deviceName)
                                spec("Load time", "\(bench.loadMs) ms")
                                if let pp = bench.prefillTps { spec("Prefill", String(format: "%.1f tok/s", pp)) }
                                if let tg = bench.decodeTps { spec("Decode", String(format: "%.1f tok/s", tg)) }
                                if let rtf = bench.asrRtf { spec("RTF", String(format: "%.2fx", rtf)) }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(MurmacColor.surface)
    }

    private func spec(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(MurmacFonts.sans(11)).foregroundColor(MurmacColor.ink3)
            Text(v).font(MurmacFonts.mono(12, weight: .medium)).foregroundColor(MurmacColor.ink)
        }
    }
}
