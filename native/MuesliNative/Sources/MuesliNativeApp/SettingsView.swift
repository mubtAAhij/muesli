import AppKit
import AVFoundation
import SwiftUI
import MuesliCore

private struct MeetingDetectionAppOption: Identifiable {
    let bundleID: String
    let name: String
    let icon: String

    var id: String { bundleID }
}

private struct MicrophoneOption: Identifiable {
    let uid: String?
    let label: String

    var id: String { uid ?? "__automatic__" }
}

struct SettingsView: View {
    private enum PendingDataDestruction {
        case dictations
        case meetings

        var title: String {
            switch self {
            case .dictations:
                return String(localized: "settings.clear_history.dictations.title", defaultValue: "Clear dictation history?", comment: "Confirmation alert title for clearing dictation history")
            case .meetings:
                return String(localized: "settings.clear_history.meetings.title", defaultValue: "Clear meeting history?", comment: "Confirmation alert title for clearing meeting history")
            }
        }

        var message: String {
            switch self {
            case .dictations:
                return String(localized: "settings.clear_history.dictations.message", defaultValue: "This will permanently remove all saved dictations. This cannot be undone.", comment: "Confirmation alert message for clearing dictation history")
            case .meetings:
                return String(localized: "settings.clear_history.meetings.message", defaultValue: "This will permanently remove all saved meetings, notes, transcripts, and retained audio recordings. This cannot be undone.", comment: "Confirmation alert message for clearing meeting history")
            }
        }

        var confirmLabel: String {
            switch self {
            case .dictations:
                return String(localized: "settings.clear_history.dictations.confirm", defaultValue: "Clear Dictations", comment: "Destructive confirmation button title for clearing dictations")
            case .meetings:
                return String(localized: "settings.clear_history.meetings.confirm", defaultValue: "Clear Meetings", comment: "Destructive confirmation button title for clearing meetings")
            }
        }
    }

    let appState: AppState
    let controller: MuesliController

    @State private var chatGPTSignInError: String?
    @State private var isSigningInChatGPT = false
    @State private var googleCalSignInError: String?
    @State private var isSigningInGoogleCal = false
    @State private var pendingDataDestruction: PendingDataDestruction?
    @State private var isShowingDictionaryAccessibilityPrompt = false
    @State private var isPreviewingClip = false
    @State private var selectedPane: SettingsPane
    @State private var downloadedBackendOptions: [BackendOption] = []
    @State private var downloadedPostProcOptions: [PostProcessorOption] = []
    @State private var downloadedMeetingLiveCaptionBackends: [MeetingLiveCaptionBackend] = []
    @State private var audioInputDevices: [AudioInputDeviceInfo] = []
    @State private var permissionPollTimer: Timer?
    @State private var isCleanupPromptManagerPresented = false
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @AppStorage("settings.pendingScreenContextEnable") private var pendingScreenContextEnable = false
    @AppStorage("settings.pendingScreenContextRequestedAt") private var pendingScreenContextRequestedAt = 0.0
    @State private var systemAudioGranted = false
    @State private var isCheckingSystemAudioPermission = false
    @State private var openRouterFreeModels: [SummaryModelPreset] = []
    @State private var isLoadingOpenRouterFreeModels = false
    @State private var openRouterFreeModelsError: String?
    @State private var hasRefreshedMeetingCalendarSources = false

    init(appState: AppState, controller: MuesliController) {
        self.appState = appState
        self.controller = controller
        _selectedPane = State(initialValue: appState.selectedSettingsPane)
    }

    // Uniform width for standard right-side controls.
    private let controlWidth: CGFloat = 220
    // Wider controls keep model/provider selections visually consistent in Settings.
    private let meetingControlWidth: CGFloat = 275
    private let iOSCompanionURL = IPhoneBridgeLinks.installURL
    private let screenContextGrantIntentTimeout: TimeInterval = 15 * 60
    private let meetingDetectionAppOptions: [MeetingDetectionAppOption] = [
        MeetingDetectionAppOption(bundleID: "com.google.Chrome", name: "Chrome", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "company.thebrowser.Browser", name: "Arc", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.apple.Safari", name: "Safari", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.edgemac", name: "Edge", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.brave.Browser", name: "Brave", icon: "globe"),
        MeetingDetectionAppOption(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", icon: "message.fill"),
        MeetingDetectionAppOption(bundleID: "us.zoom.xos", name: "Zoom", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "com.microsoft.teams2", name: "Teams", icon: "person.2.fill"),
        MeetingDetectionAppOption(bundleID: "com.apple.FaceTime", name: "FaceTime", icon: "video.fill"),
        MeetingDetectionAppOption(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", icon: "phone.fill"),
    ]

    private var dictationBackendOptions: [BackendOption] {
        backendOptions(including: appState.selectedBackend)
    }

    private var disabledDictationBackendLabels: Set<String> {
        guard !appState.selectedPostProcessorBackend.isCompatible(with: .gemma4E2BLiteRT),
              dictationBackendOptions.contains(.gemma4E2BLiteRT) else { return [] }
        return [BackendOption.gemma4E2BLiteRT.label]
    }

    private var meetingBackendOptions: [BackendOption] {
        downloadedBackendOptions.filter(\.supportsMeetingTranscription)
    }

    private var selectedMeetingLiveCaptionLabel: String {
        let selected = appState.config.resolvedMeetingLiveCaptionBackend
        guard appState.config.enableLiveStreamingPartials,
              downloadedMeetingLiveCaptionBackends.contains(selected) else {
            return "Off"
        }
        return selected.settingsLabel
    }

    private var usesUnifiedMeetingTranscript: Bool {
        appState.config.enableLiveStreamingPartials
            && appState.config.resolvedMeetingLiveCaptionBackend == .nemotron35
            && downloadedMeetingLiveCaptionBackends.contains(.nemotron35)
    }

    private var meetingLiveTranscriptDescription: String {
        let selected = appState.config.resolvedMeetingLiveCaptionBackend
        guard appState.config.enableLiveStreamingPartials,
              downloadedMeetingLiveCaptionBackends.contains(selected) else {
            return String(localized: "settings.meeting_live_transcript.description.completed_only", defaultValue: "Shows completed transcript segments only.", comment: "Description for completed-only transcript mode")
        }
        if usesUnifiedMeetingTranscript {
            return String(localized: "settings.meeting_live_transcript.description.live_and_final", defaultValue: "Creates the live and final transcript.", comment: "Description for live plus final transcript mode")
        }
        return String(localized: "settings.meeting_live_transcript.description.low_latency_preview", defaultValue: "Adds a low-latency preview.", comment: "Description for low-latency transcript preview mode")
    }

    private var selectedMeetingBackendLabel: String {
        if meetingBackendOptions.contains(appState.selectedMeetingTranscriptionBackend) {
            return appState.selectedMeetingTranscriptionBackend.label
        }
        return meetingBackendOptions.first?.label ?? String(localized: "settings.meeting_backend.no_downloaded_models", defaultValue: "No downloaded models", comment: "Fallback label when no meeting backend models are downloaded")
    }

    private var cleanupPromptPresets: [TranscriptCleanupPromptPreset] {
        TranscriptCleanupPrompts.presets(custom: appState.config.customTranscriptCleanupPrompts)
    }

    private var cleanupBackendOptions: [TranscriptCleanupBackendOption] {
        TranscriptCleanupBackendOption.all
    }

    private var disabledCleanupBackendLabels: Set<String> {
        Set(cleanupBackendOptions.lazy
            .filter { !$0.isCompatible(with: appState.selectedBackend) }
            .map(\.label))
    }

    private var selectedCleanupPromptName: String {
        cleanupPromptPresets.first { $0.id == appState.config.activeTranscriptCleanupPromptId }?.name
            ?? TranscriptCleanupPrompts.builtIns[0].name
    }

    private var cleanupBackendDescription: String {
        if appState.selectedPostProcessorBackend == .local {
            return downloadedPostProcOptions.isEmpty
                ? String(localized: "settings.cleanup_backend.description.download_model", defaultValue: "Download a cleanup model from Models to refine dictations on this Mac.", comment: "Cleanup backend description when no model is available locally")
                : String(localized: "settings.cleanup_backend.description.refines_on_mac", defaultValue: "Refines dictated text on this Mac.", comment: "Cleanup backend description for on-device refinement")
        }
        if appState.selectedPostProcessorBackend == .gemma4LiteRT {
            return Gemma4LiteRTModelStore.isAvailableLocally()
                ? String(localized: "settings.cleanup_backend.description.gemma4_refinement", defaultValue: "Uses the downloaded Gemma 4 model to refine dictated text on this Mac.", comment: "Cleanup backend description for Gemma 4 refinement mode")
                : String(localized: "settings.cleanup_backend.description.download_gemma4_for_cleanup", defaultValue: "Download Gemma 4 E2B from Models to use it for cleanup.", comment: "Cleanup backend description prompting Gemma 4 model download")
        }
        return String(format: String(localized: "settings.cleanup_backend.description.sends_to_backend_with_latency", defaultValue: "Sends dictated text to %@ and may add latency.", comment: "Cleanup backend description for network backend with latency note"), "\(appState.selectedPostProcessorBackend.label)")
    }

    private var selectedCohereLanguage: CohereTranscribeLanguage {
        appState.config.resolvedCohereLanguage
    }

    private var selectedUpcomingMeetingsWindow: UpcomingMeetingsWindow {
        UpcomingMeetingsWindow.resolve(dayCount: appState.config.upcomingMeetingsDayCount)
    }

    private var selectedIndicASRLanguage: IndicASRLanguage {
        appState.config.resolvedIndicASRLanguage
    }

    private var selectedNemotron35Language: Nemotron35Language {
        appState.config.resolvedNemotron35Language
    }
    private var selectedWhisperLanguage: WhisperKitLanguage {
        appState.config.resolvedWhisperLanguage
    }

    private var dictationMicrophoneOptions: [MicrophoneOption] {
        microphoneOptions(selectedUID: appState.config.dictationInputDeviceUID)
    }

    private var selectedDictationMicrophoneLabel: String {
        let selectedUID = appState.config.dictationInputDeviceUID
        return dictationMicrophoneOptions.first(where: { $0.uid == selectedUID })?.label ?? String(localized: "settings.dictation_microphone.automatic", defaultValue: "Automatic", comment: "Default dictation microphone selection label")
    }

    private var meetingMicrophoneOptions: [MicrophoneOption] {
        microphoneOptions(selectedUID: appState.config.meetingInputDeviceUID)
    }

    private var selectedMeetingMicrophoneLabel: String {
        let selectedUID = appState.config.meetingInputDeviceUID
        return meetingMicrophoneOptions.first(where: { $0.uid == selectedUID })?.label ?? String(localized: "settings.meeting_microphone.automatic", defaultValue: "Automatic", comment: "Default meeting microphone selection label")
    }

    private func microphoneOptions(selectedUID: String?) -> [MicrophoneOption] {
        var options = [MicrophoneOption(uid: nil, label: String(localized: "settings.microphone.option.automatic", defaultValue: "Automatic", comment: "Microphone option label in device picker"))]
        options += audioInputDevices.map { MicrophoneOption(uid: $0.uid, label: $0.name) }
        if let selectedUID, !options.contains(where: { $0.uid == selectedUID }) {
            options.append(MicrophoneOption(uid: selectedUID, label: String(localized: "settings.microphone.option.selected_unavailable", defaultValue: "Selected microphone unavailable", comment: "Status label when previously selected microphone is no longer available")))
        }
        return options
    }

    private var activeFeatureTourTarget: FeatureTourTarget? {
        appState.activeFeatureTourTarget
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                    Text(String(localized: "settings.title", defaultValue: "Settings", comment: "Title for the settings screen"))
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    settingsPanePicker
                    paneContent
                }
                .padding(MuesliTheme.spacing32)
            }
            .background(MuesliTheme.backgroundBase)
            .onAppear {
                refreshDownloadedModelOptions()
                refreshAudioInputDevices()
                startPermissionPolling()
                if appState.selectedMeetingSummaryBackend == .openRouter {
                    loadOpenRouterFreeModelsIfNeeded()
                }
                scrollToFeatureTourTarget(activeFeatureTourTarget, using: scrollProxy)
            }
            .onDisappear {
                SoundController.stopMaraudersMapClip()
                isPreviewingClip = false
                stopPermissionPolling()
            }
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .settings {
                    selectedPane = appState.selectedSettingsPane
                    refreshDownloadedModelOptions()
                    refreshAudioInputDevices()
                    refreshPermissionStatuses()
                }
            }
            .onChange(of: appState.selectedSettingsPane) { _, pane in
                selectedPane = pane
            }
            .onChange(of: selectedPane) { _, pane in
                appState.selectedSettingsPane = pane
                if pane == .dictation || pane == .meetings {
                    refreshAudioInputDevices()
                }
                scrollToFeatureTourTarget(activeFeatureTourTarget, using: scrollProxy)
            }
            .onChange(of: activeFeatureTourTarget) { _, target in
                scrollToFeatureTourTarget(target, using: scrollProxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard appState.selectedTab == .settings else { return }
                refreshAudioInputDevices()
                refreshPermissionStatuses(refreshLaunchAtLogin: true)
            }
            .onChange(of: appState.selectedBackend) { _, _ in
                refreshDownloadedModelOptions()
            }
            .onChange(of: appState.selectedMeetingTranscriptionBackend) { _, _ in
                refreshDownloadedModelOptions()
            }
            .onChange(of: appState.selectedMeetingSummaryBackend) { _, backend in
                if backend == .openRouter {
                    loadOpenRouterFreeModelsIfNeeded()
                }
            }
            .alert(
                pendingDataDestruction?.title ?? String(localized: "settings.alert.confirm_destructive_action.title", defaultValue: "Confirm Destructive Action", comment: "Alert title for confirming destructive settings actions"),
                isPresented: Binding(
                    get: { pendingDataDestruction != nil },
                    set: { if !$0 { pendingDataDestruction = nil } }
                )
            ) {
                Button(String(localized: "settings.action.cancel", defaultValue: "Cancel", comment: "Cancel button label in settings destructive confirmation alert"), role: .cancel) {
                    pendingDataDestruction = nil
                }
                Button(pendingDataDestruction?.confirmLabel ?? String(localized: "settings.action.delete", defaultValue: "Delete", comment: "Delete button label in settings destructive confirmation alert"), role: .destructive) {
                    switch pendingDataDestruction {
                    case .dictations:
                        controller.clearDictationHistory()
                    case .meetings:
                        controller.clearMeetingHistory()
                    case nil:
                        break
                    }
                    pendingDataDestruction = nil
                }
            } message: {
                Text(pendingDataDestruction?.message ?? "")
            }
            .alert(
                String(localized: "settings.alert.enable_accessibility.title", defaultValue: "Enable Accessibility?", comment: "Alert title asking user to enable Accessibility permission"),
                isPresented: $isShowingDictionaryAccessibilityPrompt
            ) {
                Button(String(localized: "settings.alert.action.cancel", defaultValue: "Cancel", comment: "Cancel button label in accessibility permission alert"), role: .cancel) {
                    controller.cancelDictionaryCorrectionAccessibilityEnableRequest()
                }
                Button(String(localized: "settings.alert.action.enable", defaultValue: "Enable", comment: "Enable button label in accessibility permission alert")) {
                    controller.requestDictionaryCorrectionAccessibilityEnable()
                }
            } message: {
                Text(String(localized: "settings.alert.enable_accessibility.message", defaultValue: "Dictionary suggestions briefly read focused app text via Accessibility after dictation. Grant access, then relaunch Muesli to turn suggestions on.", comment: "Alert message explaining why Accessibility permission is needed and requiring relaunch"))
            }
            .sheet(isPresented: $isCleanupPromptManagerPresented) {
                TranscriptCleanupPromptsManagerView(
                    appState: appState,
                    controller: controller,
                    onClose: { isCleanupPromptManagerPresented = false }
                )
            }
        }
    }

    private func scrollToFeatureTourTarget(_ target: FeatureTourTarget?, using proxy: ScrollViewProxy) {
        guard let target,
              target == .liveCaptionsSetting || target == .cloudCleanupSetting else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target.rawValue, anchor: .center)
            }
        }
    }

    private func refreshDownloadedModelOptions() {
        controller.refreshMeetingTranscriptionSelectionForAvailability()
        downloadedBackendOptions = BackendOption.downloaded
        downloadedPostProcOptions = PostProcessorOption.downloaded
        downloadedMeetingLiveCaptionBackends = MeetingLiveCaptionBackend.allCases.filter(\.isDownloaded)
    }

    private func refreshAudioInputDevices() {
        audioInputDevices = controller.availableDictationInputDevices()
    }

    private func backendOptions(including selection: BackendOption) -> [BackendOption] {
        var options = downloadedBackendOptions
        if !options.contains(where: { $0 == selection }) {
            options.insert(selection, at: 0)
        }
        return options
    }

    private static let accentPresets: [(hex: String, name: String)] = [
        ("2563eb", String(localized: "settings.accent_presets.blue", defaultValue: "Blue", comment: "Accent color preset name in settings")),
        ("ef4444", String(localized: "settings.accent_presets.red", defaultValue: "Red", comment: "Accent color preset name in settings")),
        ("f59e0b", String(localized: "settings.accent_presets.amber", defaultValue: "Amber", comment: "Accent color preset name in settings")),
        ("10b981", String(localized: "settings.accent_presets.green", defaultValue: "Green", comment: "Accent color preset name in settings")),
        ("8b5cf6", String(localized: "settings.accent_presets.purple", defaultValue: "Purple", comment: "Accent color preset name in settings")),
        ("ec4899", String(localized: "settings.accent_presets.pink", defaultValue: "Pink", comment: "Accent color preset name in settings")),
        ("1e1e2e", String(localized: "settings.accent_presets.dark", defaultValue: "Dark", comment: "Accent color preset name in settings")),
    ]

    private func screenContextDescription(includesScreenOCR: Bool) -> String {
        if !accessibilityGranted {
            return String(localized: "settings.screen_context.description.grant_accessibility_then_toggle", defaultValue: "Grant Accessibility, then toggle again if needed.", comment: "Description shown when screen context toggle requires Accessibility permission first")
        }
        if includesScreenOCR, !screenRecordingGranted {
            return String(localized: "settings.screen_context.description.app_text_plus_screen_recording_ocr", defaultValue: "Adds nearby app text for post-processing. Screen Recording enables OCR context.", comment: "Description for screen context including OCR with Screen Recording permission")
        }
        if includesScreenOCR {
            return String(localized: "settings.screen_context.description.app_text_and_ocr", defaultValue: "Adds nearby app text and OCR context.", comment: "Description for screen context when both app text and OCR context are included")
        }
        return String(localized: "settings.screen_context.description.app_text_only", defaultValue: "Adds nearby app text for post-processing.", comment: "Description for screen context when only app text is included")
    }

    private var dictationOCRContextDescription: String {
        if !appState.config.enableScreenContext {
            return String(localized: "settings.dictation_ocr_context.description.turn_on_app_context_first", defaultValue: "Turn on App context first.", comment: "Description indicating prerequisite setting before enabling dictation OCR context")
        }
        if !screenRecordingGranted {
            return String(localized: "settings.dictation_ocr_context.description.grant_screen_recording", defaultValue: "Grant Screen Recording to add frontmost-window OCR text.", comment: "Description prompting Screen Recording permission for OCR context")
        }
        return String(localized: "settings.dictation_ocr_context.description.ocr_text_cloud_cleanup_notice", defaultValue: "Adds frontmost-window OCR text. Cloud cleanup may send this text to the selected provider.", comment: "Description explaining OCR context data use with cloud cleanup")
    }

    @ViewBuilder
    private func screenContextRow(
        _ title: String,
        includesScreenOCR: Bool = false,
        controlWidth rowControlWidth: CGFloat? = nil
    ) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(screenContextDescription(includesScreenOCR: includesScreenOCR))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: width, height: 1)
                screenContextControl(width: width)
            }
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var dictationOCRContextRow: some View {
        let width = controlWidth
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "settings.dictation.screen_ocr_context", defaultValue: "Screen OCR context", comment: "Settings label for enabling screen OCR context"))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(dictationOCRContextDescription)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 20)

            ZStack(alignment: .trailing) {
                Color.clear.frame(width: width, height: 1)
                dictationOCRContextControl(width: width)
            }
        }
        .frame(minHeight: 52)
    }

    private let customIndicatorPositionLabel = String(localized: "settings.indicator_position.custom_drag_to_reposition", defaultValue: "Custom (drag to reposition)", comment: "Indicator position option label for custom draggable placement")

    private var settingsPanePicker: some View {
        HStack {
            Spacer()
            Picker("", selection: $selectedPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 760)
            Spacer()
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .general:
            generalSettingsPane
        case .sync:
            syncSettingsPane
        case .dictation:
            dictationSettingsPane
        case .computerUse:
            computerUseSettingsPane
        case .meetings:
            meetingsSettingsPane
        case .appearance:
            appearanceSettingsPane
        }
    }

    private var generalSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(String(localized: "settings.section.general", defaultValue: "General", comment: "Section header for general settings")) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    settingsRow(String(localized: "settings.general.launch_at_login", defaultValue: "Launch at login", comment: "Toggle label for launching app at login")) {
                        settingsSwitch(isOn: appState.config.launchAtLogin) { newValue in
                            controller.setLaunchAtLogin(newValue)
                        }
                    }
                    if appState.launchAtLoginRegistrationState == .requiresApproval {
                        launchAtLoginApprovalPrompt
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.general.open_dashboard_on_launch", defaultValue: "Open dashboard on launch", comment: "Toggle label for opening dashboard on app launch")) {
                    settingsSwitch(isOn: appState.config.openDashboardOnLaunch) { newValue in
                        controller.updateConfig { $0.openDashboardOnLaunch = newValue }
                    }
                }
            }

            permissionsSection

            settingsSection(String(localized: "settings.section.data", defaultValue: "Data", comment: "Section header for data settings")) {
                HStack(spacing: MuesliTheme.spacing12) {
                    actionButton(String(localized: "settings.data.clear_dictation_history", defaultValue: "Clear dictation history", comment: "Action label for clearing dictation history"), role: .destructive) {
                        pendingDataDestruction = .dictations
                    }
                    actionButton(String(localized: "settings.data.clear_meeting_history", defaultValue: "Clear meeting history", comment: "Action label for clearing meeting history"), role: .destructive) {
                        pendingDataDestruction = .meetings
                    }
                    .disabled(controller.isMeetingRecording())
                    .help(String(localized: "settings.general.help.stop_recording_before_clear_history", defaultValue: "Stop the current meeting recording before clearing meeting history.", comment: "Help text shown when clearing meeting history is blocked by active recording"))
                }
            }
        }
    }

    private var launchAtLoginApprovalPrompt: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.recording)
            Text(String(localized: "settings.launch_at_login.requires_approval_system_settings", defaultValue: "Requires approval in System Settings", comment: "Status text indicating launch at login needs system approval"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
            Spacer(minLength: MuesliTheme.spacing12)
            Button {
                controller.openLaunchAtLoginSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "settings.launch_at_login.action.open", defaultValue: "Open", comment: "Button label to open System Settings for login items approval"))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MuesliTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(MuesliTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .help(String(localized: "settings.launch_at_login.help.open_login_items_system_settings", defaultValue: "Open Login Items in System Settings", comment: "Help text guiding user to Login Items settings"))
        }
        .padding(.leading, MuesliTheme.spacing16)
        .padding(.trailing, MuesliTheme.spacing16)
        .padding(.bottom, MuesliTheme.spacing8)
    }

    private var syncSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(String(localized: "settings.sync.icloud_text_sync.section_title", defaultValue: "iCloud Text Sync", comment: "Section title for iCloud text synchronization settings")) {
                settingsRow(String(localized: "settings.sync.private_icloud_sync", defaultValue: "Private iCloud sync", comment: "Toggle label for private iCloud synchronization")) {
                    settingsSwitch(isOn: appState.config.iCloudSyncEnabled) { newValue in
                        controller.setICloudSyncEnabledFromSettings(newValue)
                    }
                }
                settingsDescription(String(localized: "settings.sync.description.private_icloud_scope", defaultValue: "Sync dictation text, meeting transcripts, notes, summaries, and manual notes with Muesli for iPhone through your private iCloud account. Audio recordings are never synced.", comment: "Description of what content is included in private iCloud sync"))

                Divider().background(MuesliTheme.surfaceBorder)

                HStack(spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        Text(syncStatusText)
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lastSyncedText = syncLastSyncedText {
                            Text(String(format: String(localized: "settings.sync.last_synced", defaultValue: "Last synced: %@", comment: "Status text showing last iCloud sync time"), "\(lastSyncedText)"))
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        if let linkedDeviceText = syncLinkedDeviceText {
                            Text(linkedDeviceText)
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: MuesliTheme.spacing16)
                    actionButton(String(localized: "settings.sync.action.sync_now", defaultValue: "Sync now", comment: "Button label to trigger immediate synchronization"), systemImage: "arrow.triangle.2.circlepath") {
                        controller.performICloudSync()
                    }
                    .frame(width: controlWidth)
                    .disabled(!appState.config.iCloudSyncEnabled)
                }
            }

            settingsSection(String(localized: "settings.sync.iphone_bridge.section_title", defaultValue: "iPhone Bridge", comment: "Section title for iPhone bridge connectivity settings")) {
                settingsRow(String(localized: "settings.sync.iphone_bridge.show_ios_companion_prompt", defaultValue: "Show iOS companion prompt", comment: "Toggle label for showing iOS companion prompt in bridge section")) {
                    settingsSwitch(isOn: appState.config.showIOSCompanionPrompt) { newValue in
                        controller.updateConfig { $0.showIOSCompanionPrompt = newValue }
                    }
                }
                settingsDescription(String(localized: "settings.sync.iphone_bridge.description.keep_timeline_card", defaultValue: "Keep the timeline bridge card available while users connect Muesli on iPhone.", comment: "Description for keeping timeline bridge card visible during iPhone setup"))

                Divider().background(MuesliTheme.surfaceBorder)

                HStack(spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        Text(String(localized: "settings.sync.muesli_for_iphone", defaultValue: "Muesli for iPhone", comment: "Heading for iPhone companion app section"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        Text(String(localized: "settings.sync.iphone_description", defaultValue: "Use iPhone for offline meetings, keyboard dictation, and private iCloud text sync with this Mac.", comment: "Description of iPhone companion app capabilities"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: MuesliTheme.spacing16)
                    actionButton(String(localized: "settings.sync.action.open_ios_app_page", defaultValue: "Open iOS app page", comment: "Button label for opening iOS app store page")) {
                        NSWorkspace.shared.open(iOSCompanionURL)
                    }
                    .frame(width: controlWidth)
                }
            }
        }
    }

    private var syncStatusText: String {
        if !appState.config.iCloudSyncEnabled {
            return String(localized: "settings.sync.status.off_turn_on_bridge", defaultValue: "Sync is off. Turn it on to bridge this Mac with Muesli for iPhone.", comment: "Status message when sync is disabled and bridge cannot be used")
        }
        return appState.iCloudSyncStatus ?? String(localized: "settings.sync.status.private_icloud_ready", defaultValue: "Private iCloud text sync is ready.", comment: "Status message when private iCloud text sync is available")
    }

    private var syncLastSyncedText: String? {
        guard let date = appState.iCloudLastSyncedAt else { return nil }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private var syncLinkedDeviceText: String? {
        guard appState.config.iCloudSyncEnabled else { return nil }
        if let remoteDeviceName = appState.iCloudBridgeCompanionDeviceName {
            if let platform = appState.iCloudBridgeRemoteDevicePlatform {
                return String(format: String(localized: "settings.sync.linked_device.with_platform_and_name", defaultValue: "Linked %@: %@", comment: "Linked device status including platform label and device name"), "\(syncDeviceLabel(for: platform))", "\(remoteDeviceName)")
            }
            return String(format: String(localized: "settings.sync.linked_device.name_only", defaultValue: "Linked device: %@", comment: "Linked device status including device name only"), "\(remoteDeviceName)")
        }
        return String(localized: "settings.sync.linked_device.none_iphone_yet", defaultValue: "No linked iPhone yet.", comment: "Status message when no iPhone has been linked")
    }

    private func syncDeviceLabel(for platform: String) -> String {
        switch platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios":
            return String(localized: "settings.sync.device_label.iphone", defaultValue: "iPhone", comment: "Device platform label for linked iPhone")
        case "ipados":
            return String(localized: "settings.sync.device_label.ipad", defaultValue: "iPad", comment: "Device platform label for linked iPad")
        default:
            return platform
        }
    }

    private var dictationModelSettingsSection: some View {
        settingsSection(String(localized: "settings.section.speech_recognition", defaultValue: "Speech Recognition", comment: "Section title for speech recognition settings")) {
            settingsRow(String(localized: "settings.speech_recognition.dictation_model", defaultValue: "Dictation model", comment: "Label for selecting dictation speech model"), controlWidth: meetingControlWidth) {
                settingsMenu(
                    selection: appState.selectedBackend.label,
                    options: dictationBackendOptions.map(\.label),
                    disabledOptions: disabledDictationBackendLabels
                ) { label in
                    if let option = dictationBackendOptions.first(where: { $0.label == label }) {
                        controller.selectBackend(option)
                    }
                }
            }
            if !disabledDictationBackendLabels.isEmpty {
                settingsDescription(String(localized: "settings.speech_recognition.description.gemma4_unavailable_with_cleanup_backend", defaultValue: "Gemma 4 dictation is unavailable while Gemma 4 is the cleanup backend.", comment: "Help text explaining dictation model availability constraint"))
            }
            if appState.selectedBackend.backend == BackendOption.cohereTranscribe.backend {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.speech_recognition.cohere_language", defaultValue: "Cohere language", comment: "Label for selecting Cohere model language"), controlWidth: meetingControlWidth) {
                    cohereLanguageMenu
                }
            }
            if appState.selectedBackend.backend == BackendOption.indicASR.backend {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.speech_recognition.indic_language", defaultValue: "Indic language", comment: "Label for selecting Indic language model option"), controlWidth: meetingControlWidth) {
                    indicLanguageMenu
                }
            }
            if appState.selectedBackend.supportsWhisperLanguageSelection {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.speech_recognition.whisper_language", defaultValue: "Whisper language", comment: "Label for selecting Whisper model language"), controlWidth: meetingControlWidth) {
                    whisperLanguageMenu
                }
            }
        }
    }

    private var meetingTranscriptionSettingsSection: some View {
        settingsSection(String(localized: "settings.section.transcription", defaultValue: "Transcription", comment: "Section title for transcription settings")) {
            settingsRow(
                "Microphone",
                description: String(localized: "settings.transcription.microphone.description.only_affects_muesli", defaultValue: "Only affects Muesli. Changes apply immediately.", comment: "Help text for transcription microphone setting scope and timing"),
                controlWidth: meetingControlWidth
            ) {
                let options = meetingMicrophoneOptions
                FixedWidthPopUp(
                    selection: selectedMeetingMicrophoneLabel,
                    options: options.map(\.label),
                    onSelectIndex: { index in
                        guard options.indices.contains(index) else { return }
                        controller.selectMeetingInputDeviceUID(options[index].uid)
                        refreshAudioInputDevices()
                    }
                )
                .frame(height: 24)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(
                String(localized: "settings.transcription.show_transcript_on_hover", defaultValue: "Show transcript on hover", comment: "Toggle label for showing transcript when hovering waveform"),
                description: String(localized: "settings.transcription.show_transcript_on_hover.description", defaultValue: "Show recent transcript beside the waveform.", comment: "Description for transcript-on-hover behavior"),
                controlWidth: meetingControlWidth
            ) {
                settingsSwitch(isOn: appState.config.showMeetingTranscriptOnIndicatorHover) { newValue in
                    controller.updateConfig { $0.showMeetingTranscriptOnIndicatorHover = newValue }
                }
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(
                String(localized: "settings.transcription.live_preview_model", defaultValue: "Live preview model", comment: "Label for selecting live preview transcription model"),
                description: meetingLiveTranscriptDescription,
                controlWidth: meetingControlWidth
            ) {
                if !downloadedMeetingLiveCaptionBackends.isEmpty {
                    settingsMenu(
                        selection: selectedMeetingLiveCaptionLabel,
                        options: downloadedMeetingLiveCaptionBackends.map(\.settingsLabel) + ["Off"]
                    ) { label in
                        guard label != "Off" else {
                            controller.updateConfig { $0.enableLiveStreamingPartials = false }
                            return
                        }
                        guard let backend = downloadedMeetingLiveCaptionBackends.first(where: { $0.settingsLabel == label }) else {
                            return
                        }
                        controller.updateConfig {
                            $0.meetingLiveCaptionBackend = backend.rawValue
                            $0.enableLiveStreamingPartials = true
                        }
                    }
                } else {
                    Text(String(localized: "settings.meeting_transcription.download_from_models", defaultValue: "Download from Models", comment: "Action label to download meeting transcription models"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: meetingControlWidth, alignment: .trailing)
                }
            }
            .id(FeatureTourTarget.liveCaptionsSetting.rawValue)
            .featureTourTarget(.liveCaptionsSetting)
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.transcription.final_transcript", defaultValue: "Final transcript", comment: "Label for selecting final transcript model"), controlWidth: meetingControlWidth) {
                if usesUnifiedMeetingTranscript {
                    Text(String(format: String(localized: "settings.transcription.final_transcript.same_model_suffix", defaultValue: "%@ (same model)", comment: "Model option label when final transcript uses same model as live preview"), "\(MeetingLiveCaptionBackend.nemotron35.label)"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: meetingControlWidth, alignment: .trailing)
                } else if meetingBackendOptions.isEmpty {
                    Text(String(localized: "settings.meeting_transcription.no_downloaded_models", defaultValue: "No downloaded models", comment: "Fallback label when no meeting transcription models are available"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    settingsMenu(
                        selection: selectedMeetingBackendLabel,
                        options: meetingBackendOptions.map(\.label)
                    ) { label in
                        if let option = meetingBackendOptions.first(where: { $0.label == label }) {
                            controller.selectMeetingTranscriptionBackend(option)
                        }
                    }
                }
            }
            if usesUnifiedMeetingTranscript {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.transcription.language", defaultValue: "Language", comment: "Label for transcription language setting"), controlWidth: meetingControlWidth) {
                    nemotron35LanguageMenu
                }
            } else if appState.selectedMeetingTranscriptionBackend.backend == BackendOption.cohereTranscribe.backend {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.transcription.cohere_language", defaultValue: "Cohere language", comment: "Label for Cohere transcription language setting"), controlWidth: meetingControlWidth) {
                    cohereLanguageMenu
                }
            } else if appState.selectedMeetingTranscriptionBackend.backend == BackendOption.indicASR.backend {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.transcription.indic_language", defaultValue: "Indic language", comment: "Label for Indic transcription language setting"), controlWidth: meetingControlWidth) {
                    indicLanguageMenu
                }
            } else if appState.selectedMeetingTranscriptionBackend.supportsWhisperLanguageSelection {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.transcription.whisper_language", defaultValue: "Whisper language", comment: "Label for Whisper transcription language setting"), controlWidth: meetingControlWidth) {
                    whisperLanguageMenu
                }
            }
        }
    }

    private var dictationCleanupSettingsSection: some View {
        settingsSection(String(localized: "settings.section.dictation_cleanup", defaultValue: "Dictation Cleanup", comment: "Section title for dictation cleanup settings")) {
            settingsRow(
                String(localized: "settings.dictation_cleanup.cleanup_backend", defaultValue: "Cleanup backend", comment: "Label for selecting dictation cleanup backend"),
                description: cleanupBackendDescription,
                controlWidth: meetingControlWidth
            ) {
                settingsMenu(
                    selection: appState.selectedPostProcessorBackend.label,
                    options: cleanupBackendOptions.map(\.label),
                    disabledOptions: disabledCleanupBackendLabels
                ) { label in
                    if let option = cleanupBackendOptions.first(where: { $0.label == label }) {
                        controller.selectPostProcessorBackend(option)
                    }
                }
            }
            .id(FeatureTourTarget.cloudCleanupSetting.rawValue)
            .featureTourTarget(.cloudCleanupSetting)
            if !disabledCleanupBackendLabels.isEmpty {
                settingsDescription(String(localized: "settings.dictation_cleanup.description.gemma4_unavailable_with_dictation_model", defaultValue: "Gemma 4 cleanup is unavailable while Gemma 4 is the dictation model.", comment: "Help text explaining cleanup model availability constraint"))
            }
            if appState.selectedPostProcessorBackend == .local {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                    if downloadedPostProcOptions.isEmpty {
                        compactActionButton(String(localized: "settings.dictation_cleanup.action.view_cleanup_models", defaultValue: "View cleanup models", comment: "Action label to open cleanup model selection or management"), systemImage: "arrow.right") {
                            controller.showModels(category: .postProcessing)
                        }
                        .frame(width: meetingControlWidth, alignment: .trailing)
                    } else {
                        let selection = downloadedPostProcOptions.contains(where: { $0.id == appState.activePostProcessor.id })
                            ? appState.activePostProcessor.label
                            : (downloadedPostProcOptions.first?.label ?? "")
                        settingsMenu(
                            selection: selection,
                            options: downloadedPostProcOptions.map(\.label)
                        ) { label in
                            if let option = downloadedPostProcOptions.first(where: { $0.label == label }) {
                                controller.selectPostProcessor(option)
                            }
                        }
                    }
                }
            } else if appState.selectedPostProcessorBackend == .gemma4LiteRT {
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                    if Gemma4LiteRTModelStore.isAvailableLocally() {
                        Text(String(localized: "settings.dictation_cleanup.model.gemma_4_e2b_downloaded", defaultValue: "Gemma 4 E2B (Downloaded)", comment: "Cleanup model option label indicating Gemma 4 E2B is downloaded"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.textSecondary)
                            .frame(width: meetingControlWidth, alignment: .trailing)
                    } else {
                        compactActionButton(String(localized: "settings.dictation_cleanup.action.view_gemma_model", defaultValue: "View Gemma model", comment: "Action label to view Gemma cleanup model details or source"), systemImage: "arrow.right") {
                            controller.showModels(category: .postProcessing)
                        }
                        .frame(width: meetingControlWidth, alignment: .trailing)
                    }
                }
            } else {
                hostedCleanupSettings(for: appState.selectedPostProcessorBackend)
            }
        }
    }

    private var cohereLanguageMenu: some View {
        settingsMenu(
            selection: selectedCohereLanguage.label,
            options: CohereTranscribeLanguage.allCases.map(\.label)
        ) { label in
            guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
            controller.selectCohereLanguage(language)
        }
    }

    private var nemotron35LanguageMenu: some View {
        settingsMenu(
            selection: selectedNemotron35Language.label,
            options: Nemotron35Language.allCases.map(\.label)
        ) { label in
            guard let language = Nemotron35Language.allCases.first(where: { $0.label == label }) else { return }
            Task { await controller.setNemotron35Language(language) }
        }
    }

    private var whisperLanguageMenu: some View {
        settingsMenu(
            selection: selectedWhisperLanguage.label,
            options: WhisperKitLanguage.allCases.map(\.label)
        ) { label in
            guard let language = WhisperKitLanguage.allCases.first(where: { $0.label == label }) else { return }
            controller.selectWhisperLanguage(language)
        }
    }

    private var indicLanguageMenu: some View {
        FixedWidthPopUp(
            selection: selectedIndicASRLanguage.label,
            options: IndicASRLanguage.allCases.map(\.label),
            onSelectIndex: { index in
                guard index >= 0, index < IndicASRLanguage.allCases.count else { return }
                controller.selectIndicASRLanguage(IndicASRLanguage.allCases[index])
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func hostedCleanupSettings(for backend: TranscriptCleanupBackendOption) -> some View {
        switch backend.llmBackend {
        case .some(.chatGPT):
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.account", defaultValue: "Account", comment: "Label for hosted cleanup account selection"), controlWidth: meetingControlWidth) {
                chatGPTAccountControl(selectMeetingSummaryBackend: false)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                settingsModelMenu(
                    currentModel: appState.config.postProcessorChatGPTModel,
                    presets: SummaryModelPreset.chatGPTTranscriptCleanupModels
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
        case .some(.openAI):
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.api_key", defaultValue: "API Key", comment: "Label for hosted cleanup API key field"), controlWidth: meetingControlWidth) {
                PastableSecureField(
                    text: appState.config.openAIAPIKey,
                    placeholder: "sk-...",
                    onChange: { val in controller.updateConfig { $0.openAIAPIKey = val } }
                )
                .frame(height: 22)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                settingsModelMenu(
                    currentModel: appState.config.postProcessorOpenAIModel,
                    presets: SummaryModelPreset.openAIModels
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
            keyStatusRow(key: appState.config.openAIAPIKey)
        case .some(.openRouter):
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.api_key", defaultValue: "API Key", comment: "Label for hosted cleanup API key field"), controlWidth: meetingControlWidth) {
                PastableSecureField(
                    text: appState.config.openRouterAPIKey,
                    placeholder: "sk-or-...",
                    onChange: { val in controller.updateConfig { $0.openRouterAPIKey = val } }
                )
                .frame(height: 22)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.model_preset", defaultValue: "Model preset", comment: "Label for hosted cleanup model preset selection"), controlWidth: meetingControlWidth) {
                settingsModelMenu(
                    currentModel: appState.config.postProcessorOpenRouterModel,
                    presets: SummaryModelPreset.openRouterModels
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.custom_model_id", defaultValue: "Custom model ID", comment: "Label for custom model identifier field in hosted cleanup settings"), controlWidth: meetingControlWidth) {
                settingsModelTextField(
                    currentModel: appState.config.postProcessorOpenRouterModel,
                    placeholder: "provider/model"
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
            keyStatusRow(key: appState.config.openRouterAPIKey)
        case .some(.ollama):
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.ollama_url", defaultValue: "Ollama URL", comment: "Label for Ollama endpoint URL in hosted cleanup settings"), controlWidth: meetingControlWidth) {
                PastableTextField(
                    text: appState.config.ollamaURL,
                    placeholder: "http://localhost:11434",
                    onChange: { val in controller.updateConfig { $0.ollamaURL = val } }
                )
                .frame(height: 22)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                settingsModelTextField(
                    currentModel: appState.config.postProcessorOllamaModel,
                    placeholder: TranscriptCleanupClient.defaultModel(for: backend)
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
        case .some(.lmStudio):
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.hosted_cleanup.lm_studio_url", defaultValue: "LM Studio URL", comment: "Label for LM Studio endpoint URL in hosted cleanup settings"), controlWidth: meetingControlWidth) {
                PastableTextField(
                    text: appState.config.lmStudioURL,
                    placeholder: "http://localhost:1234",
                    onChange: { val in controller.updateConfig { $0.lmStudioURL = val } }
                )
                .frame(height: 22)
            }
            Divider().background(MuesliTheme.surfaceBorder)
            settingsRow(String(localized: "settings.dictation_cleanup.cleanup_model", defaultValue: "Cleanup model", comment: "Label for selecting dictation cleanup model"), controlWidth: meetingControlWidth) {
                settingsModelTextField(
                    currentModel: appState.config.postProcessorLMStudioModel,
                    placeholder: String(localized: "settings.hosted_cleanup.loaded_lm_studio_model", defaultValue: "Loaded LM Studio model", comment: "Label for displaying currently loaded LM Studio model")
                ) { controller.updatePostProcessorModel($0, for: backend) }
            }
        case .some(.customLLM):
            customLLMSettingsRows(model: appState.config.postProcessorCustomLLMModel) {
                controller.updatePostProcessorModel($0, for: backend)
            }
        default:
            EmptyView()
        }
    }

    private var cleanupPromptSettings: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            settingsRow(String(localized: "settings.cleanup_prompt.cleanup_preset", defaultValue: "Cleanup preset", comment: "Label for cleanup prompt preset selection"), controlWidth: meetingControlWidth) {
                FixedWidthPopUp(
                    selection: selectedCleanupPromptName,
                    options: cleanupPromptPresets.map(\.name),
                    onSelectIndex: { index in
                        guard index >= 0, index < cleanupPromptPresets.count else { return }
                        controller.selectTranscriptCleanupPrompt(id: cleanupPromptPresets[index].id)
                    }
                )
                .frame(height: 24)
            }

            Text(appState.config.postProcessorSystemPrompt)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MuesliTheme.surfacePrimary.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )

            HStack {
                Spacer()
                compactActionButton(String(localized: "settings.cleanup_prompt.action.manage_presets", defaultValue: "Manage Presets…", comment: "Action label to open cleanup preset management"), systemImage: "slider.horizontal.3") {
                    isCleanupPromptManagerPresented = true
                }
            }
        }
    }

    private var meetingSummarySettingsSection: some View {
        settingsSection(String(localized: "settings.section.meeting_summaries", defaultValue: "Meeting Summaries", comment: "Section title for meeting summary settings")) {
            settingsRow(String(localized: "settings.meeting_summaries.summary_backend", defaultValue: "Summary backend", comment: "Label for selecting meeting summary backend"), controlWidth: meetingControlWidth) {
                settingsMenu(
                    selection: appState.selectedMeetingSummaryBackend.label,
                    options: MeetingSummaryBackendOption.all.map(\.label)
                ) { label in
                    if let option = MeetingSummaryBackendOption.all.first(where: { $0.label == label }) {
                        controller.selectMeetingSummaryBackend(option)
                    }
                }
            }
            Divider().background(MuesliTheme.surfaceBorder)

            if appState.selectedMeetingSummaryBackend == .chatGPT {
                settingsRow(String(localized: "settings.meeting_summaries.account", defaultValue: "Account", comment: "Label for account selection in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    chatGPTAccountControl()
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meeting_summaries.model", defaultValue: "Model", comment: "Label for selecting model in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    settingsModelMenu(
                        currentModel: appState.config.chatGPTModel,
                        presets: SummaryModelPreset.chatGPTModels
                    ) { val in controller.updateConfig { $0.chatGPTModel = val } }
                }
            } else if appState.selectedMeetingSummaryBackend == .openAI {
                settingsRow(String(localized: "settings.meeting_summaries.api_key", defaultValue: "API Key", comment: "Label for API key field in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    PastableSecureField(
                        text: appState.config.openAIAPIKey,
                        placeholder: "sk-...",
                        onChange: { val in controller.updateConfig { $0.openAIAPIKey = val } }
                    )
                    .frame(height: 22)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meeting_summaries.model", defaultValue: "Model", comment: "Label for model selection in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    settingsModelMenu(
                        currentModel: appState.config.openAIModel,
                        presets: SummaryModelPreset.openAIModels
                    ) { val in controller.updateConfig { $0.openAIModel = val } }
                }
                keyStatusRow(key: appState.config.openAIAPIKey)
            } else if appState.selectedMeetingSummaryBackend == .ollama {
                settingsRow(String(localized: "settings.meeting_summaries.ollama_url", defaultValue: "Ollama URL", comment: "Label for Ollama endpoint URL in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    PastableTextField(
                        text: appState.config.ollamaURL,
                        placeholder: "http://localhost:11434",
                        onChange: { val in controller.updateConfig { $0.ollamaURL = val } }
                    )
                    .frame(height: 22)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meeting_summaries.model", defaultValue: "Model", comment: "Label for model selection in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    settingsModelTextField(
                        currentModel: appState.config.ollamaModel,
                        placeholder: "qwen3.5"
                    ) { val in controller.updateConfig { $0.ollamaModel = val } }
                }
            } else if appState.selectedMeetingSummaryBackend == .lmStudio {
                settingsRow(String(localized: "settings.meeting_summaries.lm_studio_url", defaultValue: "LM Studio URL", comment: "Label for LM Studio endpoint URL in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    PastableTextField(
                        text: appState.config.lmStudioURL,
                        placeholder: "http://localhost:1234",
                        onChange: { val in controller.updateConfig { $0.lmStudioURL = val } }
                    )
                    .frame(height: 22)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meeting_summaries.model", defaultValue: "Model", comment: "Label for model selection in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    settingsModelTextField(
                        currentModel: appState.config.lmStudioModel,
                        placeholder: String(localized: "settings.meeting_summaries.select_loaded_lm_studio_model", defaultValue: "Select a loaded LM Studio model", comment: "Prompt text for selecting loaded LM Studio model in meeting summaries settings")
                    ) { val in controller.updateConfig { $0.lmStudioModel = val } }
                }
            } else if appState.selectedMeetingSummaryBackend == .customLLM {
                customLLMSettingsRows(model: appState.config.customLLMModel) {
                    val in controller.updateConfig { $0.customLLMModel = val }
                }
            } else {
                settingsRow(String(localized: "settings.meeting_summaries.api_key", defaultValue: "API Key", comment: "Label for API key field in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    PastableSecureField(
                        text: appState.config.openRouterAPIKey,
                        placeholder: "sk-or-...",
                        onChange: { val in controller.updateConfig { $0.openRouterAPIKey = val } }
                    )
                    .frame(height: 22)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meeting_summaries.model", defaultValue: "Model", comment: "Label for model selection in meeting summaries settings"), controlWidth: meetingControlWidth) {
                    openRouterFreeModelMenu
                }
                keyStatusRow(key: appState.config.openRouterAPIKey)
            }
        }
    }

    @ViewBuilder
    private func customLLMSettingsRows(model: String, onModelChange: @escaping (String) -> Void) -> some View {
        Divider().background(MuesliTheme.surfaceBorder)
        settingsRow(String(localized: "settings.custom_llm.api_format", defaultValue: "API Format", comment: "Label for custom LLM API format selection"), controlWidth: meetingControlWidth) {
            settingsMenu(
                selection: CustomLLMFormat(rawValue: appState.config.customLLMFormat)?.label ?? CustomLLMFormat.openAI.label,
                options: CustomLLMFormat.allCases.map(\.label)
            ) { label in
                guard let format = CustomLLMFormat.allCases.first(where: { $0.label == label }) else { return }
                controller.updateConfig { $0.customLLMFormat = format.rawValue }
            }
        }
        Divider().background(MuesliTheme.surfaceBorder)
        settingsRow(String(localized: "settings.custom_llm.endpoint", defaultValue: "Endpoint", comment: "Label for custom LLM endpoint URL field"), controlWidth: meetingControlWidth) {
            PastableTextField(
                text: appState.config.customLLMURL,
                placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                    ? "https://api.anthropic.com"
                    : "http://localhost:8080/v1",
                onChange: { val in controller.updateConfig { $0.customLLMURL = val } }
            )
            .frame(height: 22)
        }
        Divider().background(MuesliTheme.surfaceBorder)
        settingsRow(String(localized: "settings.custom_llm.api_key", defaultValue: "API Key", comment: "Label for custom LLM API key field"), controlWidth: meetingControlWidth) {
            PastableSecureField(
                text: appState.config.customLLMAPIKey,
                placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                    ? String(localized: "settings.custom_llm.api_key.required_for_anthropic", defaultValue: "Required for Anthropic API", comment: "Help text indicating API key requirement for Anthropic format")
                    : String(localized: "settings.custom_llm.api_key.optional_for_local_servers", defaultValue: "Optional for local servers", comment: "Help text indicating API key is optional for local server formats"),
                onChange: { val in controller.updateConfig { $0.customLLMAPIKey = val } }
            )
            .frame(height: 22)
        }
        Divider().background(MuesliTheme.surfaceBorder)
        settingsRow(String(localized: "settings.custom_llm.model", defaultValue: "Model", comment: "Label for custom LLM model identifier field"), controlWidth: meetingControlWidth) {
            settingsModelTextField(
                currentModel: model,
                placeholder: appState.config.customLLMFormat == CustomLLMFormat.anthropic.rawValue
                    ? "claude-3-5-sonnet-20241022"
                    : "custom-model-id"
            ) { val in onModelChange(val) }
        }
    }

    private var dictationSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            dictationModelSettingsSection

            settingsSection(String(localized: "settings.section.transcription", defaultValue: "Transcription", comment: "Section title for transcription settings")) {
                settingsRow(
                    "Microphone",
                    description: String(localized: "settings.dictation.microphone.description.automatic_system_or_mac_mic", defaultValue: "Automatic uses system input, or Mac mic with AirPods.", comment: "Description of automatic microphone behavior for dictation")
                ) {
                    let options = dictationMicrophoneOptions
                    FixedWidthPopUp(
                        selection: selectedDictationMicrophoneLabel,
                        options: options.map(\.label),
                        onSelectIndex: { index in
                            guard index >= 0, index < options.count else { return }
                            controller.selectDictationInputDeviceUID(options[index].uid)
                            refreshAudioInputDevices()
                        }
                    )
                    .frame(height: 24)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.dictation.ai_transcript_cleanup", defaultValue: "AI transcript cleanup", comment: "Toggle label for AI transcript cleanup in dictation settings")) {
                    settingsSwitch(isOn: appState.config.enablePostProcessor) { newValue in
                        controller.setPostProcessorEnabled(newValue)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                cleanupPromptSettings
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(
                    String(localized: "settings.dictation.dictionary_suggestions", defaultValue: "Dictionary suggestions", comment: "Toggle label for dictionary suggestions in dictation settings"),
                    description: String(localized: "settings.dictation.dictionary_suggestions.description", defaultValue: "Suggest words after corrections by briefly reading focused app text via Accessibility.", comment: "Description for dictionary suggestions feature using Accessibility text context")
                ) {
                    settingsSwitch(isOn: appState.config.enableDictionaryCorrectionPrompts) { newValue in
                        handleDictionaryCorrectionPromptsToggle(newValue)
                    }
                    .help(String(localized: "settings.dictation.help.ocr_context_brief_description", defaultValue: "Briefly reads focused app text after dictation to detect corrections.", comment: "Help text describing brief post-dictation app text reading behavior"))
                }
            }

            dictationCleanupSettingsSection

            settingsSection(String(localized: "settings.section.advanced", defaultValue: "Advanced", comment: "Section title for advanced dictation settings")) {
                settingsRow(String(localized: "settings.dictation.pause_media_during_dictation", defaultValue: "Pause media during dictation", comment: "Toggle label for pausing media while dictating")) {
                    settingsSwitch(isOn: appState.config.pauseMediaDuringDictation) { newValue in
                        controller.updateConfig { $0.pauseMediaDuringDictation = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.dictation.mute_system_audio_during_dictation", defaultValue: "Mute system audio during dictation", comment: "Toggle label for muting system audio during dictation")) {
                    settingsSwitch(isOn: appState.config.muteSystemAudioDuringDictation) { newValue in
                        controller.updateConfig { $0.muteSystemAudioDuringDictation = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                screenContextRow(String(localized: "settings.dictation.app_context", defaultValue: "App context", comment: "Toggle label for enabling app context during dictation"))
                Divider().background(MuesliTheme.surfaceBorder)
                dictationOCRContextRow
            }
        }
    }

    private var computerUseSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(String(localized: "settings.section.computer_use", defaultValue: "Computer Use", comment: "Section title for computer use settings")) {
                settingsRow(String(localized: "settings.computer_use.enable_planner", defaultValue: "Enable planner", comment: "Toggle label for enabling computer use planner"), controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.enableComputerUsePlanner) { newValue in
                        controller.updateConfig { $0.enableComputerUsePlanner = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.computer_use.account", defaultValue: "Account", comment: "Label for account selection in computer use settings"), controlWidth: meetingControlWidth) {
                    chatGPTAccountControl()
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.computer_use.planner_model", defaultValue: "Planner model", comment: "Label for planner model selection in computer use settings"), controlWidth: meetingControlWidth) {
                    settingsModelMenu(
                        currentModel: appState.config.computerUsePlannerModel,
                        presets: SummaryModelPreset.computerUsePlannerModels
                    ) { val in controller.updateConfig { $0.computerUsePlannerModel = val } }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.computer_use.timeout", defaultValue: "Timeout", comment: "Label for planner timeout setting in computer use settings"), controlWidth: meetingControlWidth) {
                    Stepper(
                        value: Binding(
                            get: { max(appState.config.computerUseTimeoutSeconds, 1) },
                            set: { newValue in
                                controller.updateConfig { $0.computerUseTimeoutSeconds = max(newValue, 1) }
                            }
                        ),
                        in: 1...600,
                        step: 15
                    ) {
                        Text(String(format: String(localized: "settings.computer_use.timeout.seconds_value", defaultValue: "%d seconds", comment: "Displayed timeout duration value in seconds for computer use planner"), max(appState.config.computerUseTimeoutSeconds, 1)))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                }
            }
        }
    }

    private var meetingsSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            meetingTranscriptionSettingsSection

            settingsSection(String(localized: "settings.section.meeting_context", defaultValue: "Meeting Context", comment: "Section title for meeting context settings")) {
                screenContextRow(String(localized: "settings.meetings.meeting_context", defaultValue: "Meeting context", comment: "Toggle label for enabling meeting context"), includesScreenOCR: true)
            }

            meetingSummarySettingsSection

            settingsSection(String(localized: "settings.section.meeting_notes", defaultValue: "Meeting Notes", comment: "Section title for meeting notes settings")) {
                settingsRow(String(localized: "settings.meetings.default_template", defaultValue: "Default template", comment: "Label for default meeting notes template selection"), controlWidth: meetingControlWidth) {
                    meetingTemplateMenu(selectionID: appState.config.defaultMeetingTemplateID) { id in
                        controller.updateDefaultMeetingTemplate(id: id)
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meetings.summary_retries", defaultValue: "Summary retries", comment: "Label for configuring number of summary retry attempts"), controlWidth: meetingControlWidth) {
                    Stepper(
                        value: Binding(
                            get: {
                                MeetingSummaryRetryPolicy.clampedRetryCount(appState.config.meetingSummaryRetryCount)
                            },
                            set: { newValue in
                                controller.updateConfig {
                                    $0.meetingSummaryRetryCount = MeetingSummaryRetryPolicy.clampedRetryCount(newValue)
                                }
                            }
                        ),
                        in: 0...MeetingSummaryRetryPolicy.maximumRetryCount
                    ) {
                        Text(summaryRetryLabel(appState.config.meetingSummaryRetryCount))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                }
                settingsDescription(String(localized: "settings.meetings.summary_retries.description", defaultValue: "Retry transient AI summary failures before saving failed notes.", comment: "Description explaining summary retry behavior before marking notes failed"))
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meetings.templates", defaultValue: "Templates", comment: "Label for meeting notes templates setting"), controlWidth: meetingControlWidth) {
                    actionButton(String(localized: "settings.meetings.action.manage_templates", defaultValue: "Manage Templates…", comment: "Action label to open meeting templates management")) {
                        controller.showMeetingTemplatesManager()
                    }
                }
            }

            settingsSection(String(localized: "settings.section.recording", defaultValue: "Recording", comment: "Section title for recording settings")) {
                settingsRow(String(localized: "settings.meetings.auto_record_calendar_meetings", defaultValue: "Auto-record calendar meetings", comment: "Toggle label for automatically recording calendar meetings")) {
                    settingsSwitch(isOn: appState.config.autoRecordMeetings) { newValue in
                        controller.updateConfig { $0.autoRecordMeetings = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meetings.save_meeting_recording", defaultValue: "Save meeting recording", comment: "Toggle label for saving meeting recordings")) {
                    settingsMenu(
                        selection: recordingSaveLabel(for: appState.config.meetingRecordingSavePolicy),
                        options: MeetingRecordingSavePolicy.allCases.map(recordingSaveLabel(for:))
                    ) { label in
                        guard let policy = recordingSavePolicy(for: label) else { return }
                        controller.updateConfig { $0.meetingRecordingSavePolicy = policy }
                    }
                }
                if appState.config.meetingRecordingSavePolicy != .never {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(String(localized: "settings.meetings.recording_format", defaultValue: "Recording format", comment: "Label for selecting meeting recording format")) {
                        settingsMenu(
                            selection: appState.config.resolvedMeetingRecordingFileFormat.displayName,
                            options: MeetingRecordingFileFormat.allCases.map(recordingFileFormatLabel(for:))
                        ) { label in
                            guard let format = recordingFileFormat(for: label) else { return }
                            controller.updateConfig { $0.meetingRecordingFileFormat = format.rawValue }
                        }
                    }
                    settingsDescription(String(localized: "settings.meetings.recording_format.description", defaultValue: "M4A is recommended for smaller files. WAV is lossless and uses more storage.", comment: "Description of tradeoffs between supported meeting recording formats"))
                }
            }

            settingsSection(String(localized: "settings.section.auto_export", defaultValue: "Auto Export", comment: "Section title for automatic export settings")) {
                settingsRow(String(localized: "settings.meetings.auto_export_meetings", defaultValue: "Auto-export meetings", comment: "Toggle label for automatically exporting completed meetings")) {
                    settingsSwitch(isOn: appState.config.autoExportMarkdownEnabled) { newValue in
                        controller.updateConfig { $0.autoExportMarkdownEnabled = newValue }
                    }
                }
                if appState.config.autoExportMarkdownEnabled {
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(String(localized: "settings.meetings.destination_folder", defaultValue: "Destination folder", comment: "Label for auto-export destination folder setting")) {
                        autoExportFolderPicker
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(String(localized: "settings.meetings.content", defaultValue: "Content", comment: "Label for selecting exported meeting content")) {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportMarkdownContent.displayName,
                            options: MeetingExportContent.allCases.map(\.displayName)
                        ) { label in
                            guard let index = MeetingExportContent.allCases.firstIndex(where: { $0.displayName == label }) else { return }
                            let content = MeetingExportContent.allCases[index]
                            controller.updateConfig { $0.autoExportMarkdownContent = content.rawValue }
                        }
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow(String(localized: "settings.meetings.file_format", defaultValue: "File format", comment: "Label for selecting auto-export file format")) {
                        settingsMenu(
                            selection: appState.config.resolvedAutoExportFileFormat.displayName,
                            options: MeetingAutoExportFileFormat.allCases.map(\.displayName)
                        ) { label in
                            guard let format = MeetingAutoExportFileFormat.allCases.first(where: { $0.displayName == label }) else { return }
                            controller.updateConfig { $0.autoExportFileFormat = format.rawValue }
                        }
                    }
                }
                Text(String(localized: "settings.meetings.auto_export.description", defaultValue: "Automatically saves each completed meeting to the chosen folder in the selected format.", comment: "Description of automatic meeting export behavior"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing16)
            }

            settingsSection(String(localized: "settings.section.meeting_notifications", defaultValue: "Meeting Notifications", comment: "Section title for meeting notification settings")) {
                settingsRow(String(localized: "settings.meetings.notifications.scheduled_meetings", defaultValue: "Scheduled meetings", comment: "Toggle label for scheduled meeting notifications")) {
                    settingsSwitch(isOn: appState.config.showScheduledMeetingNotifications) { newValue in
                        controller.updateConfig { $0.showScheduledMeetingNotifications = newValue }
                    }
                }
                settingsDescription(String(localized: "settings.meetings.notifications.scheduled_meetings.description", defaultValue: "Show notifications for calendar meetings with a join link.", comment: "Description for scheduled meeting notification behavior"))

                if appState.config.showScheduledMeetingNotifications {
                    Divider().background(MuesliTheme.surfaceBorder)

                    settingsRow(String(localized: "settings.meetings.notifications.reminder_timing", defaultValue: "Reminder timing", comment: "Label for selecting meeting reminder timing")) {
                        settingsMenu(
                            selection: scheduledMeetingLeadTimeLabel(for: appState.config.scheduledMeetingNotificationLeadTime),
                            options: ScheduledMeetingNotificationLeadTime.allCases.map(scheduledMeetingLeadTimeLabel(for:))
                        ) { label in
                            guard let leadTime = scheduledMeetingLeadTime(for: label) else { return }
                            controller.updateConfig { $0.scheduledMeetingNotificationLeadTime = leadTime }
                        }
                    }
                    settingsDescription(String(localized: "settings.meetings.notifications.reminder_timing.description", defaultValue: "At start time avoids early calendar-only prompts before you join.", comment: "Description explaining reminder timing choice effect"))
                }

                Divider().background(MuesliTheme.surfaceBorder)

                settingsRow(String(localized: "settings.meetings.notifications.auto_detected_meetings", defaultValue: "Auto-detected meetings", comment: "Toggle label for notifications from auto-detected meetings")) {
                    settingsSwitch(isOn: appState.config.showMeetingDetectionNotification) { newValue in
                        controller.updateConfig { $0.showMeetingDetectionNotification = newValue }
                    }
                }
                settingsDescription(String(localized: "settings.meetings.notifications.auto_detected_meetings.description", defaultValue: "Show notifications when a call is detected from browser, camera, microphone, or app audio activity.", comment: "Description for auto-detected meeting notification criteria"))

                if appState.config.showMeetingDetectionNotification {
                    Divider().background(MuesliTheme.surfaceBorder)
                    mutedMeetingDetectionAppsControl
                }
            }

            settingsSection(String(localized: "settings.section.calendars", defaultValue: "Calendars", comment: "Section title for calendar integration settings")) {
                settingsRow(String(localized: "settings.meetings.calendars.upcoming_meetings", defaultValue: "Upcoming meetings", comment: "Label for upcoming meetings calendar setting"), controlWidth: meetingControlWidth) {
                    settingsMenu(
                        selection: selectedUpcomingMeetingsWindow.label,
                        options: UpcomingMeetingsWindow.allCases.map(\.label)
                    ) { label in
                        guard let window = UpcomingMeetingsWindow.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateUpcomingMeetingsWindow(dayCount: window.dayCount)
                    }
                }
                settingsDescription(String(localized: "settings.meetings.calendars.upcoming_meetings.description", defaultValue: "Controls how many calendar days appear in Coming Up, the menu bar, and scheduled meeting checks.", comment: "Description for upcoming meetings calendar window setting"))
                Divider().background(MuesliTheme.surfaceBorder)
                calendarSourcesControl
                    .padding(.bottom, MuesliTheme.spacing8)
            }

            if appState.isGoogleCalendarAvailable {
                settingsSection(String(localized: "settings.section.calendar", defaultValue: "Calendar", comment: "Section title for calendar integration settings")) {
                    settingsRow(String(localized: "settings.meetings.calendar.google_calendar", defaultValue: "Google Calendar", comment: "Toggle label for Google Calendar integration")) {
                        googleCalendarControl
                    }
                }
            }

            settingsSection(String(localized: "settings.section.advanced", defaultValue: "Advanced", comment: "Section title for advanced meeting settings")) {
                settingsRow(String(localized: "settings.meetings.advanced.enable_post_meeting_hook", defaultValue: "Enable post-meeting hook", comment: "Toggle label for enabling post-meeting hook execution"), controlWidth: meetingControlWidth) {
                    settingsSwitch(isOn: appState.config.meetingHookEnabled) { newValue in
                        controller.updateConfig { $0.meetingHookEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meetings.advanced.hook_script", defaultValue: "Hook script", comment: "Label for selecting post-meeting hook script executable"), controlWidth: meetingControlWidth) {
                    meetingHookPathPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.meetings.advanced.timeout", defaultValue: "Timeout", comment: "Label for post-meeting hook timeout setting"), controlWidth: meetingControlWidth) {
                    meetingHookTimeoutControl
                }
                settingsDescription(String(localized: "settings.meetings.advanced.hook_script.description", defaultValue: "Runs a user-supplied executable after each completed meeting. The executable receives JSON on stdin and must already be runnable on its own.", comment: "Description of post-meeting hook script behavior and requirements"))
            }
            .padding(.top, MuesliTheme.spacing8)
        }
        .onAppear {
            refreshMeetingCalendarSourcesIfNeeded()
        }
    }

    private var appearanceSettingsPane: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
            settingsSection(String(localized: "settings.section.floating_indicator", defaultValue: "Floating Indicator", comment: "Section title for floating indicator appearance settings")) {
                settingsRow(String(localized: "settings.appearance.show_floating_indicator", defaultValue: "Show floating indicator", comment: "Toggle label for showing floating indicator")) {
                    settingsSwitch(isOn: appState.config.showFloatingIndicator) { newValue in
                        controller.updateConfig { $0.showFloatingIndicator = newValue }
                        controller.refreshIndicatorVisibility()
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.show_hotkey_on_floating_indicator", defaultValue: "Show hotkey on floating indicator", comment: "Toggle label for showing hotkey on floating indicator")) {
                    settingsSwitch(isOn: appState.config.showHotkeyOnFloatingIndicator) { newValue in
                        controller.updateConfig { $0.showHotkeyOnFloatingIndicator = newValue }
                    }
                    .disabled(!appState.config.showFloatingIndicator)
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.indicator_position", defaultValue: "Indicator position", comment: "Label for choosing floating indicator position")) {
                    let isCustom = appState.config.indicatorAnchor == .custom
                    let selection = isCustom ? customIndicatorPositionLabel : appState.config.indicatorAnchor.label
                    let options = (isCustom ? [customIndicatorPositionLabel] : [])
                        + IndicatorAnchor.allCases.filter { $0 != .custom }.map(\.label)
                    settingsMenu(
                        selection: selection,
                        options: options
                    ) { label in
                        if label == customIndicatorPositionLabel { return }
                        guard let anchor = IndicatorAnchor.allCases.first(where: { $0.label == label }) else { return }
                        controller.updateConfig { $0.indicatorAnchor = anchor }
                        controller.refreshIndicatorVisibility()
                    }
                }
            }

            settingsSection(String(localized: "settings.section.appearance", defaultValue: "Appearance", comment: "Section title for general appearance settings")) {
                settingsRow(String(localized: "settings.appearance.dark_mode", defaultValue: "Dark mode", comment: "Toggle label for dark mode setting")) {
                    settingsSwitch(isOn: appState.config.darkMode) { newValue in
                        controller.updateConfig { $0.darkMode = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.menu_bar_icon", defaultValue: "Menu bar icon", comment: "Label for selecting menu bar icon style")) {
                    menuBarIconPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.show_hotkey_in_menu_bar", defaultValue: "Show hotkey in menu bar", comment: "Toggle label for showing hotkey text in menu bar")) {
                    settingsSwitch(isOn: appState.config.showHotkeyInMenuBar) { newValue in
                        controller.updateConfig { $0.showHotkeyInMenuBar = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.accent_color", defaultValue: "Accent color", comment: "Label for selecting application accent color")) {
                    glassTintPicker
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.play_sound_effects", defaultValue: "Play sound effects", comment: "Toggle label for enabling sound effects")) {
                    settingsSwitch(isOn: appState.config.soundEnabled) { newValue in
                        controller.updateConfig { $0.soundEnabled = newValue }
                    }
                }
                Divider().background(MuesliTheme.surfaceBorder)
                settingsRow(String(localized: "settings.appearance.show_next_meeting_in_menu_bar", defaultValue: "Show next meeting in menu bar", comment: "Toggle label for displaying next meeting info in menu bar")) {
                    settingsSwitch(isOn: appState.config.showNextMeetingInMenuBar) { newValue in
                        controller.updateConfig { $0.showNextMeetingInMenuBar = newValue }
                    }
                }
            }

            if appState.config.maraudersMapUnlocked {
                settingsSection(String(localized: "settings.section.marauders_map", defaultValue: "Marauder’s Map", comment: "Section title for Marauder’s Map settings")) {
                    settingsRow(String(localized: "settings.appearance.meeting_countdown_audio", defaultValue: "Meeting countdown audio", comment: "Label for selecting meeting countdown audio clip")) {
                        maraudersMapControl
                    }
                    Divider().background(MuesliTheme.surfaceBorder)
                    settingsRow("") {
                        Button {
                            SoundController.stopMaraudersMapClip()
                            isPreviewingClip = false
                            controller.resetMaraudersMap()
                        } label: {
                            Text(String(localized: "settings.appearance.mischief_managed", defaultValue: "Mischief Managed", comment: "Preset name in Marauder’s Map appearance options"))
                                .font(.system(size: 11))
                                .foregroundColor(MuesliTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var glassTintPicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.accentPresets, id: \.hex) { preset in
                let isSelected = appState.config.recordingColorHex.lowercased() == preset.hex
                Button {
                    controller.updateConfig { $0.recordingColorHex = preset.hex }
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        )
                        .overlay(
                            Circle().strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private var menuBarIconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MenuBarIconRenderer.options, id: \.id) { option in
                    let isSelected = appState.config.menuBarIcon == option.id
                    Button {
                        controller.updateConfig { $0.menuBarIcon = option.id }
                    } label: {
                        Group {
                            if option.id == "muesli",
                               let img = MenuBarIconRenderer.make(choice: "muesli") {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: option.id)
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }
        }
    }

    @ViewBuilder
    private func chatGPTAccountControl(selectMeetingSummaryBackend: Bool = true) -> some View {
        if appState.isChatGPTAuthenticated {
            Button {
                controller.signOutChatGPT()
            } label: {
                HStack(spacing: 5) {
                    OpenAILogoShape()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                    Text(String(localized: "settings.chatgpt_account.signed_in_sign_out", defaultValue: "Signed in · Sign Out", comment: "Status and action label for signed-in ChatGPT account"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInChatGPT {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "settings.chatgpt_account.signing_in", defaultValue: "Signing in...", comment: "Status label while ChatGPT sign-in is in progress"))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInChatGPT = true
                    chatGPTSignInError = nil
                    Task {
                        let error = await controller.signInWithChatGPT(selectMeetingSummaryBackend: selectMeetingSummaryBackend)
                        isSigningInChatGPT = false
                        chatGPTSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                        Text(String(localized: "settings.chatgpt_account.sign_in_with_chatgpt", defaultValue: "Sign in with ChatGPT", comment: "Button label to start ChatGPT sign-in flow"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let chatGPTSignInError {
                    Text(chatGPTSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var googleCalendarControl: some View {
        if appState.isGoogleCalendarAuthenticated {
            Button {
                controller.signOutGoogleCalendar()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                    Text(String(localized: "settings.google_calendar.connected_disconnect", defaultValue: "Connected · Disconnect", comment: "Status and action label for connected Google Calendar account"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        } else if isSigningInGoogleCal {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "settings.google_calendar.connecting", defaultValue: "Connecting...", comment: "Status label while Google Calendar connection is in progress"))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
        } else if !appState.isGoogleCalendarVerified {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(String(localized: "settings.google_calendar.connect", defaultValue: "Connect Google Calendar", comment: "Button label to connect Google Calendar"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MuesliTheme.textTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                Text(String(localized: "settings.google_calendar.oauth_verification_pending", defaultValue: "Google OAuth verification pending", comment: "Status label when Google OAuth app verification is pending"))
                    .font(.system(size: 10))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isSigningInGoogleCal = true
                    googleCalSignInError = nil
                    Task {
                        let error = await controller.signInWithGoogleCalendar()
                        isSigningInGoogleCal = false
                        googleCalSignInError = error
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                        Text(String(localized: "settings.google_calendar.connect", defaultValue: "Connect Google Calendar", comment: "Button label to connect Google Calendar"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)

                if let googleCalSignInError {
                    Text(googleCalSignInError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    private var maraudersMapControl: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            settingsMenu(
                selection: SoundController.labelForClip(
                    id: appState.config.maraudersMapAudioClip,
                    customPath: appState.config.maraudersMapCustomAudioPath
                ),
                options: SoundController.maraudersMapClipLabels
            ) { label in
                if label == "Custom…" {
                    pickCustomAudioFile()
                } else if let preset = SoundController.maraudersMapPresets
                    .first(where: { $0.label == label }) {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                    controller.updateConfig {
                        $0.maraudersMapAudioClip = preset.id
                        $0.maraudersMapCustomAudioPath = nil
                    }
                    controller.updateMaraudersMapAudioClip()
                }
            }
            Button {
                if isPreviewingClip {
                    SoundController.stopMaraudersMapClip()
                    isPreviewingClip = false
                } else {
                    SoundController.playMaraudersMapClip(
                        id: appState.config.maraudersMapAudioClip,
                        customPath: appState.config.maraudersMapCustomAudioPath
                    ) {
                        isPreviewingClip = false
                    }
                    isPreviewingClip = true
                }
            } label: {
                Image(systemName: isPreviewingClip ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MuesliTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Marauder's Map

    private func pickCustomAudioFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.appearance.audio_picker.choose_clip", defaultValue: "Choose an audio clip", comment: "File picker prompt title for selecting countdown audio clip")
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fputs("[muesli-native] Could not resolve Application Support directory\n", stderr)
            return
        }

        do {
            let supportDir = appSupportBase
                .appendingPathComponent(Bundle.main.infoDictionary?["MuesliSupportDirectoryName"] as? String ?? "Muesli")
            let destPath = try SoundController.importCustomClip(from: url, supportDir: supportDir)
            controller.updateConfig {
                $0.maraudersMapAudioClip = SoundController.customClipID
                $0.maraudersMapCustomAudioPath = destPath
            }
            controller.updateMaraudersMapAudioClip()
        } catch {
            fputs("[muesli-native] Failed to import custom audio: \(error)\n", stderr)
        }
    }

    private func pickMeetingHookFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.meetings.hook_script.choose_prompt", defaultValue: "Choose a hook script", comment: "File picker prompt title for selecting post-meeting hook script")
        panel.prompt = String(localized: "settings.meetings.hook_script.choose_button", defaultValue: "Choose Script", comment: "File picker confirm button for selecting hook script")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = preferredMeetingHookDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.meetingHookPath = url.standardizedFileURL.path }
        }
    }

    private func pickAutoExportFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.meetings.auto_export.choose_folder_prompt", defaultValue: "Choose a folder for exported notes", comment: "Folder picker prompt title for auto-export destination")
        panel.prompt = String(localized: "settings.meetings.auto_export.choose_folder_button", defaultValue: "Choose Folder", comment: "Folder picker confirm button for auto-export destination")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferredAutoExportDirectoryURL()

        presentOpenPanel(panel) { url in
            controller.updateConfig { $0.autoExportMarkdownFolderPath = url.standardizedFileURL.path }
        }
    }

    private func preferredAutoExportDirectoryURL() -> URL {
        let configuredPath = appState.config.autoExportMarkdownFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    }

    private func preferredMeetingHookDirectoryURL() -> URL {
        let configuredPath = appState.config.meetingHookPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            let parentDirectory = configuredURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDirectory.path) {
                return parentDirectory
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func presentOpenPanel(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        settingsSection(String(localized: "settings.permissions.section", defaultValue: "Permissions", comment: "Section title for permissions settings")) {
            permissionStatusRow(
                "Microphone",
                granted: micGranted,
                action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } },
                pane: "Privacy_Microphone"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                "Accessibility",
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(opts)
                },
                pane: "Privacy_Accessibility"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                "Input Monitoring",
                granted: inputMonitoringGranted,
                action: {
                    if !CGRequestListenEventAccess() {
                        openPrivacyPane("Privacy_ListenEvent")
                    }
                },
                pane: "Privacy_ListenEvent"
            )
            Divider().background(MuesliTheme.surfaceBorder)
            permissionStatusRow(
                String(localized: "settings.permissions.screen_recording", defaultValue: "Screen Recording", comment: "Permission row title for screen recording access"),
                granted: screenRecordingGranted,
                action: { CGRequestScreenCaptureAccess() },
                pane: "Privacy_ScreenCapture"
            )
            if appState.config.useCoreAudioTap {
                Divider().background(MuesliTheme.surfaceBorder)
                permissionStatusRow(
                    String(localized: "settings.permissions.system_audio", defaultValue: "System Audio", comment: "Permission row title for system audio capture access"),
                    granted: systemAudioGranted,
                    action: {
                        Task { await CoreAudioSystemRecorder.requestSystemAudioAccess() }
                    },
                    pane: "Privacy_ScreenCapture"
                )
            }
        }
    }

    @ViewBuilder
    private func permissionStatusRow(_ name: String, granted: Bool, action: @escaping () -> Void, pane: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? MuesliTheme.success : MuesliTheme.recording)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            Spacer()
            if granted {
                Text(String(localized: "settings.permissions.status.granted", defaultValue: "Granted", comment: "Permission status label when access is granted"))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.success)
            } else {
                Button(String(localized: "settings.permissions.action.grant", defaultValue: "Grant", comment: "Action button label to grant missing permission")) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            Button {
                openPrivacyPane(pane)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "settings.permissions.help.open_in_system_settings", defaultValue: "Open in System Settings", comment: "Help action label to open permission pane in System Settings"))
        }
        .frame(minHeight: 32)
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func screenContextControl(width: CGFloat? = nil) -> some View {
        if accessibilityGranted {
            settingsSwitch(isOn: appState.config.enableScreenContext) { newValue in
                handleScreenContextToggle(newValue)
            }
            .frame(width: width, alignment: .trailing)
        } else {
            Button {
                handleScreenContextToggle(true)
            } label: {
                Text(String(localized: "settings.screen_context.action.grant", defaultValue: "Grant", comment: "Action button label to grant permission needed for screen context"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: width)
                    .frame(minHeight: 32)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func dictationOCRContextControl(width: CGFloat? = nil) -> some View {
        if !appState.config.enableScreenContext {
            settingsSwitch(isOn: false) { _ in }
                .frame(width: width, alignment: .trailing)
                .disabled(true)
        } else if screenRecordingGranted {
            settingsSwitch(isOn: appState.config.enableDictationOCRContext) { newValue in
                controller.updateConfig { $0.enableDictationOCRContext = newValue }
            }
            .frame(width: width, alignment: .trailing)
        } else {
            Button {
                _ = CGRequestScreenCaptureAccess()
                refreshPermissionStatuses()
            } label: {
                Text(String(localized: "settings.dictation_ocr_context.action.grant", defaultValue: "Grant", comment: "Action button label to grant permission needed for dictation OCR context"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: width)
                    .frame(minHeight: 32)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
            .buttonStyle(.plain)
        }
    }

    @discardableResult
    private func handleScreenContextToggle(_ enabled: Bool) -> Bool {
        guard enabled else {
            clearPendingScreenContextEnable()
            controller.updateConfig {
                $0.enableScreenContext = false
                $0.enableDictationOCRContext = false
            }
            return false
        }

        guard accessibilityGranted else {
            pendingScreenContextEnable = true
            pendingScreenContextRequestedAt = Date().timeIntervalSince1970
            let granted = controller.requestScreenContextEnable()
            accessibilityGranted = AXIsProcessTrusted()
            if granted || accessibilityGranted {
                clearPendingScreenContextEnable()
            }
            return granted || accessibilityGranted
        }

        clearPendingScreenContextEnable()
        return controller.requestScreenContextEnable()
    }

    private func handleDictionaryCorrectionPromptsToggle(_ enabled: Bool) {
        if controller.setDictionaryCorrectionPromptsFromToggle(enabled) == .needsAccessibilityPermission {
            isShowingDictionaryAccessibilityPrompt = true
        }
    }

    private func startPermissionPolling() {
        // Startup already synchronizes this state. Querying SMAppService here can
        // block the main thread long enough to make Settings appear unresponsive.
        refreshPermissionStatuses()
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshPermissionStatuses()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionStatuses(refreshLaunchAtLogin: Bool = false) {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        controller.reconcilePendingDictionaryCorrectionAccessibilityEnable()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if refreshLaunchAtLogin {
            controller.refreshLaunchAtLoginState()
        }
        if accessibilityGranted && pendingScreenContextEnable {
            if controller.requestScreenContextEnable() {
                clearPendingScreenContextEnable()
            }
        }
        if !accessibilityGranted && isPendingScreenContextGrantExpired {
            clearPendingScreenContextEnable()
        }
        if !accessibilityGranted && appState.config.enableScreenContext {
            clearPendingScreenContextEnable()
            controller.updateConfig {
                $0.enableScreenContext = false
                $0.enableDictationOCRContext = false
            }
        }
        if (!appState.config.enableScreenContext || !screenRecordingGranted) && appState.config.enableDictationOCRContext {
            controller.updateConfig { $0.enableDictationOCRContext = false }
        }
        controller.reclassifyVoiceNotesAsDictationIfReady(
            microphoneGranted: micGranted,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted
        )
        refreshSystemAudioPermissionIfNeeded()
    }

    private var isPendingScreenContextGrantExpired: Bool {
        guard pendingScreenContextEnable else { return false }
        guard pendingScreenContextRequestedAt > 0 else { return true }
        return Date().timeIntervalSince1970 - pendingScreenContextRequestedAt > screenContextGrantIntentTimeout
    }

    private func clearPendingScreenContextEnable() {
        pendingScreenContextEnable = false
        pendingScreenContextRequestedAt = 0
    }

    private func refreshSystemAudioPermissionIfNeeded() {
        guard appState.config.useCoreAudioTap, !isCheckingSystemAudioPermission else { return }
        isCheckingSystemAudioPermission = true

        Task {
            let granted = await Task.detached(priority: .utility) {
                CoreAudioSystemRecorder.checkSystemAudioPermission()
            }.value
            await MainActor.run {
                self.systemAudioGranted = granted
                self.isCheckingSystemAudioPermission = false
            }
        }
    }

    // MARK: - Layout Primitives

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(MuesliTheme.spacing16)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    /// Standardized row: label on left, control on right.
    /// Controls share a fixed-width column so they all right-align consistently.
    @ViewBuilder
    private func settingsRow(_ label: String, controlWidth rowControlWidth: CGFloat? = nil, @ViewBuilder control: () -> some View) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center) {
            Text(label)
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .layoutPriority(1)
            Spacer(minLength: 20)
            ZStack(alignment: .trailing) {
                // Invisible spacer forces the ZStack to exactly controlWidth
                Color.clear.frame(width: width, height: 1)
                control()
                    .frame(maxWidth: width)
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private func settingsRow(
        _ label: String,
        description: String,
        controlWidth rowControlWidth: CGFloat? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        let width = rowControlWidth ?? controlWidth
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(description)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            control()
                .frame(width: width, alignment: .trailing)
        }
        .frame(minHeight: 44)
    }

    private func settingsDescription(_ text: String) -> some View {
        Text(text)
            .font(MuesliTheme.caption())
            .foregroundStyle(MuesliTheme.textTertiary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.top, -4)
            .padding(.bottom, MuesliTheme.spacing8)
    }

    private func summaryRetryLabel(_ retryCount: Int) -> String {
        let clamped = MeetingSummaryRetryPolicy.clampedRetryCount(retryCount)
        switch clamped {
        case 0:
            return String(localized: "settings.meetings.summary_retries.none", defaultValue: "No retries", comment: "Option label for zero summary retry attempts")
        case 1:
            return String(localized: "settings.meetings.summary_retries.one", defaultValue: "1 retry", comment: "Option label for one summary retry attempt")
        default:
            return String(format: String(localized: "settings.meetings.summary_retries.many", defaultValue: "%d retries", comment: "Option label for multiple summary retry attempts"), clamped)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func settingsSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .tint(MuesliTheme.accent)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func settingsMenu(
        selection: String,
        options: [String],
        disabledOptions: Set<String> = [],
        onChange: @escaping (String) -> Void
    ) -> some View {
        FixedWidthPopUp(
            selection: selection,
            options: options,
            disabledOptions: disabledOptions,
            onChange: onChange
        )
            .frame(height: 24)
    }

    @ViewBuilder
    private func compactActionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isDestructive ? MuesliTheme.recording.opacity(0.25) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var mutedMeetingDetectionAppsControl: some View {
        let muted = Set(appState.config.mutedMeetingDetectionAppBundleIDs)
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.meeting_detection.muted_apps.description", defaultValue: "Don't notify me when a call is detected in these apps:", comment: "Description above muted apps list for meeting detection notifications"))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(meetingDetectionAppOptions) { app in
                    mutedDetectionAppButton(app, isMuted: muted.contains(app.bundleID))
                }
            }
        }
        .padding(.leading, MuesliTheme.spacing16)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MuesliTheme.surfaceBorder)
                .frame(width: 2)
        }
    }

    private func mutedDetectionAppButton(_ app: MeetingDetectionAppOption, isMuted: Bool) -> some View {
        Button {
            updateMutedMeetingDetectionApp(app.bundleID, isMuted: !isMuted)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMuted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMuted ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 16)
                Image(systemName: app.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 14)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isMuted ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isMuted ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func updateMutedMeetingDetectionApp(_ bundleID: String, isMuted: Bool) {
        controller.updateConfig { config in
            var muted = Set(config.mutedMeetingDetectionAppBundleIDs)
            if isMuted {
                muted.insert(bundleID)
            } else {
                muted.remove(bundleID)
            }
            config.mutedMeetingDetectionAppBundleIDs = muted.sorted()
        }
    }

    // MARK: - Calendars

    private struct CalendarToggleItem: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String?
        let isEnabled: Bool
    }

    private struct CalendarSourceGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let iconName: String
        let items: [CalendarToggleItem]
    }

    private var calendarSourceGroups: [CalendarSourceGroup] {
        let disabled = Set(appState.config.disabledCalendarIDs)
        var groups: [CalendarSourceGroup] = []

        let ekBySource = Dictionary(grouping: appState.availableEventKitCalendars) { $0.sourceTitle }
        for sourceTitle in ekBySource.keys.sorted() {
            let items = (ekBySource[sourceTitle] ?? [])
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { cal in
                    CalendarToggleItem(
                        id: cal.id,
                        title: cal.title,
                        colorHex: cal.colorHex,
                        isEnabled: !disabled.contains(cal.id)
                    )
                }
            groups.append(CalendarSourceGroup(
                id: "ek::\(sourceTitle)",
                title: sourceTitle,
                subtitle: calendarSourceSubtitle(for: sourceTitle),
                iconName: calendarSourceIconName(for: sourceTitle),
                items: items
            ))
        }

        if appState.isGoogleCalendarAuthenticated && !appState.availableGoogleCalendars.isEmpty {
            let items = appState.availableGoogleCalendars.map { cal in
                CalendarToggleItem(
                    id: cal.id,
                    title: cal.summary + (cal.isPrimary ? " " + String(localized: "settings.calendars.primary_suffix", defaultValue: "(Primary)", comment: "Suffix appended to calendar name for primary calendar indicator") : ""),
                    colorHex: cal.colorHex,
                    isEnabled: !disabled.contains(cal.id)
                )
            }
            groups.append(CalendarSourceGroup(
                id: "google_oauth",
                title: "Google Calendar",
                subtitle: String(localized: "settings.calendars.google.connected_directly", defaultValue: "Connected directly to Muesli", comment: "Subtitle indicating calendar source is connected directly through Muesli"),
                iconName: "calendar.badge.plus",
                items: items
            ))
        }

        return groups
    }

    private var calendarSourcesControl: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            Text(String(localized: "settings.calendars.sources.explanation", defaultValue: "Calendar sources are listed first, with their calendars underneath. Disabled calendars are hidden from Muesli — no notifications, no Coming Up, no meeting detection.", comment: "Help text explaining calendar source grouping and effects of disabling calendars"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if calendarSourceGroups.isEmpty {
                Text(String(localized: "settings.calendars.none_detected_permission_hint", defaultValue: "No calendars detected. Make sure Calendar permission is granted in System Settings > Privacy & Security > Calendars.", comment: "Permission hint shown when no calendars are detected"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(calendarSourceGroups) { group in
                    calendarSourceGroupView(group)
                }
            }

            if appState.isGoogleCalendarAuthenticated && !appState.availableEventKitCalendars.isEmpty {
                Text(String(localized: "settings.calendars.google_duplicates_explanation", defaultValue: "Google calendars may appear once from macOS Calendar and once from Muesli's Google connection. Turn off both copies to hide that calendar completely.", comment: "Help text explaining duplicate Google calendar sources and hiding behavior"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.isGoogleCalendarAuthenticated {
                googleCalendarListLoadStateView
            }
        }
    }

    @ViewBuilder
    private func calendarSourceGroupView(_ group: CalendarSourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(group.subtitle) • \(group.items.count) \(group.items.count == 1 ? String(localized: "settings.calendar_source.count.singular", defaultValue: "calendar", comment: "Singular unit label for calendar count") : String(localized: "settings.calendar_source.count.plural", defaultValue: "calendars", comment: "Plural unit label for calendar count"))")
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    calendarToggleButton(item)
                }
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 2)
    }

    private func calendarSourceSubtitle(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return String(localized: "settings.calendars.source_subtitle.icloud_account", defaultValue: "iCloud account in macOS Calendar", comment: "Subtitle for iCloud calendar source in macOS Calendar app")
        }
        if normalized == "subscribed calendars" {
            return String(localized: "settings.calendars.source_subtitle.subscribed", defaultValue: "Subscribed in macOS Calendar", comment: "Subtitle for subscribed calendar source in macOS Calendar app")
        }
        if normalized == "other" {
            return String(localized: "settings.calendars.source_subtitle.system_calendars", defaultValue: "System calendars from macOS", comment: "Subtitle for calendar source representing system calendars from macOS")
        }
        return String(localized: "settings.calendars.source_subtitle.account_macos", defaultValue: "Calendar account in macOS", comment: "Subtitle for calendar source representing a macOS calendar account")
    }

    private func calendarSourceIconName(for sourceTitle: String) -> String {
        let normalized = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "icloud" {
            return "icloud"
        }
        if normalized == "subscribed calendars" {
            return "calendar.badge.clock"
        }
        if normalized == "other" {
            return "person.crop.circle.badge.clock"
        }
        return "calendar"
    }

    private func calendarToggleButton(_ item: CalendarToggleItem) -> some View {
        Button {
            updateDisabledCalendar(item.id, isDisabled: item.isEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.isEnabled ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 16)
                Circle()
                    .fill(item.colorHex.map { Color(hex: $0) } ?? MuesliTheme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(item.isEnabled ? MuesliTheme.textPrimary : MuesliTheme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var googleCalendarListLoadStateView: some View {
        switch appState.googleCalendarListLoadState {
        case .loading:
            Text(String(localized: "settings.google_calendar.loading_calendars", defaultValue: "Loading Google calendars…", comment: "Loading state text while fetching Google calendars"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
        case .failed(let message):
            HStack(spacing: 8) {
                Text(String(format: String(localized: "settings.google_calendar.load_failed_with_message", defaultValue: "Failed to load Google calendars: %@", comment: "Error text shown when Google calendars fail to load with server message"), "\(message)"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                Button(String(localized: "settings.google_calendar.retry", defaultValue: "Retry", comment: "Button label to retry loading Google calendars")) {
                    Task { await controller.refreshGoogleCalendarList() }
                }
                .buttonStyle(.link)
                .font(MuesliTheme.caption())
            }
        case .idle, .loaded:
            EmptyView()
        }
    }

    private func refreshMeetingCalendarSourcesIfNeeded() {
        guard !hasRefreshedMeetingCalendarSources else { return }
        hasRefreshedMeetingCalendarSources = true
        controller.refreshAvailableEventKitCalendars()
        Task { await controller.refreshGoogleCalendarList() }
    }

    private func updateDisabledCalendar(_ calendarID: String, isDisabled: Bool) {
        controller.updateConfig { config in
            var disabled = Set(config.disabledCalendarIDs)
            if isDisabled {
                disabled.insert(calendarID)
            } else {
                disabled.remove(calendarID)
            }
            config.disabledCalendarIDs = disabled.sorted()
        }
        Task { await controller.refreshUpcomingCalendarEvents() }
    }

    @ViewBuilder
    private var autoExportFolderPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)

                if appState.config.autoExportMarkdownFolderPath.isEmpty {
                    Text(String(localized: "settings.auto_export.choose_folder", defaultValue: "Choose a folder…", comment: "Button label to choose auto-export destination folder"))
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.autoExportMarkdownFolderPath)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .help(appState.config.autoExportMarkdownFolderPath.isEmpty ? String(localized: "settings.auto_export.no_destination_folder_selected", defaultValue: "No destination folder selected", comment: "Placeholder text when auto-export destination folder is not selected") : appState.config.autoExportMarkdownFolderPath)

            if !appState.config.autoExportMarkdownFolderPath.isEmpty {
                Button {
                    controller.updateConfig { $0.autoExportMarkdownFolderPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "settings.auto_export.clear_destination_folder_accessibility_label", defaultValue: "Clear destination folder", comment: "Accessibility label for button that clears selected destination folder"))
                .help(String(localized: "settings.auto_export.help.clear_destination_folder", defaultValue: "Clear destination folder", comment: "Help tooltip for button that clears selected destination folder"))
            }

            Button {
                pickAutoExportFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "settings.auto_export.choose_destination_folder_accessibility_label", defaultValue: "Choose destination folder", comment: "Accessibility label for button that selects destination folder"))
            .help(String(localized: "settings.auto_export.help.choose_destination_folder", defaultValue: "Choose destination folder", comment: "Help tooltip for button that selects destination folder"))
        }
    }

    @ViewBuilder
    private var meetingHookPathPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)

                if appState.config.meetingHookPath.isEmpty {
                    Text(String(localized: "settings.meeting_hook.choose_script", defaultValue: "Choose a script…", comment: "Button label to choose post-meeting hook script"))
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(appState.config.meetingHookPath)
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .help(appState.config.meetingHookPath.isEmpty ? String(localized: "settings.meeting_hook.no_script_selected", defaultValue: "No hook script selected", comment: "Placeholder text when no hook script has been selected") : appState.config.meetingHookPath)

            if !appState.config.meetingHookPath.isEmpty {
                Button {
                    controller.updateConfig { $0.meetingHookPath = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "settings.meeting_hook.help.clear_script", defaultValue: "Clear hook script", comment: "Help tooltip for button that clears selected hook script"))
            }

            Button {
                pickMeetingHookFile()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "settings.meeting_hook.help.choose_script", defaultValue: "Choose hook script", comment: "Help tooltip for button that chooses a hook script"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var meetingHookTimeoutControl: some View {
        Stepper(
            value: Binding(
                get: { max(appState.config.meetingHookTimeoutSeconds, 1) },
                set: { newValue in
                    controller.updateConfig { $0.meetingHookTimeoutSeconds = max(newValue, 1) }
                }
            ),
            in: 1...600
        ) {
            Text(String(format: String(localized: "settings.meeting_hook.timeout.seconds_value", defaultValue: "%d seconds", comment: "Displayed timeout value for meeting hook execution in seconds"), max(appState.config.meetingHookTimeoutSeconds, 1)))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 92, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func meetingTemplateMenu(selectionID: String, onChange: @escaping (String) -> Void) -> some View {
        let allItems: [(id: String, label: String)] = {
            var items: [(String, String)] = [(MeetingTemplates.autoID, MeetingTemplates.auto.title)]
            items += controller.builtInMeetingTemplates().map { ($0.id, $0.title) }
            items += controller.customMeetingTemplates().map { ($0.id, $0.name) }
            return items
        }()
        let selectedLabel = allItems.first(where: { $0.id == selectionID })?.label ?? String(localized: "settings.common.auto", defaultValue: "Auto", comment: "Common option label for automatic selection")
        FixedWidthPopUp(
            selection: selectedLabel,
            options: allItems.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < allItems.count else { return }
                onChange(allItems[index].id)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelMenu(currentModel: String, presets: [SummaryModelPreset], onChange: @escaping (String) -> Void) -> some View {
        let menuPresets = SummaryModelPreset.menuPresets(presets, currentModel: currentModel)
        let effectiveModel = currentModel.isEmpty ? (presets.first?.id ?? "") : currentModel
        let selectedLabel = menuPresets.first(where: { $0.id == effectiveModel })?.label ?? menuPresets.first?.label ?? ""
        FixedWidthPopUp(
            selection: selectedLabel,
            options: menuPresets.map(\.label),
            onSelectIndex: { index in
                guard index >= 0 && index < menuPresets.count else { return }
                let selectedId = menuPresets[index].id
                onChange(selectedId == presets.first?.id ? "" : selectedId)
            }
        )
        .frame(height: 24)
    }

    @ViewBuilder
    private func settingsModelTextField(currentModel: String, placeholder: String, onChange: @escaping (String) -> Void) -> some View {
        PastableTextField(
            text: currentModel,
            placeholder: placeholder,
            onChange: { value in
                onChange(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
        .frame(height: 22)
    }

    @ViewBuilder
    private var openRouterFreeModelMenu: some View {
        if isLoadingOpenRouterFreeModels {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "settings.open_router_free_model.loading_models", defaultValue: "Loading models", comment: "Loading state text while fetching OpenRouter free model list"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else if !openRouterFreeModels.isEmpty {
            settingsModelMenu(
                currentModel: appState.config.openRouterModel,
                presets: openRouterFreeModels
            ) { val in controller.updateConfig { $0.openRouterModel = val } }
        } else {
            HStack(spacing: 8) {
                if let openRouterFreeModelsError {
                    Text(openRouterFreeModelsError)
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .lineLimit(1)
                }
                Button(String(localized: "settings.open_router_free_model.load", defaultValue: "Load", comment: "Button label to load OpenRouter free models")) {
                    loadOpenRouterFreeModels(force: true)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func loadOpenRouterFreeModelsIfNeeded() {
        guard openRouterFreeModels.isEmpty, !isLoadingOpenRouterFreeModels else { return }
        loadOpenRouterFreeModels(force: false)
    }

    private func loadOpenRouterFreeModels(force: Bool) {
        guard force || openRouterFreeModels.isEmpty else { return }
        isLoadingOpenRouterFreeModels = true
        openRouterFreeModelsError = nil

        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=text")!
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let catalog = try JSONDecoder().decode(OpenRouterModelCatalog.self, from: data)
                let presets = OpenRouterModelCatalogFilter.freeTextSummaryPresets(from: catalog.data)

                await MainActor.run {
                    openRouterFreeModels = presets
                    openRouterFreeModelsError = presets.isEmpty ? "No free text models found" : nil
                    isLoadingOpenRouterFreeModels = false
                }
            } catch {
                await MainActor.run {
                    openRouterFreeModels = []
                    openRouterFreeModelsError = "Could not load"
                    isLoadingOpenRouterFreeModels = false
                }
            }
        }
    }

    @ViewBuilder
    private func keyStatusRow(key: String) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Circle()
                .fill(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                .frame(width: 6, height: 6)
            Text(key.isEmpty ? String(localized: "settings.api_key.status.not_configured", defaultValue: "No API key configured", comment: "Status text indicating API key is not configured") : String(localized: "settings.api_key.status.configured", defaultValue: "Key configured", comment: "Status text indicating API key is configured"))
                .font(.system(size: 11))
                .foregroundStyle(key.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: MuesliTheme.spacing8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(isDestructive ? MuesliTheme.recording.opacity(0.1) : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(
                            isDestructive ? MuesliTheme.recording.opacity(0.2) : MuesliTheme.surfaceBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func recordingSaveLabel(for policy: MeetingRecordingSavePolicy) -> String {
        switch policy {
        case .never:
            return String(localized: "settings.meetings.recording_save.never", defaultValue: "Never", comment: "Option label for never saving meeting recordings")
        case .prompt:
            return String(localized: "settings.meetings.recording_save.ask_every_time", defaultValue: "Ask every time", comment: "Option label for prompting every time before saving meeting recordings")
        case .always:
            return String(localized: "settings.meetings.recording_save.always", defaultValue: "Always", comment: "Option label for always saving meeting recordings")
        }
    }

    private func recordingSavePolicy(for label: String) -> MeetingRecordingSavePolicy? {
        let policy = MeetingRecordingSavePolicy.allCases.first { recordingSaveLabel(for: $0) == label }
        if policy == nil {
            assertionFailure("Unexpected recording save label: \(label)")
        }
        return policy
    }

    private func recordingFileFormatLabel(for format: MeetingRecordingFileFormat) -> String {
        format.displayName
    }

    private func recordingFileFormat(for label: String) -> MeetingRecordingFileFormat? {
        let format = MeetingRecordingFileFormat.allCases.first { recordingFileFormatLabel(for: $0) == label }
        if format == nil {
            assertionFailure("Unexpected recording file format label: \(label)")
        }
        return format
    }

    private func scheduledMeetingLeadTimeLabel(for leadTime: ScheduledMeetingNotificationLeadTime) -> String {
        switch leadTime {
        case .atStart:
            return String(localized: "settings.meetings.reminder_timing.at_start", defaultValue: "At start time", comment: "Reminder timing option label for start time")
        case .oneMinute:
            return String(localized: "settings.meetings.reminder_timing.one_min_before", defaultValue: "1 min before", comment: "Reminder timing option label for one minute before start")
        case .threeMinutes:
            return String(localized: "settings.meetings.reminder_timing.three_min_before", defaultValue: "3 min before", comment: "Reminder timing option label for three minutes before start")
        case .fiveMinutes:
            return String(localized: "settings.meetings.reminder_timing.five_min_before", defaultValue: "5 min before", comment: "Reminder timing option label for five minutes before start")
        }
    }

    private func scheduledMeetingLeadTime(for label: String) -> ScheduledMeetingNotificationLeadTime? {
        let leadTime = ScheduledMeetingNotificationLeadTime.allCases.first {
            scheduledMeetingLeadTimeLabel(for: $0) == label
        }
        if leadTime == nil {
            assertionFailure("Unexpected scheduled meeting notification lead time label: \(label)")
        }
        return leadTime
    }
}

// MARK: - Pastable Secure Field (NSViewRepresentable)

/// NSSecureTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
/// Required because the app runs as .accessory (no menu bar), so key equivalents
/// don't route to text fields by default.
class EditableNSSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// NSPopUpButton wrapper that respects width constraints (SwiftUI Picker with .menu style ignores them).
struct FixedWidthPopUp: NSViewRepresentable {
    let selection: String
    let options: [String]
    let disabledOptions: Set<String>
    /// Reports the selected index, avoiding label collision issues.
    let onSelectionIndex: (Int) -> Void

    init(
        selection: String,
        options: [String],
        disabledOptions: Set<String> = [],
        onChange: @escaping (String) -> Void
    ) {
        self.selection = selection
        self.options = options
        self.disabledOptions = disabledOptions
        self.onSelectionIndex = { index in
            guard index >= 0 && index < options.count else { return }
            guard !disabledOptions.contains(options[index]) else { return }
            onChange(options[index])
        }
    }

    init(
        selection: String,
        options: [String],
        disabledOptions: Set<String> = [],
        onSelectIndex: @escaping (Int) -> Void
    ) {
        self.selection = selection
        self.options = options
        self.disabledOptions = disabledOptions
        self.onSelectionIndex = { index in
            guard index >= 0 && index < options.count else { return }
            guard !disabledOptions.contains(options[index]) else { return }
            onSelectIndex(index)
        }
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.removeAllItems()
        button.addItems(withTitles: options)
        button.menu?.autoenablesItems = false
        updateEnabledItems(in: button)
        button.selectItem(withTitle: selection)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let currentTitles = button.itemTitles
        if currentTitles != options {
            button.removeAllItems()
            button.addItems(withTitles: options)
        }
        updateEnabledItems(in: button)
        if button.titleOfSelectedItem != selection {
            button.selectItem(withTitle: selection)
        }
        context.coordinator.onSelectionIndex = onSelectionIndex
    }

    private func updateEnabledItems(in button: NSPopUpButton) {
        for item in button.itemArray {
            item.isEnabled = !disabledOptions.contains(item.title)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelectionIndex: onSelectionIndex) }

    class Coordinator: NSObject {
        var onSelectionIndex: (Int) -> Void
        init(onSelectionIndex: @escaping (Int) -> Void) { self.onSelectionIndex = onSelectionIndex }
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            onSelectionIndex(sender.indexOfSelectedItem)
        }
    }
}

/// A text field that supports Cmd+V paste and masks the value when not focused.
struct PastableSecureField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSSecureTextField {
        let field = EditableNSSecureTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

/// Plain text field with the same accessory-app edit shortcuts as secure fields.
struct PastableTextField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: EditableNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) {
            self.onChange = onChange
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            onChange(field.stringValue)
        }
    }
}

private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else {
            self = .black; return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

private extension NSColor {
    func toHexString() -> String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent  * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
