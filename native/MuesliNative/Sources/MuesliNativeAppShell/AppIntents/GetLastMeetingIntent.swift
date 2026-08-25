import AppIntents
import Foundation

@available(macOS 13.0, *)
struct GetLastMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = String(localized: "app_intents.get_last_meeting.title", defaultValue: "Get Last Meeting Notes", comment: "")
    static var description = IntentDescription(String(localized: "app_intents.get_last_meeting.description", defaultValue: "Returns the formatted notes from your most recent Muesli meeting.", comment: ""))

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = try MuesliShortcutsStore.open()
        // Skip meetings still recording or being processed: their notes and
        // transcript are not ready yet, so returning one would yield empty
        // text. Find the most recent meeting with usable content instead.
        for meeting in try store.recentMeetings(limit: 10) {
            switch meeting.status {
            case .recording, .processing: continue
            default: break
            }
            let notes = meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { return .result(value: notes) }
            let transcript = meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty { return .result(value: transcript) }
        }
        throw MuesliShortcutsError.noMeetings
    }
}
