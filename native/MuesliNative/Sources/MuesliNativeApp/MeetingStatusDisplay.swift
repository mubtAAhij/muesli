import SwiftUI
import MuesliCore

extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .recording:
            return String(localized: "meeting_status_display.label.recording", defaultValue: "Recording", comment: "Meeting status label when recording is active")
        case .processing:
            return String(localized: "meeting_status_display.label.processing", defaultValue: "Processing", comment: "Meeting status label while processing recording")
        case .completed:
            return String(localized: "meeting_status_display.label.completed", defaultValue: "Completed", comment: "Meeting status label when processing is complete")
        case .noteOnly:
            return String(localized: "meeting_status_display.label.note_only", defaultValue: "Note only", comment: "Meeting status label for note-only meetings")
        case .failed:
            return String(localized: "meeting_status_display.label.needs_attention", defaultValue: "Needs attention", comment: "Meeting status label when action is needed due to an issue")
        }
    }

    var displayColor: Color {
        switch self {
        case .recording:
            return MuesliTheme.recording
        case .processing:
            return MuesliTheme.accent
        case .completed:
            return MuesliTheme.success
        case .noteOnly:
            return MuesliTheme.textTertiary
        case .failed:
            return MuesliTheme.transcribing
        }
    }
}
