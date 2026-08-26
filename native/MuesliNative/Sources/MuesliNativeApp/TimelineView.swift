import SwiftUI
import MuesliCore

struct TimelineView: View {
    let appState: AppState
    let controller: MuesliController

    private struct DayGroup: Identifiable {
        let id: Date
        let header: String
        let entries: [TimelineEntry]
    }

    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var entriesByDay: [Date: [TimelineEntry]] = [:]
        for entry in appState.timelineRows {
            let date = MeetingBrowserLogic.parseDate(entry.timestamp) ?? now
            let day = calendar.startOfDay(for: date)
            entriesByDay[day, default: []].append(entry)
        }
        return entriesByDay.keys.sorted(by: >).map { day in
            let header: String
            if day == today {
                header = String(localized: "timeline.section.today", defaultValue: "TODAY", comment: "Section header label for today's timeline entries.")
            } else if day == yesterday {
                header = String(localized: "timeline.section.yesterday", defaultValue: "YESTERDAY", comment: "Section header label for yesterday's timeline entries.")
            } else {
                header = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
            }
            return DayGroup(id: day, header: header, entries: entriesByDay[day] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(
                dictationStats: appState.dictationStats,
                meetingStats: appState.meetingStats,
                showsMeetingStat: true,
                tracksInsightsFeatureTour: true,
                onSelect: { controller.openInsights(section: $0) }
            )

            if appState.config.showIOSCompanionPrompt {
                IPhoneBridgeCard(appState: appState, controller: controller)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.bottom, MuesliTheme.spacing12)
            }

            filterBar
                .padding(.horizontal, MuesliTheme.spacing24)
                .padding(.bottom, MuesliTheme.spacing12)

            if appState.timelineRows.isEmpty {
                emptyState
            } else {
                timelineScrollView
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: MuesliTheme.spacing12) {
            RecordOriginPicker(selection: Binding(
                get: { appState.timelineOriginFilter },
                set: { controller.filterTimeline(origin: $0) }
            ))
            if !appState.dictationTargetApplications.isEmpty || appState.timelineApplicationFilter != nil {
                TargetApplicationFilterMenu(
                    applications: appState.dictationTargetApplications,
                    selection: appState.timelineApplicationFilter,
                    onSelect: { controller.filterTimeline(application: $0) }
                )
                .featureTourTarget(.timelineApplications)
            }
            Spacer(minLength: 0)
            dateFilterMenu
        }
    }

    private var dateFilterMenu: some View {
        Menu {
            ForEach(HistoryDateFilter.allCases, id: \.self) { filter in
                Button {
                    controller.filterTimeline(dateFilter: filter)
                } label: {
                    HStack {
                        Text(filter.label)
                        if appState.timelineDateFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                if appState.timelineDateFilter != .all {
                    Text(appState.timelineDateFilter.label)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(
                appState.timelineDateFilter == .all
                    ? MuesliTheme.textTertiary
                    : MuesliTheme.accent
            )
            .padding(.horizontal, appState.timelineDateFilter == .all ? 0 : 8)
            .padding(.vertical, 3)
            .background(
                appState.timelineDateFilter == .all
                    ? Color.clear
                    : MuesliTheme.accent.opacity(0.12)
            )
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: MuesliTheme.spacing12) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(emptyStateTitle)
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(String(localized: "timeline.empty_state.try_another_source", defaultValue: "Try another source, app, or time range", comment: "Empty-state suggestion to adjust timeline filters."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if let application = appState.timelineApplicationFilter {
            return String(format: String(localized: "timeline.empty_state.no_dictations_for_app", defaultValue: "No dictations for %@", comment: "Empty-state title when selected app has no timeline dictations."), "\(application.name)")
        }
        switch appState.timelineOriginFilter {
        case .all: return String(localized: "timeline.empty_state.no_activity_yet", defaultValue: "No activity yet", comment: "Empty-state title when no timeline activity exists.")
        case .thisMac: return String(localized: "timeline.empty_state.no_activity_this_mac", defaultValue: "No activity from this Mac", comment: "Empty-state title when no timeline activity is recorded on this Mac.")
        case .fromIPhone: return String(localized: "timeline.empty_state.no_activity_iphone", defaultValue: "No activity from iPhone", comment: "Empty-state title when no timeline activity is synced from iPhone.")
        }
    }

    private var timelineScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
                ForEach(groupedEntries) { group in
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                        Text(group.header)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .padding(.leading, MuesliTheme.spacing4)

                        VStack(spacing: 1) {
                            ForEach(group.entries) { entry in
                                timelineRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .scrollTargetLayout()
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                }

                if appState.hasMoreTimelineEntries {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { controller.loadMoreTimelineEntries() }
                }
            }
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.bottom, MuesliTheme.spacing24)
        }
        .scrollPosition(id: Binding(
            get: { appState.timelineScrollAnchor },
            set: { appState.timelineScrollAnchor = $0 }
        ), anchor: .top)
    }

    @ViewBuilder
    private func timelineRow(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .dictation(let record):
            DictationRowView(
                record: record,
                timeOnly: Self.formatTime(record.timestamp),
                onCopy: { controller.copyToClipboard(record.rawText) },
                onCopyTrace: record.computerUseTrace == nil ? nil : {
                    controller.copyToClipboard(ComputerUseTraceFormatter.debugText(for: record))
                },
                onDelete: { controller.deleteDictation(id: record.id) }
            )
        case .meeting(let record):
            TimelineMeetingRow(record: record) {
                controller.showTimelineMeetingDocument(id: record.id)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "hh:mm a"
        return formatter
    }()

    fileprivate static func formatTime(_ raw: String) -> String {
        guard let date = MeetingBrowserLogic.parseDate(raw) else {
            return MeetingBrowserLogic.formatStartTime(raw)
        }
        return timeFormatter.string(from: date)
    }
}

private struct TimelineMeetingRow: View {
    let record: MeetingRecord
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing20) {
            Text(TimelineView.formatTime(record.startTime))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(width: 80, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                HStack(spacing: MuesliTheme.spacing8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                        .accessibilityLabel(String(localized: "timeline.meeting.accessibility_label", defaultValue: "Meeting", comment: "Accessibility label for meeting timeline entry."))

                    Text(record.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)

                    Text(record.status.displayLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(record.status.displayColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(record.status.displayColor.opacity(0.12))
                        .clipShape(Capsule())

                    if let label = SyncOriginDisplay.badgeLabel(forMeetingSource: record.source) {
                        SyncOriginBadge(label: label)
                    } else {
                        SyncOriginBadge(label: String(localized: "timeline.sync_origin.mac.title", defaultValue: "Mac", comment: "Sync origin badge title for entries from current Mac."), help: String(localized: "timeline.sync_origin.mac.subtitle", defaultValue: "Recorded on this Mac", comment: "Sync origin badge subtitle for entries recorded on current Mac."))
                    }

                    Spacer(minLength: 0)

                    Text(Self.formatDuration(record.durationSeconds))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }

                Text(previewText)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing20)
        .padding(.vertical, MuesliTheme.spacing16)
        .background(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundRaised)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "timeline.meeting.accessibility_hint.open", defaultValue: "Open meeting", comment: "Accessibility hint for opening a meeting entry."))
    }

    private var previewText: String {
        let content: String
        if !record.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.status != .completed {
            content = record.manualNotes
        } else if !record.formattedNotes.isEmpty {
            content = record.formattedNotes
        } else {
            content = record.rawTranscript
        }
        let preview = MeetingPreviewText.snippet(from: content)
        return preview.isEmpty ? String(localized: "timeline.preview.no_transcript_or_notes", defaultValue: "No transcript or notes yet", comment: "Placeholder preview when meeting has no transcript or notes.") : preview
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        if rounded >= 3600 {
            return String(format: String(localized: "timeline.duration.hours_minutes", defaultValue: "%@h %@m", comment: "Duration label showing hours and minutes."), "\(rounded / 3600)", "\((rounded % 3600) / 60)")
        }
        if rounded >= 60 {
            let minutes = rounded / 60
            let remainingSeconds = rounded % 60
            return remainingSeconds == 0 ? String(format: String(localized: "timeline.duration.minutes_only", defaultValue: "%@m", comment: "Duration label showing whole minutes only."), "\(minutes)") : String(format: String(localized: "timeline.duration.minutes_seconds", defaultValue: "%@m %@s", comment: "Duration label showing minutes and remaining seconds."), "\(minutes)", "\(remainingSeconds)")
        }
        return String(format: String(localized: "timeline.duration.seconds_only", defaultValue: "%@s", comment: "Duration label showing whole seconds only."), "\(rounded)")
    }

}
