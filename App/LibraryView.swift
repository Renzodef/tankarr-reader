import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var showBookmarks = false
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]
    private var filtered: [LibrarySeries] {
        search.isEmpty ? model.library : model.library.filter { $0.title.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = model.error {
                    ContentUnavailableView("Connessione non riuscita", systemImage: "wifi.exclamationmark", description: Text(error))
                    Button("Riprova") { Task { await model.refresh() } }.buttonStyle(.bordered)
                }
                if model.busy && model.library.isEmpty { ProgressView("Apro la libreria…").padding(48) }
                else if !model.canBrowse {
                    ContentUnavailableView("La tua libreria, con te", systemImage: "books.vertical", description: Text("Collega il lettore al tuo server Tankarr."))
                    Button("Configura connessione") { model.showConnection = true }.buttonStyle(.borderedProminent)
                    Button("Esplora la demo") { model.startDemo() }.padding(.top, 8)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(filtered) { series in
                            NavigationLink(value: series) {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverView(series: series).aspectRatio(2.0 / 3.0, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(series.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                                    Text("\(series.booksCount) file disponibili").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .navigationTitle("Tankarr")
            .searchable(text: $search, prompt: "Cerca nella libreria")
            .refreshable { await model.refresh() }
            .navigationDestination(for: LibrarySeries.self) { SeriesView(series: $0) }
            .toolbar {
                if model.canUseBookmarks {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showBookmarks = true } label: { Image(systemName: "bookmark") }.accessibilityLabel("Segnalibri")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showConnection = true } label: { Image(systemName: "network") }.accessibilityLabel("Connessione")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(systemName: "lock.shield")
                    Text("Libreria in sola lettura").font(.caption)
                    Spacer()
                    Text(model.endpointLabel).font(.caption2).lineLimit(1)
                }.foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
        }.sheet(isPresented: $model.showConnection) { ConnectionView() }
            .sheet(isPresented: $showBookmarks) { BookmarksView() }
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
                    Text(model.isDemo ? "I segnalibri della demo restano su questo dispositivo." :
                        "Un segnalibro per serie, condiviso con Tankarr e gli altri dispositivi. Salvalo dal lettore per scegliere dove riprendere.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.bookmarkError {
                    Section { Text(error).foregroundStyle(.orange); Button("Aggiorna segnalibri") { Task { await model.refreshBookmarks() } } }
                }
                if model.bookmarksLoading { ProgressView("Carico i segnalibri…") }
                if model.bookmarks.isEmpty && !model.bookmarksLoading {
                    ContentUnavailableView("Nessun segnalibro", systemImage: "bookmark", description: Text("Apri un libro e usa Segnalibro per salvare una pagina."))
                }
                ForEach(model.bookmarks) { bookmark in
                    Button { selected = bookmark } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.seriesTitle).font(.headline).foregroundStyle(.primary)
                            Text("\(bookmark.label) · Pagina \(bookmark.pageIndex + 1)").font(.subheadline).foregroundStyle(.secondary)
                            Label("Riprendi lettura", systemImage: "book.pages").font(.caption)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("bookmark-\(bookmark.seriesId)")
                        .swipeActions {
                            Button("Rimuovi", role: .destructive) { Task { await model.removeBookmark(bookmark) } }
                        }.disabled(model.bookmarkBusy || model.bookmarksLoading)
                }
                if model.bookmarkBusy { ProgressView("Aggiorno i segnalibri…") }
            }.navigationTitle("Segnalibri")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
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
            if loading { ProgressView("Carico i libri…") }
            if let error { Section { Text(error); Button("Riprova") { Task { await load() } } } }
            Section("Disponibili da leggere") {
                ForEach(books) { book in
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
                    }
                }
            }
        }.navigationTitle(series.title).navigationBarTitleDisplayMode(.inline)
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
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Esplora la libreria dimostrativa") { model.startDemo(); dismiss() }.disabled(model.busy)
                } footer: { Text("Tre racconti originali per provare ricerca, lettura e zoom. Funziona senza account e senza connessione.") }
                Section("Server") {
                    TextField("Indirizzo locale (opzionale)", text: $profile.localAddress).keyboardType(.URL)
                    TextField("Indirizzo HTTPS", text: $profile.remoteAddress).keyboardType(.URL)
                    Picker("Connessione", selection: $profile.mode) { ForEach(ConnectionMode.allCases) { Text($0.label).tag($0) } }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Section("Account lettore") {
                    TextField("Utente", text: $profile.username).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Section {
                    Button { Task { await model.connect(profile, password: password) } } label: {
                        HStack { Text("Connetti"); Spacer(); if model.busy { ProgressView() } }
                    }.disabled(model.busy)
                    Button("Importa configurazione…") { importing = true }.disabled(model.busy)
                } footer: {
                    Text("La password resta nel Portachiavi. L’ultima pagina letta è ricordata su questo dispositivo; i segnalibri salvati dal lettore sono condivisi con Tankarr. In Automatico provo prima l’indirizzo locale e poi HTTPS; aggiorna la libreria per cambiare rete.")
                }
                if let error = importError ?? model.error { Section { Text(error).foregroundStyle(.red) } }
                Section { NavigationLink("Privacy e assistenza") { PrivacyView() } }
                if model.canBrowse { Section { Button("Disconnetti", role: .destructive) { model.disconnect(); password = ""; profile = ServerProfile() } } }
            }.navigationTitle("Connessione").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
                .onAppear { profile = model.profile; password = PasswordStore.read() ?? "" }
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
                    } catch { importError = "Configurazione non valida: \(error.localizedDescription)" }
                }
        }
    }
    private struct ImportedConnection: Decodable {
        let localAddress: String?; let remoteAddress: String; let username: String; let password: String; let instanceID: String?
    }
}
