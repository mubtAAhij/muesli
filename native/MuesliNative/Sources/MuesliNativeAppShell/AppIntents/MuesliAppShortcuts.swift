import AppIntents

@available(macOS 13.0, *)
struct MuesliAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.start_dictation.phrase", defaultValue: "Start dictation in %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.start_dictation.short_title", defaultValue: "Start Dictation", comment: ""),
            systemImageName: "mic"
        )
        AppShortcut(
            intent: StopDictationIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.stop_dictation.phrase", defaultValue: "Stop dictation in %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.stop_dictation.short_title", defaultValue: "Stop Dictation", comment: ""),
            systemImageName: "mic.slash"
        )
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.start_meeting_recording.phrase", defaultValue: "Start a meeting recording in %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.start_meeting_recording.short_title", defaultValue: "Start Meeting Recording", comment: ""),
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopMeetingIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.stop_meeting_recording.phrase", defaultValue: "Stop the meeting recording in %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.stop_meeting_recording.short_title", defaultValue: "Stop Meeting Recording", comment: ""),
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: GetLastDictationIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.get_last_dictation.phrase", defaultValue: "Get my last dictation from %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.get_last_dictation.short_title", defaultValue: "Get Last Dictation", comment: ""),
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: GetLastMeetingIntent(),
            phrases: [String(format: String(localized: "app_shortcuts.get_last_meeting_notes.phrase", defaultValue: "Get my last meeting notes from %@", comment: ""), "\(.applicationName)")],
            shortTitle: String(localized: "app_shortcuts.get_last_meeting_notes.short_title", defaultValue: "Get Last Meeting Notes", comment: ""),
            systemImageName: "doc.text"
        )
    }
}
