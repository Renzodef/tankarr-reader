import SwiftUI

struct DownloadBookControl: View {
    let series: LibrarySeries
    let book: LibraryBook
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @State private var confirmRemove = false
    var body: some View {
        Group {
            if downloads.isQueued(book.id) {
                Button { downloads.pause(book.id) } label: {
                    Image(systemName: "pause.circle")
                }.accessibilityLabel(L10n.text("Pausa download"))
                    .accessibilityIdentifier("pause-download-\(book.id)")
            } else if downloads.item(book.id)?.complete == true {
                Button { confirmRemove = true } label: { Image(systemName: "checkmark.circle.fill") }
                    .accessibilityLabel(L10n.text("Scaricato · Rimuovi dal dispositivo"))
                    .accessibilityIdentifier("remove-download-\(book.id)")
            } else {
                Button {
                    downloads.enqueue(series: series, books: [book], api: model.api, demo: model.isDemo)
                } label: { Image(systemName: "arrow.down.circle") }
                    .accessibilityLabel(L10n.text("Scarica sul dispositivo"))
                    .accessibilityIdentifier("download-\(book.id)")
                    .disabled(!model.canDownload)
            }
        }.buttonStyle(.borderless).font(.title3)
            .confirmationDialog(L10n.text("Rimuovere questa copia dal dispositivo?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(L10n.text("Rimuovi download"), role: .destructive) { Task { await downloads.remove(book.id) } }
            } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
    }
}

struct DownloadsView: View {
    var onShowSeries: (String) -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LibraryBook?
    @State private var confirmRemoveAll = false
    @State private var removeID: String?
    @State private var error: String?
    @State private var pendingSeries: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.format("Spazio usato: %@", ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file)))
                        .accessibilityIdentifier("download-storage")
                    Text(L10n.text("Scarica capitoli o volumi con l’app aperta. Puoi metterli in pausa e riprendere le pagine mancanti. Le copie complete si leggono anche senza rete."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if !downloads.queuedIDs.isEmpty { Text(L10n.format("%d download in coda", downloads.queuedIDs.count)) }
                    if model.offlineMode {
                        Label(L10n.text("Lettura offline"), systemImage: "wifi.slash")
                        Button(L10n.text("Ricollega al server")) { Task { await model.reconnect() } }.disabled(model.busy)
                    } else if downloads.items.contains(where: { $0.complete }) {
                        Button(L10n.text("Usa senza connessione")) { Task { await model.useOffline() } }
                            .accessibilityIdentifier("use-offline")
                    }
                }
                if let message = error ?? downloads.storageError?.localizedDescription {
                    Section { Text(message).foregroundStyle(.orange) }
                }
                if downloads.items.isEmpty {
                    ContentUnavailableView(L10n.text("Nessun download"), systemImage: "arrow.down.circle",
                        description: Text(L10n.text("Apri una serie e tocca la freccia accanto al capitolo o volume.")))
                }
                ForEach(downloads.items) { item in
                    HStack {
                        Button { selected = item.listing } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.series.title).font(.headline).foregroundStyle(.primary)
                                Text(item.listing.label).foregroundStyle(.primary)
                                if item.complete {
                                    Label(L10n.text("Disponibile offline"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                                } else {
                                    ProgressView(value: Double(item.downloadedPages), total: Double(item.book.pageCount))
                                    Text(L10n.format("%d di %d pagine scaricate", item.downloadedPages, item.book.pageCount))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if downloads.activeID != item.id { Text(L10n.text("In pausa · Riprendi per completare")).font(.caption) }
                                }
                                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain).disabled(!item.complete)
                            .accessibilityIdentifier("offline-book-\(item.id)")
                        Spacer()
                        DownloadBookControl(series: item.series, book: item.listing)
                    }.padding(.vertical, 4)
                        .swipeActions {
                            Button(L10n.text("Rimuovi download"), role: .destructive) { removeID = item.id }
                        }
                }
                if !downloads.failures.isEmpty {
                    Section(L10n.text("Download interrotto")) {
                        ForEach(downloads.failures.keys.sorted(), id: \.self) { id in
                            Text(downloads.failures[id]?.localizedDescription ?? "").foregroundStyle(.orange)
                        }
                    }
                }
            }.navigationTitle(L10n.text("Download"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Chiudi")) { dismiss() } }
                    if downloads.hasDownloads {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .destructive) { confirmRemoveAll = true } label: { Image(systemName: "trash") }
                                .accessibilityLabel(L10n.text("Rimuovi tutti i download"))
                                .accessibilityIdentifier("remove-all-downloads")
                        }
                    }
                }
                .task { await downloads.reload() }
                .fullScreenCover(item: $selected, onDismiss: {
                    if let id = pendingSeries { pendingSeries = nil; onShowSeries(id) }
                }) { book in
                    ReaderView(bookID: book.id, onShowSeries: { pendingSeries = $0; selected = nil })
                }
                .confirmationDialog(L10n.text("Rimuovere tutti i download di questo account?"), isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                    Button(L10n.text("Rimuovi tutti i download"), role: .destructive) {
                        Task { do { try await downloads.removeAll() } catch { self.error = error.localizedDescription } }
                    }.accessibilityIdentifier("confirm-remove-all-downloads")
                } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
                .confirmationDialog(L10n.text("Rimuovere questa copia dal dispositivo?"), isPresented: Binding(
                    get: { removeID != nil }, set: { if !$0 { removeID = nil } }), titleVisibility: .visible) {
                        if let id = removeID {
                            Button(L10n.text("Rimuovi download"), role: .destructive) { Task { await downloads.remove(id) }; removeID = nil }
                        }
                    } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
        }
    }
}
