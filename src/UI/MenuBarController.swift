import AppKit

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let presenter: MenuBarSummaryPresenter
    private let popoverPresenter: PopoverSummaryPresenter
    private let popover: NSPopover
    private let onRefresh: () -> PopoverMaintenanceResult?
    private let lastUpdatedText: () -> String
    private let diagnostics: () -> PopoverDiagnostics
    private let maintenanceActions: PopoverMaintenanceActions

    init(
        statusBar: NSStatusBar = .system,
        displayMode: MenuBarSummaryDisplayMode = .cost,
        summaryProvider: MenuBarSummaryProviding = InMemoryMenuBarSummaryProvider(),
        popoverProvider: PopoverSummaryProviding = InMemoryPopoverSummaryProvider(),
        onRefresh: @escaping () -> PopoverMaintenanceResult? = { nil },
        lastUpdatedText: @escaping () -> String = { "Last updated: Never" },
        diagnostics: @escaping () -> PopoverDiagnostics = { .empty },
        refreshErrorText: @escaping () -> String? = { nil },
        maintenanceActions: PopoverMaintenanceActions = .disabled
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        presenter = MenuBarSummaryPresenter(
            displayMode: displayMode,
            summaryProvider: summaryProvider
        )
        popoverPresenter = PopoverSummaryPresenter(summaryProvider: popoverProvider, refreshErrorText: refreshErrorText)
        popover = NSPopover()
        self.onRefresh = onRefresh
        self.lastUpdatedText = lastUpdatedText
        self.diagnostics = diagnostics
        self.maintenanceActions = maintenanceActions
        configureStatusItem()
        configurePopover()
        refresh()
    }

    private func configureStatusItem() {
        statusItem.button?.toolTip = "TokenScope"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        if let image = NSImage(systemSymbolName: "scope", accessibilityDescription: "TokenScope") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageLeading
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentViewController = PopoverViewController(
            presenter: popoverPresenter,
            onRefresh: onRefresh,
            lastUpdatedText: lastUpdatedText,
            diagnostics: diagnostics,
            maintenanceActions: maintenanceActions,
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    func refresh() {
        popoverPresenter.invalidateCache()
        apply(presenter.refresh())

        if popover.isShown {
            (popover.contentViewController as? PopoverViewController)?.refresh()
        }
    }

    private func apply(_ renderState: MenuBarRenderState) {
        statusItem.button?.title = renderState.statusTitle
        statusItem.menu = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        (popover.contentViewController as? PopoverViewController)?.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
