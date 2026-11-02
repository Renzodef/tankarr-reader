import SwiftUI

struct DownloadBookControl: View {
    let series: LibrarySeries
    let book: LibraryBook
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @State private var confirmRemove = false
    private var resumable: Bool { downloads.item(book.id) != nil || downloads.queuePosition(book.id) != nil }
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
                } label: { Image(systemName: resumable ? "arrow.clockwise.circle" : "arrow.down.circle") }
                    .accessibilityLabel(L10n.text(resumable ? "Riprendi download" : "Scarica sul dispositivo"))
                    .accessibilityIdentifier("download-\(book.id)")
                    .disabled(!model.canDownload)
            }
        }.buttonStyle(.borderless).font(.title3)
            .confirmationDialog(L10n.text("Rimuovere questa copia dal dispositivo?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(L10n.text("Rimuovi download"), role: .destructive) { Task { await downloads.remove(book.id) } }
            } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
    }
}

/// Shared by the series and the global download list; never starts a second
/// transfer or caches progress separately from DownloadManager.
struct DownloadBookProgress: View {
    let bookID: String
    @EnvironmentObject private var downloads: DownloadManager
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let item = downloads.item(bookID) {
                if item.complete {
                    Label(L10n.text("Disponibile offline"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("download-state-\(bookID)")
                } else {
                    ProgressView(value: Double(item.downloadedPages), total: Double(item.book.pageCount))
                        .accessibilityIdentifier("download-progress-\(bookID)")
                        .accessibilityLabel(L10n.text("Avanzamento download"))
                        .accessibilityValue(String(item.downloadedPages))
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.format("%d di %d pagine scaricate", item.downloadedPages, item.book.pageCount))
                            .accessibilityIdentifier("download-pages-\(bookID)")
                        Spacer(minLength: 8)
                        Text(Double(item.downloadedPages) / Double(max(1, item.book.pageCount)), format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }.foregroundStyle(.secondary)
                    state
                }
                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    .foregroundStyle(.secondary)
            } else if downloads.queuePosition(bookID) != nil {
                state
            }
            if let failure = downloads.failures[bookID] {
                Text(failure.localizedDescription).foregroundStyle(.orange)
                    .accessibilityIdentifier("download-error-\(bookID)")
            }
        }.font(.caption)
    }
    @ViewBuilder private var state: some View {
        if !downloads.isQueued(bookID) {
            Text(L10n.text("In pausa · Riprendi per completare"))
                .accessibilityIdentifier("download-state-\(bookID)")
        } else if let position = downloads.queuePosition(bookID) {
            Label(L10n.format("In coda · posizione %d", position), systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("download-state-\(bookID)")
        }
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
    @State private var retrying = false
    @AppStorage("reader.downloads.sort.v1") private var sorting: ReaderListSort = .recent
    private var groups: [DownloadSeriesGroup] {
        ReaderListOrdering.downloadGroups(downloads.items, sort: sorting)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L10n.text("Ordina per"), selection: $sorting) {
                        ForEach(ReaderListSort.allCases) { option in Text(option.title).tag(option) }
                    }.accessibilityIdentifier("downloads-sort")
                    Text(L10n.format("Spazio usato: %@", ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file)))
                        .accessibilityIdentifier("download-storage")
                    Text(L10n.text("I download continuano quando cambi app o blocchi lo schermo. La coda viene salvata: dopo una chiusura forzata riprende alla riapertura dalle pagine mancanti. iOS decide i tempi in background."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if !downloads.queuedIDs.isEmpty { Text(L10n.format("%d download in coda", downloads.queuedIDs.count)) }
                    if downloads.canResumeBackgroundQueue && model.canDownload {
                        Button(L10n.text("Riprova i download")) {
                            retrying = true
                            Task {
                                defer { retrying = false }
                                // Choose a working LAN/HTTPS route again, rather
                                // than retrying an unreachable cached endpoint.
                                await model.reconnect()
                            }
                        }.disabled(retrying || model.busy)
                            .accessibilityIdentifier("resume-download-queue")
                    }
                    if retrying { ProgressView(L10n.text("Ricollegamento…")) }
                    if model.offlineMode {
                        Label(L10n.text("Lettura offline"), systemImage: "wifi.slash")
                        Button(L10n.text("Ricollega al server")) { Task { await model.reconnect() } }.disabled(model.busy)
                    } else if downloads.items.contains(where: { $0.complete }) {
                        Button(L10n.text("Attiva modalità offline")) { Task { await model.useOffline() } }
                            .accessibilityIdentifier("use-offline")
                        Text(L10n.text("Mostra solo i libri scaricati e mette in pausa i download finché non torni online."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let message = error ?? downloads.storageError?.localizedDescription ?? model.error {
                    Section { Text(message).foregroundStyle(.orange) }
                }
                if downloads.items.isEmpty {
                    ContentUnavailableView(L10n.text("Nessun download"), systemImage: "arrow.down.circle",
                        description: Text(L10n.text("Apri una serie e tocca la freccia accanto al capitolo o volume.")))
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                        HStack {
                            Button { selected = item.listing } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.listing.label).font(.headline).foregroundStyle(.primary)
                                    DownloadBookProgress(bookID: item.id)
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
                        } header: { Text(group.series.title).textCase(nil) }
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
