import SwiftUI
import MuesliCore

struct InsightsView: View {
    let initialSection: InsightsSection
    let loadSnapshot: (InsightsRange) async throws -> InsightsSnapshot
    let onBack: () -> Void
    let backLabel: String

    @State private var range: InsightsRange = .twelveMonths
    @State private var metric: InsightsMetric
    @State private var snapshot: InsightsSnapshot?
    @State private var errorMessage: String?
    @State private var loadGeneration = 0
    @State private var isSharing = false
    @State private var initialScrollGate = InsightsInitialScrollGate()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        initialSection: InsightsSection,
        loadSnapshot: @escaping (InsightsRange) async throws -> InsightsSnapshot,
        onBack: @escaping () -> Void,
        backLabel: String
    ) {
        self.initialSection = initialSection
        self.loadSnapshot = loadSnapshot
        self.onBack = onBack
        self.backLabel = backLabel
        _metric = State(initialValue: initialSection == .meetings ? .meetings : .words)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    Group {
                        if let snapshot {
                            hero(snapshot)
                            activityPanel(snapshot).id(initialSection == .meetings ? InsightsSection.meetings : .words)
                            usagePanel(snapshot).id(InsightsSection.pace)
                            streakPanel(snapshot).id(InsightsSection.streak)
                            wordClouds(snapshot)
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else {
                            loadingState
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(insightsBackground)
            .sheet(isPresented: $isSharing) {
                if let snapshot {
                    InsightsShareSheet(snapshot: snapshot, rangeLabel: range.label)
                }
            }
            .task(id: loadGeneration) {
                await refresh()
                guard initialScrollGate.consume(hasSnapshot: snapshot != nil) else { return }
                if reduceMotion {
                    proxy.scrollTo(initialSection, anchor: .top)
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(initialSection, anchor: .top)
                    }
                }
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerIdentity
                Spacer()
                rangeControls
            }
            VStack(alignment: .leading, spacing: 14) {
                headerIdentity
                rangeControls
            }
        }
    }

    private var headerIdentity: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Label(backLabel, systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(InsightsPalette.secondaryText)
            .keyboardShortcut(.cancelAction)

            Rectangle()
                .fill(MuesliTheme.surfaceBorder)
                .frame(width: 1, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "insights.header.title", defaultValue: "INSIGHTS", comment: ""))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(MuesliTheme.accent)
                Text(String(localized: "insights.header.subtitle_privacy", defaultValue: "Private and on-device", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InsightsPalette.secondaryText)
            }
        }
    }

    private var rangeControls: some View {
        HStack(spacing: 12) {
            Picker(String(localized: "insights.time_range", defaultValue: "Time range", comment: ""), selection: Binding(
                get: { range },
                set: { newValue in range = newValue; loadGeneration += 1 }
            )) {
                ForEach(InsightsRange.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(String(localized: "insights.time_range.accessibility_label", defaultValue: "Time range", comment: ""))
            .frame(width: 340)

            Button {
                loadGeneration += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(InsightsPalette.secondaryText)
            .help(String(localized: "insights.refresh_local_insights.help", defaultValue: "Refresh local insights", comment: ""))
            .accessibilityLabel(String(localized: "insights.refresh_local_insights.accessibility_label", defaultValue: "Refresh local insights", comment: ""))

            Button {
                isSharing = true
            } label: {
                Label(String(localized: "insights.share.button", defaultValue: "Share", comment: ""), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(snapshot == nil)
            .help(String(localized: "insights.share.help", defaultValue: "Share an anonymous activity image", comment: ""))
            .accessibilityLabel(String(localized: "insights.share_activity.accessibility_label", defaultValue: "Share your activity", comment: ""))
        }
    }

    private func hero(_ data: InsightsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "insights.hero.title", defaultValue: "Your time with Muesli", comment: ""))
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(data.lifetime.totalWords.formatted())
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .tracking(-2.4)
                        .monospacedDigit()
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(String(localized: "insights.hero.total_words_dictated", defaultValue: "Total words dictated", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(InsightsPalette.secondaryText)
            }

            HStack(spacing: 0) {
                heroDatum(String(localized: "insights.hero.meetings", defaultValue: "Meetings", comment: ""), value: format(data.lifetime.meetings))
                divider
                heroDatum(String(localized: "insights.hero.average_pace", defaultValue: "Average pace", comment: ""), value: String(format: String(localized: "insights.hero.average_pace_value_wpm", defaultValue: "%d WPM", comment: ""), Int(data.lifetime.averageWPM.rounded())))
                divider
                heroDatum(String(localized: "insights.hero.current_streak", defaultValue: "Current streak", comment: ""), value: dayCount(data.currentStreakDays))
                divider
                heroDatum(String(localized: "insights.hero.longest_streak", defaultValue: "Longest streak", comment: ""), value: dayCount(data.longestStreakDays))
            }
        }
        .padding(26)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(MuesliTheme.backgroundRaised)
                LinearGradient(
                    colors: [MuesliTheme.accent.opacity(0.13), Color.cyan.opacity(0.025), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(panelBorder)
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
    }

    private func activityPanel(_ data: InsightsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                panelTitle(String(localized: "insights.activity_panel.title", defaultValue: "DAILY ACTIVITY", comment: ""), subtitle: String(localized: "insights.activity_panel.subtitle", defaultValue: "Words and meetings by day", comment: ""))
                Spacer()
                Picker(String(localized: "insights.activity_metric", defaultValue: "Activity metric", comment: ""), selection: $metric) {
                    ForEach(InsightsMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(String(localized: "insights.activity_metric.accessibility_label", defaultValue: "Activity metric", comment: ""))
                .frame(width: 190)
            }
            ActivityHeatmap(activity: data.dailyActivity, metric: metric)
                .frame(minHeight: 156)
            HStack(spacing: 8) {
                Text(String(localized: "insights.activity_level.quiet", defaultValue: "QUIET", comment: ""))
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(InsightsPalette.intensity(level))
                        .frame(width: 15, height: 15)
                }
                Text(String(localized: "insights.activity_level.loud", defaultValue: "LOUD", comment: ""))
            }
            .font(.system(size: 9, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(InsightsPalette.tertiaryText)
        }
        .insightsPanel()
    }

    private func usagePanel(_ data: InsightsSnapshot) -> some View {
        let total = max(data.selected.totalWords, 1)
        let dictationShare = Double(data.selected.dictationWords) / Double(total)
        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                panelTitle(String(localized: "insights.usage_panel.title", defaultValue: "DICTATIONS AND MEETINGS", comment: ""), subtitle: String(localized: "insights.usage_panel.subtitle", defaultValue: "Activity for the selected time period", comment: ""))
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(format(data.selected.totalWords))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text(String(localized: "insights.words_unit", defaultValue: "words", comment: ""))
                        .foregroundStyle(InsightsPalette.tertiaryText)
                }
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MuesliTheme.accent)
                            .frame(width: max(4, geometry.size.width * dictationShare))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cyan.opacity(0.75))
                    }
                }
                .frame(height: 12)
                HStack {
                    usageLegend(String(localized: "insights.usage_legend.dictation", defaultValue: "Dictation", comment: ""), data.selected.dictationWords, MuesliTheme.accent)
                    Spacer()
                    usageLegend(String(localized: "insights.usage_legend.meetings", defaultValue: "Meetings", comment: ""), data.selected.meetingWords, .cyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "insights.usage.overview_heading", defaultValue: "OVERVIEW", comment: ""))
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundStyle(InsightsPalette.tertiaryText)
                readout(String(localized: "insights.usage_readout.dictation_sessions", defaultValue: "Dictation sessions", comment: ""), format(data.selected.dictationSessions))
                readout(String(localized: "insights.usage_readout.completed_meetings", defaultValue: "Completed meetings", comment: ""), format(data.selected.meetings))
                readout(String(localized: "insights.usage_readout.average_pace", defaultValue: "Average pace", comment: ""), String(format: String(localized: "insights.usage_readout.average_pace_value_wpm", defaultValue: "%d WPM", comment: ""), Int(data.selected.averageWPM.rounded())))
                readout(String(localized: "insights.usage_readout.active_days", defaultValue: "Active days", comment: ""), format(data.activeDaysInRange))
            }
            .padding(20)
            .frame(width: 300, alignment: .leading)
            .background(MuesliTheme.backgroundDeep.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuesliTheme.surfaceBorder))
        }
        .insightsPanel()
    }

    private func streakPanel(_ data: InsightsSnapshot) -> some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(data.currentStreakDays)")
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                    .tracking(-3)
                    .monospacedDigit()
                Text(String(localized: "insights.streak.current_heading", defaultValue: "CURRENT STREAK", comment: ""))
                    .font(.system(size: 11, weight: .bold)).tracking(1.8)
                    .foregroundStyle(MuesliTheme.accent)
            }
            VStack(alignment: .leading, spacing: 14) {
                panelTitle(String(localized: "insights.streak_panel.title", defaultValue: "STREAKS", comment: ""), subtitle: String(localized: "insights.streak_panel.subtitle", defaultValue: "Your consecutive dictation days", comment: ""))
                Text(streakMessage(data))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(InsightsPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Label(String(format: String(localized: "insights.streak.best_days", defaultValue: "Best: %d days", comment: ""), data.longestStreakDays), systemImage: "flag.checkered")
                    Label(String(format: String(localized: "insights.streak.active_days_in_range", defaultValue: "%d active days", comment: ""), data.activeDaysInRange), systemImage: "calendar.badge.checkmark")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InsightsPalette.tertiaryText)
            }
        }
        .insightsPanel()
    }

    private func wordClouds(_ data: InsightsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            panelTitle(String(localized: "insights.word_cloud.title", defaultValue: "MOST-USED WORDS", comment: ""), subtitle: String(localized: "insights.word_cloud.subtitle", defaultValue: "Common words from your dictations and meetings", comment: ""))
            HStack(alignment: .top, spacing: 16) {
                WordCloudPanel(title: String(localized: "insights.word_cloud.dictations.title", defaultValue: "DICTATIONS", comment: ""), icon: "waveform", words: data.dictationWords)
                WordCloudPanel(title: String(localized: "insights.word_cloud.meetings.title", defaultValue: "MEETINGS", comment: ""), icon: "person.2.wave.2", words: data.meetingWords)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            InsightsLoadingStatus()
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 14)
                    .fill(MuesliTheme.backgroundRaised)
                    .frame(height: index == 0 ? 235 : 190)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(MuesliTheme.surfacePrimary).frame(width: 130, height: 12)
                            RoundedRectangle(cornerRadius: 5).fill(MuesliTheme.surfacePrimary).frame(width: 230, height: 30)
                        }.padding(24)
                    }
                    .opacity(0.72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "insights.loading.accessibility_label", defaultValue: "Calculating local insights", comment: ""))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MuesliTheme.accent)
            Text(String(localized: "insights.error.calculation_failed", defaultValue: "Insights could not be calculated", comment: ""))
                .font(MuesliTheme.title3())
            Text(message)
                .font(MuesliTheme.callout())
                .foregroundStyle(InsightsPalette.secondaryText)
            Button(String(localized: "insights.error.retry_button", defaultValue: "Try Again", comment: "")) { loadGeneration += 1 }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .insightsPanel()
    }

    private func refresh() async {
        snapshot = nil
        errorMessage = nil
        do {
            let result = try await loadSnapshot(range)
            try Task.checkCancellation()
            snapshot = result
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var insightsBackground: some View {
        ZStack {
            MuesliTheme.backgroundBase
            LinearGradient(
                colors: [MuesliTheme.accent.opacity(0.045), .clear, Color.cyan.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }.ignoresSafeArea()
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
    }

    private var divider: some View {
        Rectangle().fill(MuesliTheme.surfaceBorder).frame(width: 1, height: 42)
    }

    private func heroDatum(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(InsightsPalette.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }

    private func panelTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1.8).foregroundStyle(MuesliTheme.textPrimary)
            Text(subtitle).font(.system(size: 12, weight: .regular)).foregroundStyle(InsightsPalette.secondaryText)
        }
    }

    private func usageLegend(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(InsightsPalette.secondaryText)
            Text(format(value)).fontWeight(.semibold).monospacedDigit()
        }.font(.system(size: 12))
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(InsightsPalette.tertiaryText)
            Spacer()
            Text(value).foregroundStyle(MuesliTheme.textPrimary).monospacedDigit()
        }.font(.system(size: 12, weight: .medium))
    }

    private func streakMessage(_ data: InsightsSnapshot) -> String {
        guard data.currentStreakDays > 0 else { return String(localized: "insights.streak.message.start_new_streak", defaultValue: "Dictate today to start a new streak.", comment: "") }
        if data.currentStreakDays == data.longestStreakDays { return String(localized: "insights.streak.message.longest_so_far", defaultValue: "This is your longest streak so far.", comment: "") }
        return String(format: String(localized: "insights.streak.message.longest_streak_value", defaultValue: "Your longest streak is %@.", comment: ""), "\(dayCount(data.longestStreakDays))")
    }

    private func format(_ value: Int) -> String { value.formatted(.number.notation(.compactName)) }

    private func dayCount(_ value: Int) -> String { "\(value) \(value == 1 ? String(localized: "insights.streak.unit.day_singular", defaultValue: "day", comment: "") : String(localized: "insights.streak.unit.day_plural", defaultValue: "days", comment: ""))" }
}

enum InsightsLoadingCopy {
    static let messages = [
        String(localized: "insights.loading.message.calculating_history", defaultValue: "Calculating your private activity history", comment: ""),
        String(localized: "insights.loading.message.on_device_not_uploaded", defaultValue: "Insights are computed on this Mac and never uploaded", comment: ""),
        String(localized: "insights.loading.message.user_control", defaultValue: "Your transcripts and statistics stay under your control", comment: ""),
        String(localized: "insights.loading.message.hybrid_ai_local_choice", defaultValue: "Hybrid AI works best when you choose what stays local", comment: ""),
    ]
}

private struct InsightsLoadingStatus: View {
    @State private var messageIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .tint(MuesliTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "insights.loading.title", defaultValue: "Building your Insights", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                ZStack(alignment: .leading) {
                    Text(InsightsLoadingCopy.messages[messageIndex])
                        .id(messageIndex)
                        .transition(.opacity)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(InsightsPalette.secondaryText)
            }
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(MuesliTheme.accent.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MuesliTheme.surfaceBorder))
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    messageIndex = (messageIndex + 1) % InsightsLoadingCopy.messages.count
                }
            }
        }
    }
}

struct InsightsInitialScrollGate {
    private(set) var hasScrolled = false

    mutating func consume(hasSnapshot: Bool) -> Bool {
        guard hasSnapshot, !hasScrolled else { return false }
        hasScrolled = true
        return true
    }
}

private enum InsightsMetric: CaseIterable {
    case words, meetings
    var label: String { self == .words ? String(localized: "insights.metric.words", defaultValue: "Words", comment: "") : String(localized: "insights.metric.meetings", defaultValue: "Meetings", comment: "") }
}

private enum InsightsPalette {
    static let secondaryText = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.70,
        light: .black, lightAlpha: 0.72
    )
    static let tertiaryText = Color.adaptiveAlpha(
        dark: .white, darkAlpha: 0.52,
        light: .black, lightAlpha: 0.58
    )

    static func intensity(_ level: Int) -> Color {
        switch level {
        case 1: return MuesliTheme.accent.opacity(0.24)
        case 2: return MuesliTheme.accent.opacity(0.48)
        case 3: return Color.cyan.opacity(0.67)
        case 4...: return Color.cyan.opacity(0.95)
        default: return MuesliTheme.surfacePrimary.opacity(0.62)
        }
    }
}

enum ActivityHeatmapCalendarLayout {
    static func weeks(
        from activity: [InsightsDailyActivity],
        calendar: Calendar
    ) -> [[InsightsDailyActivity]] {
        Dictionary(grouping: activity) { day -> Date in
            let startOfDay = calendar.startOfDay(for: day.date)
            let daysSinceSunday = calendar.component(.weekday, from: startOfDay) - 1
            return calendar.date(byAdding: .day, value: -daysSinceSunday, to: startOfDay) ?? startOfDay
        }
        .sorted { $0.key < $1.key }
        .map { _, days in days.sorted { $0.date < $1.date } }
    }

    static func monthMarker(
        for week: [InsightsDailyActivity],
        at index: Int,
        calendar: Calendar
    ) -> Date? {
        if let monthStart = week.first(where: { calendar.component(.day, from: $0.date) == 1 }) {
            return monthStart.date
        }
        return index == 0 ? week.first?.date : nil
    }
}

private struct ActivityHeatmap: View {
    let activity: [InsightsDailyActivity]
    let metric: InsightsMetric
    private let cell: CGFloat = 14
    private let gap: CGFloat = 4
    private let monthLabelHeight: CGFloat = 14
    private let weekdayLabels = ["", String(localized: "insights.weekday.mon_short", defaultValue: "Mon", comment: ""), "", String(localized: "insights.weekday.wed_short", defaultValue: "Wed", comment: ""), "", String(localized: "insights.weekday.fri_short", defaultValue: "Fri", comment: ""), ""]

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing, spacing: gap) {
                    Color.clear.frame(width: 24, height: monthLabelHeight)
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(InsightsPalette.tertiaryText)
                            .frame(width: 24, height: cell, alignment: .trailing)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: gap) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            VStack(alignment: .leading, spacing: gap) {
                                Color.clear
                                    .frame(width: cell, height: monthLabelHeight)
                                    .overlay(alignment: .leading) {
                                        if let marker = ActivityHeatmapCalendarLayout.monthMarker(
                                            for: week,
                                            at: index,
                                            calendar: calendar
                                        ) {
                                            Text(marker.formatted(.dateTime.month(.abbreviated)))
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(InsightsPalette.tertiaryText)
                                                .fixedSize()
                                        }
                                    }
                                VStack(spacing: gap) {
                                    ForEach(0..<7, id: \.self) { weekday in
                                        if let day = week.first(where: {
                                            calendar.component(.weekday, from: $0.date) - 1 == weekday
                                        }) {
                                            cellView(day)
                                        } else {
                                            Color.clear.frame(width: cell, height: cell)
                                        }
                                    }
                                }
                                .id(week.first?.date)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: activity.last?.date) { _, _ in scrollToLatest(proxy) }
            .accessibilityLabel(String(format: String(localized: "insights.activity.daily_metric_activity", defaultValue: "Daily %@ activity", comment: ""), "\(metric.label.lowercased())"))
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let latestWeek = weeks.last?.first?.date else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(latestWeek, anchor: .trailing)
        }
    }

    private var calendar: Calendar { Calendar.current }

    private var weeks: [[InsightsDailyActivity]] {
        ActivityHeatmapCalendarLayout.weeks(from: activity, calendar: calendar)
    }

    private var maximum: Int {
        max(1, activity.map(value).max() ?? 1)
    }

    private func value(_ day: InsightsDailyActivity) -> Int {
        metric == .words ? day.words : day.meetings
    }

    private func level(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let ratio = log(Double(count) + 1) / log(Double(maximum) + 1)
        return min(4, max(1, Int(ceil(ratio * 4))))
    }

    private func cellView(_ day: InsightsDailyActivity) -> some View {
        let count = value(day)
        return ActivityHeatmapCell(
            day: day,
            count: count,
            metric: metric,
            level: level(count),
            size: cell
        )
    }
}

private struct ActivityHeatmapCell: View {
    let day: InsightsDailyActivity
    let count: Int
    let metric: InsightsMetric
    let level: Int
    let size: CGFloat
    @State private var isHovered = false

    private var dateText: String {
        day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private var countText: String {
        switch metric {
        case .words:
            return count == 1 ? String(localized: "insights.count.word_dictated_one", defaultValue: "1 word dictated", comment: "") : String(format: String(localized: "insights.count.word_dictated_many", defaultValue: "%@ words dictated", comment: ""), "\(count.formatted())")
        case .meetings:
            return count == 1 ? String(localized: "insights.count.meeting_one", defaultValue: "1 meeting", comment: "") : String(format: String(localized: "insights.count.meeting_many", defaultValue: "%@ meetings", comment: ""), "\(count.formatted())")
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(InsightsPalette.intensity(level))
            .frame(width: size, height: size)
            .overlay {
                if count > 0 {
                    Circle().fill(Color.white.opacity(0.42)).frame(width: 2.5, height: 2.5)
                }
            }
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(InsightsPalette.secondaryText, lineWidth: 1.5)
                }
            }
            .onHover { isHovered = $0 }
            .popover(isPresented: $isHovered, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(countText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(InsightsPalette.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .fixedSize()
                .allowsHitTesting(false)
            }
            .focusable(true)
            .accessibilityElement()
            .accessibilityLabel("\(dateText), \(countText)")
    }
}

private struct WordCloudPanel: View {
    let title: String
    let icon: String
    let words: [InsightsWordFrequency]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(InsightsPalette.tertiaryText)
            if words.isEmpty {
                Text(String(localized: "insights.empty.no_words_for_period", defaultValue: "No words to show for this time period.", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(InsightsPalette.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                WordFlowLayout(spacing: 9) {
                    ForEach(displayedWords) { item in
                        Text(item.word)
                            .font(.system(
                                size: InsightsWordCloudSizing.fontSize(for: item, displayedWords: displayedWords),
                                weight: item.count == displayedWords.first?.count ? .bold : .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(wordColor(item))
                            .help(String(format: String(localized: "insights.word_cloud.used_count", defaultValue: "Used %@ times", comment: ""), "\(item.count.formatted())"))
                            .accessibilityLabel(String(format: String(localized: "insights.word_cloud.word_used_count_accessibility", defaultValue: "%@, used %@ times", comment: ""), "\(item.word)", "\(item.count.formatted())"))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .insightsPanel()
    }

    private var displayedWords: [InsightsWordFrequency] {
        Array(words.prefix(32))
    }

    private func wordColor(_ item: InsightsWordFrequency) -> Color {
        guard item.id != words.first?.id else { return .cyan }
        return item.count >= (words.first?.count ?? 0) / 2 ? MuesliTheme.accent : InsightsPalette.secondaryText
    }
}

enum InsightsWordCloudSizing {
    static func fontSize(for item: InsightsWordFrequency, displayedWords: [InsightsWordFrequency]) -> CGFloat {
        let high = max(1, displayedWords.first?.count ?? 1)
        let low = max(1, displayedWords.last?.count ?? 1)
        guard high > low else { return 18 }
        let ratio = log(Double(item.count - low + 1)) / log(Double(high - low + 1))
        return 13 + CGFloat(ratio) * 20
    }
}

struct WordFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
        }
    }

    func layout(sizes: [CGSize], width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        layout(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: proposal.width ?? 420
        )
    }
}

private extension InsightsRange {
    var label: String {
        switch self {
        case .thirtyDays: return String(localized: "insights.time_range.30_days", defaultValue: "30 days", comment: "")
        case .ninetyDays: return String(localized: "insights.time_range.90_days", defaultValue: "90 days", comment: "")
        case .twelveMonths: return String(localized: "insights.time_range.12_months", defaultValue: "12 months", comment: "")
        case .allTime: return String(localized: "insights.time_range.all_time", defaultValue: "All time", comment: "")
        }
    }
}

private extension View {
    func insightsPanel() -> some View {
        self
            .padding(22)
            .background(MuesliTheme.backgroundRaised.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.07), radius: 14, y: 7)
    }
}
