import Foundation

enum UpcomingMeetingsWindow: Int, CaseIterable, Identifiable {
    case today = 1
    case twoDays = 2
    case threeDays = 3

    static let defaultDayCount = UpcomingMeetingsWindow.today.rawValue

    static var maxDayCount: Int {
        allCases.map(\.dayCount).max() ?? defaultDayCount
    }

    var id: Int { rawValue }
    var dayCount: Int { rawValue }

    var label: String {
        switch self {
        case .today:
            return String(localized: "upcoming_meetings_window.range_label.today_only", defaultValue: "Today only", bundle: .module, comment: "Range option label for showing only today's meetings.")
        case .twoDays:
            return String(localized: "upcoming_meetings_window.range_label.two_days", defaultValue: "Two days", bundle: .module, comment: "Range option label for showing two days of meetings.")
        case .threeDays:
            return String(localized: "upcoming_meetings_window.range_label.three_days", defaultValue: "Three days", bundle: .module, comment: "Range option label for showing three days of meetings.")
        }
    }

    static func resolve(dayCount: Int?) -> UpcomingMeetingsWindow {
        guard let dayCount, let window = UpcomingMeetingsWindow(rawValue: dayCount) else {
            return .today
        }
        return window
    }

    static func endDate(
        from now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int
    ) -> Date? {
        let window = resolve(dayCount: dayCount)
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: window.dayCount, to: startOfToday)
    }

    static func staleHiddenEventIDs(
        hiddenIDs: Set<String>,
        visibleEventIDs: Set<String>,
        dayCount: Int,
        canConfirmMissingEvents: Bool = true,
        canConfirmMissingEventID: ((String) -> Bool)? = nil
    ) -> Set<String> {
        guard canConfirmMissingEvents || canConfirmMissingEventID != nil else {
            return []
        }

        let resolvedDayCount = resolve(dayCount: dayCount).dayCount
        guard resolvedDayCount >= maxDayCount else {
            return []
        }

        return hiddenIDs.filter { hiddenID in
            guard !visibleEventIDs.contains(hiddenID) else { return false }
            return canConfirmMissingEventID?(hiddenID) ?? canConfirmMissingEvents
        }
    }
}
