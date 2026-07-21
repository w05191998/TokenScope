import XCTest
@testable import TokenScope

final class PopoverSummaryPresenterTests: XCTestCase {
    func testStorageBackedProviderBuildsTodaySummaryFromNormalizedSessions() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "claude-1",
                provider: .claude,
                model: "opus",
                projectName: "Monitor",
                startTime: today,
                inputTokens: 100,
                outputTokens: 50,
                totalTokens: 160,
                estimatedCost: Decimal(string: "3.25")
            ),
            makeSession(
                id: "codex-1",
                provider: .codex,
                model: "gpt-5",
                projectName: "Monitor",
                startTime: today.addingTimeInterval(60),
                inputTokens: 200,
                outputTokens: 25,
                totalTokens: nil,
                estimatedCost: Decimal(string: "1.75")
            ),
            makeSession(
                id: "old",
                provider: .codex,
                model: "gpt-5",
                projectName: "Old",
                startTime: yesterday,
                inputTokens: 999,
                outputTokens: 999,
                totalTokens: 1998,
                estimatedCost: Decimal(string: "9.99")
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.totalCost, Decimal(string: "5.00"))
        XCTAssertEqual(snapshot.totalTokens, 385)
        XCTAssertEqual(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.rangeTitle, "Today")
        XCTAssertEqual(snapshot.tokenPhases.map(\.name), ["Prompt/context", "Output"])
        XCTAssertEqual(snapshot.providerSections.map(\.providerName), ["Claude", "Codex"])
        XCTAssertEqual(snapshot.providerBreakdown.map(\.name), ["Claude", "Codex"])
        XCTAssertEqual(snapshot.modelBreakdown.map(\.name), ["opus", "gpt-5"])
        XCTAssertEqual(snapshot.projectBreakdown, [
            PopoverBreakdownItem(
                name: "Monitor",
                cost: Decimal(string: "5.00"),
                tokens: 385,
                sessionCount: 2
            )
        ])
        XCTAssertEqual(snapshot.mostExpensiveSessions.map(\.projectName), ["Monitor", "Monitor"])
        XCTAssertEqual(snapshot.timeline.map(\.providerName), ["Codex", "Claude"])
        XCTAssertEqual(snapshot.timeline.map(\.tokens), [225, 160])
        XCTAssertEqual(snapshot.refreshedAt, today)
    }

    func testStorageBackedProviderFiltersTotalTodayAndCustomRange() throws {
        let storage = InMemorySpendStorage()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "today",
                provider: .claude,
                model: "opus",
                projectName: "Today",
                startTime: now,
                inputTokens: 10,
                outputTokens: 5,
                estimatedCost: Decimal(string: "0.15")
            ),
            makeSession(
                id: "week",
                provider: .codex,
                model: "gpt-5.5",
                projectName: "Week",
                startTime: now.addingTimeInterval(-3 * 86_400),
                inputTokens: 20,
                outputTokens: 5,
                estimatedCost: Decimal(string: "0.25")
            ),
            makeSession(
                id: "old",
                provider: .claude,
                model: "opus",
                projectName: "Old",
                startTime: now.addingTimeInterval(-10 * 86_400),
                inputTokens: 30,
                outputTokens: 5,
                estimatedCost: Decimal(string: "0.35")
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { now }
        )

        XCTAssertEqual(try provider.currentPopoverSummary(range: .today).sessionCount, 1)
        XCTAssertEqual(try provider.currentPopoverSummary(range: .customLastDays(7)).sessionCount, 2)
        XCTAssertEqual(try provider.currentPopoverSummary(range: .total).sessionCount, 3)
    }

    func testTimelineUsesMostRecentFirstWithDeterministicTies() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let sharedStart = today.addingTimeInterval(-60)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "later",
                provider: .codex,
                model: "gpt-5",
                projectName: "Zulu",
                startTime: today,
                inputTokens: 50,
                outputTokens: 10,
                estimatedCost: Decimal(string: "0.20")
            ),
            makeSession(
                id: "tie-b",
                provider: .codex,
                model: "gpt-5",
                projectName: "Bravo",
                startTime: sharedStart,
                inputTokens: 30,
                outputTokens: 5,
                estimatedCost: nil
            ),
            makeSession(
                id: "tie-a",
                provider: .claude,
                model: "opus",
                projectName: "Alpha",
                startTime: sharedStart,
                inputTokens: 20,
                outputTokens: 5,
                estimatedCost: Decimal(string: "0.10")
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let timeline = try provider.currentPopoverSummary(range: .today).timeline

        XCTAssertEqual(timeline.map(\.projectName), ["Zulu", "Alpha", "Bravo"])
        XCTAssertEqual(timeline.map(\.providerName), ["Codex", "Claude", "Codex"])
        XCTAssertEqual(timeline.map(\.modelName), ["gpt-5", "opus", "gpt-5"])
        XCTAssertEqual(timeline.map(\.cost), [Decimal(string: "0.20"), Decimal(string: "0.10"), nil])
        XCTAssertEqual(timeline.map(\.tokens), [60, 25, 35])
        XCTAssertEqual(timeline.map(\.startTime), [today, sharedStart, sharedStart])
    }

    func testDisplaySessionsAreCollapsedByProviderSession() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "turn-1",
                provider: .claude,
                model: "opus",
                projectName: "Monitor",
                sessionId: "claude-session-1",
                startTime: today.addingTimeInterval(-60),
                inputTokens: 60_000,
                outputTokens: 2_000,
                estimatedCost: Decimal(string: "0.50")
            ),
            makeSession(
                id: "turn-2",
                provider: .claude,
                model: "opus",
                projectName: "Monitor",
                sessionId: "claude-session-1",
                startTime: today,
                inputTokens: 50_000,
                outputTokens: 3_000,
                estimatedCost: Decimal(string: "0.40")
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.totalTokens, 115_000)
        XCTAssertEqual(snapshot.sessionCount, 1)
        XCTAssertEqual(snapshot.timeline.map(\.projectName), ["Monitor"])
        XCTAssertEqual(snapshot.timeline.map(\.tokens), [115_000])
        XCTAssertEqual(snapshot.mostExpensiveSessions.map(\.tokens), [115_000])
        XCTAssertEqual(snapshot.sessionInsights.map(\.reason), ["Large session over 100k tokens"])
    }

    func testUnknownCostStaysUnknownAndExpensiveSessionsRequireCost() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "unknown",
                provider: .claude,
                model: "opus",
                projectName: "NoCost",
                startTime: today,
                inputTokens: 10,
                outputTokens: 5,
                estimatedCost: nil
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertNil(snapshot.totalCost)
        XCTAssertNil(snapshot.providerBreakdown.first?.cost)
        XCTAssertEqual(snapshot.totalTokens, 15)
        XCTAssertEqual(snapshot.mostExpensiveSessions, [])
        XCTAssertEqual(snapshot.timeline.map(\.projectName), ["NoCost"])
        XCTAssertEqual(snapshot.timeline.first?.cost, nil)
    }

    func testStorageBackedProviderBuildsTokenAnalysisAndWasteSignals() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(sessions: [
            makeSession(
                id: "large-context",
                provider: .claude,
                model: "opus",
                projectName: "Monitor",
                startTime: today,
                inputTokens: 120_000,
                cacheCreationInputTokens: 40_000,
                cacheReadInputTokens: 20_000,
                outputTokens: 10_000,
                estimatedCost: Decimal(string: "2.00")
            ),
            makeSession(
                id: "codex-cached",
                provider: .codex,
                model: "gpt-5-codex",
                projectName: "Monitor",
                startTime: today.addingTimeInterval(60),
                inputTokens: 50_000,
                cacheReadInputTokens: 30_000,
                outputTokens: 5_000,
                estimatedCost: Decimal(string: "0.50")
            )
        ]))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.tokenPhases, [
            PopoverTokenPhase(
                name: "Prompt/context",
                detail: "Base input, tools, files, and instructions",
                tokens: 140_000,
                percentage: 57
            ),
            PopoverTokenPhase(
                name: "Cache writes",
                detail: "New context prepared for reuse",
                tokens: 40_000,
                percentage: 16
            ),
            PopoverTokenPhase(
                name: "Cache reads",
                detail: "Previously cached context reused",
                tokens: 50_000,
                percentage: 20
            ),
            PopoverTokenPhase(
                name: "Output",
                detail: "Generated answer, code, and reasoning output",
                tokens: 15_000,
                percentage: 6
            )
        ])
        XCTAssertEqual(snapshot.wasteSignals.map(\.title), ["Input-heavy sessions", "Large sessions"])
        XCTAssertEqual(snapshot.optimizationTips.prefix(3).map(\.title), [
            "Split the session",
            "Trim carried context",
            "Stabilize reusable context"
        ])
        XCTAssertEqual(snapshot.sessionInsights.map(\.reason), [
            "Large session over 100k tokens",
            "Most tokens are prompt/context"
        ])
        XCTAssertEqual(snapshot.sessionInsights.first?.recommendation, "Split work into smaller passes and keep only current files in context")
        XCTAssertEqual(snapshot.sessionDetails.first?.optimizationTips, [
            PopoverOptimizationTip(
                title: "Split the session",
                detail: "Run analysis, edit, and verification as separate passes",
                valueText: "Large"
            ),
            PopoverOptimizationTip(
                title: "Trim carried context",
                detail: "Keep only current files, active errors, and recent decisions",
                valueText: "94%"
            ),
            PopoverOptimizationTip(
                title: "Stabilize reusable context",
                detail: "Keep setup text unchanged so cache reads replace cache writes",
                valueText: "21%"
            )
        ])
    }

    func testStorageBackedProviderFlagsRepeatedFileReads() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let targetPath = "/Users/example/Monitor/Sources/App.swift"

        try storage.upsert(NormalizedUsageBatch(
            sessions: [
                makeSession(
                    id: "repeat-reader",
                    provider: .claude,
                    model: "opus",
                    projectName: "Monitor",
                    sessionId: "provider-repeat-reader",
                    startTime: today,
                    inputTokens: 1_000,
                    outputTokens: 200
                )
            ],
            toolEvents: [
                makeToolEvent(
                    id: "read-1",
                    sessionId: "provider-repeat-reader",
                    timestamp: today,
                    targetPath: targetPath,
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "read-2",
                    sessionId: "provider-repeat-reader",
                    timestamp: today.addingTimeInterval(5),
                    toolName: "Bash",
                    command: "sed -n '1,120p' Sources/App.swift",
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "read-3",
                    sessionId: "provider-repeat-reader",
                    timestamp: today.addingTimeInterval(10),
                    toolName: "exec_command",
                    command: "cat ./Sources/App.swift",
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(id: "old-read", sessionId: "provider-repeat-reader", timestamp: today.addingTimeInterval(-86_400), targetPath: targetPath)
            ]
        ))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            toolEventReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.wasteSignals.first, PopoverWasteSignal(
            title: "Repeated file reads",
            detail: "Claude · App.swift read 3x · Fix: keep a file summary",
            tokens: 0,
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.optimizationTips.first, PopoverOptimizationTip(
            title: "Avoid rereading stable files",
            detail: "Keep App.swift summary in context; ask for diffs only",
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.sessionInsights.first?.reason, "Repeated file reads")
        XCTAssertEqual(snapshot.sessionInsights.first?.valueText, "3x")
        XCTAssertEqual(snapshot.sessionDetails.first?.toolSignals, [
            PopoverSessionToolSignal(
                title: "Repeated file reads",
                detail: "App.swift read 3x",
                valueText: "3x"
            )
        ])
        XCTAssertEqual(snapshot.sessionDetails.first?.optimizationTips.first, PopoverOptimizationTip(
            title: "Avoid rereading stable files",
            detail: "Keep App.swift summary in context; ask for diffs only",
            valueText: "3x"
        ))
    }

    func testStorageBackedProviderFlagsRepeatedBroadSearches() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(
            sessions: [
                makeSession(
                    id: "repeat-searcher",
                    provider: .claude,
                    model: "opus",
                    projectName: "Monitor",
                    sessionId: "provider-repeat-searcher",
                    startTime: today,
                    inputTokens: 900,
                    outputTokens: 100
                )
            ],
            toolEvents: [
                makeToolEvent(
                    id: "search-1",
                    sessionId: "provider-repeat-searcher",
                    timestamp: today,
                    toolName: "Bash",
                    command: #"rg "TokenScope" Sources"#,
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "search-2",
                    sessionId: "provider-repeat-searcher",
                    timestamp: today.addingTimeInterval(5),
                    toolName: "exec_command",
                    command: #"rg "Popover" ./Sources"#,
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "search-3",
                    sessionId: "provider-repeat-searcher",
                    timestamp: today.addingTimeInterval(10),
                    toolName: "Bash",
                    command: "rg --files Sources",
                    workingDirectory: "/Users/example/Monitor"
                )
            ]
        ))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            toolEventReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.wasteSignals.first, PopoverWasteSignal(
            title: "Repeated broad searches",
            detail: "Claude · rg over Sources 3x · Fix: search exact files",
            tokens: 0,
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.optimizationTips.first, PopoverOptimizationTip(
            title: "Narrow broad searches",
            detail: "Search exact files or symbols instead of Sources",
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.sessionInsights.first?.reason, "Repeated broad searches")
        XCTAssertEqual(snapshot.sessionInsights.first?.recommendation, "rg over Sources 3x; narrow the search root")
        XCTAssertEqual(snapshot.sessionDetails.first?.toolSignals, [
            PopoverSessionToolSignal(
                title: "Repeated broad searches",
                detail: "rg over Sources 3x",
                valueText: "3x"
            )
        ])
        XCTAssertEqual(snapshot.sessionDetails.first?.optimizationTips.first, PopoverOptimizationTip(
            title: "Narrow broad searches",
            detail: "Search exact files or symbols instead of Sources",
            valueText: "3x"
        ))
    }

    func testStorageBackedProviderFlagsRepeatedDirectoryListings() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(
            sessions: [
                makeSession(
                    id: "repeat-lister",
                    provider: .claude,
                    model: "opus",
                    projectName: "Monitor",
                    sessionId: "provider-repeat-lister",
                    startTime: today,
                    inputTokens: 700,
                    outputTokens: 80
                )
            ],
            toolEvents: [
                makeToolEvent(
                    id: "list-1",
                    sessionId: "provider-repeat-lister",
                    timestamp: today,
                    toolName: "Bash",
                    command: "ls Sources",
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "list-2",
                    sessionId: "provider-repeat-lister",
                    timestamp: today.addingTimeInterval(5),
                    toolName: "exec_command",
                    command: "tree ./Sources",
                    workingDirectory: "/Users/example/Monitor"
                ),
                makeToolEvent(
                    id: "list-3",
                    sessionId: "provider-repeat-lister",
                    timestamp: today.addingTimeInterval(10),
                    toolName: "Bash",
                    command: "find Sources -maxdepth 1",
                    workingDirectory: "/Users/example/Monitor"
                )
            ]
        ))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            toolEventReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.wasteSignals.first, PopoverWasteSignal(
            title: "Repeated directory listings",
            detail: "Claude · ls over Sources 3x · Fix: reuse a directory map",
            tokens: 0,
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.optimizationTips.first, PopoverOptimizationTip(
            title: "Reuse directory map",
            detail: "Keep a short map of Sources; avoid listing it again",
            valueText: "3x"
        ))
        XCTAssertEqual(snapshot.sessionInsights.first?.reason, "Repeated directory listings")
        XCTAssertEqual(snapshot.sessionInsights.first?.recommendation, "ls over Sources 3x; keep a brief directory map")
        XCTAssertEqual(snapshot.sessionDetails.first?.toolSignals, [
            PopoverSessionToolSignal(
                title: "Repeated directory listings",
                detail: "ls over Sources 3x",
                valueText: "3x"
            )
        ])
        XCTAssertEqual(snapshot.sessionDetails.first?.optimizationTips.first, PopoverOptimizationTip(
            title: "Reuse directory map",
            detail: "Keep a short map of Sources; avoid listing it again",
            valueText: "3x"
        ))
    }

    func testStorageBackedProviderFlagsRepeatedFailedCommands() throws {
        let storage = InMemorySpendStorage()
        let today = Date(timeIntervalSince1970: 1_800_000_000)

        try storage.upsert(NormalizedUsageBatch(
            sessions: [
                makeSession(
                    id: "repeat-failer",
                    provider: .claude,
                    model: "opus",
                    projectName: "Monitor",
                    sessionId: "provider-repeat-failer",
                    startTime: today,
                    inputTokens: 600,
                    outputTokens: 120
                )
            ],
            toolEvents: [
                makeToolEvent(
                    id: "fail-1",
                    sessionId: "provider-repeat-failer",
                    timestamp: today,
                    toolName: "Bash",
                    command: "npm test -- --filter ParserTests",
                    workingDirectory: "/Users/example/Monitor",
                    exitCode: 1,
                    errorSummary: "No tests found"
                ),
                makeToolEvent(
                    id: "fail-2",
                    sessionId: "provider-repeat-failer",
                    timestamp: today.addingTimeInterval(5),
                    toolName: "exec_command",
                    command: "npm   test -- --filter ParserTests",
                    workingDirectory: "/Users/example/Monitor",
                    exitCode: 1,
                    errorSummary: "No tests found"
                )
            ]
        ))

        let provider = StorageBackedPopoverSummaryProvider(
            sessionReader: storage,
            toolEventReader: storage,
            calendar: Calendar(identifier: .gregorian),
            now: { today }
        )

        let snapshot = try provider.currentPopoverSummary(range: .today)

        XCTAssertEqual(snapshot.wasteSignals.first, PopoverWasteSignal(
            title: "Repeated failed commands",
            detail: "Claude · npm failed 2x · Fix: inspect first error",
            tokens: 0,
            valueText: "2x"
        ))
        XCTAssertEqual(snapshot.optimizationTips.first, PopoverOptimizationTip(
            title: "Stop retry loops",
            detail: "Read the first error, fix the command, then rerun once",
            valueText: "2x"
        ))
        XCTAssertEqual(snapshot.sessionInsights.first?.reason, "Repeated failed commands")
        XCTAssertEqual(snapshot.sessionInsights.first?.recommendation, "npm failed 2x; inspect the error before retrying")
        XCTAssertEqual(snapshot.sessionDetails.first?.toolSignals, [
            PopoverSessionToolSignal(
                title: "Repeated failed commands",
                detail: "npm failed 2x · No tests found",
                valueText: "2x"
            )
        ])
        XCTAssertEqual(snapshot.sessionDetails.first?.optimizationTips.first, PopoverOptimizationTip(
            title: "Stop retry loops",
            detail: "Read the first error, fix the command, then rerun once",
            valueText: "2x"
        ))
    }

    func testPresenterFormatsCompactRowsAndTimelineWithoutRawSourcePaths() {
        let timelineStart = Date(timeIntervalSince1970: 54_240)
        let snapshot = PopoverSummarySnapshot(
            rangeTitle: "Today",
            totalCost: Decimal(string: "5.00"),
            totalTokens: 385,
            sessionCount: 2,
            tokenPhases: [
                PopoverTokenPhase(
                    name: "Prompt/context",
                    detail: "Base input, tools, files, and instructions",
                    tokens: 300,
                    percentage: 78
                )
            ],
            wasteSignals: [
                PopoverWasteSignal(
                    title: "Input-heavy sessions",
                    detail: "1 session dominated by prompt/context · Fix: trim carried context",
                    tokens: 300
                )
            ],
            optimizationTips: [
                PopoverOptimizationTip(
                    title: "Trim carried context",
                    detail: "Keep only current files, active errors, and recent decisions",
                    valueText: "80%"
                )
            ],
            sessionInsights: [
                PopoverSessionInsight(
                    projectName: "Monitor",
                    providerName: "Claude",
                    modelName: "opus",
                    reason: "Most tokens are prompt/context",
                    recommendation: "Trim repeated context, old logs, and broad file dumps before retrying",
                    tokens: 300,
                    cost: Decimal(string: "3.25"),
                    startTime: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            providerSections: [
                PopoverProviderSection(
                    providerName: "Claude",
                    cost: Decimal(string: "3.25"),
                    tokens: 160,
                    sessionCount: 1,
                    modelBreakdown: [
                        PopoverBreakdownItem(name: "opus", cost: Decimal(string: "3.25"), tokens: 160, sessionCount: 1)
                    ],
                    projectBreakdown: [
                        PopoverBreakdownItem(name: "Monitor", cost: Decimal(string: "3.25"), tokens: 160, sessionCount: 1)
                    ]
                )
            ],
            providerBreakdown: [
                PopoverBreakdownItem(name: "Claude", cost: Decimal(string: "3.25"), tokens: 160, sessionCount: 1)
            ],
            modelBreakdown: [
                PopoverBreakdownItem(name: "opus", cost: Decimal(string: "3.25"), tokens: 160, sessionCount: 1)
            ],
            projectBreakdown: [
                PopoverBreakdownItem(name: "Monitor", cost: Decimal(string: "5.00"), tokens: 385, sessionCount: 2)
            ],
            mostExpensiveSessions: [
                PopoverSessionItem(
                    providerName: "Claude",
                    modelName: "opus",
                    projectName: "Monitor",
                    cost: Decimal(string: "3.25"),
                    tokens: 160,
                    startTime: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ],
            timeline: [
                PopoverTimelineItem(
                    providerName: "Codex",
                    modelName: "gpt-5",
                    projectName: "Monitor",
                    cost: nil,
                    tokens: 225,
                    startTime: timelineStart
                )
            ]
        )
        let provider = InMemoryPopoverSummaryProvider(snapshot: snapshot)
        let formatter = MenuBarSummaryFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let presenter = PopoverSummaryPresenter(
            summaryProvider: provider,
            formatter: formatter
        )

        let state = presenter.refresh()
        let renderedText = ([state.totalCostText, state.totalTokensText, state.sessionCountText] +
            state.sections.flatMap { section in
                [section.title] + section.rows.flatMap { [$0.title, $0.detail, $0.value] }
            }).joined(separator: "\n")

        XCTAssertEqual(state.totalCostText, "$5.00")
        XCTAssertEqual(state.totalTokensText, "385 tokens")
        XCTAssertEqual(state.sessionCountText, "2 sessions")
        XCTAssertEqual(state.rangeTitle, "Today")
        XCTAssertEqual(state.selectedRange, .today)
        XCTAssertEqual(state.selectedContent, .overview)
        XCTAssertEqual(state.footerTitle, "Quit")
        XCTAssertEqual(state.sections.map(\.title), ["Token Analysis", "Waste Signals", "Optimization Tips", "Session Insights"])
        XCTAssertEqual(state.sections.first?.rows, [
            PopoverRowRenderState(
                title: "Prompt/context",
                detail: "78% · Base input, tools, files, and instructions",
                value: "300 tokens"
            )
        ])
        XCTAssertEqual(state.sections[2].rows, [
            PopoverRowRenderState(
                title: "Trim carried context",
                detail: "Keep only current files, active errors, and recent decisions",
                value: "80%"
            )
        ])
        XCTAssertEqual(state.sections[3].rows, [
            PopoverRowRenderState(
                title: "Monitor · Most tokens are prompt/context",
                detail: "Claude · opus",
                value: "300 tokens"
            )
        ])
        presenter.selectedContent = .providers
        let providerState = presenter.refresh()
        XCTAssertEqual(providerState.selectedContent, .providers)
        XCTAssertEqual(providerState.sections.map(\.title), ["Claude"])

        presenter.selectedContent = .activity
        let activityState = presenter.refresh()
        XCTAssertEqual(activityState.selectedContent, .activity)
        XCTAssertEqual(activityState.sections.map(\.title), ["Expensive Sessions", "Timeline"])
        XCTAssertEqual(activityState.sections.last?.rows, [
            PopoverRowRenderState(
                title: "Monitor",
                detail: "Codex · gpt-5 · — · 225 tokens",
                value: formatter.menuTimeText(timelineStart)
            )
        ])
        XCTAssertFalse(renderedText.contains(".claude"))
        XCTAssertFalse(renderedText.contains(".codex"))
        XCTAssertFalse(renderedText.contains("/Users/"))
    }

    func testPresenterSelectsSessionDetailWithoutRawSourcePaths() {
        let startTime = Date(timeIntervalSince1970: 54_240)
        let snapshot = PopoverSummarySnapshot(
            rangeTitle: "Today",
            totalCost: Decimal(string: "1.25"),
            totalTokens: 21_000,
            sessionCount: 1,
            tokenPhases: [],
            wasteSignals: [],
            sessionInsights: [
                PopoverSessionInsight(
                    detailID: "detail-1",
                    projectName: "Monitor",
                    providerName: "Claude",
                    modelName: "opus",
                    reason: "Most tokens are prompt/context",
                    recommendation: "Trim repeated context, old logs, and broad file dumps before retrying",
                    tokens: 21_000,
                    cost: Decimal(string: "1.25"),
                    startTime: startTime
                )
            ],
            sessionDetails: [
                PopoverSessionDetail(
                    id: "detail-1",
                    projectName: "Monitor",
                    providerName: "Claude",
                    modelName: "opus",
                    sessionId: "provider-session-abcdef",
                    cost: Decimal(string: "1.25"),
                    inputTokens: 12_000,
                    cacheCreationInputTokens: 4_000,
                    cacheReadInputTokens: 3_000,
                    outputTokens: 2_000,
                    totalTokens: 21_000,
                    startTime: startTime,
                    endTime: nil,
                    durationSeconds: nil,
                    sourceDescription: "Claude local log",
                    reason: "Most tokens are prompt/context",
                    recommendation: "Trim repeated context, old logs, and broad file dumps before retrying"
                )
            ],
            providerSections: [],
            providerBreakdown: [],
            modelBreakdown: [],
            projectBreakdown: [],
            mostExpensiveSessions: [],
            timeline: []
        )
        let provider = InMemoryPopoverSummaryProvider(snapshot: snapshot)
        let formatter = MenuBarSummaryFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let presenter = PopoverSummaryPresenter(
            summaryProvider: provider,
            formatter: formatter
        )

        let initialState = presenter.refresh()
        XCTAssertFalse(initialState.sections.map(\.title).contains("Session Detail"))
        XCTAssertEqual(initialState.sections[2].rows.first?.action, .selectSessionDetail("detail-1"))

        let selectedState = presenter.selectSessionDetail("detail-1")
        let detailSection = selectedState.sections.first { $0.title == "Session Detail" }

        XCTAssertEqual(selectedState.sections[2].rows.first?.isSelected, true)
        XCTAssertEqual(detailSection?.rows, [
            PopoverRowRenderState(
                title: "Monitor",
                detail: "Claude · opus",
                value: "$1.25"
            ),
            PopoverRowRenderState(
                title: "Token split",
                detail: "Input 12K tokens · Output 2.0K tokens",
                value: "21K tokens"
            ),
            PopoverRowRenderState(
                title: "Cache",
                detail: "Cache write 4.0K tokens · Cache read 3.0K tokens",
                value: "7.0K tokens"
            ),
            PopoverRowRenderState(
                title: "Most tokens are prompt/context",
                detail: "Trim repeated context, old logs, and broad file dumps before retrying",
                value: "Signal"
            ),
            PopoverRowRenderState(
                title: "Started",
                detail: "Session provider-ses...",
                value: formatter.menuTimeText(startTime)
            ),
            PopoverRowRenderState(
                title: "Source",
                detail: "Claude local log",
                value: "Local"
            )
        ])

        let renderedText = selectedState.sections.flatMap { section in
            [section.title] + section.rows.flatMap { [$0.title, $0.detail, $0.value] }
        }.joined(separator: "\n")
        XCTAssertFalse(renderedText.contains(".claude"))
        XCTAssertFalse(renderedText.contains(".codex"))
        XCTAssertFalse(renderedText.contains("/Users/"))

        let deselectedState = presenter.selectSessionDetail("detail-1")
        XCTAssertFalse(deselectedState.sections.map(\.title).contains("Session Detail"))
        XCTAssertEqual(deselectedState.sections[2].rows.first?.isSelected, false)
    }

    func testPresenterHandlesProviderFailureWithoutDetails() {
        let presenter = PopoverSummaryPresenter(summaryProvider: ThrowingPopoverProvider())

        XCTAssertEqual(presenter.refresh(), .unavailable)
    }

    func testPresenterUsesSingleEmptyStateForEmptyRange() {
        let presenter = PopoverSummaryPresenter(summaryProvider: InMemoryPopoverSummaryProvider())

        let state = presenter.refresh()

        XCTAssertEqual(state.sections, [
            PopoverSectionRenderState(
                title: "No Sessions",
                rows: [
                    PopoverRowRenderState(
                        title: "No activity in Today",
                        detail: "Try Total or 7d if today has no local sessions",
                        value: "—"
                    )
                ],
                emptyText: "No sessions"
            )
        ])
    }

    func testPresenterShowsOnboardingEmptyStateForEmptyTotalRange() {
        let presenter = PopoverSummaryPresenter(
            selectedRange: .total,
            summaryProvider: InMemoryPopoverSummaryProvider()
        )

        let state = presenter.refresh()

        XCTAssertEqual(state.sections, [
            PopoverSectionRenderState(
                title: "No Sessions",
                rows: [
                    PopoverRowRenderState(
                        title: "No local usage found yet",
                        detail: "TokenScope reads local Claude Code and Codex session logs from ~/.claude and ~/.codex. No usage found yet — data appears after your next Claude Code or Codex session.",
                        value: "—"
                    )
                ],
                emptyText: "No sessions"
            )
        ])
    }

    func testPresenterSurfacesRefreshWarningOnOverviewOnly() {
        let presenter = PopoverSummaryPresenter(
            summaryProvider: InMemoryPopoverSummaryProvider(),
            refreshErrorText: { "Refresh failed: offline" }
        )

        let overviewState = presenter.refresh()
        XCTAssertEqual(overviewState.refreshWarningText, "⚠️ Last refresh failed — see System tab")

        presenter.selectedContent = .system
        let systemState = presenter.refresh()
        XCTAssertNil(systemState.refreshWarningText)
    }

    func testPresenterOmitsRefreshWarningWithoutError() {
        let presenter = PopoverSummaryPresenter(summaryProvider: InMemoryPopoverSummaryProvider())

        XCTAssertNil(presenter.refresh().refreshWarningText)
    }

    private func makeSession(
        id: String,
        provider: Provider,
        model: String,
        projectName: String,
        sessionId: String? = nil,
        startTime: Date,
        inputTokens: Int?,
        cacheCreationInputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil,
        outputTokens: Int?,
        totalTokens: Int? = nil,
        estimatedCost: Decimal? = nil
    ) -> NormalizedSession {
        NormalizedSession(
            id: id,
            provider: provider,
            model: model,
            projectPath: "/Users/example/\(projectName)",
            projectName: projectName,
            sessionId: sessionId ?? "provider-\(id)",
            startTime: startTime,
            endTime: nil,
            durationSeconds: nil,
            inputTokens: inputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCost: estimatedCost,
            rawSourcePath: "/Users/example/.claude/log.jsonl"
        )
    }

    private func makeToolEvent(
        id: String,
        sessionId: String,
        timestamp: Date,
        toolName: String = "Read",
        targetPath: String? = nil,
        command: String? = nil,
        workingDirectory: String? = nil,
        exitCode: Int? = nil,
        errorSummary: String? = nil
    ) -> ToolEvent {
        ToolEvent(
            id: id,
            provider: .claude,
            sessionId: sessionId,
            timestamp: timestamp,
            toolName: toolName,
            targetPath: targetPath,
            command: command,
            workingDirectory: workingDirectory,
            exitCode: exitCode,
            errorSummary: errorSummary,
            rawSourcePath: "/Users/example/.claude/log.jsonl"
        )
    }
}

private struct ThrowingPopoverProvider: PopoverSummaryProviding {
    func currentPopoverSummary(range: PopoverTimeRange) throws -> PopoverSummarySnapshot {
        throw TestError.unavailable
    }
}

private enum TestError: Error {
    case unavailable
}
