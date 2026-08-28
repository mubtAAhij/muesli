import SwiftUI

struct MeetingPreparationBanner: View {
    let status: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: MuesliTheme.spacing12) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
                .accessibilityLabel(String(localized: "meeting_preparation_banner.title.preparing_transcription", defaultValue: "Preparing transcription", bundle: .module, comment: "Banner title shown while meeting transcription is being prepared."))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "meeting_preparation_banner.title.preparing_transcription", defaultValue: "Preparing transcription", bundle: .module, comment: "Banner title shown while meeting transcription is being prepared."))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(status ?? String(localized: "meeting_preparation_banner.message.starting_shortly", defaultValue: "Meeting transcription will start shortly.", bundle: .module, comment: "Banner message indicating transcription startup is imminent."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: MuesliTheme.spacing12)

            Button(action: onCancel) {
                Label(String(localized: "meeting_preparation_banner.cancel", defaultValue: "Cancel", bundle: .module, comment: "Button title to cancel meeting preparation."), systemImage: "xmark.circle")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "meeting_preparation_banner.cancel_help", defaultValue: "Cancel meeting preparation", bundle: .module, comment: "Accessibility/help label for cancel meeting preparation action."))
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
