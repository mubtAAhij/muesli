import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import TelemetryDeck

enum ICloudBridgeWorkingCopy {
    static func title(isActivationPending: Bool) -> String {
        isActivationPending
            ? String(localized: "iphone_bridge.status.setting_up_private_icloud_sync", defaultValue: "Setting up private iCloud sync", comment: "Status shown while private iCloud sync is being set up.")
            : String(localized: "iphone_bridge.status.syncing_with_private_icloud", defaultValue: "Syncing with private iCloud", comment: "Status shown while syncing through private iCloud.")
    }

    static func subtitle(isActivationPending: Bool) -> String {
        isActivationPending
            ? String(localized: "iphone_bridge.subtitle.creating_sync_channel", defaultValue: "Creating the sync channel and pulling your latest text records.", comment: "Subtitle for initial sync channel setup phase.")
            : String(localized: "iphone_bridge.subtitle.checking_for_new_text", defaultValue: "Checking for new text and uploading local changes.", comment: "Subtitle for active text synchronization phase.")
    }

    static func buttonHelp(isActivationPending: Bool) -> String {
        isActivationPending
            ? String(localized: "iphone_bridge.button_help.sync_setup_in_progress", defaultValue: "Sync setup is in progress", comment: "Help text for disabled button while sync setup is running.")
            : String(localized: "iphone_bridge.button_help.text_sync_in_progress", defaultValue: "Text sync is in progress", comment: "Help text for disabled button while text sync is running.")
    }
}
struct IPhoneBridgeCard: View {
    let appState: AppState
    let controller: MuesliController

    @State private var promptSeen = false
    @State private var isQRCodePresented = false

    var body: some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
            BridgeSyncIcon(
                systemName: bridgeIcon,
                isAnimating: bridgeSyncIconIsAnimating,
                font: .system(size: 18, weight: .semibold)
            )
            .foregroundStyle(bridgeIconColor)
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(bridgeTitle)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(bridgeSubtitle)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: MuesliTheme.spacing12)

            if shouldShowHandoffButton {
                Button {
                    isQRCodePresented = true
                    TelemetryDeck.signal("bridge_qr_shown", parameters: ["platform": "macos"])
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .help(String(localized: "iphone_bridge.help.show_setup_qr", defaultValue: "Show iPhone setup QR", comment: "Help text for showing iPhone setup QR code."))
            }

            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Text(buttonTitle)
                    BridgeSyncIcon(
                        systemName: buttonIcon,
                        isAnimating: buttonIconIsAnimating,
                        font: .system(size: 12, weight: .semibold)
                    )
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(MuesliTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .disabled(actionDisabled)
            .help(buttonHelp)

            Button {
                controller.updateConfig { $0.showIOSCompanionPrompt = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
            .help(String(localized: "iphone_bridge.help.hide_ios_companion_prompt", defaultValue: "Hide iOS companion prompt", comment: "Help text for hiding iOS companion prompt."))
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .onAppear {
            guard !promptSeen else { return }
            promptSeen = true
            TelemetryDeck.signal("bridge_prompt_seen", parameters: ["platform": "macos"])
        }
        .sheet(isPresented: $isQRCodePresented) {
            IPhoneBridgeQRCodeSheet(
                deepLinkURL: IPhoneBridgeLinks.iOSSyncDeepLinkURL,
                installURL: IPhoneBridgeLinks.installURL
            )
        }
    }

    private var bridgeState: ICloudBridgeState {
        appState.iCloudBridgeState
    }

    private var shouldShowHandoffButton: Bool {
        guard appState.config.iCloudSyncEnabled else { return false }
        switch bridgeState {
        case .needsICloud, .error:
            return false
        case .active:
            return appState.iCloudBridgeCompanionDeviceName == nil
        case .notConfigured, .checkingICloud, .syncing:
            return false
        }
    }

    private var bridgeSyncIconIsAnimating: Bool {
        isSyncWorking && bridgeIcon == "arrow.triangle.2.circlepath"
    }

    private var buttonIconIsAnimating: Bool {
        isSyncWorking && buttonIcon == "arrow.triangle.2.circlepath"
    }

    private var isSyncWorking: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var bridgeIcon: String {
        switch bridgeState {
        case .active: return "checkmark.icloud"
        case .checkingICloud, .syncing: return "arrow.triangle.2.circlepath"
        case .needsICloud, .error: return "exclamationmark.icloud"
        case .notConfigured: return "iphone.gen3"
        }
    }

    private var bridgeIconColor: Color {
        switch bridgeState {
        case .active: return MuesliTheme.success
        case .needsICloud, .error: return MuesliTheme.transcribing
        default: return MuesliTheme.accent
        }
    }

    private var bridgeTitle: String {
        switch bridgeState {
        case .active:
            guard let deviceName = appState.iCloudBridgeCompanionDeviceName else {
                if let lastSyncedAt = appState.iCloudLastSyncedAt {
                    return String(format: String(localized: "iphone_bridge.title.icloud_sync_active_with_time", defaultValue: "iCloud sync active · %@", comment: "Title showing active iCloud sync with relative sync time."), "\(relativeSyncTime(lastSyncedAt))")
                }
                return String(localized: "iphone_bridge.title.icloud_sync_active", defaultValue: "iCloud sync active", comment: "Title showing active iCloud sync state.")
            }
            if let lastSyncedAt = appState.iCloudLastSyncedAt {
                return String(format: String(localized: "iphone_bridge.title.synced_with_device_with_time", defaultValue: "Synced with %@ · %@", comment: "Title showing synced device name with relative sync time."), "\(deviceName)", "\(relativeSyncTime(lastSyncedAt))")
            }
            return String(format: String(localized: "iphone_bridge.title.synced_with_device", defaultValue: "Synced with %@", comment: "Title showing synced device name."), "\(deviceName)")
        case .checkingICloud:
            return String(localized: "iphone_bridge.title.setting_up_private_icloud_sync", defaultValue: "Setting up private iCloud sync", comment: "Title shown while private iCloud sync setup is in progress.")
        case .syncing:
            return ICloudBridgeWorkingCopy.title(
                isActivationPending: appState.isICloudBridgeActivationPending
            )
        case .needsICloud:
            return String(localized: "iphone_bridge.title.sign_in_to_icloud_to_sync", defaultValue: "Sign in to iCloud to sync", comment: "Title prompting user to sign in to iCloud for sync.")
        case .error:
            return String(localized: "iphone_bridge.title.sync_needs_attention", defaultValue: "iPhone sync needs attention", comment: "Title indicating iPhone sync requires attention.")
        case .notConfigured:
            return String(localized: "iphone_bridge.title.use_muesli_on_iphone", defaultValue: "Use Muesli on iPhone", comment: "Title inviting user to use Muesli on iPhone.")
        }
    }

    private var bridgeSubtitle: String {
        switch bridgeState {
        case .active:
            if let deviceName = appState.iCloudBridgeCompanionDeviceName {
                return String(format: String(localized: "iphone_bridge.subtitle.sync_on_with_device_audio_local", defaultValue: "Private iCloud text sync is on with %@. Audio stays local.", comment: "Subtitle confirming sync is enabled with device and audio remains local."), "\(deviceName)")
            }
            return String(localized: "iphone_bridge.subtitle.scan_qr_connect_iphone", defaultValue: "Scan the QR code to connect your iPhone. Audio stays local.", comment: "Subtitle instructing user to scan QR code to connect iPhone.")
        case .checkingICloud:
            return String(localized: "iphone_bridge.subtitle.checking_macos_icloud_account", defaultValue: "Checking this Mac's iCloud account...", comment: "Subtitle shown while checking Mac iCloud account state.")
        case .syncing:
            return ICloudBridgeWorkingCopy.subtitle(
                isActivationPending: appState.isICloudBridgeActivationPending
            )
        case .needsICloud, .error:
            return appState.iCloudBridgeMessage ?? String(localized: "iphone_bridge.subtitle.open_icloud_settings_try_again", defaultValue: "Open iCloud settings, then try again.", comment: "Subtitle instructing user to open iCloud settings and retry.")
        case .notConfigured:
            return String(localized: "iphone_bridge.subtitle.history_follows_private_icloud", defaultValue: "Your Muesli history follows you through private iCloud. Audio stays local.", comment: "Subtitle describing private iCloud history sync behavior.")
        }
    }

    private var buttonTitle: String {
        switch bridgeState {
        case .active: return String(localized: "iphone_bridge.button_title.sync", defaultValue: "Sync", comment: "Primary button title to trigger sync.")
        case .checkingICloud, .syncing: return String(localized: "iphone_bridge.button_title.syncing", defaultValue: "Syncing", comment: "Button title shown while sync is in progress.")
        case .needsICloud, .error: return String(localized: "iphone_bridge.button_title.try_again", defaultValue: "Try again", comment: "Button title to retry failed iPhone bridge action.")
        case .notConfigured: return String(localized: "iphone_bridge.button_title.set_up_private_icloud_sync", defaultValue: "Set up private iCloud sync", comment: "Button title to start private iCloud sync setup.")
        }
    }

    private var buttonIcon: String {
        bridgeState == .notConfigured ? "icloud" : "arrow.triangle.2.circlepath"
    }

    private var actionDisabled: Bool {
        bridgeState == .checkingICloud || bridgeState == .syncing
    }

    private var buttonHelp: String {
        switch bridgeState {
        case .active:
            return String(localized: "iphone_bridge.button_help.sync_text_with_icloud", defaultValue: "Sync text with iCloud", comment: "Help text for sync action button.")
        case .checkingICloud:
            return String(localized: "iphone_bridge.button_help.sync_setup_in_progress", defaultValue: "Sync setup is in progress", comment: "Help text when sync setup is currently running.")
        case .syncing:
            return ICloudBridgeWorkingCopy.buttonHelp(
                isActivationPending: appState.isICloudBridgeActivationPending
            )
        default:
            return String(localized: "iphone_bridge.button_help.set_up_private_icloud_text_sync", defaultValue: "Set up private iCloud text sync", comment: "Help text for setting up private iCloud text sync.")
        }
    }

    private func primaryAction() {
        switch bridgeState {
        case .active:
            controller.performICloudSync()
        case .checkingICloud, .syncing:
            break
        default:
            controller.enableIPhoneBridgeSync()
        }
    }

    private func relativeSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct BridgeSyncIcon: View {
    let systemName: String
    let isAnimating: Bool
    let font: Font
    @State private var rotationDegrees = 0.0

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear { updateRotation(animated: false) }
            .onChange(of: isAnimating) { _, _ in updateRotation(animated: true) }
    }

    private func updateRotation(animated: Bool) {
        guard isAnimating else {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) { rotationDegrees = 0 }
            } else {
                rotationDegrees = 0
            }
            return
        }

        rotationDegrees = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotationDegrees = 360
        }
    }
}

private struct IPhoneBridgeQRCodeSheet: View {
    let deepLinkURL: URL
    let installURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var didCopySetupLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(String(localized: "iphone_bridge.open_muesli_on_iphone", defaultValue: "Open Muesli on iPhone", comment: "Button title to open Muesli iPhone app information."))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(String(localized: "iphone_bridge.scan_after_install_description", defaultValue: "Scan this after installing the iPhone app. The QR only opens setup; private iCloud does the actual sync.", comment: "Description text for QR setup flow after iPhone app installation."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
                QRCodeImage(payload: deepLinkURL.absoluteString)
                    .frame(width: 148, height: 148)
                    .padding(MuesliTheme.spacing8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Label(String(localized: "iphone_bridge.benefit.same_icloud_account", defaultValue: "Same iCloud account", comment: "Benefit bullet indicating same iCloud account requirement."), systemImage: "icloud")
                    Label(String(localized: "iphone_bridge.benefit.text_sync_only", defaultValue: "Text sync only", comment: "Benefit bullet indicating only text is synced."), systemImage: "text.badge.checkmark")
                    Label(String(localized: "iphone_bridge.benefit.audio_stays_local", defaultValue: "Audio stays local", comment: "Benefit bullet indicating audio remains local to device."), systemImage: "lock")
                }
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
            }

            HStack(spacing: MuesliTheme.spacing8) {
                Button(String(localized: "iphone_bridge.button.open_iphone_app_page", defaultValue: "Open iPhone app page", comment: "Button title to open iPhone app page.")) { NSWorkspace.shared.open(installURL) }
                    .buttonStyle(.bordered)

                Button(didCopySetupLink ? String(localized: "iphone_bridge.copied", defaultValue: "Copied!", comment: "Transient confirmation text after copying setup link.") : String(localized: "iphone_bridge.button.copy_setup_link", defaultValue: "Copy setup link", comment: "Button title to copy iPhone setup link.")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deepLinkURL.absoluteString, forType: .string)
                    didCopySetupLink = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1500))
                        didCopySetupLink = false
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MuesliTheme.spacing20)
        .frame(width: 430)
        .background(MuesliTheme.backgroundBase)
    }
}

private struct QRCodeImage: View {
    let payload: String
    @State private var cachedImage: NSImage?

    var body: some View {
        Group {
            if let cachedImage {
                Image(nsImage: cachedImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
        .accessibilityLabel(String(localized: "iphone_bridge.accessibility.qr_code_label", defaultValue: "iPhone sync setup QR code", comment: "Accessibility label for the iPhone sync setup QR code image."))
        .onAppear {
            if cachedImage == nil {
                cachedImage = makeQRCodeImage(payload: payload)
            }
        }
    }

    private func makeQRCodeImage(payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            return nil
        }

        let representation = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
