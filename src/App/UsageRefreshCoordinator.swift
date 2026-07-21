import Foundation

struct UsageRefreshSnapshot: Equatable {
    var lastSucceededAt: Date?
    var lastResult: LocalUsageIngestionResult?
    var lastErrorDescription: String?
    var isRefreshing: Bool

    static let empty = UsageRefreshSnapshot(
        lastSucceededAt: nil,
        lastResult: nil,
        lastErrorDescription: nil,
        isRefreshing: false
    )
}

final class UsageRefreshCoordinator {
    private let ingest: () throws -> LocalUsageIngestionResult
    private let now: () -> Date
    private let snapshotLock = NSLock()
    private var snapshot: UsageRefreshSnapshot = .empty

    init(
        ingest: @escaping () throws -> LocalUsageIngestionResult,
        now: @escaping () -> Date = Date.init
    ) {
        self.ingest = ingest
        self.now = now
    }

    @discardableResult
    func refreshNow() -> UsageRefreshSnapshot {
        snapshotLock.lock()
        snapshot.isRefreshing = true
        snapshotLock.unlock()

        do {
            let refreshedSnapshot = UsageRefreshSnapshot(
                lastSucceededAt: now(),
                lastResult: try ingest(),
                lastErrorDescription: nil,
                isRefreshing: false
            )
            snapshotLock.lock()
            snapshot = refreshedSnapshot
            snapshotLock.unlock()
        } catch {
            snapshotLock.lock()
            snapshot.lastErrorDescription = "Refresh failed: \(error.localizedDescription)"
            snapshot.isRefreshing = false
            snapshotLock.unlock()
        }

        return currentSnapshot()
    }

    func currentSnapshot() -> UsageRefreshSnapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshot
    }
}
