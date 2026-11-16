import SwiftUI

struct ReaderStorageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @State private var sizes: [ReaderStorageSection: Int64] = [:]
    @State private var pendingRemoval: ReaderStorageSection?
    @State private var confirmRemoval = false
    @State private var refreshID: UUID?
    @State private var showDownloads = false

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.text("Totale sul dispositivo"),
                               value: size(sizes.values.reduce(downloads.totalBytes, +)))
            }

            ForEach(ReaderStorageSection.allCases, id: \.self) { section in
                Section {
                    LabeledContent(title(section), value: size(sizes[section, default: 0]))
                    Button(L10n.format("Elimina %@", title(section).lowercased()), role: .destructive) {
                        pendingRemoval = section
                        confirmRemoval = true
                    }.disabled(sizes[section, default: 0] == 0 || model.storageRefreshProgress != nil || model.busy)
                }
            }

            Section {
                LabeledContent(L10n.text("Volumi scaricati"), value: size(downloads.totalBytes))
                Button(L10n.text("Gestisci download")) { showDownloads = true }
            }

            Section {
                Button {
                    refreshID = UUID()
                } label: {
                    Label(L10n.text("Aggiorna catalogo e tutte le copertine"), systemImage: "arrow.clockwise")
                }
                .disabled(model.api == nil || model.offlineMode || model.busy || model.refreshing || model.storageRefreshProgress != nil || refreshID != nil)
                if let progress = model.storageRefreshProgress {
                    ProgressView(value: Double(progress), total: Double(max(1, model.library.count)))
                    Text(L10n.format("%d di %d copertine controllate", progress, model.library.count))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.text("Interrompi")) { refreshID = nil }
                }
                if let notice = model.storageNotice { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L10n.text("Spazio sul dispositivo"))
        .sheet(isPresented: $showDownloads) { DownloadsView(onShowSeries: { _ in }) }
        .task(id: model.localStorageRevision) {
            if let account = downloads.account { sizes = await model.localStorage.sizes(account: account) }
            else { sizes = [:] }
        }
        .task(id: refreshID) {
            guard refreshID != nil else { return }
            await model.refreshSaved()
            if !Task.isCancelled { refreshID = nil }
        }
        .confirmationDialog(L10n.text("Liberare spazio sul dispositivo?"), isPresented: $confirmRemoval,
                            titleVisibility: .visible) {
            if let pendingRemoval {
                Button(L10n.format("Elimina %@", title(pendingRemoval).lowercased()), role: .destructive) {
                    Task { await model.clearSaved(pendingRemoval) }
                }
            }
            Button(L10n.text("Annulla"), role: .cancel) {}
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func title(_ section: ReaderStorageSection) -> String {
        switch section {
        case .catalogue: L10n.text("Dati della libreria")
        case .covers: L10n.text("Copertine")
        }
    }
}
