import SwiftUI
import MuesliCore

extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .recording:
            return String(localized: "meeting_status_display.label.recording", defaultValue: "Recording", bundle: .module, comment: "Status label indicating a meeting is being recorded.")
        case .processing:
            return String(localized: "meeting_status_display.label.processing", defaultValue: "Processing", bundle: .module, comment: "Status label indicating meeting output is processing.")
        case .completed:
            return String(localized: "meeting_status_display.label.completed", defaultValue: "Completed", bundle: .module, comment: "Status label indicating meeting processing has completed.")
        case .noteOnly:
            return String(localized: "meeting_status_display.label.note_only", defaultValue: "Note only", bundle: .module, comment: "Status label indicating a note-only meeting entry.")
        case .failed:
            return String(localized: "meeting_status_display.label.needs_attention", defaultValue: "Needs attention", bundle: .module, comment: "Status label indicating the meeting needs user attention.")
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
