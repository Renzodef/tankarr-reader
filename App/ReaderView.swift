import SwiftUI
import UIKit

struct ReaderView: View {
    let bookID: String
    var openingPage: Int? = nil
    var onShowSeries: ((String) -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var book: ReaderBook?
    @State private var page = 0
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = true
    @State private var loadedPage: Int?
    @State private var retry = 0
    @State private var controls = true
    @State private var options = ReadingOptions()
    @State private var showOptions = false
    @State private var continuousRequestPage = 0
    @State private var continuousRequestID = 0
    private var axis: ReaderAxis { book.map { options.resolvedAxis(for: $0) } ?? .horizontal }
    private var rtl: Bool { axis == .horizontal && (book.map { options.resolvedRTL(for: $0) } ?? false) }
    private var continuous: Bool { book.map { options.resolvedContinuous(for: $0) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if controls {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L10n.text("Chiudi libro"))
                    if let seriesID = book?.seriesId {
                        Button {
                            if let onShowSeries { onShowSeries(seriesID) }
                            else { dismiss() }
                        } label: { Image(systemName: "books.vertical") }
                            .accessibilityLabel(L10n.text("Torna alla serie"))
                            .accessibilityIdentifier("reader-show-series")
                    }
                    Spacer()
                    VStack { Text(book?.seriesTitle ?? "Tankarr").font(.caption).lineLimit(1); Text(book?.title ?? L10n.text("Caricamento…")).font(.caption2).lineLimit(1) }
                    Spacer()
                    if let book, model.canUseBookmarks, book.seriesId != nil {
                        Menu {
                            Button(L10n.text(model.bookmark(for: book) == nil ? "Salva segnalibro" : "Sposta segnalibro a questa pagina")) {
                                guard let displayed = loadedPage else { return }
                                Task { await model.saveBookmark(book, page: displayed) }
                            }
                            if let bookmark = model.bookmark(for: book) {
                                Button(L10n.text("Rimuovi segnalibro"), role: .destructive) { Task { await model.removeBookmark(bookmark) } }
                            }
                        } label: {
                            Image(systemName: model.bookmark(for: book) == nil ? "bookmark" : "bookmark.fill")
                        }.accessibilityLabel(L10n.text("Segnalibro"))
                            .disabled(loadedPage == nil || loading || model.bookmarkBusy || model.bookmarksLoading)
                    }
                    Image(systemName: axis == .vertical ? "arrow.down" : (rtl ? "arrow.left" : "arrow.right")).font(.caption)
                        .accessibilityLabel(L10n.text(axis == .vertical ? "Lettura dall’alto in basso" : (rtl ? "Lettura da destra a sinistra" : "Lettura da sinistra a destra")))
                    Button { showOptions = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel(L10n.text("Opzioni di lettura")).disabled(book == nil)
                }.padding().background(.ultraThinMaterial)
            }
            ZStack {
                Color.black
                if continuous, let book {
                    ContinuousReaderView(bookID: bookID, pageCount: book.pageCount,
                        axis: axis, rightToLeft: rtl,
                        requestedPage: continuousRequestPage, requestID: continuousRequestID,
                        loadImage: { index in try await model.page(bookID, at: index) },
                        onVisiblePage: visiblePageChanged)
                } else if let image {
                    ZoomPage(image: image, identity: "\(bookID):\(loadedPage ?? 0)", axis: axis,
                             rightToLeft: rtl, onStep: step)
                }
                if loading && !continuous { ProgressView().tint(.white).padding(20).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)) }
                if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text(error).multilineTextAlignment(.center)
                        Button(L10n.text("Riprova")) { retry += 1 }.buttonStyle(.borderedProminent)
                    }.foregroundStyle(.white).padding(28).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16)).padding()
                }
            }
            if let book {
                VStack(spacing: 8) {
                    if let error = model.bookmarkError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button(L10n.text("Aggiorna segnalibri")) { Task { await model.refreshBookmarks() } }
                            .font(.caption).disabled(model.bookmarkBusy || model.bookmarksLoading)
                    }
                    if model.bookmarkBusy { ProgressView(L10n.text("Salvo il segnalibro…")).font(.caption) }
                    else if let bookmark = model.bookmark(for: book) {
                        Text(L10n.format("Segnalibro a pagina %d", bookmark.pageIndex + 1)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { step(rtl ? 1 : -1) } label: { Image(systemName: axis == .vertical ? "chevron.up" : "chevron.left").frame(width: 44, height: 36) }
                            .disabled(rtl ? page >= book.pageCount - 1 : page <= 0).accessibilityLabel(L10n.text(rtl ? "Pagina successiva" : "Pagina precedente"))
                        Spacer()
                        Text("\(page + 1) / \(book.pageCount)").monospacedDigit().font(.callout)
                            .accessibilityIdentifier("reader-page-counter")
                        Spacer()
                        Button { step(rtl ? -1 : 1) } label: { Image(systemName: axis == .vertical ? "chevron.down" : "chevron.right").frame(width: 44, height: 36) }
                            .disabled(rtl ? page <= 0 : page >= book.pageCount - 1).accessibilityLabel(L10n.text(rtl ? "Pagina precedente" : "Pagina successiva"))
                    }
                    if book.pageCount > 1 {
                        Slider(value: Binding(get: { Double(page) }, set: { navigate(to: Int($0)) }), in: 0...Double(book.pageCount - 1), step: 1)
                            .accessibilityLabel(L10n.text("Pagina")).accessibilityValue(L10n.format("%d di %d", page + 1, book.pageCount))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial)
            }
        }.background(.black).preferredColorScheme(.dark)
            .task(id: "metadata-\(retry)") { if book == nil { await loadBook() } }
            .task(id: "\(book?.id ?? "")-\(page)-\(retry)-\(continuous)") { if book != nil && !continuous { await loadPage() } }
            .onChange(of: options) { _, value in
                if let book { model.saveReadingOptions(value, book: book) }
            }
            .onChange(of: continuous) { _, _ in
                image = nil; loadedPage = nil; error = nil; loading = true
                continuousRequestPage = page; continuousRequestID += 1
            }
            .sheet(isPresented: $showOptions) { readingOptionsSheet }
    }
    private var readingOptionsSheet: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Visualizzazione")) {
                    ForEach(ReaderLayout.allCases) { layout in
                        Button { options.layout = layout } label: {
                            optionRow(layout.label, selected: options.layout == layout)
                        }.accessibilityIdentifier("reader-layout-\(layout.rawValue)")
                            .accessibilityValue(options.layout == layout ? L10n.text("Selezionato") : "")
                    }
                }
                Section(L10n.text("Asse di lettura")) {
                    ForEach(ReaderAxis.allCases) { value in
                        Button { options.axis = value } label: {
                            optionRow(value.label, selected: options.axis == value)
                        }.accessibilityIdentifier("reader-axis-\(value.rawValue)")
                            .accessibilityValue(options.axis == value ? L10n.text("Selezionato") : "")
                    }
                }
                Section {
                    ForEach(ReaderDirection.allCases) { direction in
                        Button { options.direction = direction } label: {
                            optionRow(direction.label, selected: options.direction == direction)
                        }.accessibilityIdentifier("reader-direction-\(direction.rawValue)")
                            .accessibilityValue(options.direction == direction ? L10n.text("Selezionato") : "")
                            .disabled(axis == .vertical)
                    }
                } header: { Text(L10n.text("Verso orizzontale"))
                } footer: {
                    if axis == .vertical { Text(L10n.text("In verticale si legge dall’alto in basso. Il verso sinistra/destra si applica solo all’asse orizzontale.")) }
                }
                Section {
                    Text(L10n.text("L’asse automatico è verticale nel continuo e orizzontale a pagine. Modalità e verso automatici seguono il volume. Le scelte restano salvate su questo dispositivo per volume, senza modificare i segnalibri."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("reader-options")
                .navigationTitle(L10n.text("Lettura")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Fine")) { showOptions = false } } }
        }.preferredColorScheme(.dark)
    }
    private func optionRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func step(_ delta: Int) { navigate(to: page + delta) }
    private func navigate(to target: Int) {
        guard let book else { return }
        let target = min(max(0, target), book.pageCount - 1)
        guard target != page else { return }
        page = target
        if continuous {
            loadedPage = nil; loading = true
            continuousRequestPage = target; continuousRequestID += 1
        }
    }
    private func visiblePageChanged(_ index: Int, _ ready: Bool) {
        guard continuous, let book, (0..<book.pageCount).contains(index) else { return }
        page = index; loadedPage = ready ? index : nil; loading = !ready
        if ready { model.savePosition(index, book: bookID) }
    }
    private func loadBook() async {
        guard model.canBrowse else { return }; loading = true; error = nil
        do {
            let result = try await model.book(bookID)
            guard result.pageCount > 0 else { throw ReaderError.unavailable(422) }
            // A downloaded book opens immediately, even if the server has just
            // become unreachable and the last online session is still selected.
            if model.downloads.item(bookID)?.complete != true { await model.refreshBookmarks() }
            try Task.checkCancellation()
            options = model.readingOptions(result)
            page = model.resumePosition(result, openingPage: openingPage)
            continuousRequestPage = page; book = result
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
    private func loadPage() async {
        guard model.canBrowse else { return }; loading = true; error = nil
        let requested = page
        do {
            // Debounce a moving slider; keep just the displayed page in memory.
            try await Task.sleep(for: .milliseconds(150))
            let decoded = try await model.page(bookID, at: requested)
            try Task.checkCancellation()
            image = decoded; loadedPage = requested; model.savePosition(requested, book: bookID); loading = false
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
}

// UIScrollView gives native pinch/pan/double-tap zoom without retaining a whole book.
struct ZoomPage: UIViewRepresentable {
    let image: UIImage
    let identity: String
    let axis: ReaderAxis
    let rightToLeft: Bool
    let onStep: (Int) -> Void
    func makeUIView(context: Context) -> PageScrollView { PageScrollView() }
    func updateUIView(_ view: PageScrollView, context: Context) {
        view.display(image, identity: identity, axis: axis, rightToLeft: rightToLeft, onStep: onStep)
    }
}

final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    private let pageView = UIImageView()
    private var identity = ""
    private var axis: ReaderAxis = .horizontal
    private var rightToLeft = false
    private var onStep: ((Int) -> Void)?
    private var previousBounds = CGSize.zero
    init() {
        super.init(frame: .zero)
        backgroundColor = .black; delegate = self; maximumZoomScale = 5
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        pageView.contentMode = .scaleAspectFit; addSubview(pageView)
        pageView.isAccessibilityElement = true
        pageView.accessibilityIdentifier = "reader-page"
        pageView.accessibilityLabel = L10n.text("Pagina del libro")
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomTapped(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(pageSwiped(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
            panGestureRecognizer.require(toFail: swipe)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func display(_ image: UIImage, identity: String, axis: ReaderAxis, rightToLeft: Bool, onStep: @escaping (Int) -> Void) {
        self.axis = axis; self.rightToLeft = rightToLeft; self.onStep = onStep
        pageView.accessibilityLabel = L10n.text("Pagina del libro")
        guard self.identity != identity else { return }
        self.identity = identity; pageView.image = image
        previousBounds = .zero; setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousBounds, bounds.width > 0, bounds.height > 0, let image = pageView.image {
            previousBounds = bounds.size
            zoomScale = 1
            let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
            pageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * factor, height: image.size.height * factor))
            contentSize = pageView.frame.size; contentOffset = .zero
        }
        centerPage()
    }
    private func centerPage() {
        pageView.center = CGPoint(x: max(contentSize.width, bounds.width) / 2, y: max(contentSize.height, bounds.height) / 2)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage() }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let swipe = gestureRecognizer as? UISwipeGestureRecognizer {
            guard zoomScale <= 1.05 else { return false }
            return axis == .vertical ? (swipe.direction == .up || swipe.direction == .down)
                                     : (swipe.direction == .left || swipe.direction == .right)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    @objc private func pageSwiped(_ sender: UISwipeGestureRecognizer) {
        guard zoomScale <= 1.05 else { return }
        let forward = axis == .vertical ? sender.direction == .up
                                       : sender.direction == (rightToLeft ? .right : .left)
        onStep?(forward ? 1 : -1)
    }
    @objc private func zoomTapped(_ sender: UITapGestureRecognizer) {
        if zoomScale > 1.1 { setZoomScale(1, animated: true) }
        else {
            let point = sender.location(in: pageView)
            let rect = CGRect(x: point.x - bounds.width / 4, y: point.y - bounds.height / 4, width: bounds.width / 2, height: bounds.height / 2)
            zoom(to: rect, animated: true)
        }
    }
}
