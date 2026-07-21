import Foundation

struct PopoverRenderState: Equatable {
    var rangeTitle: String
    var selectedRange: PopoverTimeRange
    var selectedContent: PopoverContentView
    var totalCostText: String
    var totalTokensText: String
    var sessionCountText: String
    var sections: [PopoverSectionRenderState]
    var refreshWarningText: String? = nil
    var footerTitle: String

    static let unavailable = PopoverRenderState(
        rangeTitle: "Today",
        selectedRange: .today,
        selectedContent: .overview,
        totalCostText: "—",
        totalTokensText: "—",
        sessionCountText: "—",
        sections: [],
        footerTitle: "Quit"
    )
}

enum PopoverRowAction: Equatable {
    case selectSessionDetail(String)
}

enum PopoverContentView: Equatable {
    case overview
    case providers
    case activity
    case system
}

struct PopoverSectionRenderState: Equatable {
    var title: String
    var rows: [PopoverRowRenderState]
    var emptyText: String
}

struct PopoverRowRenderState: Equatable {
    var title: String
    var detail: String
    var value: String
    var action: PopoverRowAction? = nil
    var isSelected: Bool = false
}

final class PopoverSummaryPresenter {
    var selectedRange: PopoverTimeRange
    var selectedContent: PopoverContentView = .overview
    private var selectedSessionDetailID: String?
    private var snapshotCache: [PopoverTimeRange: PopoverSummarySnapshot] = [:]

    private let summaryProvider: PopoverSummaryProviding
    private let formatter: MenuBarSummaryFormatter
    private let refreshErrorText: () -> String?

    init(
        selectedRange: PopoverTimeRange = .today,
        summaryProvider: PopoverSummaryProviding,
        formatter: MenuBarSummaryFormatter = MenuBarSummaryFormatter(),
        refreshErrorText: @escaping () -> String? = { nil }
    ) {
        self.selectedRange = selectedRange
        self.summaryProvider = summaryProvider
        self.formatter = formatter
        self.refreshErrorText = refreshErrorText
    }

    func refresh() -> PopoverRenderState {
        if let cachedSnapshot = snapshotCache[selectedRange] {
            return render(cachedSnapshot)
        }

        return reload()
    }

    func reload() -> PopoverRenderState {
        do {
            let snapshot = try summaryProvider.currentPopoverSummary(range: selectedRange)
            snapshotCache[selectedRange] = snapshot
            return render(snapshot)
        } catch {
            return .unavailable
        }
    }

    func invalidateCache() {
        snapshotCache.removeAll()
    }

    func selectRange(_ range: PopoverTimeRange) -> PopoverRenderState {
        selectedRange = range
        return refresh()
    }

    func selectSessionDetail(_ detailID: String) -> PopoverRenderState {
        selectedSessionDetailID = selectedSessionDetailID == detailID ? nil : detailID
        return refresh()
    }

    private func render(_ snapshot: PopoverSummarySnapshot) -> PopoverRenderState {
        let selectedDetail = snapshot.sessionDetails.first { $0.id == selectedSessionDetailID }
        let detailSections = selectedDetail.map { [sessionDetailSection($0)] } ?? []
        let sections: [PopoverSectionRenderState]

        if selectedContent != .system && snapshot.sessionCount == 0 {
            sections = [emptyStateSection()]
        } else {
            switch selectedContent {
            case .overview:
                var overviewSections = [
                    tokenAnalysisSection(rows: snapshot.tokenPhases),
                    wasteSignalsSection(rows: snapshot.wasteSignals)
                ]
                if !snapshot.optimizationTips.isEmpty {
                    overviewSections.append(optimizationTipsSection(rows: snapshot.optimizationTips))
                }
                overviewSections.append(sessionInsightsSection(rows: snapshot.sessionInsights))
                sections = overviewSections + detailSections
            case .providers:
                sections = providerSections(snapshot.providerSections)
            case .activity:
                sections = detailSections + [
                    sessionsSection(rows: snapshot.mostExpensiveSessions),
                    timelineSection(rows: snapshot.timeline)
                ]
            case .system:
                sections = []
            }
        }

        return PopoverRenderState(
            rangeTitle: snapshot.rangeTitle,
            selectedRange: selectedRange,
            selectedContent: selectedContent,
            totalCostText: formatter.compactCostText(snapshot.totalCost),
            totalTokensText: formatter.compactTokensText(snapshot.totalTokens),
            sessionCountText: formatter.menuSessionText(snapshot.sessionCount),
            sections: sections,
            refreshWarningText: refreshWarningText(),
            footerTitle: "Quit"
        )
    }

    private func refreshWarningText() -> String? {
        guard selectedContent == .overview, refreshErrorText() != nil else {
            return nil
        }

        return "⚠️ Last refresh failed — see System tab"
    }

    private func emptyStateSection() -> PopoverSectionRenderState {
        switch selectedRange {
        case .total:
            return onboardingEmptyStateSection()
        case .today:
            return noSessionsSection(detail: "Try Total or 7d if today has no local sessions")
        case .customLastDays:
            return noSessionsSection(detail: "Try Total if this range has no local sessions")
        }
    }

    private func onboardingEmptyStateSection() -> PopoverSectionRenderState {
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
    }

    private func noSessionsSection(detail: String) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "No Sessions",
            rows: [
                PopoverRowRenderState(
                    title: "No activity in \(selectedRange.title)",
                    detail: detail,
                    value: "—"
                )
            ],
            emptyText: "No sessions"
        )
    }

    private func tokenAnalysisSection(rows: [PopoverTokenPhase]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Token Analysis",
            rows: rows.map {
                PopoverRowRenderState(
                    title: $0.name,
                    detail: "\($0.percentage)% · \($0.detail)",
                    value: formatter.compactTokensText($0.tokens)
                )
            },
            emptyText: "No token phase data"
        )
    }

    private func wasteSignalsSection(rows: [PopoverWasteSignal]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Waste Signals",
            rows: rows.map {
                PopoverRowRenderState(
                    title: $0.title,
                    detail: $0.detail,
                    value: $0.valueText ?? formatter.compactTokensText($0.tokens)
                )
            },
            emptyText: "No obvious waste signal"
        )
    }

    private func optimizationTipsSection(rows: [PopoverOptimizationTip]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Optimization Tips",
            rows: rows.map {
                PopoverRowRenderState(
                    title: $0.title,
                    detail: $0.detail,
                    value: $0.valueText
                )
            },
            emptyText: "No optimization tip"
        )
    }

    private func sessionInsightsSection(rows: [PopoverSessionInsight]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Session Insights",
            rows: rows.map {
                PopoverRowRenderState(
                    title: "\($0.projectName) · \($0.reason)",
                    detail: "\($0.providerName) · \($0.modelName)",
                    value: $0.valueText ?? formatter.compactTokensText($0.tokens),
                    action: $0.detailID.isEmpty ? nil : .selectSessionDetail($0.detailID),
                    isSelected: !$0.detailID.isEmpty && $0.detailID == selectedSessionDetailID
                )
            },
            emptyText: "No notable session"
        )
    }

    private func sessionDetailSection(_ detail: PopoverSessionDetail?) -> PopoverSectionRenderState {
        guard let detail else {
            return PopoverSectionRenderState(
                title: "Session Detail",
                rows: [],
                emptyText: "Select a session"
            )
        }

        let cacheText = "Cache write \(formatter.compactTokensText(detail.cacheCreationInputTokens)) · Cache read \(formatter.compactTokensText(detail.cacheReadInputTokens))"
        let generatedText = "Input \(formatter.compactTokensText(detail.inputTokens)) · Output \(formatter.compactTokensText(detail.outputTokens))"

        let behaviorRows = detail.toolSignals.map {
            PopoverRowRenderState(
                title: $0.title,
                detail: $0.detail,
                value: $0.valueText
            )
        }
        let optimizationRows = detail.optimizationTips.map {
            PopoverRowRenderState(
                title: $0.title,
                detail: $0.detail,
                value: $0.valueText
            )
        }

        return PopoverSectionRenderState(
            title: "Session Detail",
            rows: [
                PopoverRowRenderState(
                    title: detail.projectName,
                    detail: "\(detail.providerName) · \(detail.modelName)",
                    value: formatter.compactCostText(detail.cost)
                ),
                PopoverRowRenderState(
                    title: "Token split",
                    detail: generatedText,
                    value: formatter.compactTokensText(detail.totalTokens)
                ),
                PopoverRowRenderState(
                    title: "Cache",
                    detail: cacheText,
                    value: formatter.compactTokensText(detail.cacheCreationInputTokens + detail.cacheReadInputTokens)
                ),
                PopoverRowRenderState(
                    title: detail.reason,
                    detail: detail.recommendation,
                    value: "Signal"
                )
            ] + optimizationRows + behaviorRows + [
                PopoverRowRenderState(
                    title: "Started",
                    detail: compactSessionID(detail.sessionId),
                    value: formatter.menuTimeText(detail.startTime)
                ),
                PopoverRowRenderState(
                    title: "Source",
                    detail: detail.sourceDescription,
                    value: "Local"
                )
            ],
            emptyText: "Select a session"
        )
    }

    private func providerSections(_ sections: [PopoverProviderSection]) -> [PopoverSectionRenderState] {
        sections.map { provider in
            let modelRows = provider.modelBreakdown.prefix(2).map {
                PopoverRowRenderState(
                    title: $0.name,
                    detail: "Model · \($0.sessionCount == 1 ? "1 session" : "\($0.sessionCount) sessions") · \(formatter.compactTokensText($0.tokens))",
                    value: formatter.compactCostText($0.cost)
                )
            }
            let projectRows = provider.projectBreakdown.prefix(2).map {
                PopoverRowRenderState(
                    title: $0.name,
                    detail: "Project · \($0.sessionCount == 1 ? "1 session" : "\($0.sessionCount) sessions") · \(formatter.compactTokensText($0.tokens))",
                    value: formatter.compactCostText($0.cost)
                )
            }

            return PopoverSectionRenderState(
                title: provider.providerName,
                rows: [
                    PopoverRowRenderState(
                        title: "Total",
                        detail: "\(provider.sessionCount == 1 ? "1 session" : "\(provider.sessionCount) sessions") · \(formatter.compactTokensText(provider.tokens))",
                        value: formatter.compactCostText(provider.cost)
                    )
                ] + modelRows + projectRows,
                emptyText: "No data"
            )
        }
    }

    private func sessionsSection(rows: [PopoverSessionItem]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Expensive Sessions",
            rows: rows.map {
                PopoverRowRenderState(
                    title: $0.projectName,
                    detail: "\($0.providerName) · \($0.modelName) · \(formatter.compactTokensText($0.tokens))",
                    value: formatter.compactCostText($0.cost),
                    action: $0.detailID.isEmpty ? nil : .selectSessionDetail($0.detailID),
                    isSelected: !$0.detailID.isEmpty && $0.detailID == selectedSessionDetailID
                )
            },
            emptyText: "No cost data"
        )
    }

    private func timelineSection(rows: [PopoverTimelineItem]) -> PopoverSectionRenderState {
        PopoverSectionRenderState(
            title: "Timeline",
            rows: rows.map {
                PopoverRowRenderState(
                    title: $0.projectName,
                    detail: "\($0.providerName) · \($0.modelName) · \(formatter.compactCostText($0.cost)) · \(formatter.compactTokensText($0.tokens))",
                    value: formatter.menuTimeText($0.startTime),
                    action: $0.detailID.isEmpty ? nil : .selectSessionDetail($0.detailID),
                    isSelected: !$0.detailID.isEmpty && $0.detailID == selectedSessionDetailID
                )
            },
            emptyText: "No sessions"
        )
    }

    private func compactSessionID(_ sessionId: String) -> String {
        guard !sessionId.isEmpty else {
            return "Unknown session"
        }

        if sessionId.count <= 12 {
            return "Session \(sessionId)"
        }

        return "Session \(String(sessionId.prefix(12)))..."
    }
}
