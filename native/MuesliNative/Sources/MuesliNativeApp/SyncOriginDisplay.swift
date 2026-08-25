import SwiftUI
import MuesliCore

enum SyncOriginDisplay {
    static let iOSSource = "ios"
    static let iOSBadgeLabel = String(localized: "sync_origin_display.ios_badge_label", defaultValue: "iOS", comment: "Badge label indicating record originated from iOS app")
    static let iOSBadgeHelp = String(localized: "sync_origin_display.ios_badge_help", defaultValue: "Synced from Muesli for iOS", comment: "Help text for iOS origin badge in sync origin display")

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
        case .all: return String(localized: "sync_origin_display.filter_label.all", defaultValue: "All", comment: "Filter option label to show records from all origins")
        case .thisMac: return String(localized: "sync_origin_display.filter_label.this_mac", defaultValue: "This Mac", comment: "Filter option label for records created on this Mac")
        case .fromIPhone: return String(localized: "sync_origin_display.filter_label.from_iphone", defaultValue: "From iPhone", comment: "Filter option label for records synced from iPhone")
        }
    }
}

struct RecordOriginPicker: View {
    @Binding var selection: RecordOriginFilter

    var body: some View {
        Picker(String(localized: "sync_origin_display.record_source", defaultValue: "Record source", comment: "UI label for sync origin filter control"), selection: $selection) {
            ForEach(RecordOriginFilter.allCases, id: \.self) { origin in
                Text(origin.label).tag(origin)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
        .help(String(localized: "sync_origin_display.record_source.help_text", defaultValue: "Filter by the device where the recording was created", comment: "Help text describing sync origin filter behavior"))
        .accessibilityLabel(String(localized: "sync_origin_display.record_source.accessibility_label", defaultValue: "Record source", comment: "Accessibility label for sync origin filter control"))
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
