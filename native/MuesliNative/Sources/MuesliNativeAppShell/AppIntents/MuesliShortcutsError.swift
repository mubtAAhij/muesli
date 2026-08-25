import AppIntents

@available(macOS 13.0, *)
enum MuesliShortcutsError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noDictations
    case noMeetings
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDictations: return String(localized: "muesli_shortcuts_error.no_dictations", defaultValue: "Muesli has no dictations yet.", comment: "")
        case .noMeetings: return String(localized: "muesli_shortcuts_error.no_meetings", defaultValue: "Muesli has no meetings yet.", comment: "")
        case .notRunning: return String(localized: "muesli_shortcuts_error.app_not_running", defaultValue: "Muesli isn't running. Open Muesli and try again.", comment: "")
        }
    }
}
