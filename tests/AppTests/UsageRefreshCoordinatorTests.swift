import Foundation
import XCTest
@testable import TokenScope

final class UsageRefreshCoordinatorTests: XCTestCase {
    func testRefreshStoresSuccessfulIngestionResultAndTime() {
        let refreshedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expectedResult = LocalUsageIngestionResult(
            discoveredFileCount: 3,
            parsedFileCount: 2,
            importedSessionCount: 4,
            skippedFileCount: 1
        )
        var refreshCount = 0
        let coordinator = UsageRefreshCoordinator(
            ingest: {
                refreshCount += 1
                return expectedResult
            },
            now: { refreshedAt }
        )

        let snapshot = coordinator.refreshNow()

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(snapshot.lastSucceededAt, refreshedAt)
        XCTAssertEqual(snapshot.lastResult, expectedResult)
        XCTAssertNil(snapshot.lastErrorDescription)
        XCTAssertEqual(snapshot.isRefreshing, false)
        XCTAssertEqual(coordinator.currentSnapshot(), snapshot)
    }

    func testRefreshFailurePreservesPreviousSuccessfulSnapshot() {
        var shouldFail = false
        let coordinator = UsageRefreshCoordinator(
            ingest: {
                if shouldFail {
                    throw TestError.unavailable
                }

                return LocalUsageIngestionResult(importedSessionCount: 2)
            },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let successfulSnapshot = coordinator.refreshNow()
        shouldFail = true

        let failedSnapshot = coordinator.refreshNow()

        XCTAssertEqual(failedSnapshot.lastSucceededAt, successfulSnapshot.lastSucceededAt)
        XCTAssertEqual(failedSnapshot.lastResult, successfulSnapshot.lastResult)
        XCTAssertEqual(failedSnapshot.lastErrorDescription, "Refresh failed: unavailable for testing")
        XCTAssertEqual(failedSnapshot.isRefreshing, false)
    }

    func testCurrentSnapshotDoesNotWaitForInFlightRefresh() {
        let ingestStarted = DispatchSemaphore(value: 0)
        let finishIngest = DispatchSemaphore(value: 0)
        let snapshotRead = expectation(description: "snapshot read")
        let refreshFinished = expectation(description: "refresh finished")
        let coordinator = UsageRefreshCoordinator(
            ingest: {
                ingestStarted.signal()
                _ = finishIngest.wait(timeout: .now() + 2)
                return LocalUsageIngestionResult(importedSessionCount: 1)
            },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        DispatchQueue.global(qos: .utility).async {
            _ = coordinator.refreshNow()
            refreshFinished.fulfill()
        }
        XCTAssertEqual(ingestStarted.wait(timeout: .now() + 1), .success)

        DispatchQueue.global(qos: .utility).async {
            let snapshot = coordinator.currentSnapshot()
            XCTAssertNil(snapshot.lastSucceededAt)
            XCTAssertNil(snapshot.lastResult)
            XCTAssertNil(snapshot.lastErrorDescription)
            XCTAssertEqual(snapshot.isRefreshing, true)
            snapshotRead.fulfill()
        }

        wait(for: [snapshotRead], timeout: 0.5)
        finishIngest.signal()
        wait(for: [refreshFinished], timeout: 1)
    }
}

private enum TestError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? { "unavailable for testing" }
}
