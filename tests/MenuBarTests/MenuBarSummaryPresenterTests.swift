import XCTest
@testable import TokenScope

final class MenuBarSummaryPresenterTests: XCTestCase {
    func testRefreshRendersMenuItemsFromCurrentSummary() {
        let provider = InMemoryMenuBarSummaryProvider(snapshot: MenuBarSummarySnapshot(
            totalCost: Decimal(string: "3.21"),
            totalTokens: 4321,
            sessionCount: 2
        ))
        let presenter = MenuBarSummaryPresenter(
            summaryProvider: provider,
            formatter: MenuBarSummaryFormatter(locale: Locale(identifier: "en_US"))
        )

        let state = presenter.refresh()

        XCTAssertEqual(state.statusTitle, "$3.21")
        XCTAssertEqual(state.menuItems, [
            .item("TokenScope"),
            .separator,
            .item("Today Cost: $3.21 estimated"),
            .item("Today Tokens: 4,321 tokens"),
            .item("Sessions Today: 2 sessions"),
            .separator,
            .quit("Quit")
        ])
    }

    func testRefreshUsesLatestProviderSnapshot() {
        let provider = InMemoryMenuBarSummaryProvider(snapshot: MenuBarSummarySnapshot(
            totalCost: Decimal(string: "1.00"),
            totalTokens: 100,
            sessionCount: 1
        ))
        let presenter = MenuBarSummaryPresenter(
            displayMode: .tokens,
            summaryProvider: provider,
            formatter: MenuBarSummaryFormatter(locale: Locale(identifier: "en_US"))
        )

        XCTAssertEqual(presenter.refresh().statusTitle, "100 tokens")

        provider.snapshot = MenuBarSummarySnapshot(
            totalCost: Decimal(string: "2.00"),
            totalTokens: 2500,
            sessionCount: 4
        )

        let refreshedState = presenter.refresh()

        XCTAssertEqual(refreshedState.statusTitle, "2,500 tokens")
        XCTAssertTrue(refreshedState.menuItems.contains(.item("Today Cost: $2.00 estimated")))
        XCTAssertTrue(refreshedState.menuItems.contains(.item("Sessions Today: 4 sessions")))
    }

    func testStorageBackedProviderSummarizesTodaySessionsOnly() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "today-1",
                startTime: today,
                inputTokens: 100,
                outputTokens: 25,
                totalTokens: 125,
                estimatedCost: Decimal(string: "1.25")
            ),
            makeSession(
                id: "today-2",
                startTime: today.addingTimeInterval(60),
                inputTokens: 50,
                outputTokens: 10,
                totalTokens: nil,
                estimatedCost: Decimal(string: "0.75")
            ),
            makeSession(
                id: "yesterday",
                startTime: yesterday,
                inputTokens: 999,
                outputTokens: 999,
                totalTokens: 1998,
                estimatedCost: Decimal(string: "9.99")
            )
        ]))

        let provider = StorageBackedMenuBarSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        XCTAssertEqual(
            try provider.currentSummary(),
            MenuBarSummarySnapshot(
                totalCost: Decimal(string: "2.00"),
                totalTokens: 185,
                sessionCount: 2,
                refreshedAt: today
            )
        )
    }

    func testStorageBackedProviderKeepsUnknownCostUnknown() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(id: "today", startTime: today, inputTokens: 100, outputTokens: 20)
        ]))

        let provider = StorageBackedMenuBarSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        XCTAssertEqual(
            try provider.currentSummary(),
            MenuBarSummarySnapshot(
                totalCost: nil,
                totalTokens: 120,
                sessionCount: 1,
                refreshedAt: today
            )
        )
    }

    func testRefreshHandlesProviderFailureWithoutExposingDetails() {
        let presenter = MenuBarSummaryPresenter(summaryProvider: ThrowingSummaryProvider())

        let state = presenter.refresh()

        XCTAssertEqual(state.statusTitle, "TokenScope")
        XCTAssertEqual(state.menuItems, [
            .item("TokenScope"),
            .separator,
            .item("Summary unavailable"),
            .separator,
            .quit("Quit")
        ])
    }

    private func makeSession(
        id: String,
        startTime: Date,
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int? = nil,
        estimatedCost: Decimal? = nil
    ) -> NormalizedSession {
        NormalizedSession(
            id: id,
            provider: .claude,
            model: "test-model",
            projectPath: "/Users/example/project",
            projectName: "project",
            sessionId: "provider-\(id)",
            startTime: startTime,
            endTime: nil,
            durationSeconds: nil,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCost: estimatedCost,
            rawSourcePath: "/Users/example/.claude/log.jsonl"
        )
    }
}

private struct ThrowingSummaryProvider: MenuBarSummaryProviding {
    func currentSummary() throws -> MenuBarSummarySnapshot {
        throw TestError.unavailable
    }
}

private enum TestError: Error {
    case unavailable
}
