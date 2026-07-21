import XCTest
@testable import TokenScope

final class MenuBarSummaryFormatterTests: XCTestCase {
    private let formatter = MenuBarSummaryFormatter(locale: Locale(identifier: "en_US"))

    func testCostIsDefaultDisplayMode() {
        let presenter = MenuBarSummaryPresenter(
            summaryProvider: InMemoryMenuBarSummaryProvider(snapshot: snapshot()),
            formatter: formatter
        )

        XCTAssertEqual(presenter.displayMode, .cost)
        XCTAssertEqual(presenter.refresh().statusTitle, "$12.35")
    }

    func testFormatsCostDisplayMode() {
        XCTAssertEqual(
            formatter.statusTitle(for: snapshot(totalCost: Decimal(string: "12.345")!), displayMode: .cost),
            "$12.35"
        )
    }

    func testFormatsTokensDisplayMode() {
        XCTAssertEqual(
            formatter.statusTitle(for: snapshot(totalTokens: 1250), displayMode: .tokens),
            "1,250 tokens"
        )
    }

    func testFormatsCostAndTokensDisplayMode() {
        XCTAssertEqual(
            formatter.statusTitle(
                for: snapshot(totalCost: Decimal(string: "2.5")!, totalTokens: 9876),
                displayMode: .costAndTokens
            ),
            "$2.50 · 9,876 tokens"
        )
    }

    func testUnknownCostUsesTokenFallbackForStatusTitle() {
        XCTAssertEqual(
            formatter.statusTitle(for: snapshot(totalCost: nil, totalTokens: 100), displayMode: .cost),
            "100 tokens"
        )
        XCTAssertEqual(
            formatter.statusTitle(for: snapshot(totalCost: nil, totalTokens: 100), displayMode: .costAndTokens),
            "— · 100 tokens"
        )
    }

    func testUnknownCostWithoutTokensUsesPlaceholder() {
        XCTAssertEqual(
            formatter.statusTitle(for: snapshot(totalCost: nil, totalTokens: 0), displayMode: .cost),
            "—"
        )
    }

    private func snapshot(
        totalCost: Decimal? = Decimal(string: "12.345"),
        totalTokens: Int = 1250,
        sessionCount: Int = 3
    ) -> MenuBarSummarySnapshot {
        MenuBarSummarySnapshot(
            totalCost: totalCost,
            totalTokens: totalTokens,
            sessionCount: sessionCount
        )
    }
}
