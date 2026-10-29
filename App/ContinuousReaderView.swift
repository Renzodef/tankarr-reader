import SwiftUI
import UIKit

/// A vertical reader whose cells own their images only while on screen.
struct ContinuousReaderView: UIViewControllerRepresentable {
    let bookID: String
    let pageCount: Int
    let requestedPage: Int
    let requestID: Int
    let loadImage: @MainActor (Int) async throws -> UIImage
    let onVisiblePage: @MainActor (Int, Bool) -> Void

    func makeUIViewController(context: Context) -> ContinuousReaderController {
        let controller = ContinuousReaderController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: ContinuousReaderController, context: Context) {
        controller.configure(bookID: bookID, pageCount: pageCount, requestedPage: requestedPage,
                             requestID: requestID, loadImage: loadImage, onVisiblePage: onVisiblePage)
    }

    static func dismantleUIViewController(_ controller: ContinuousReaderController, coordinator: ()) {
        controller.stop()
    }
}

@MainActor
final class ContinuousReaderController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private struct Anchor {
        let page: Int
        let fraction: CGFloat
    }

    private struct Request {
        let page: Int
        let generation: Int
        let task: Task<Void, Never>
    }

    private let pageLayout = ContinuousPageLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: pageLayout)
    private var bookID: String?
    private var pageCount = 0
    private var requestID: Int?
    private var generation = 0
    private var loadImage: (@MainActor (Int) async throws -> UIImage)?
    private var onVisiblePage: (@MainActor (Int, Bool) -> Void)?
    private var requests: [UUID: Request] = [:]
    private var pendingJump: Int?
    private var anchor: Anchor?
    private var lastReportedPage: Int?
    private var lastReportedLoaded = false
    private var updateScheduled = false
    private var adjustingLayout = false
    private var stopped = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ContinuousPageCell.self, forCellWithReuseIdentifier: "page")
        collectionView.isPrefetchingEnabled = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.accessibilityIdentifier = "reader-continuous"
        // Vertical page order is the same for manga and left-to-right books.
        collectionView.semanticContentAttribute = .forceLeftToRight
        view.addSubview(collectionView)
        pageLayout.reset(pageCount: pageCount)
    }

    func configure(bookID: String, pageCount: Int, requestedPage: Int, requestID: Int,
                   loadImage: @escaping @MainActor (Int) async throws -> UIImage,
                   onVisiblePage: @escaping @MainActor (Int, Bool) -> Void) {
        guard !stopped else { return }
        self.loadImage = loadImage
        self.onVisiblePage = onVisiblePage
        let changedBook = self.bookID != bookID || self.pageCount != pageCount
        if changedBook {
            generation += 1
            requests.values.forEach { $0.task.cancel() }
            self.bookID = bookID
            self.pageCount = max(0, pageCount)
            anchor = nil
            lastReportedPage = nil
            if isViewLoaded {
                collectionView.visibleCells.compactMap { $0 as? ContinuousPageCell }.forEach { $0.releaseImage() }
                pageLayout.reset(pageCount: self.pageCount)
                collectionView.reloadData()
            }
        }
        if changedBook || self.requestID != requestID {
            self.requestID = requestID
            pendingJump = self.pageCount > 0 ? min(max(0, requestedPage), self.pageCount - 1) : nil
            lastReportedPage = nil
            if isViewLoaded { view.setNeedsLayout() }
        }
        scheduleVisibleUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !stopped, view.bounds.width > 0, view.bounds.height > 0, !adjustingLayout else { return }
        if pageLayout.viewportSize != view.bounds.size {
            // Keep the same point in the same page across rotation and toolbar changes.
            let previousAnchor = anchor
            adjustingLayout = true
            collectionView.frame = view.bounds
            pageLayout.setViewportSize(view.bounds.size)
            collectionView.layoutIfNeeded()
            if pendingJump == nil, let previousAnchor {
                restore(previousAnchor)
            }
            adjustingLayout = false
        }
        applyPendingJump()
        scheduleVisibleUpdate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleVisibleUpdate()
    }

    func stop() {
        stopped = true
        generation += 1
        requests.values.forEach { $0.task.cancel() }
        requests.removeAll()
        loadImage = nil
        onVisiblePage = nil
        if isViewLoaded {
            collectionView.visibleCells.compactMap { $0 as? ContinuousPageCell }.forEach { $0.releaseImage() }
            collectionView.delegate = nil
            collectionView.dataSource = nil
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { pageCount }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! ContinuousPageCell
        let cellGeneration = generation
        cell.configure(page: indexPath.item, generation: cellGeneration) { [weak self, weak cell] in
            guard let self, self.generation == cellGeneration, let cell,
                  cell.page == indexPath.item else { return }
            cell.showLoading()
            self.scheduleVisibleUpdate()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? ContinuousPageCell, cell.needsImage { cell.showLoading() }
        scheduleVisibleUpdate()
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? ContinuousPageCell else { return }
        for request in requests.values where request.page == cell.page && request.generation == cell.generation {
            request.task.cancel()
        }
        // Reusable cells can remain retained by UICollectionView after leaving the screen.
        cell.releaseImage()
        scheduleVisibleUpdate()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !adjustingLayout, pendingJump == nil else { return }
        anchor = captureAnchor()
        scheduleVisibleUpdate()
    }

    private func scheduleVisibleUpdate() {
        guard !stopped, !updateScheduled else { return }
        updateScheduled = true
        // Neither image completion nor UIKit layout may mutate SwiftUI state inline.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.refreshVisiblePages()
        }
    }

    private func refreshVisiblePages() {
        guard !stopped, isViewLoaded, view.window != nil, !adjustingLayout else { return }
        view.layoutIfNeeded()
        applyPendingJump()
        guard pendingJump == nil, pageLayout.viewportSize.width > 0 else { return }
        collectionView.layoutIfNeeded()
        let visiblePages = collectionView.indexPathsForVisibleItems.map(\.item).sorted()
        let visibleSet = Set(visiblePages)
        anchor = captureAnchor()
        for request in requests.values where request.generation != generation || !visibleSet.contains(request.page) {
            request.task.cancel()
        }
        let viewport = collectionView.bounds
        for page in visiblePages {
            guard let cell = visibleCell(page), let frame = pageLayout.frame(for: page) else { continue }
            let intersection = frame.intersection(viewport)
            cell.setVisibleRegion(intersection.offsetBy(dx: -frame.minX, dy: -frame.minY))
        }

        // Ignore the last few pixels of a departing page when choosing the counter.
        let currentPage = visiblePages.first { page in
            guard let frame = pageLayout.frame(for: page) else { return false }
            let minimumVisibleHeight = min(24, frame.height * 0.1, viewport.height * 0.1)
            return frame.intersection(viewport).height >= minimumVisibleHeight
        } ?? visiblePages.first

        // Prioritize the page being read, then the other genuinely visible cells.
        let orderedPages = currentPage.map { current in [current] + visiblePages.filter { $0 != current } } ?? visiblePages
        for page in orderedPages {
            guard requests.count < 2 else { break }
            guard let cell = visibleCell(page), cell.needsImage,
                  !requests.values.contains(where: { $0.page == page && $0.generation == generation }) else { continue }
            startRequest(page)
        }
        if let currentPage, let cell = visibleCell(currentPage) {
            let loaded = cell.hasImage
            if lastReportedPage != currentPage || lastReportedLoaded != loaded {
                lastReportedPage = currentPage
                lastReportedLoaded = loaded
                onVisiblePage?(currentPage, loaded)
            }
        }
    }

    private func startRequest(_ page: Int) {
        guard let loadImage else { return }
        let token = UUID()
        let requestGeneration = generation
        let task = Task { @MainActor [weak self] in
            let result: Result<UIImage, Error>
            do { result = .success(try await loadImage(page)) }
            catch { result = .failure(error) }
            self?.finishRequest(token, page: page, generation: requestGeneration,
                                result: result, cancelled: Task.isCancelled)
        }
        requests[token] = Request(page: page, generation: requestGeneration, task: task)
    }

    private func finishRequest(_ token: UUID, page: Int, generation: Int,
                               result: Result<UIImage, Error>, cancelled: Bool) {
        requests.removeValue(forKey: token)
        defer { scheduleVisibleUpdate() }
        guard !stopped, !cancelled, generation == self.generation,
              let cell = visibleCell(page), cell.generation == generation else { return }
        switch result {
        case .success(let image):
            guard image.size.width > 0, image.size.height > 0,
                  (image.size.height / image.size.width).isFinite else {
                cell.showError("Immagine non valida.")
                updatePageGeometry { pageLayout.setMinimumHeight(cell.errorHeight + 48, for: page) }
                return
            }
            cell.showImage(image)
            updatePageGeometry {
                pageLayout.setAspectRatio(image.size.height / image.size.width, for: page)
                pageLayout.setMinimumHeight(nil, for: page)
            }
        case .failure(let error):
            cell.showError(error.localizedDescription)
            // Even a failed short banner needs room for its localized retry button.
            updatePageGeometry { pageLayout.setMinimumHeight(cell.errorHeight + 48, for: page) }
        }
    }

    private func updatePageGeometry(_ update: () -> Void) {
        let previousAnchor = captureAnchor()
        adjustingLayout = true
        UIView.performWithoutAnimation {
            update()
            collectionView.layoutIfNeeded()
            if let previousAnchor { restore(previousAnchor) }
        }
        adjustingLayout = false
    }

    private func visibleCell(_ page: Int) -> ContinuousPageCell? {
        let indexPath = IndexPath(item: page, section: 0)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath),
              let cell = collectionView.cellForItem(at: indexPath) as? ContinuousPageCell,
              cell.page == page, cell.generation == generation else { return nil }
        return cell
    }

    private func applyPendingJump() {
        guard let page = pendingJump, pageLayout.viewportSize.width > 0 else { return }
        collectionView.layoutIfNeeded()
        guard let frame = pageLayout.frame(for: page) else { return }
        adjustingLayout = true
        collectionView.setContentOffset(CGPoint(x: 0, y: frame.minY), animated: false)
        collectionView.layoutIfNeeded()
        pendingJump = nil
        anchor = captureAnchor()
        adjustingLayout = false
    }

    private func captureAnchor() -> Anchor? {
        let offset = max(0, collectionView.contentOffset.y)
        guard let page = pageLayout.page(at: offset), let frame = pageLayout.frame(for: page) else { return nil }
        let withinPage = max(0, offset - frame.minY)
        return Anchor(page: page, fraction: min(1, withinPage / max(1, frame.height)))
    }

    private func restore(_ anchor: Anchor) {
        guard let frame = pageLayout.frame(for: anchor.page) else { return }
        let withinPage = frame.height * anchor.fraction
        let maximumOffset = max(0, pageLayout.collectionViewContentSize.height - collectionView.bounds.height)
        collectionView.setContentOffset(CGPoint(x: 0, y: min(maximumOffset, frame.minY + withinPage)), animated: false)
        self.anchor = captureAnchor()
    }
}

/// Stores geometry, never decoded images. Unknown pages use an estimate until displayed.
@MainActor
private final class ContinuousPageLayout: UICollectionViewLayout {
    private(set) var viewportSize = CGSize.zero
    private var pageCount = 0
    private var aspectRatios: [Int: CGFloat] = [:]
    private var minimumHeights: [Int: CGFloat] = [:]
    private var frames: [CGRect] = []
    private var contentSize = CGSize.zero
    private var needsPreparation = true

    func reset(pageCount: Int) {
        self.pageCount = pageCount
        aspectRatios.removeAll()
        minimumHeights.removeAll()
        invalidateLayout()
    }

    func setViewportSize(_ size: CGSize) {
        viewportSize = size
        invalidateLayout()
    }

    func setAspectRatio(_ ratio: CGFloat, for page: Int) {
        guard aspectRatios[page] != ratio else { return }
        aspectRatios[page] = ratio
        invalidateLayout()
    }

    func setMinimumHeight(_ height: CGFloat?, for page: Int) {
        guard minimumHeights[page] != height else { return }
        minimumHeights[page] = height
        invalidateLayout()
    }

    override func invalidateLayout() {
        needsPreparation = true
        super.invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        guard needsPreparation, viewportSize.width > 0 else { return }
        needsPreparation = false
        frames.removeAll(keepingCapacity: true)
        var y: CGFloat = 0
        for page in 0..<pageCount {
            let height = max(minimumHeights[page] ?? 1, viewportSize.width * (aspectRatios[page] ?? 1.5))
            frames.append(CGRect(x: 0, y: y, width: viewportSize.width, height: height))
            y += height
        }
        // A short final page can still align at the top after a resume or explicit jump.
        let lastPageBottom = (frames.last?.minY ?? 0) + viewportSize.height
        contentSize = CGSize(width: viewportSize.width, height: max(y, lastPageBottom))
    }

    override var collectionViewContentSize: CGSize { contentSize }

    func frame(for page: Int) -> CGRect? {
        prepare()
        return frames.indices.contains(page) ? frames[page] : nil
    }

    func page(at y: CGFloat) -> Int? {
        prepare()
        guard !frames.isEmpty else { return nil }
        var lower = 0
        var upper = frames.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if frames[middle].maxY <= y { lower = middle + 1 }
            else { upper = middle }
        }
        return min(lower, frames.count - 1)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let frame = frame(for: indexPath.item) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let first = page(at: rect.minY) else { return [] }
        var attributes: [UICollectionViewLayoutAttributes] = []
        for page in first..<frames.count {
            guard frames[page].minY < rect.maxY else { break }
            if frames[page].intersects(rect), let item = layoutAttributesForItem(at: IndexPath(item: page, section: 0)) {
                attributes.append(item)
            }
        }
        return attributes
    }
}

@MainActor
private final class ContinuousPageCell: UICollectionViewCell {
    private(set) var page = -1
    private(set) var generation = -1
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let errorStack = UIStackView()
    private var retry: (() -> Void)?
    private var visibleRegion: CGRect?
    private var failed = false
    var hasImage: Bool { imageView.image != nil }
    var needsImage: Bool { !hasImage && !failed }
    var errorHeight: CGFloat { fittedErrorSize().height }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "reader-page"
        contentView.addSubview(imageView)
        spinner.color = .white
        contentView.addSubview(spinner)
        errorLabel.textColor = .white
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.numberOfLines = 5
        errorLabel.textAlignment = .center
        retryButton.configuration = .borderedProminent()
        retryButton.setTitle("Riprova", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        errorStack.axis = .vertical
        errorStack.spacing = 16
        errorStack.alignment = .center
        errorStack.addArrangedSubview(errorLabel)
        errorStack.addArrangedSubview(retryButton)
        errorLabel.widthAnchor.constraint(equalTo: errorStack.widthAnchor).isActive = true
        contentView.addSubview(errorStack)
        showLoading()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(page: Int, generation: Int, retry: @escaping () -> Void) {
        self.page = page
        self.generation = generation
        self.retry = retry
        visibleRegion = nil
        accessibilityIdentifier = "continuous-page-\(page)"
        imageView.accessibilityLabel = "Pagina \(page + 1) del libro"
        retryButton.accessibilityIdentifier = "continuous-retry-\(page)"
        retryButton.accessibilityLabel = "Riprova pagina \(page + 1)"
        showLoading()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        releaseImage()
        page = -1
        generation = -1
        retry = nil
        visibleRegion = nil
    }

    func releaseImage() {
        imageView.image = nil
        imageView.isAccessibilityElement = false
        spinner.stopAnimating()
    }

    func showLoading() {
        releaseImage()
        failed = false
        errorStack.isHidden = true
        errorLabel.text = nil
        spinner.startAnimating()
    }

    func showImage(_ image: UIImage) {
        failed = false
        imageView.image = image
        imageView.isAccessibilityElement = true
        spinner.stopAnimating()
        errorStack.isHidden = true
    }

    func showError(_ message: String) {
        releaseImage()
        failed = true
        errorLabel.text = "Impossibile caricare pagina \(page + 1).\n\(message)"
        errorStack.isHidden = false
        setNeedsLayout()
    }

    func setVisibleRegion(_ region: CGRect) {
        guard !region.isNull, !region.isEmpty else { return }
        visibleRegion = region
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        let centerY = visibleRegion?.midY ?? contentView.bounds.midY
        spinner.center = CGPoint(x: contentView.bounds.midX, y: centerY)
        let width = max(1, min(480, contentView.bounds.width - 48))
        let size = fittedErrorSize()
        let y = max(0, min(contentView.bounds.height - size.height, centerY - size.height / 2))
        errorStack.frame = CGRect(x: (contentView.bounds.width - width) / 2, y: y, width: width, height: size.height)
    }

    private func fittedErrorSize() -> CGSize {
        let width = max(1, min(480, contentView.bounds.width - 48))
        return errorStack.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }

    @objc private func retryTapped() { retry?() }
}
