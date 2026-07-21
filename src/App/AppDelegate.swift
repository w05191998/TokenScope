import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let storageContext = AppDelegate.makeStorageContext()
    private let refreshQueue = DispatchQueue(label: "TokenScope.refresh", qos: .utility)
    private let refreshScheduleLock = NSLock()
    private var automaticRefreshRunning = false
    private var automaticRefreshPending = false
    private var refreshTimer: Timer?
    private lazy var refreshCoordinator = UsageRefreshCoordinator(
        ingest: { [storage = storageContext.storage] in
            try LocalUsageIngestionService(
                normalizer: RawUsageNormalizer(),
                storage: storage
            ).ingest()
        }
    )
    private lazy var lastUpdatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            summaryProvider: StorageBackedMenuBarSummaryProvider(sessionReader: storageContext.storage),
            popoverProvider: StorageBackedPopoverSummaryProvider(
                sessionReader: storageContext.storage,
                toolEventReader: storageContext.storage
            ),
            onRefresh: { [weak self] in
                self?.refreshMaintenanceResult()
            },
            lastUpdatedText: { [weak self] in
                self?.lastUpdatedText() ?? "Last updated: Never"
            },
            diagnostics: { [weak self] in
                self?.diagnostics() ?? .empty
            },
            refreshErrorText: { [weak self] in
                self?.refreshCoordinator.currentSnapshot().lastErrorDescription
            },
            maintenanceActions: PopoverMaintenanceActions(
                rebuildDatabase: { [weak self] in
                    guard let self else {
                        return .unavailable
                    }
                    return try self.rebuildDatabase()
                },
                clearLocalData: { [weak self] in
                    guard let self else {
                        return .unavailable
                    }
                    return try self.clearLocalData()
                },
                openDatabaseLocation: { [weak self] in
                    self?.openDatabaseLocation() ?? .openedDatabaseLocation(false)
                }
            )
        )

        scheduleRefreshUsage()
        startRefreshTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.scheduleRefreshUsage()
        }
        refreshTimer?.tolerance = 10
    }

    private func scheduleRefreshUsage() {
        refreshScheduleLock.lock()
        if automaticRefreshRunning {
            automaticRefreshPending = true
            refreshScheduleLock.unlock()
            return
        }

        automaticRefreshRunning = true
        refreshScheduleLock.unlock()
        enqueueAutomaticRefresh()
    }

    private func enqueueAutomaticRefresh() {
        refreshQueue.async { [weak self] in
            guard let self else {
                return
            }

            _ = refreshCoordinator.refreshNow()

            DispatchQueue.main.async { [weak self] in
                self?.menuBarController?.refresh()
                self?.finishAutomaticRefresh()
            }
        }
    }

    private func finishAutomaticRefresh() {
        refreshScheduleLock.lock()
        if automaticRefreshPending {
            automaticRefreshPending = false
            refreshScheduleLock.unlock()
            enqueueAutomaticRefresh()
        } else {
            automaticRefreshRunning = false
            refreshScheduleLock.unlock()
        }
    }

    @discardableResult
    private func refreshUsage() -> UsageRefreshSnapshot {
        let snapshot = refreshQueue.sync {
            refreshCoordinator.refreshNow()
        }
        menuBarController?.refresh()
        return snapshot
    }

    private func refreshMaintenanceResult() -> PopoverMaintenanceResult {
        let snapshot = refreshUsage()
        return .refreshed(snapshot.lastResult)
    }

    private func lastUpdatedText() -> String {
        guard let lastSucceededAt = refreshCoordinator.currentSnapshot().lastSucceededAt else {
            return "Last updated: Never"
        }

        return "Last updated: \(lastUpdatedFormatter.string(from: lastSucceededAt))"
    }

    private func diagnostics() -> PopoverDiagnostics {
        let snapshot = refreshCoordinator.currentSnapshot()
        let refreshSummary: String

        if snapshot.isRefreshing {
            refreshSummary = "Refreshing local logs..."
        } else if let result = snapshot.lastResult {
            refreshSummary = "Discovered \(result.discoveredFileCount) · Parsed \(result.parsedFileCount) · Unchanged \(result.unchangedFileCount) · Skipped \(result.skippedFileCount)"
        } else {
            refreshSummary = "No refresh yet"
        }

        return PopoverDiagnostics(
            storageMode: storageContext.mode,
            databaseLocation: storageContext.databaseURL?.path,
            pricingCatalogVersion: PricingCatalog.sourceVersion,
            refreshSummary: refreshSummary,
            refreshError: snapshot.lastErrorDescription
        )
    }

    private func rebuildDatabase() throws -> PopoverMaintenanceResult {
        let snapshot = try refreshQueue.sync {
            try storageContext.storage.clearAllData()
            return refreshCoordinator.refreshNow()
        }
        menuBarController?.refresh()
        return .rebuilt(snapshot.lastResult)
    }

    private func clearLocalData() throws -> PopoverMaintenanceResult {
        let removedSessionCount = try refreshQueue.sync {
            let count = (try? storageContext.storage.menuBarSessions().count) ?? 0
            try storageContext.storage.clearAllData()
            return count
        }
        menuBarController?.refresh()
        return .cleared(removedSessionCount: removedSessionCount)
    }

    private func openDatabaseLocation() -> PopoverMaintenanceResult {
        guard let databaseURL = storageContext.databaseURL else {
            return .openedDatabaseLocation(false)
        }

        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
        return .openedDatabaseLocation(true)
    }

    private static func makeStorageContext() -> StorageContext {
        do {
            let databaseURL = try SQLiteSpendStorage.defaultDatabaseURL()
            return StorageContext(
                storage: try SQLiteSpendStorage(databaseURL: databaseURL),
                mode: "SQLite",
                databaseURL: databaseURL
            )
        } catch {
            return StorageContext(
                storage: InMemorySpendStorage(),
                mode: "In-memory fallback",
                databaseURL: nil
            )
        }
    }
}

private struct StorageContext {
    var storage: any SpendStoring & SpendMaintenance & MenuBarSessionReading & PopoverSessionReading & PopoverToolEventReading
    var mode: String
    var databaseURL: URL?
}
