import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @State private var search = ""
    @State private var showBookmarks = false
    @State private var showDownloads = false
    @State private var path: [LibrarySeries] = []
    @State private var pendingSeries: String?
    @State private var showFollowed = false
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16, alignment: .top)]
    private var filtered: [LibrarySeries] {
        if showFollowed && model.offlineMode { return [] }
        let rows = showFollowed ? model.visibleLibrary.filter { model.followedSeries.contains($0.id) } : model.visibleLibrary
        return search.isEmpty ? rows : rows.filter { $0.title.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let error = model.error {
                    ContentUnavailableView(L10n.text("Connessione non riuscita"), systemImage: "wifi.exclamationmark", description: Text(error))
                    Button(L10n.text("Riprova")) { Task { await model.reconnect() } }.buttonStyle(.bordered)
                }
                if model.busy && model.library.isEmpty { ProgressView(L10n.text("Apro la libreria…")).padding(48) }
                else if !model.canBrowse {
                    ContentUnavailableView(L10n.text("La tua libreria, con te"), systemImage: "books.vertical", description: Text(L10n.text("Collega il lettore al tuo server Tankarr.")))
                    Button(L10n.text("Configura connessione")) { model.showConnection = true }.buttonStyle(.borderedProminent)
                    Button(L10n.text("Esplora la demo")) { Task { await model.startDemo() } }.padding(.top, 8)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(filtered) { series in
                            NavigationLink(value: series) {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverView(series: series)
                                    Text(series.title).font(.headline).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
                                    Text(L10n.format(model.offlineMode ? "%d file scaricati" : "%d file disponibili",
                                        model.offlineMode ? downloads.items.filter { $0.complete && $0.series.id == series.id }.count : series.booksCount))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                    if filtered.isEmpty {
                        if showFollowed && model.offlineMode {
                            ContentUnavailableView(L10n.text("Serie seguite non disponibili offline"), systemImage: "bell.slash",
                                description: Text(L10n.text("Torna online per vedere le serie seguite e gestire le notifiche.")))
                        } else if showFollowed && search.isEmpty {
                            ContentUnavailableView(L10n.text("Nessuna serie seguita"), systemImage: "bell",
                                description: Text(L10n.text("Apri una serie e tocca Segui per ricevere gli avvisi dei nuovi capitoli.")))
                        } else if model.offlineMode && search.isEmpty {
                            ContentUnavailableView(L10n.text("Nessun download"), systemImage: "arrow.down.circle",
                                description: Text(L10n.text("Disattiva Offline per scegliere i libri da scaricare.")))
                        } else { ContentUnavailableView.search(text: search) }
                    }
                }
            }
            .navigationTitle("Tankarr")
            .searchable(text: $search, prompt: L10n.text("Cerca nella libreria"))
            .scrollBounceBehavior(.always, axes: .vertical)
            .refreshable { await model.refresh() }
            .navigationDestination(for: LibrarySeries.self) { SeriesView(series: $0) }
            .toolbar {
                if model.followingWritable || model.isDemo || !model.followedSeries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFollowed.toggle() } label: {
                            Image(systemName: showFollowed ? "bell.fill" : "bell")
                                .padding(5).background(showFollowed ? Color.orange.opacity(0.2) : .clear, in: Circle())
                        }.accessibilityLabel(L10n.text("Serie seguite"))
                            .accessibilityValue(L10n.text(showFollowed ? "Attiva" : "Disattiva"))
                            .accessibilityIdentifier("followed-series-filter")
                    }
                }
                if model.canBrowse {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { if model.offlineMode { await model.reconnect() } else { await model.useOffline() } }
                        } label: {
                            Image(systemName: "wifi.slash")
                                .padding(5).background(model.offlineMode ? Color.orange.opacity(0.2) : .clear, in: Circle())
                        }.accessibilityLabel(L10n.text("Modalità offline"))
                            .accessibilityValue(L10n.text(model.offlineMode ? "Attiva" : "Disattiva"))
                            .accessibilityIdentifier("offline-mode")
                            .disabled(model.busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDownloads = true } label: { Image(systemName: "arrow.down.circle") }
                        .accessibilityLabel(L10n.text("Download")).accessibilityIdentifier("downloads")
                }
                if model.canViewBookmarks {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showBookmarks = true } label: { Image(systemName: "bookmark") }.accessibilityLabel(L10n.text("Segnalibri"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showConnection = true } label: { Image(systemName: "network") }.accessibilityLabel(L10n.text("Connessione"))
                        .accessibilityIdentifier("connection-settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if model.offlineMode {
                        Button { Task { await model.reconnect() } } label: {
                            Label(L10n.text("Torna online"), systemImage: "wifi")
                        }.font(.caption).disabled(model.busy).accessibilityIdentifier("return-online")
                    } else {
                        Image(systemName: "lock.shield")
                        Text(L10n.text("Libreria in sola lettura")).font(.caption)
                    }
                    Spacer()
                    Text(model.endpointLabel).font(.caption2).lineLimit(1)
                }.foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
        }.sheet(isPresented: $model.showConnection) { ConnectionView() }
            .onChange(of: model.pendingPushSeriesID) { _, _ in openPushSeries() }
            .onChange(of: model.library.map(\.id)) { _, _ in openPushSeries() }
            .onChange(of: model.busy) { _, busy in if !busy { openPushSeries() } }
            .sheet(isPresented: $showBookmarks, onDismiss: openPendingSeries) {
                BookmarksView { pendingSeries = $0; showBookmarks = false }
            }
            .sheet(isPresented: $showDownloads, onDismiss: openPendingSeries) {
                DownloadsView { pendingSeries = $0; showDownloads = false }
            }
    }
    private func openPendingSeries() {
        guard let id = pendingSeries else { return }; pendingSeries = nil
        if let series = model.series(id) { path = [series] }
    }
    private func openPushSeries() {
        guard !model.busy, model.canBrowse, let id = model.pendingPushSeriesID, let series = model.series(id) else { return }
        model.pendingPushSeriesID = nil
        showBookmarks = false; showDownloads = false; model.showConnection = false
        path = [series]
    }
}

struct BookmarksView: View {
    var onShowSeries: (String) -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ReaderBookmark?
    @State private var pendingSeries: String?
    @AppStorage("reader.bookmarks.sort.v1") private var sorting: ReaderListSort = .recent
    private var orderedBookmarks: [ReaderBookmark] {
        ReaderListOrdering.bookmarks(model.visibleBookmarks, sort: sorting)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text(model.isDemo ? "I segnalibri della demo restano su questo dispositivo." : model.offlineMode ? "Segnalibri delle serie scaricate. Le modifiche restano sul dispositivo e si sincronizzano quando torni online." :
                        "Un segnalibro per serie, condiviso con Tankarr e gli altri dispositivi. Salvalo dal lettore per scegliere dove riprendere."))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(L10n.text("Apri un capitolo e tocca l’icona Segnalibro in alto, poi Salva segnalibro."))
                        .font(.callout).foregroundStyle(.secondary)
                    Picker(L10n.text("Ordina per"), selection: $sorting) {
                        ForEach(ReaderListSort.allCases) { option in Text(option.title).tag(option) }
                    }.accessibilityIdentifier("bookmarks-sort")
                }
                if !model.pendingBookmarkSeries.isEmpty {
                    Section {
                        Label(L10n.format("%d modifiche in attesa di sincronizzazione", model.pendingBookmarkSeries.count),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("bookmark-sync-pending")
                    }
                }
                if let error = model.bookmarkError {
                    Section { Text(error).foregroundStyle(.orange); Button(L10n.text("Aggiorna segnalibri")) { Task { await model.refreshBookmarks() } } }
                }
                if model.bookmarksLoading { ProgressView(L10n.text("Carico i segnalibri…")) }
                if model.visibleBookmarks.isEmpty && !model.bookmarksLoading {
                    ContentUnavailableView(L10n.text("Nessun segnalibro"), systemImage: "bookmark", description: Text(L10n.text("Apri un libro e usa Segnalibro per salvare una pagina.")))
                }
                ForEach(orderedBookmarks) { bookmark in
                    let available = !model.offlineMode || downloads.item(bookmark.bookId)?.complete == true
                    Button {
                        if available { selected = bookmark } else { onShowSeries(bookmark.seriesId) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.seriesTitle).font(.headline).foregroundStyle(.primary)
                            Text(L10n.format("%@ · Pagina %d", bookmark.label, bookmark.pageIndex + 1)).font(.subheadline).foregroundStyle(.secondary)
                            if available { Label(L10n.text("Riprendi lettura"), systemImage: "book.pages").font(.caption) }
                            else {
                                Text(L10n.text("Il capitolo del segnalibro non è scaricato. Apri la serie per leggere le copie disponibili."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("bookmark-\(bookmark.seriesId)")
                        .swipeActions {
                            if model.canUseBookmarks {
                                Button(L10n.text("Rimuovi"), role: .destructive) { Task { await model.removeBookmark(bookmark) } }
                            }
                        }.disabled(model.bookmarkBusy || model.bookmarksLoading)
                }
                if model.bookmarkBusy { ProgressView(L10n.text("Aggiorno i segnalibri…")) }
            }.navigationTitle(L10n.text("Segnalibri"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Chiudi")) { dismiss() } } }
                .task { await model.refreshBookmarks() }
                .refreshable { await model.refreshBookmarks() }
                .fullScreenCover(item: $selected, onDismiss: {
                    if let id = pendingSeries { pendingSeries = nil; onShowSeries(id) }
                }) { bookmark in
                    ReaderView(bookID: bookmark.bookId, openingPage: bookmark.pageIndex,
                        onShowSeries: { pendingSeries = $0; selected = nil })
                }
        }
    }
}

struct CoverView: View {
    let series: LibrarySeries
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    var body: some View {
        Rectangle().fill(Color.secondary.opacity(0.12))
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore).accessibilityLabel(series.title)
            .accessibilityIdentifier("cover-\(series.id)")
            .task(id: "\(series.id)-\(model.offlineMode)") { image = await model.cover(series.id) }
    }
}

struct SeriesView: View {
    private struct Opening: Identifiable {
        let id: String
        var page: Int? = nil
    }
    let series: LibrarySeries
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @ObservedObject private var push = ReaderPush.shared
    @State private var books: [LibraryBook] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: Opening?
    @State private var bookmarkUnavailable = false
    @State private var showDownloadRange = false
    @State private var confirmRemoveSeries = false
    @State private var removeBookID: String?
    private var bookmarkDownloads: [LibraryBook] {
        DownloadSelection.fromBookmark(model.bookmarks.first { $0.seriesId == series.id }, seriesID: series.id, books: books)
    }
    private var bookmark: ReaderBookmark? { model.bookmarks.first { $0.seriesId == series.id } }
    var body: some View {
        List {
            if model.followingWritable || model.isDemo || model.followedSeries.contains(series.id) {
                Section {
                    Button { Task { await model.toggleFollowing(series.id) } } label: {
                        HStack {
                            Label(L10n.text(model.followedSeries.contains(series.id) ? "Serie seguita" : "Segui la serie"),
                                  systemImage: model.followedSeries.contains(series.id) ? "bell.fill" : "bell.badge")
                            Spacer()
                            if model.followingBusy.contains(series.id) { ProgressView() }
                        }
                    }.disabled(!model.canFollowSeries || model.followingBusy.contains(series.id))
                        .accessibilityIdentifier("series-follow")
                        .accessibilityValue(L10n.text(model.followedSeries.contains(series.id) ? "Attiva" : "Disattiva"))
                    Text(L10n.text("Ricevi un avviso quando un nuovo capitolo è disponibile nella tua libreria."))
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.isDemo, model.followedSeries.contains(series.id) {
                        if !model.pushNotificationsAvailable {
                            Text(L10n.text("Le notifiche push non sono ancora configurate su questo server."))
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Button(L10n.text(push.denied ? "Apri impostazioni notifiche" : "Attiva notifiche")) {
                                if push.denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                else { Task { await push.requestPermission() } }
                            }.accessibilityIdentifier("enable-push-notifications")
                            if let message = push.notice { Text(message).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    if let error = model.followingError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
            if let bookmark {
                Section {
                    Button {
                        if model.offlineMode && downloads.item(bookmark.bookId)?.complete != true {
                            bookmarkUnavailable = true
                        } else { selected = Opening(id: bookmark.bookId, page: bookmark.pageIndex) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(L10n.text("Riprendi dal segnalibro"), systemImage: "bookmark.fill").font(.headline)
                            Text(L10n.format("%@ · Pagina %d", bookmark.label, bookmark.pageIndex + 1))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("series-resume-bookmark")
                }
            } else if model.canUseBookmarks {
                Section {
                    Label(L10n.text("Apri un capitolo e tocca l’icona Segnalibro in alto, poi Salva segnalibro."), systemImage: "bookmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if !series.description.isEmpty {
                Section { Text(series.description).font(.callout).foregroundStyle(.secondary).lineLimit(7) }
            }
            if loading { ProgressView(L10n.text("Carico i libri…")) }
            if let error { Section { Text(error); Button(L10n.text("Riprova")) { Task { await load() } } } }
            if downloads.hasDownloads(seriesID: series.id) {
                Section(L10n.text("Download della serie")) {
                    Text(L10n.format("%d libri scaricati · %d in coda",
                        downloads.items.filter { $0.series.id == series.id && $0.complete }.count,
                        downloads.queuedCount(seriesID: series.id)))
                        .accessibilityIdentifier("series-download-summary")
                    if let error = downloads.storageError { Text(error.localizedDescription).foregroundStyle(.orange) }
                }
            }
            Section(L10n.text("Disponibili da leggere")) {
                ForEach(books) { book in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Button { selected = Opening(id: book.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: model.position(book.id) > 0 ? "book.pages" : "book.closed").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(book.label).foregroundStyle(.primary)
                                        if !book.title.isEmpty { Text(book.title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                    Spacer()
                                    Text(book.language.uppercased()).font(.caption2).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }.buttonStyle(.plain)
                            DownloadBookControl(series: series, book: book)
                        }
                        DownloadBookProgress(bookID: book.id)
                    }.padding(.vertical, 4)
                    .swipeActions {
                        if downloads.item(book.id) != nil || downloads.queuePosition(book.id) != nil {
                            Button(L10n.text("Rimuovi download"), role: .destructive) { removeBookID = book.id }
                        }
                    }
                }
            }
        }.navigationTitle(series.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if model.canDownload && !books.isEmpty {
                            Button(L10n.text("Scarica intervallo…")) { showDownloadRange = true }
                                .accessibilityIdentifier("download-range")
                            Button(L10n.text("Scarica dal segnalibro alla fine")) { enqueue(bookmarkDownloads) }
                                .disabled(bookmarkDownloads.isEmpty || model.bookmarksLoading)
                                .accessibilityIdentifier("download-from-bookmark")
                            Button(L10n.text("Scarica tutti")) { enqueue(books) }
                                .accessibilityIdentifier("download-series")
                        }
                        Button(L10n.text("Rimuovi download della serie"), role: .destructive) { confirmRemoveSeries = true }
                            .disabled(!downloads.hasDownloads(seriesID: series.id))
                            .accessibilityIdentifier("remove-series-downloads")
                    } label: { Image(systemName: "arrow.down.circle") }
                        .accessibilityLabel(L10n.text("Download della serie")).accessibilityIdentifier("series-downloads")
                }
            }
            .task(id: model.offlineMode) { await load(); await model.refreshBookmarks(); await model.refreshFollows() }
            .refreshable { await load(); await model.refreshBookmarks(); await model.refreshFollows() }
            .onChange(of: downloads.items.filter { $0.complete && $0.series.id == series.id }.map(\.id)) { _, _ in
                if model.offlineMode { books = OfflineLibrary.books(seriesID: series.id, downloads: downloads.items) }
            }
            .fullScreenCover(item: $selected) { ReaderView(bookID: $0.id, openingPage: $0.page) }
            .alert(L10n.text("Segnalibro non disponibile offline"), isPresented: $bookmarkUnavailable) {
                Button(L10n.text("OK"), role: .cancel) {}
            } message: { Text(L10n.text("Il capitolo del segnalibro non è scaricato. Torna online per leggerlo.")) }
            .sheet(isPresented: $showDownloadRange) { SeriesDownloadRangeView(series: series, books: books) }
            .confirmationDialog(L10n.text("Rimuovere tutti i download di questa serie?"), isPresented: $confirmRemoveSeries, titleVisibility: .visible) {
                Button(L10n.text("Rimuovi download della serie"), role: .destructive) {
                    Task {
                        do { try await downloads.removeSeries(series.id) }
                        catch { self.error = error.localizedDescription }
                    }
                }.accessibilityIdentifier("confirm-remove-series-downloads")
            } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
            .confirmationDialog(L10n.text("Rimuovere questa copia dal dispositivo?"), isPresented: Binding(
                get: { removeBookID != nil }, set: { if !$0 { removeBookID = nil } }), titleVisibility: .visible) {
                    if let id = removeBookID {
                        Button(L10n.text("Rimuovi download"), role: .destructive) {
                            Task { await downloads.remove(id) }; removeBookID = nil
                        }
                    }
                } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
    }
    private func enqueue(_ selection: [LibraryBook]) {
        downloads.enqueue(series: series, books: selection, api: model.api, demo: model.isDemo)
    }
    private func load() async {
        guard model.canBrowse else { return }; loading = true; error = nil
        defer { loading = false }
        do { books = try await model.books(for: series.id) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ServerProfile()
    @State private var password = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: ReaderConfigurationDocument?
    @State private var importedConfiguration: ImportedReaderConfiguration?
    @State private var importError: String?
    @State private var confirmDisconnect = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.text("Lingua dell’app"), selection: Binding(
                        get: { model.appLanguage }, set: { model.setLanguage($0) })) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language).accessibilityIdentifier("app-language-\(language.rawValue)")
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("app-language")
                } header: { Text(L10n.text("Lingua dell’app")) } footer: {
                    Text(L10n.text("La lingua dell’interfaccia è salvata su questo dispositivo. Sistema segue la lingua preferita dell’iPhone o iPad fra italiano e inglese; le altre lingue usano l’inglese. Non cambia la lingua dei libri."))
                }
                Section {
                    Button(L10n.text("Esplora la libreria dimostrativa")) { Task { await model.startDemo(); dismiss() } }.disabled(model.busy)
                } footer: { Text(L10n.text("Tre racconti originali per provare ricerca, lettura e zoom. Funziona senza account e senza connessione.")) }
                Section(L10n.text("Server")) {
                    TextField(L10n.text("Indirizzo locale (opzionale)"), text: $profile.localAddress).keyboardType(.URL)
                    TextField(L10n.text("Indirizzo HTTPS"), text: $profile.remoteAddress).keyboardType(.URL)
                    Picker(L10n.text("Connessione"), selection: $profile.mode) { ForEach(ConnectionMode.allCases) { Text($0.label).tag($0) } }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Section(L10n.text("Account lettore")) {
                    TextField(L10n.text("Utente"), text: $profile.username).textContentType(.username)
                    SecureField(L10n.text("Password"), text: $password).textContentType(.password)
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Section {
                    Button {
                        Task {
                            let imported = importedConfiguration
                            if await model.connect(profile, password: password), let imported {
                                await model.applyConfiguration(imported)
                                importedConfiguration = nil
                            }
                        }
                    } label: {
                        HStack { Text(L10n.text("Connetti")); Spacer(); if model.busy { ProgressView() } }
                    }.disabled(model.busy)
                    if model.canBrowse {
                        Button {
                            Task {
                                if model.offlineMode { await model.reconnect() }
                                else { await model.refresh() }
                            }
                        } label: {
                            HStack {
                                Label(L10n.text("Aggiorna Tankarr"), systemImage: "arrow.clockwise")
                                Spacer(); if model.refreshing { ProgressView() }
                            }
                        }.disabled(model.busy || model.refreshing)
                            .accessibilityIdentifier("refresh-tankarr")
                        if let notice = model.refreshNotice {
                            Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("refresh-result")
                        }
                    }
                    Button(L10n.text("Importa configurazione…")) { importing = true }.disabled(model.busy)
                    Button(L10n.text("Esporta configurazione…")) {
                        do {
                            var configuration = model.configuration()
                            if profile != model.profile {
                                configuration.readingOptions = [:]; configuration.followedSeries = []
                            }
                            configuration.profile = profile
                            exportDocument = ReaderConfigurationDocument(data: try configuration.encoded())
                            importError = nil; exporting = true
                        } catch { importError = L10n.format("Configurazione non valida: %@", error.localizedDescription) }
                    }.disabled(model.busy).accessibilityIdentifier("export-configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("La password resta nel Portachiavi. L’ultima pagina letta è ricordata su questo dispositivo; i segnalibri salvati dal lettore sono condivisi con Tankarr. In Automatico provo prima l’indirizzo locale e poi HTTPS; aggiorna la libreria per cambiare rete."))
                        Text(L10n.text("L’esportazione contiene indirizzi, utente, lingua, opzioni di lettura e serie seguite. Non contiene password, download o token push. Dopo l’importazione tocca Connetti: le serie seguite vengono aggiunte solo allo stesso account e server; il consenso alle notifiche va dato su ogni dispositivo."))
                    }
                }
                if let error = importError ?? model.error { Section { Text(error).foregroundStyle(.red) } }
                Section(L10n.text("Modalità offline")) {
                    Text(L10n.text("Il pulsante con il Wi-Fi barrato mostra solo i download. Se manca la rete, l’app passa automaticamente alle copie scaricate e riprova al ritorno della rete o alla riapertura. Se attivi Offline tu, resta attivo finché tocchi Torna online."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section { NavigationLink(L10n.text("Privacy e assistenza")) { PrivacyView() } }
                if model.canBrowse {
                    Section {
                        Button(L10n.text("Disconnetti"), role: .destructive) { confirmDisconnect = true }.disabled(model.busy)
                    }
                }
            }.navigationTitle(L10n.text("Connessione")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Chiudi")) { dismiss() } } }
                .onAppear { profile = model.profile; password = PasswordStore.read() ?? "" }
                .confirmationDialog(L10n.text("Disconnettere ed eliminare i download di questo account?"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button(L10n.text("Disconnetti"), role: .destructive) {
                        Task { await model.disconnect(); password = ""; profile = model.profile }
                    }
                } message: {
                    Text(L10n.text(model.pendingBookmarkSeries.isEmpty ? "La libreria e i segnalibri sul server restano invariati." :
                        "Le modifiche ai segnalibri non ancora sincronizzate saranno eliminate dal dispositivo. I segnalibri sul server restano invariati."))
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= ReaderConfiguration.maximumBytes else { throw ReaderError.invalidAccount }
                        let imported = try ImportedReaderConfiguration(data: Data(contentsOf: url, options: [.mappedIfSafe]))
                        let value = imported.configuration
                        password = imported.password ?? (value.canReusePassword(from: model.profile) ? PasswordStore.read() ?? "" : "")
                        profile = value.profile; importedConfiguration = imported; importError = nil
                    } catch { importError = L10n.format("Configurazione non valida: %@", error.localizedDescription) }
                }
                .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                              defaultFilename: "Tankarr Reader") { result in
                    if case .failure(let error) = result {
                        importError = L10n.format("Configurazione non valida: %@", error.localizedDescription)
                    }
                }
        }
    }
}

private struct ReaderConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ReaderError.invalidAccount }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
