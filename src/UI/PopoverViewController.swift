import AppKit

final class PopoverViewController: NSViewController {
    private let presenter: PopoverSummaryPresenter
    private let onRefresh: () -> PopoverMaintenanceResult?
    private let lastUpdatedText: () -> String
    private let diagnostics: () -> PopoverDiagnostics
    private let diagnosticsPresenter = PopoverDiagnosticsPresenter()
    private let maintenanceActions: PopoverMaintenanceActions
    private let maintenancePresenter = PopoverMaintenancePresenter()
    private let onQuit: () -> Void
    private let contentStack = NSStackView()
    private let contentWidth: CGFloat = 430
    private var maintenanceResult: PopoverMaintenanceResult?

    init(
        presenter: PopoverSummaryPresenter,
        onRefresh: @escaping () -> PopoverMaintenanceResult? = { nil },
        lastUpdatedText: @escaping () -> String = { "Last updated: Never" },
        diagnostics: @escaping () -> PopoverDiagnostics = { .empty },
        maintenanceActions: PopoverMaintenanceActions = .disabled,
        onQuit: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.onRefresh = onRefresh
        self.lastUpdatedText = lastUpdatedText
        self.diagnostics = diagnostics
        self.maintenanceActions = maintenanceActions
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 460, height: 660)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 660))
        view.wantsLayer = true
        view.layer?.backgroundColor = PopoverPalette.background.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureContentStack()
        refresh()
    }

    func refresh() {
        render(presenter.refresh())
    }

    func reload() {
        render(presenter.reload())
    }

    private func render(_ state: PopoverRenderState) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        contentStack.addArrangedSubview(contentSelector(state))

        if state.selectedContent == .system {
            contentStack.addArrangedSubview(systemStatusView())
            contentStack.addArrangedSubview(diagnosticsView(diagnostics()))
            contentStack.addArrangedSubview(maintenanceControls())
        } else {
            contentStack.addArrangedSubview(rangeSelector(state))
            if let refreshWarningText = state.refreshWarningText {
                contentStack.addArrangedSubview(refreshWarningLabel(refreshWarningText))
            }
            contentStack.addArrangedSubview(summaryGrid(state))

            for section in state.sections {
                contentStack.addArrangedSubview(sectionView(section))
            }

            contentStack.addArrangedSubview(lastUpdatedLabel())
        }
        contentStack.addArrangedSubview(footerControls(quitTitle: state.footerTitle))
    }

    private func configureContentStack() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = PopoverPalette.background
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = PopoverPalette.background.cgColor
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -12)
        ])
    }

    private func rangeSelector(_ state: PopoverRenderState) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["Total", "Today", "7d"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(rangeChanged(_:))
        )
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegment = selectedSegment(for: state.selectedRange)
        control.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        for segment in 0..<control.segmentCount {
            control.setWidth(contentWidth / CGFloat(control.segmentCount), forSegment: segment)
        }

        return control
    }

    private func contentSelector(_ state: PopoverRenderState) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["Overview", "Providers", "Activity", "System"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(contentChanged(_:))
        )
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegment = selectedSegment(for: state.selectedContent)
        control.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        for segment in 0..<control.segmentCount {
            control.setWidth(contentWidth / CGFloat(control.segmentCount), forSegment: segment)
        }

        return control
    }

    private func summaryGrid(_ state: PopoverRenderState) -> NSView {
        let grid = NSGridView(views: [
            [metricTitle("Cost"), metricTitle("Tokens"), metricTitle("Sessions")],
            [metricValue(state.totalCostText), metricValue(state.totalTokensText), metricValue(state.sessionCountText)]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 3
        grid.translatesAutoresizingMaskIntoConstraints = false

        for column in 0..<grid.numberOfColumns {
            grid.column(at: column).xPlacement = .leading
            grid.column(at: column).width = 132
        }

        return grid
    }

    private func sectionView(_ section: PopoverSectionRenderState) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = label(section.title, font: .boldSystemFont(ofSize: 12), color: sectionTitleColor(section.title))
        title.toolTip = sectionTitleTooltip(section.title)
        stack.addArrangedSubview(title)

        if section.rows.isEmpty {
            stack.addArrangedSubview(label(section.emptyText, font: .systemFont(ofSize: 12), color: PopoverPalette.mutedText))
        } else {
            for row in section.rows {
                stack.addArrangedSubview(rowView(row, in: section.title))
            }
        }

        stack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return stack
    }

    private func rowView(_ row: PopoverRowRenderState, in sectionTitle: String) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = rowBackgroundColor(sectionTitle: sectionTitle, selected: row.isSelected).cgColor
        container.layer?.cornerRadius = 6
        if row.isSelected {
            container.layer?.borderColor = PopoverPalette.accent.cgColor
            container.layer?.borderWidth = 1
        }

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let title = label(row.title, font: .systemFont(ofSize: 12), color: PopoverPalette.primaryText)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = label(row.detail, font: .systemFont(ofSize: 11), color: PopoverPalette.secondaryText)
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(detail)

        let value = label(row.value, font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: valueColor(sectionTitle))
        value.alignment = .right
        value.lineBreakMode = .byTruncatingMiddle
        value.maximumNumberOfLines = 1
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        container.addArrangedSubview(textStack)
        container.addArrangedSubview(value)
        textStack.widthAnchor.constraint(equalToConstant: 292).isActive = true
        value.widthAnchor.constraint(equalToConstant: 118).isActive = true
        container.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        if let action = row.action {
            container.addGestureRecognizer(PopoverRowGestureRecognizer(
                rowAction: action,
                target: self,
                action: #selector(rowActionSelected(_:))
            ))
        }

        return container
    }

    private func refreshWarningLabel(_ text: String) -> NSTextField {
        let field = label(text, font: .systemFont(ofSize: 11, weight: .medium), color: .systemRed)
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        field.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return field
    }

    private func lastUpdatedLabel() -> NSTextField {
        label(lastUpdatedText(), font: .systemFont(ofSize: 11), color: PopoverPalette.mutedText)
    }

    private func systemStatusView() -> NSView {
        sectionView(PopoverSectionRenderState(
            title: "Status",
            rows: [
                PopoverRowRenderState(
                    title: "Refresh",
                    detail: lastUpdatedText(),
                    value: "Local"
                )
            ],
            emptyText: "No status"
        ))
    }

    private func diagnosticsView(_ diagnostics: PopoverDiagnostics) -> NSView {
        sectionView(diagnosticsPresenter.section(for: diagnostics))
    }

    private func footerControls(quitTitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh Now", target: self, action: #selector(refreshNow))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.toolTip = "Rescan local logs now"

        let quitButton = NSButton(title: quitTitle, target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small

        stack.addArrangedSubview(refreshButton)
        stack.addArrangedSubview(quitButton)
        stack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true

        return stack
    }

    private func maintenanceControls() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label("Maintenance", font: .boldSystemFont(ofSize: 12), color: .secondaryLabelColor))

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let rebuildButton = NSButton(title: "Rebuild Database", target: self, action: #selector(rebuildDatabase))
        rebuildButton.bezelStyle = .rounded
        rebuildButton.controlSize = .small
        rebuildButton.toolTip = "Clears the local database and rescans all logs"

        let clearButton = NSButton(title: "Clear Data", target: self, action: #selector(clearLocalData))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.toolTip = "Deletes all locally stored usage data"

        let openButton = NSButton(title: "Open DB", target: self, action: #selector(openDatabaseLocation))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.toolTip = "Reveals the SQLite database file in Finder"

        buttonStack.addArrangedSubview(rebuildButton)
        buttonStack.addArrangedSubview(clearButton)
        buttonStack.addArrangedSubview(openButton)
        stack.addArrangedSubview(buttonStack)

        if let maintenanceResult {
            stack.addArrangedSubview(rowView(maintenancePresenter.row(for: maintenanceResult), in: "Maintenance"))
        }

        stack.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return stack
    }

    private func metricTitle(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 11), color: PopoverPalette.secondaryText)
    }

    private func metricValue(_ text: String) -> NSTextField {
        let field = label(text, font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold), color: PopoverPalette.primaryText)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func sectionTitleTooltip(_ sectionTitle: String) -> String? {
        switch sectionTitle {
        case "Waste Signals":
            return "Patterns that burned tokens without adding value"
        case "Optimization Tips":
            return "Suggestions to reduce token spend"
        default:
            return nil
        }
    }

    private func sectionTitleColor(_ sectionTitle: String) -> NSColor {
        switch sectionTitle {
        case "Waste Signals":
            return PopoverPalette.warningText
        case "Optimization Tips":
            return PopoverPalette.successText
        case "Session Insights", "Session Detail":
            return PopoverPalette.infoText
        case "Diagnostics", "Maintenance", "Status":
            return PopoverPalette.secondaryText
        default:
            return PopoverPalette.secondaryText
        }
    }

    private func rowBackgroundColor(sectionTitle: String, selected: Bool) -> NSColor {
        if selected {
            return PopoverPalette.selectedBackground
        }

        switch sectionTitle {
        case "Waste Signals":
            return PopoverPalette.warningBackground
        case "Optimization Tips":
            return PopoverPalette.successBackground
        case "Session Insights", "Session Detail":
            return PopoverPalette.infoBackground
        case "No Sessions":
            return PopoverPalette.neutralBackground
        case "Diagnostics", "Maintenance", "Status":
            return PopoverPalette.systemBackground
        default:
            return PopoverPalette.rowBackground
        }
    }

    private func valueColor(_ sectionTitle: String) -> NSColor {
        switch sectionTitle {
        case "Waste Signals":
            return PopoverPalette.warningText
        case "Optimization Tips":
            return PopoverPalette.successText
        case "Session Insights", "Session Detail":
            return PopoverPalette.infoText
        default:
            return PopoverPalette.primaryText
        }
    }

    @objc private func quit() {
        onQuit()
    }

    @objc private func refreshNow() {
        maintenanceResult = onRefresh() ?? .refreshed(nil)
        reload()
    }

    @objc private func rebuildDatabase() {
        guard confirm(
            title: "Rebuild Database?",
            message: "TokenScope will clear its local database and re-scan local Claude and Codex logs."
        ) else {
            return
        }

        do {
            maintenanceResult = try maintenanceActions.rebuildDatabase()
            refresh()
        } catch {
            showMaintenanceError("Rebuild failed")
        }
    }

    @objc private func clearLocalData() {
        guard confirm(
            title: "Clear Local Data?",
            message: "TokenScope will remove stored sessions and ingestion state. The next refresh can re-import local logs."
        ) else {
            return
        }

        do {
            maintenanceResult = try maintenanceActions.clearLocalData()
            refresh()
        } catch {
            showMaintenanceError("Clear failed")
        }
    }

    @objc private func openDatabaseLocation() {
        maintenanceResult = maintenanceActions.openDatabaseLocation()
        refresh()
    }

    @objc private func rowActionSelected(_ recognizer: PopoverRowGestureRecognizer) {
        switch recognizer.rowAction {
        case .selectSessionDetail(let detailID):
            _ = presenter.selectSessionDetail(detailID)
        }

        refresh()
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        presenter.selectedRange = range(for: sender.selectedSegment)
        refresh()
    }

    @objc private func contentChanged(_ sender: NSSegmentedControl) {
        presenter.selectedContent = content(for: sender.selectedSegment)
        refresh()
    }

    private func selectedSegment(for range: PopoverTimeRange) -> Int {
        switch range {
        case .total:
            return 0
        case .today:
            return 1
        case .customLastDays:
            return 2
        }
    }

    private func selectedSegment(for content: PopoverContentView) -> Int {
        switch content {
        case .overview:
            return 0
        case .providers:
            return 1
        case .activity:
            return 2
        case .system:
            return 3
        }
    }

    private func range(for selectedSegment: Int) -> PopoverTimeRange {
        switch selectedSegment {
        case 0:
            return .total
        case 1:
            return .today
        default:
            return .customLastDays(7)
        }
    }

    private func content(for selectedSegment: Int) -> PopoverContentView {
        switch selectedSegment {
        case 1:
            return .providers
        case 2:
            return .activity
        case 3:
            return .system
        default:
            return .overview
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showMaintenanceError(_ message: String) {
        maintenanceResult = .failed(message)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "The database was not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        refresh()
    }

}

private final class PopoverRowGestureRecognizer: NSClickGestureRecognizer {
    let rowAction: PopoverRowAction

    init(rowAction: PopoverRowAction, target: AnyObject?, action: Selector?) {
        self.rowAction = rowAction
        super.init(target: target, action: action)
        numberOfClicksRequired = 1
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private enum PopoverPalette {
    static let background = NSColor.windowBackgroundColor
    static let rowBackground = NSColor.controlBackgroundColor
    static let selectedBackground = NSColor.controlAccentColor.withAlphaComponent(0.18)
    static let warningBackground = NSColor.systemYellow.withAlphaComponent(0.18)
    static let successBackground = NSColor.systemGreen.withAlphaComponent(0.16)
    static let infoBackground = NSColor.systemBlue.withAlphaComponent(0.16)
    static let neutralBackground = NSColor.underPageBackgroundColor
    static let systemBackground = NSColor.systemPurple.withAlphaComponent(0.12)

    static let primaryText = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let mutedText = NSColor.tertiaryLabelColor
    static let warningText = NSColor.systemOrange
    static let successText = NSColor.systemGreen
    static let infoText = NSColor.systemBlue
    static let accent = NSColor.controlAccentColor
}
