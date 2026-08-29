import SwiftUI
import MuesliCore

extension MeetingStatus {
    var displayLabel: String {
        switch self {
        case .recording:
            return String(localized: "meeting_status_display.label.recording", defaultValue: "Recording", bundle: .module, comment: "Meeting status label indicating recording is in progress")
        case .processing:
            return String(localized: "meeting_status_display.label.processing", defaultValue: "Processing", bundle: .module, comment: "Meeting status label indicating processing is in progress")
        case .completed:
            return String(localized: "meeting_status_display.label.completed", defaultValue: "Completed", bundle: .module, comment: "Meeting status label indicating completion")
        case .noteOnly:
            return String(localized: "meeting_status_display.label.note_only", defaultValue: "Note only", bundle: .module, comment: "Meeting status label indicating note-only mode")
        case .failed:
            return String(localized: "meeting_status_display.label.needs_attention", defaultValue: "Needs attention", bundle: .module, comment: "Meeting status label indicating attention is required")
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
