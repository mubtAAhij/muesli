import SwiftUI
import MuesliCore

enum SyncOriginDisplay {
    static let iOSSource = "ios"
    static let iOSBadgeLabel = String(localized: "sync_origin_display.ios_badge_label", defaultValue: "iOS", comment: "Badge label shown for recordings synced from iOS")
    static let iOSBadgeHelp = String(localized: "sync_origin_display.ios_badge_help", defaultValue: "Synced from Muesli for iOS", comment: "Help text for iOS sync origin badge")

    static func badgeLabel(forDictationSource source: String) -> String? {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == iOSSource
            ? iOSBadgeLabel
            : nil
    }

    static func badgeLabel(forMeetingSource source: MeetingSource) -> String? {
        source == .iOS ? iOSBadgeLabel : nil
    }
}

extension RecordOriginFilter {
    var label: String {
        switch self {
        case .all: return String(localized: "sync_origin_display.filter_label.all", defaultValue: "All", comment: "Segment label for showing all recording sources")
        case .thisMac: return String(localized: "sync_origin_display.filter_label.from_iphone", defaultValue: "This Mac", comment: "Segment label for recordings created on this Mac")
        case .fromIPhone: return String(localized: "sync_origin_display.record_source", defaultValue: "From iPhone", comment: "Segment label for recordings created on iPhone")
        }
    }
}

struct RecordOriginPicker: View {
    @Binding var selection: RecordOriginFilter

    var body: some View {
        Picker(String(localized: "sync_origin_display.record_source.help_text", defaultValue: "Record source", comment: "Label for recording source filter picker"), selection: $selection) {
            ForEach(RecordOriginFilter.allCases, id: \.self) { origin in
                Text(origin.label).tag(origin)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
        .help(String(localized: "sync_origin_display.record_source.accessibility_label", defaultValue: "Filter by the device where the recording was created", comment: "Help text explaining the recording source filter"))
        .accessibilityLabel(String(localized: "sync_origin_display.record_source.accessibility_label-record-source", defaultValue: "Record source", comment: "Accessibility label for recording source filter picker"))
    }
}

struct SyncOriginBadge: View {
    let label: String
    var help: String = SyncOriginDisplay.iOSBadgeHelp

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(MuesliTheme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(MuesliTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help(help)
            .accessibilityLabel(help)
    }
}
