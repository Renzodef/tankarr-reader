import SwiftUI

struct SeriesDownloadRangeView: View {
    let series: LibrarySeries
    let books: [LibraryBook]
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    init(series: LibrarySeries, books: [LibraryBook]) {
        self.series = series; self.books = books
        _first = State(initialValue: books.first?.id ?? "")
        _last = State(initialValue: books.last?.id ?? "")
    }
    private var selection: [LibraryBook] { DownloadSelection.range(books, from: first, through: last) }
    private var endChoices: [LibraryBook] {
        guard let start = books.firstIndex(where: { $0.id == first }) else { return [] }
        return Array(books[start...])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.text("Da"), selection: $first) {
                        ForEach(books) { Text(label($0)).tag($0.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("download-range-from")
                    Picker(L10n.text("A"), selection: $last) {
                        ForEach(endChoices) { Text(label($0)).tag($0.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("download-range-through")
                } header: { Text(series.title) } footer: {
                    Text(L10n.text("Entrambi gli estremi sono inclusi. I libri già scaricati vengono saltati; quelli incompleti riprendono dalle pagine mancanti."))
                }
                Section {
                    Button(L10n.format("Scarica %d libri", selection.count)) {
                        downloads.enqueue(series: series, books: selection, api: model.api, demo: model.isDemo)
                        dismiss()
                    }.disabled(selection.isEmpty || !model.canDownload)
                        .accessibilityIdentifier("confirm-download-range")
                    Text(L10n.text("Puoi cambiare app: i download continuano in background e la coda resta salvata."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(L10n.text("Scarica intervallo"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Annulla")) { dismiss() } } }
                .onChange(of: first) { _, _ in
                    if !endChoices.contains(where: { $0.id == last }) { last = first }
                }
        }
    }
    private func label(_ book: LibraryBook) -> String {
        [book.label, book.title, book.language.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
