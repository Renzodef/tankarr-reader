import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @State private var search = ""
    @State private var showBookmarks = false
    @State private var showDownloads = false
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]
    private var filtered: [LibrarySeries] {
        search.isEmpty ? model.library : model.library.filter { $0.title.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = model.error {
                    ContentUnavailableView(L10n.text("Connessione non riuscita"), systemImage: "wifi.exclamationmark", description: Text(error))
                    Button(L10n.text("Riprova")) { Task { await model.refresh() } }.buttonStyle(.bordered)
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
                                    CoverView(series: series).aspectRatio(2.0 / 3.0, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(series.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                                    Text(L10n.format("%d file disponibili", series.booksCount)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .navigationTitle("Tankarr")
            .searchable(text: $search, prompt: L10n.text("Cerca nella libreria"))
            .refreshable { await model.refresh() }
            .navigationDestination(for: LibrarySeries.self) { SeriesView(series: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDownloads = true } label: { Image(systemName: "arrow.down.circle") }
                        .accessibilityLabel(L10n.text("Download")).accessibilityIdentifier("downloads")
                }
                if model.canUseBookmarks {
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
                    Image(systemName: "lock.shield")
                    Text(L10n.text("Libreria in sola lettura")).font(.caption)
                    Spacer()
                    Text(model.endpointLabel).font(.caption2).lineLimit(1)
                }.foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
        }.sheet(isPresented: $model.showConnection) { ConnectionView() }
            .sheet(isPresented: $showBookmarks) { BookmarksView() }
            .sheet(isPresented: $showDownloads) { DownloadsView() }
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ReaderBookmark?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text(model.isDemo ? "I segnalibri della demo restano su questo dispositivo." :
                        "Un segnalibro per serie, condiviso con Tankarr e gli altri dispositivi. Salvalo dal lettore per scegliere dove riprendere."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.bookmarkError {
                    Section { Text(error).foregroundStyle(.orange); Button(L10n.text("Aggiorna segnalibri")) { Task { await model.refreshBookmarks() } } }
                }
                if model.bookmarksLoading { ProgressView(L10n.text("Carico i segnalibri…")) }
                if model.bookmarks.isEmpty && !model.bookmarksLoading {
                    ContentUnavailableView(L10n.text("Nessun segnalibro"), systemImage: "bookmark", description: Text(L10n.text("Apri un libro e usa Segnalibro per salvare una pagina.")))
                }
                ForEach(model.bookmarks) { bookmark in
                    Button { selected = bookmark } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.seriesTitle).font(.headline).foregroundStyle(.primary)
                            Text(L10n.format("%@ · Pagina %d", bookmark.label, bookmark.pageIndex + 1)).font(.subheadline).foregroundStyle(.secondary)
                            Label(L10n.text("Riprendi lettura"), systemImage: "book.pages").font(.caption)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("bookmark-\(bookmark.seriesId)")
                        .swipeActions {
                            Button(L10n.text("Rimuovi"), role: .destructive) { Task { await model.removeBookmark(bookmark) } }
                        }.disabled(model.bookmarkBusy || model.bookmarksLoading)
                }
                if model.bookmarkBusy { ProgressView(L10n.text("Aggiorno i segnalibri…")) }
            }.navigationTitle(L10n.text("Segnalibri"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Chiudi")) { dismiss() } } }
                .task { await model.refreshBookmarks() }
                .refreshable { await model.refreshBookmarks() }
                .fullScreenCover(item: $selected) { ReaderView(bookID: $0.bookId, openingPage: $0.pageIndex) }
        }
    }
}

struct CoverView: View {
    let series: LibrarySeries
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) }
        }.clipped().task(id: series.id) { image = await model.cover(series.id) }
    }
}

struct SeriesView: View {
    let series: LibrarySeries
    @EnvironmentObject private var model: AppModel
    @State private var books: [LibraryBook] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: LibraryBook?
    var body: some View {
        List {
            if !series.description.isEmpty {
                Section { Text(series.description).font(.callout).foregroundStyle(.secondary).lineLimit(7) }
            }
            if loading { ProgressView(L10n.text("Carico i libri…")) }
            if let error { Section { Text(error); Button(L10n.text("Riprova")) { Task { await load() } } } }
            Section(L10n.text("Disponibili da leggere")) {
                ForEach(books) { book in
                    HStack(spacing: 12) {
                      Button { selected = book } label: {
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
                }
            }
        }.navigationTitle(series.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.canDownload && !books.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.text("Scarica tutti")) {
                            model.downloads.enqueue(series: series, books: books, api: model.api, demo: model.isDemo)
                        }.accessibilityIdentifier("download-series")
                    }
                }
            }
            .task { await load() }.refreshable { await load() }
            .fullScreenCover(item: $selected) { ReaderView(bookID: $0.id) }
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
                    Button { Task { await model.connect(profile, password: password) } } label: {
                        HStack { Text(L10n.text("Connetti")); Spacer(); if model.busy { ProgressView() } }
                    }.disabled(model.busy)
                    Button(L10n.text("Importa configurazione…")) { importing = true }.disabled(model.busy)
                } footer: {
                    Text(L10n.text("La password resta nel Portachiavi. L’ultima pagina letta è ricordata su questo dispositivo; i segnalibri salvati dal lettore sono condivisi con Tankarr. In Automatico provo prima l’indirizzo locale e poi HTTPS; aggiorna la libreria per cambiare rete."))
                }
                if let error = importError ?? model.error { Section { Text(error).foregroundStyle(.red) } }
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
                } message: { Text(L10n.text("La libreria e i segnalibri sul server restano invariati.")) }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                        guard data.count <= 16 * 1024 else { throw ReaderError.invalidAccount }
                        let imported = try JSONDecoder().decode(ImportedConnection.self, from: data)
                        let newProfile = ServerProfile(localAddress: imported.localAddress ?? "", remoteAddress: imported.remoteAddress,
                            username: imported.username, mode: .automatic, instanceID: imported.instanceID)
                        _ = try newProfile.candidates()
                        profile = newProfile; password = imported.password; importError = nil
                    } catch { importError = L10n.format("Configurazione non valida: %@", error.localizedDescription) }
                }
        }
    }
    private struct ImportedConnection: Decodable {
        let localAddress: String?; let remoteAddress: String; let username: String; let password: String; let instanceID: String?
    }
}
