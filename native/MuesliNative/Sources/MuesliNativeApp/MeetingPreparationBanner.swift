import SwiftUI

struct MeetingPreparationBanner: View {
    let status: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: MuesliTheme.spacing12) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
                .accessibilityLabel(String(localized: "meeting_preparation_banner.accessibility.preparing_transcription", defaultValue: "Preparing transcription", comment: "Accessibility value while meeting transcription preparation is in progress"))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "meeting_preparation_banner.preparing_transcription", defaultValue: "Preparing transcription", comment: "Primary banner text while meeting transcription preparation is in progress"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(status ?? String(localized: "meeting_preparation_banner.subtitle.transcription_will_start_shortly", defaultValue: "Meeting transcription will start shortly.", comment: "Subtitle text indicating transcription will begin soon"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: MuesliTheme.spacing12)

            Button(action: onCancel) {
                Label(String(localized: "meeting_preparation_banner.cancel", defaultValue: "Cancel", comment: "Button title to cancel meeting preparation"), systemImage: "xmark.circle")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "meeting_preparation_banner.cancel_help", defaultValue: "Cancel meeting preparation", comment: "Help text for canceling meeting preparation"))
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }
}
