import SwiftUI
import MuesliCore

struct AboutView: View {
    let appState: AppState
    let onOpenManualDiagnosticReport: () -> Void
    let onSetAutomaticDiagnosticIssuePrompts: (Bool) -> Void

    private let githubURL = "https://github.com/Muesli-HQ/muesli"
    private let donateURL = "https://buymeacoffee.com/phequals7"
    private let actionButtonWidth: CGFloat = 136

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        return "v\(v)"
    }

    private var appDataPath: String {
        AppIdentity.supportDirectoryURL.path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing32) {
                Text(String(localized: "about.title", defaultValue: "About", comment: ""))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                if let banner = updateBanner {
                    updateBannerView(banner)
                }

                // MARK: - App Info
                sectionHeader(String(localized: "about.section.app_info", defaultValue: "App Info", comment: ""))
                aboutCard {
                    aboutRow(String(localized: "about.version.label", defaultValue: "Version", comment: "")) {
                        Text(version)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(String(localized: "about.updates", defaultValue: "Updates", comment: "")) {
                        Text(updateRowGuidance)
                            .font(MuesliTheme.callout())
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - Support
                sectionHeader(String(localized: "about.section.support", defaultValue: "Support", comment: ""))
                aboutCard {
                    aboutRow(String(localized: "about.support_development", defaultValue: "Support Development", comment: "")) {
                        Button {
                            if let url = URL(string: donateURL) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 12))
                                Text(String(localized: "about.donate", defaultValue: "Donate", comment: ""))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, MuesliTheme.spacing20)
                            .padding(.vertical, MuesliTheme.spacing8)
                            .frame(width: actionButtonWidth)
                            .background(MuesliTheme.success)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(String(localized: "about.source_code", defaultValue: "Source Code", comment: "")) {
                        actionButton("GitHub", icon: "arrow.up.right.square") {
                            if let url = URL(string: githubURL) { NSWorkspace.shared.open(url) }
                        }
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(String(localized: "about.report_problem", defaultValue: "Report a Problem", comment: "")) {
                        actionButton(String(localized: "about.open_report", defaultValue: "Open Report", comment: ""), icon: "exclamationmark.bubble") {
                            onOpenManualDiagnosticReport()
                        }
                    }

                    Divider().background(MuesliTheme.surfaceBorder)

                    aboutRow(String(localized: "about.automatic_issue_reporting_prompts", defaultValue: "Automatic issue reporting prompts", comment: "")) {
                        Toggle(String(localized: "about.auto_reporting", defaultValue: "Auto reporting", comment: ""), isOn: Binding(
                            get: { appState.config.enableAutomaticDiagnosticIssuePrompts },
                            set: onSetAutomaticDiagnosticIssuePrompts
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(String(localized: "about.auto_reporting.help", defaultValue: "Suggest an anonymized GitHub issue after an app error", comment: ""))
                        .accessibilityLabel(String(localized: "about.auto_reporting.accessibility_label", defaultValue: "Automatic issue reporting prompts", comment: ""))
                    }
                }

                // MARK: - Data
                sectionHeader(String(localized: "about.section.data", defaultValue: "Data", comment: ""))
                aboutCard {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        Text(String(localized: "about.app_data_directory", defaultValue: "App Data Directory", comment: ""))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        HStack {
                            Text(appDataPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            actionButton(String(localized: "common.open", defaultValue: "Open", comment: ""), icon: "folder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDataPath)
                            }
                        }
                    }
                }

                // MARK: - Acknowledgements
                sectionHeader(String(localized: "about.section.acknowledgements", defaultValue: "Acknowledgements", comment: ""))
                aboutCard {
                    acknowledgement(
                        name: String(localized: "about.acknowledgements.fluidaudio.title", defaultValue: "FluidAudio by FluidInference", comment: ""),
                        description: String(localized: "about.acknowledgements.fluidaudio.description", defaultValue: "CoreML speech stack powering Parakeet, Qwen3 ASR, Silero VAD, and speaker diarization on Apple Silicon.", comment: "")
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: String(localized: "about.acknowledgements.localvqe.title", defaultValue: "LocalVQE by localai-org", comment: ""),
                        description: String(localized: "about.acknowledgements.localvqe.description", defaultValue: "On-device acoustic echo cancellation powering cleaner meeting transcription.", comment: "")
                    )
                    Divider().background(MuesliTheme.surfaceBorder)
                    acknowledgement(
                        name: String(localized: "about.acknowledgements.whisperkit.title", defaultValue: "WhisperKit by Argmax", comment: ""),
                        description: String(localized: "about.acknowledgements.whisperkit.description", defaultValue: "Swift Whisper inference on CoreML/ANE powering the app's Whisper Small, Medium, and Large Turbo backends.", comment: "")
                    )
                }

                Spacer(minLength: MuesliTheme.spacing32)
            }
            .padding(MuesliTheme.spacing32)
        }
        .background(MuesliTheme.backgroundBase)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MuesliTheme.textTertiary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func aboutCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(MuesliTheme.spacing20)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private struct UpdateBanner {
        let icon: String
        let title: String
        let message: String
        let tint: Color
    }

    private var updateRowGuidance: String {
        switch appState.sparkleUpdateStatus {
        case .available:
            return String(localized: "about.updates.guidance.check_for_updates", defaultValue: "Use the menu bar icon > Check for Updates...", comment: "")
        case .downloaded:
            return String(localized: "about.updates.guidance.finish_installation", defaultValue: "Use the menu bar updater to finish installation.", comment: "")
        case .checking, .busy, .installing:
            return String(localized: "about.updates.status.checking", defaultValue: "Checking...", comment: "")
        case .failed:
            return String(localized: "about.updates.guidance.check_for_updates", defaultValue: "Use the menu bar icon > Check for Updates...", comment: "")
        case .idle, .upToDate, .disabled:
            return String(localized: "about.updates.guidance.check_for_updates", defaultValue: "Use the menu bar icon > Check for Updates...", comment: "")
        }
    }

    private var updateBanner: UpdateBanner? {
        switch appState.sparkleUpdateStatus {
        case .idle:
            return nil
        case .checking:
            return UpdateBanner(
                icon: "arrow.triangle.2.circlepath",
                title: String(localized: "about.updates.banner.checking_title", defaultValue: "Checking for updates", comment: ""),
                message: String(localized: "about.updates.banner.checking_message", defaultValue: "Muesli is checking the appcast for the latest version.", comment: ""),
                tint: MuesliTheme.transcribing
            )
        case .busy(let message):
            return UpdateBanner(
                icon: "clock.arrow.circlepath",
                title: String(localized: "about.updates.banner.busy_title", defaultValue: "Updater is busy", comment: ""),
                message: message,
                tint: MuesliTheme.transcribing
            )
        case .available(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: String(format: String(localized: "about.updates.banner.available_title", defaultValue: "Muesli %@ is available", comment: ""), "\(version)"),
                message: String(localized: "about.updates.banner.available_message", defaultValue: "An update is available. Use the menu bar icon > Check for Updates... to open the updater.", comment: ""),
                tint: MuesliTheme.transcribing
            )
        case .downloaded(let version):
            return UpdateBanner(
                icon: "exclamationmark.triangle.fill",
                title: String(format: String(localized: "about.updates.banner.ready_to_install_title", defaultValue: "Muesli %@ is ready to install", comment: ""), "\(version)"),
                message: String(localized: "about.updates.banner.ready_to_install_message", defaultValue: "The update is downloaded. Use the menu bar updater to finish installation.", comment: ""),
                tint: MuesliTheme.transcribing
            )
        case .installing(let version):
            return UpdateBanner(
                icon: "arrow.down.circle.fill",
                title: String(format: String(localized: "about.updates.banner.installing_title", defaultValue: "Installing Muesli %@", comment: ""), "\(version)"),
                message: String(localized: "about.updates.banner.installing_message", defaultValue: "Sparkle is preparing the update. Muesli may relaunch when installation finishes.", comment: ""),
                tint: MuesliTheme.transcribing
            )
        case .upToDate:
            return UpdateBanner(
                icon: "checkmark.circle.fill",
                title: String(localized: "about.updates.banner.up_to_date_title", defaultValue: "Muesli is up to date", comment: ""),
                message: String(localized: "about.updates.banner.up_to_date_message", defaultValue: "No newer version was found in the appcast.", comment: ""),
                tint: MuesliTheme.success
            )
        case .disabled(let message):
            return UpdateBanner(
                icon: "minus.circle.fill",
                title: String(localized: "about.updates.banner.disabled_title", defaultValue: "Updates are disabled", comment: ""),
                message: message,
                tint: MuesliTheme.textTertiary
            )
        case .failed(let message):
            return UpdateBanner(
                icon: "xmark.octagon.fill",
                title: String(localized: "about.updates.banner.check_failed_title", defaultValue: "Update check failed", comment: ""),
                message: String(format: String(localized: "about.updates.banner.check_failed_message", defaultValue: "%@ Use the menu bar icon > Check for Updates... to try again.", comment: ""), "\(message)"),
                tint: MuesliTheme.recording
            )
        }
    }

    @ViewBuilder
    private func updateBannerView(_ banner: UpdateBanner) -> some View {
        HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
            Image(systemName: banner.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(banner.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(banner.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(banner.message)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MuesliTheme.spacing16)
        }
        .padding(MuesliTheme.spacing16)
        .background(banner.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(banner.tint.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func aboutRow(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
            Spacer()
            control()
        }
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func acknowledgement(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuesliTheme.textPrimary)
            Text(description)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .frame(width: actionButtonWidth)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
