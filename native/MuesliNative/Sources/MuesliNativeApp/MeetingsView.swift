import SwiftUI
import MuesliCore

enum MeetingBrowserFilter: Hashable {
    case all, last2Days, lastWeek, last2Weeks, lastMonth, last3Months

    var label: String {
        switch self {
        case .all: return String(localized: "meetings.filter.range.all_time", defaultValue: "All time", bundle: .module, comment: "Filter option for showing meetings from all time")
        case .last2Days: return String(localized: "meetings.filter.range.last_2_days", defaultValue: "Last 2 days", bundle: .module, comment: "Filter option for showing meetings from last two days")
        case .lastWeek: return String(localized: "meetings.filter.range.last_week", defaultValue: "Last week", bundle: .module, comment: "Filter option for showing meetings from last week")
        case .last2Weeks: return String(localized: "meetings.filter.range.last_2_weeks", defaultValue: "Last 2 weeks", bundle: .module, comment: "Filter option for showing meetings from last two weeks")
        case .lastMonth: return String(localized: "meetings.filter.range.last_month", defaultValue: "Last month", bundle: .module, comment: "Filter option for showing meetings from last month")
        case .last3Months: return String(localized: "meetings.filter.range.last_3_months", defaultValue: "Last 3 months", bundle: .module, comment: "Filter option for showing meetings from last three months")
        }
    }
}

enum MeetingBrowserSort: Hashable {
    case newestFirst
    case oldestFirst

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "meetings.sort.newest_first", defaultValue: "Newest first", bundle: .module, comment: "Sort option for ordering meetings from newest to oldest")
        case .oldestFirst: return String(localized: "meetings.sort.oldest_first", defaultValue: "Oldest first", bundle: .module, comment: "Sort option for ordering meetings from oldest to newest")
        }
    }
}

struct MeetingBrowserPresentation {
    let meetings: [MeetingRecord]
    let meetingIDsWithFollowUps: Set<Int64>
}

enum MeetingBrowserLogic {
    static func availableFilters(
        for meetings: [MeetingRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingBrowserFilter] {
        var filters: [MeetingBrowserFilter] = [.all]
        let oldestDate = meetings.compactMap { parseDate($0.startTime) }.min()

        guard let oldest = oldestDate else { return filters }
        let daysSinceOldest = calendar.dateComponents([.day], from: oldest, to: now).day ?? 0

        if daysSinceOldest >= 1 { filters.append(.last2Days) }
        if daysSinceOldest >= 3 { filters.append(.lastWeek) }
        if daysSinceOldest >= 8 { filters.append(.last2Weeks) }
        if daysSinceOldest >= 15 { filters.append(.lastMonth) }
        if daysSinceOldest >= 31 { filters.append(.last3Months) }

        return filters
    }

    static func filteredMeetings(
        from meetings: [MeetingRecord],
        filter: MeetingBrowserFilter,
        sort: MeetingBrowserSort,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingRecord] {
        presentation(
            from: meetings,
            filter: filter,
            sort: sort,
            now: now,
            calendar: calendar
        ).meetings
    }

    static func presentation(
        from meetings: [MeetingRecord],
        filter: MeetingBrowserFilter,
        sort: MeetingBrowserSort,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MeetingBrowserPresentation {
        let threshold = threshold(for: filter, now: now, calendar: calendar)
        var meetingIDsWithFollowUps = Set<Int64>()
        var filtered: [MeetingRecord] = []

        for meeting in meetings {
            if let followUpToID = meeting.followUpToID {
                meetingIDsWithFollowUps.insert(followUpToID)
            }
            if isAfterThreshold(meeting, threshold: threshold) {
                filtered.append(meeting)
            }
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsDate = parseDate(lhs.startTime) ?? .distantPast
            let rhsDate = parseDate(rhs.startTime) ?? .distantPast
            switch sort {
            case .newestFirst:
                return lhsDate > rhsDate
            case .oldestFirst:
                return lhsDate < rhsDate
            }
        }

        return MeetingBrowserPresentation(
            meetings: sorted,
            meetingIDsWithFollowUps: meetingIDsWithFollowUps
        )
    }

    private static func threshold(
        for filter: MeetingBrowserFilter,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        switch filter {
        case .all:
            return nil
        case .last2Days:
            return calendar.date(byAdding: .day, value: -2, to: now)
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .last2Weeks:
            return calendar.date(byAdding: .day, value: -14, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .last3Months:
            return calendar.date(byAdding: .month, value: -3, to: now)
        }
    }

    private static func isAfterThreshold(_ meeting: MeetingRecord, threshold: Date?) -> Bool {
        guard let threshold else { return true }
        guard let date = parseDate(meeting.startTime) else { return false }
        return date >= threshold
    }

    static func parseDate(_ raw: String) -> Date? {
        isoParsers.lazy.compactMap { $0.date(from: raw) }.first
            ?? localParsers.lazy.compactMap { $0.date(from: raw) }.first
    }

    static func formatStartTime(
        _ raw: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date = parseDate(raw) else {
            return formatStartTimeFallback(raw)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func formatStartTimeFallback(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "T", with: " ")
        if clean.count > 16 {
            return String(clean.prefix(16))
        }
        return clean
    }

    private static let isoParsers: [ISO8601DateFormatter] = {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return [iso1, iso2]
    }()

    private static let localParsers: [DateFormatter] = {
        let local1: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return f
        }()
        let local2: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        return [local1, local2]
    }()
}

struct MeetingsView: View {
    let appState: AppState
    let controller: MuesliController
    @State private var selectedFilter: MeetingBrowserFilter = .all
    @State private var selectedSort: MeetingBrowserSort = .newestFirst

    private var scopedMeetings: [MeetingRecord] {
        appState.meetingRows
    }

    private var browserPresentation: MeetingBrowserPresentation {
        MeetingBrowserLogic.presentation(
            from: scopedMeetings,
            filter: selectedFilter,
            sort: selectedSort
        )
    }

    private var currentFolderName: String {
        guard let folderID = appState.selectedFolderID else { return String(localized: "meetings.navigation.all_meetings", defaultValue: "All Meetings", bundle: .module, comment: "Navigation title for all meetings view") }
        return appState.folders.first(where: { $0.id == folderID })?.name ?? String(localized: "meetings.navigation.all_meetings", defaultValue: "All Meetings", bundle: .module, comment: "Label for all meetings navigation destination")
    }

    private var currentDocumentMeeting: MeetingRecord? {
        guard case let .document(id) = appState.meetingsNavigationState else { return nil }
        if appState.selectedMeetingID == id, let selectedMeeting = appState.selectedMeeting {
            return selectedMeeting
        }
        return controller.meeting(id: id)
    }

    private var activeLiveMeeting: MeetingRecord? {
        controller.activeLiveMeetingRecord()
    }

    var body: some View {
        Group {
            if let meeting = currentDocumentMeeting {
                MeetingDetailView(
                    meeting: meeting,
                    controller: controller,
                    appState: appState,
                    onBack: { controller.showMeetingsHome(folderID: appState.selectedFolderID) },
                    backLabel: String(localized: "meetings.navigation.back_to_meetings", defaultValue: "Back to Meetings", bundle: .module, comment: "Back navigation label to return to meetings list")
                )
                .id(meeting.id)
            } else {
                browserView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuesliTheme.backgroundBase)
        .sheet(
            isPresented: Binding(
                get: { appState.isMeetingTemplatesManagerPresented },
                set: { appState.isMeetingTemplatesManagerPresented = $0 }
            )
        ) {
            MeetingTemplatesManagerView(
                appState: appState,
                controller: controller,
                onClose: { appState.isMeetingTemplatesManagerPresented = false }
            )
        }
    }

    @ViewBuilder
    private var browserView: some View {
        ScrollView {
            let presentation = browserPresentation
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                if !appState.upcomingCalendarEvents.isEmpty {
                    comingUpSection
                }

                if appState.isMeetingStarting {
                    MeetingPreparationBanner(
                        status: appState.meetingStartStatus,
                        onCancel: { controller.cancelMeetingPreparation() }
                    )
                }

                if let activeLiveMeeting {
                    activeMeetingBanner(activeLiveMeeting)
                }

                browserHeader(meetingCount: presentation.meetings.count)

                if presentation.meetings.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: MuesliTheme.spacing12) {
                        ForEach(presentation.meetings) { meeting in
                            MeetingListItemView(
                                record: meeting,
                                isSelected: appState.selectedMeetingID == meeting.id,
                                hasFollowUps: presentation.meetingIDsWithFollowUps.contains(meeting.id),
                                folders: appState.folders,
                                onSelect: { controller.showMeetingDocument(id: meeting.id) },
                                onMove: { folderID in
                                    controller.moveMeeting(id: meeting.id, toFolder: folderID)
                                },
                                onCreateFolderAndMove: { name in
                                    controller.createFolderAndMoveMeeting(name: name, meetingID: meeting.id)
                                },
                                onDelete: controller.canDeleteMeeting(meeting) ? {
                                    controller.deleteMeeting(id: meeting.id)
                                } : nil
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else { return }
                guard AudioFileImportController.isSupportedFileURL(url) else { return }
                DispatchQueue.main.async {
                    controller.importAudioFileFromURL(url)
                }
            }
            return true
        }
    }

    // MARK: - Coming Up

    private struct UpcomingEventGroup: Identifiable {
        let id: String
        let date: Date
        let dayLabel: String
        let dayNumber: String
        let dayOfWeek: String
        let isToday: Bool
        let events: [UnifiedCalendarEvent]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    private static let maxUpcomingEvents = 5

    private var groupedUpcomingEvents: [UpcomingEventGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let timedEvents = appState.upcomingCalendarEvents.filter { !$0.isAllDay && !appState.hiddenCalendarEventIDs.contains($0.id) }
        let grouped = Dictionary(grouping: timedEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        let dayFormatter = Self.dayFormatter
        let monthFormatter = Self.monthFormatter
        let weekdayFormatter = Self.weekdayFormatter

        let sortedDates = grouped.keys.sorted()
        var result: [UpcomingEventGroup] = []
        var remaining = Self.maxUpcomingEvents

        for date in sortedDates {
            guard remaining > 0 else { break }
            let sortedEvents = grouped[date]!.sorted { $0.startDate < $1.startDate }
            let limitedEvents = Array(sortedEvents.prefix(remaining))
            remaining -= limitedEvents.count

            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isTomorrow = calendar.date(byAdding: .day, value: 1, to: today).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
            let dayLabel: String
            if isToday {
                dayLabel = String(localized: "meetings.group.today", defaultValue: "Today", bundle: .module, comment: "Group header for meetings occurring today")
            } else if isTomorrow {
                dayLabel = String(localized: "meetings.group.tomorrow", defaultValue: "Tomorrow", bundle: .module, comment: "Group header for meetings occurring tomorrow")
            } else {
                dayLabel = monthFormatter.string(from: date)
            }
            result.append(UpcomingEventGroup(
                id: date.description,
                date: date,
                dayLabel: dayLabel,
                dayNumber: dayFormatter.string(from: date),
                dayOfWeek: weekdayFormatter.string(from: date),
                isToday: isToday,
                events: limitedEvents
            ))
        }

        return result
    }

    @ViewBuilder
    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "meetings.coming_up.title", defaultValue: "Coming Up", bundle: .module, comment: "Section title for upcoming meetings"))
                    .font(.custom("Cormorant Garamond", size: 22).weight(.medium))
                    .foregroundStyle(MuesliTheme.textPrimary)

                if appState.isGoogleCalendarAuthenticated {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                            Text(String(localized: "meetings.coming_up.add_google_calendar_realtime_sync", defaultValue: "Add Google to macOS Calendar for real-time sync", bundle: .module, comment: "Prompt to add Google account to macOS Calendar for live sync"))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(MuesliTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            let groups = groupedUpcomingEvents
            let lastGroupId = groups.last?.id
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 20) {
                    // Date column
                    VStack(alignment: .center, spacing: 2) {
                        Text(group.dayNumber)
                            .font(.system(size: 24, weight: .light, design: .default))
                            .foregroundStyle(group.isToday ? MuesliTheme.accent : MuesliTheme.textPrimary)
                        Text(group.dayLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(group.isToday ? MuesliTheme.accent : MuesliTheme.textSecondary)
                        Text(group.dayOfWeek)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                    .frame(width: 60)

                    // Events column
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(group.events) { event in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(group.isToday ? MuesliTheme.accent : MuesliTheme.textSecondary.opacity(0.4))
                                    .frame(width: 3, height: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(MuesliTheme.textPrimary)
                                        .lineLimit(1)

                                    Text(formatTimeRange(event))
                                        .font(.system(size: 11))
                                        .foregroundStyle(MuesliTheme.textSecondary)
                                }

                                Spacer()

                                if let meetingURL = event.meetingURL,
                                   !appState.isMeetingRecording,
                                   !appState.isMeetingStarting {
                                    Button {
                                        controller.joinAndRecord(
                                            title: event.title,
                                            meetingURL: meetingURL,
                                            endDate: event.endDate,
                                            calendarOccurrence: event.resolvedCalendarOccurrence
                                        )
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "video.fill")
                                                .font(.system(size: 9))
                                            Text(String(localized: "meetings.coming_up.join_and_record", defaultValue: "Join & Record", bundle: .module, comment: "Button label to join and record a meeting"))
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(nsColor: NSColor(red: 0.20, green: 0.72, blue: 0.53, alpha: 1.0)))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Menu {
                                    Button(String(localized: "meetings.coming_up.all_meetings_button", defaultValue: "All Meetings", bundle: .module, comment: "Button label to open all meetings from coming up section")) {
                                        controller.createMeetingFromCalendarEvent(event, folderID: nil)
                                    }
                                    Divider()
                                    ForEach(appState.folders) { folder in
                                        Button(folder.name) {
                                            controller.createMeetingFromCalendarEvent(event, folderID: folder.id)
                                        }
                                    }
                                } label: {
                                    Text(String(localized: "meetings.coming_up.add_to_folder", defaultValue: "Add to folder", bundle: .module, comment: "Action label to add meeting to a folder"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(MuesliTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MuesliTheme.surfacePrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 0.5)
                                        )
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()

                                hideEventButton(event)
                            }
                        }
                    }
                }

                if group.id != lastGroupId {
                    Divider()
                        .foregroundStyle(MuesliTheme.surfaceBorder)
                }
            }
        }
        .padding(20)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func formatTimeRange(_ event: UnifiedCalendarEvent) -> String {
        let f = Self.timeFormatter
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }

    private func hideEventButton(_ event: UnifiedCalendarEvent) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                controller.hideCalendarEvent(event)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary.opacity(0.6))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(String(localized: "meetings.coming_up.hide_event_help", defaultValue: "Hide from Coming Up", bundle: .module, comment: "Help text for hiding a calendar event from Coming Up section"))
    }

    @ViewBuilder
    private func browserHeader(meetingCount: Int) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: MuesliTheme.spacing16) {
                    browserHeaderTitle
                    Spacer(minLength: MuesliTheme.spacing16)
                    browserHeaderActions
                }

                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    browserHeaderTitle
                    HStack {
                        Spacer(minLength: 0)
                        browserHeaderActions
                    }
                }
            }

            browserHeaderMeta(meetingCount: meetingCount)

            RecordOriginPicker(selection: Binding(
                get: { appState.meetingOriginFilter },
                set: { controller.filterMeetings(origin: $0) }
            ))
        }
    }

    @ViewBuilder
    private var browserHeaderTitle: some View {
        Text(currentFolderName)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(MuesliTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func browserHeaderMeta(meetingCount: Int) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Text(String(format: String(localized: "meetings.count.summary", defaultValue: "%d meeting(s)", bundle: .module, comment: "Meeting count summary shown in browser header."), meetingCount))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize()

            Text("\u{2022}")
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
                .fixedSize()

            Text(String(localized: "meetings.browser.header.review_notes_transcript_summaries", defaultValue: "Open a meeting to review notes, transcript, and template-driven summaries", bundle: .module, comment: "Header text prompting user to open a meeting for details"))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var browserHeaderActions: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Button {
                controller.startQuickNoteMeeting()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "meetings.browser.quick_note", defaultValue: "Quick Note", bundle: .module, comment: "Button title for starting a quick note meeting"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(MuesliTheme.backgroundBase)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 8)
                .background(appState.isMeetingRecording || appState.isMeetingStarting ? MuesliTheme.surfacePrimary : MuesliTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .disabled(appState.isMeetingRecording || appState.isMeetingStarting)
            .help(String(localized: "meetings.browser.quick_note_help", defaultValue: "Start a quick meeting note", bundle: .module, comment: "Help text for quick note action"))
            .fixedSize()

            Button {
                controller.importAudioFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "meetings.browser.import_audio", defaultValue: "Import Audio", bundle: .module, comment: "Button title for importing an audio file"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 8)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isMeetingRecording || appState.isMeetingStarting)
            .help(String(localized: "meetings.browser.import_audio_help", defaultValue: "Import an audio file for offline transcription", bundle: .module, comment: "Help text for audio import action"))
            .fixedSize()

            sortButton
            dateFilterButton

            Button {
                controller.showMeetingTemplatesManager()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .medium))
                    Text(String(localized: "meetings.browser.manage_templates", defaultValue: "Manage Templates", bundle: .module, comment: "Button title for managing meeting templates"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 8)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func activeMeetingBanner(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(activeMeetingStatusColor(for: meeting))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                    Text(activeMeetingStatusText(for: meeting))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
            }

            Spacer(minLength: MuesliTheme.spacing12)

            Button {
                controller.showMeetingDocument(id: meeting.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "meetings.active_banner.open_notes", defaultValue: "Open Notes", bundle: .module, comment: "Action button to open notes for active meeting"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 8)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)

            if meeting.status == .recording {
                Button {
                    controller.toggleMeetingRecordingPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appState.isMeetingRecordingPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(appState.isMeetingRecordingPaused ? String(localized: "meetings.active_banner.resume", defaultValue: "Resume", bundle: .module, comment: "Button label to resume active recording") : String(localized: "meetings.active_banner.pause", defaultValue: "Pause", bundle: .module, comment: "Button label to pause active recording"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(appState.isMeetingRecordingPaused ? MuesliTheme.backgroundBase : MuesliTheme.textPrimary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 8)
                    .background(appState.isMeetingRecordingPaused ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(appState.isMeetingRecordingPaused ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!appState.isMeetingRecording)

                Button {
                    controller.stopMeetingRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(String(localized: "meetings.active_banner.stop", defaultValue: "Stop", bundle: .module, comment: "Button label to stop active recording"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 8)
                    .background(MuesliTheme.recording)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .disabled(!appState.isMeetingRecording)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func activeMeetingStatusText(for meeting: MeetingRecord) -> String {
        guard meeting.status == .recording else { return String(localized: "meetings.active_status.finalizing_notes", defaultValue: "Finalizing notes", bundle: .module, comment: "Status text while meeting notes are finalizing") }
        return appState.isMeetingRecordingPaused ? String(localized: "meetings.active_status.recording_paused", defaultValue: "Recording paused", bundle: .module, comment: "Status text when recording is paused") : String(localized: "meetings.active_status.recording_now", defaultValue: "Recording now", bundle: .module, comment: "Status text when recording is in progress")
    }

    private func activeMeetingStatusColor(for meeting: MeetingRecord) -> Color {
        guard meeting.status == .recording else { return MuesliTheme.accent }
        return appState.isMeetingRecordingPaused ? MuesliTheme.transcribing : MuesliTheme.recording
    }

    @ViewBuilder
    private var sortButton: some View {
        Menu {
            ForEach([MeetingBrowserSort.newestFirst, .oldestFirst], id: \.self) { option in
                Button {
                    selectedSort = option
                } label: {
                    HStack {
                        Text(option.label)
                        if selectedSort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                Text(selectedSort.label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(selectedSort != .newestFirst ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(selectedSort != .newestFirst ? MuesliTheme.accent.opacity(0.12) : MuesliTheme.surfacePrimary.opacity(0.5))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var dateFilterButton: some View {
        Menu {
            ForEach(availableFilters, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    HStack {
                        Text(filter.label)
                        if selectedFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                if selectedFilter != .all {
                    Text(selectedFilter.label)
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(selectedFilter != .all ? MuesliTheme.accent : MuesliTheme.textTertiary)
            .padding(.horizontal, selectedFilter != .all ? 8 : 0)
            .padding(.vertical, 3)
            .background(selectedFilter != .all ? MuesliTheme.accent.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var availableFilters: [MeetingBrowserFilter] {
        MeetingBrowserLogic.availableFilters(for: scopedMeetings)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Image(systemName: appState.selectedFolderID == nil ? "person.2.wave.2" : "folder")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(MuesliTheme.textTertiary)

            Text(emptyStateTitle)
                .font(MuesliTheme.title3())
                .foregroundStyle(MuesliTheme.textSecondary)

            Text(emptyStateInstruction)
            .font(MuesliTheme.callout())
            .foregroundStyle(MuesliTheme.textTertiary)
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(MuesliTheme.spacing24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerXL))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerXL)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var emptyStateTitle: String {
        switch appState.meetingOriginFilter {
        case .thisMac:
            return String(localized: "meetings.empty_state.title.no_meetings_from_mac", defaultValue: "No meetings from this Mac", bundle: .module, comment: "Empty state title when no meetings are available from Mac source")
        case .fromIPhone:
            return String(localized: "meetings.empty_state.title.no_meetings_from_iphone", defaultValue: "No meetings from iPhone", bundle: .module, comment: "Empty state title when no meetings are available from iPhone source")
        case .all:
            return appState.selectedFolderID == nil ? String(localized: "meetings.empty_state.title.no_meetings_yet", defaultValue: "No meetings yet", bundle: .module, comment: "Empty state title when there are no meetings at all") : String(localized: "meetings.empty_state.title.no_meetings_in_folder", defaultValue: "No meetings in this folder", bundle: .module, comment: "Empty state title when selected folder has no meetings")
        }
    }

    private var emptyStateInstruction: String {
        if appState.meetingOriginFilter != .all || selectedFilter != .all {
            return String(localized: "meetings.empty_state.instruction.try_another_source_time_range_or_folder", defaultValue: "Try another source, time range, or folder.", bundle: .module, comment: "Empty state guidance to broaden filters")
        }
        return appState.selectedFolderID == nil
            ? String(localized: "meetings.empty_state.instruction.start_recording_from_menu_bar", defaultValue: "Start a recording from the menu bar to create your first meeting note.", bundle: .module, comment: "Empty state guidance for first meeting note creation")
            : String(localized: "meetings.empty_state.instruction.choose_another_folder_or_move_meeting", defaultValue: "Choose another folder or move a meeting here from the browser.", bundle: .module, comment: "Empty state guidance for folder with no meetings")
    }
}
