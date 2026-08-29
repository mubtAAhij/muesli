import AVFoundation
import ApplicationServices
import SwiftUI
import MuesliCore

struct OnboardingView: View {
    let controller: MuesliController
    let appState: AppState

    @State private var currentStep: Int
    @State private var userName: String
    @State private var selectedUseCase: OnboardingUseCase
    @State private var selectedBackend: BackendOption
    @State private var selectedCohereLanguage: CohereTranscribeLanguage
    @State private var summaryBackend: MeetingSummaryBackendOption = .chatGPT
    @State private var apiKey = ""
    @State private var isSigningInChatGPT = false
    @State private var chatGPTSignInDone = false
    @State private var chatGPTSignInError: String?

    // Permission states — polled from OS every second
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var screenRecordingGranted = false
    @State private var systemAudioGranted = false
    @State private var permissionPollTimer: Timer?
    @State private var grantingPermissionName: String?
    @State private var nativePermissionPromptName: String?
    @State private var recentlyGrantedPermissionName: String?

    // Hotkey recorder
    @State private var selectedHotkey: HotkeyConfig
    @State private var isRecordingHotkey = false
    @State private var hotkeyEventMonitor: Any?

    // Model selection
    @State private var showMoreModels = false

    // Dictation test
    @State private var isDictationTesting = false
    @State private var isDictationTestMonitorActive = false
    @State private var dictationTestResult: String?
    @State private var dictationTestError: String?
    @State private var isModelStillDownloading = false
    @State private var modelReadyBackend: BackendOption?
    @State private var modelDownloadBackend: BackendOption?
    @State private var modelDownloadTask: Task<Void, Never>?
    @State private var modelDownloadGeneration = UUID()
    @State private var modelDownloadProgress: Double?
    @State private var modelDownloadSnapshot: ModelDownloadProgress?
    @State private var isModelPreparingAfterDownload = false
    @State private var modelDownloadStatus: String?
    @State private var modelDownloadError: String?
    @State private var modelReadyIndicatorBackend: BackendOption?
    @State private var modelReadyIndicatorTask: Task<Void, Never>?

    // Google Calendar
    @State private var isSigningInGoogleCal = false
    @State private var googleCalSignInDone = false
    @State private var googleCalSignInError: String?
    @State private var hasFinishedOnboarding = false

    static let permissionsStep = OnboardingFlow.Step.permissions.rawValue
    static let dictationTestStep = OnboardingFlow.dictationTestStep

    private var orderedSteps: [Int] {
        OnboardingFlow.orderedSteps(for: selectedUseCase)
    }

    private var currentStepIndex: Int {
        OnboardingFlow.stepIndex(currentStep, for: selectedUseCase)
    }

    private var totalSteps: Int {
        orderedSteps.count
    }

    private var onboardingAlternativeModels: [BackendOption] {
        var options = BackendOption.onboarding.filter { $0 != BackendOption.onboardingDefault }
        if BackendOption.onboarding.contains(selectedBackend),
           selectedBackend != BackendOption.onboardingDefault,
           !options.contains(selectedBackend) {
            options.insert(selectedBackend, at: 0)
        }
        return options
    }

    private var onboardingModelDescription: String {
        if BackendOption.onboardingDefault == .appleSpeechAnalyzer {
            return String(localized: "onboarding.model.description.apple_speech_or_local", defaultValue: "Use Apple Speech, or choose another local model to download while you continue setup.", bundle: .module, comment: "Onboarding description for using Apple Speech or downloading another local model")
        }
        return String(localized: "onboarding.model.description.fast_local_model", defaultValue: "Start with a fast local model. Larger models can download while you continue setup.", bundle: .module, comment: "Onboarding description recommending a fast local model first")
    }

    init(
        controller: MuesliController,
        appState: AppState,
        initialStep: Int = 0,
        initialUserName: String = "",
        initialBackend: BackendOption = BackendOption.onboardingDefault,
        initialCohereLanguage: CohereTranscribeLanguage = CohereTranscribeLanguage.defaultLanguage,
        initialHotkey: HotkeyConfig = .default,
        initialSystemAudioRequested: Bool = false,
        initialUseCase: OnboardingUseCase = .dictation,
        initialSummaryBackend: MeetingSummaryBackendOption = .chatGPT,
        initialModelDownloadProgress: Double? = nil,
        initialModelDownloadStatus: String? = nil
    ) {
        self.controller = controller
        self.appState = appState
        // Pre-populate permission states so resumed onboarding reflects grants
        // that happened before the deliberate restart.
        let initialMicGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let initialAccessibilityGranted = AXIsProcessTrusted()
        let initialInputMonitoringGranted = CGPreflightListenEventAccess()
        let initialScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        let initialSystemAudioGranted = initialSystemAudioRequested
        let initialPermissions = OnboardingPermissionSnapshot(
            microphone: initialMicGranted,
            accessibility: initialAccessibilityGranted,
            inputMonitoring: initialInputMonitoringGranted,
            systemAudio: initialSystemAudioGranted,
            screenRecording: initialScreenRecordingGranted
        )
        let permissionGatedInitialStep = OnboardingPermissionGate.resumeStep(
            requestedStep: initialStep,
            permissions: initialPermissions,
            useCase: initialUseCase,
            permissionsStep: Self.permissionsStep,
            dictationTestStep: Self.dictationTestStep
        )
        let effectiveInitialStep = OnboardingFlow.normalizedStep(permissionGatedInitialStep, for: initialUseCase)

        _currentStep = State(initialValue: effectiveInitialStep)
        _userName = State(initialValue: initialUserName)
        _selectedUseCase = State(initialValue: initialUseCase)
        let sanitizedInitialBackend = BackendOption.onboarding.contains(initialBackend)
            ? initialBackend
            : BackendOption.onboardingDefault
        _selectedBackend = State(initialValue: sanitizedInitialBackend)
        _selectedCohereLanguage = State(initialValue: initialCohereLanguage)
        _selectedHotkey = State(initialValue: initialHotkey)
        _summaryBackend = State(initialValue: initialSummaryBackend)
        _modelDownloadProgress = State(initialValue: initialModelDownloadProgress)
        _modelDownloadStatus = State(initialValue: initialModelDownloadStatus)
        _micGranted = State(initialValue: initialMicGranted)
        _accessibilityGranted = State(initialValue: initialAccessibilityGranted)
        _inputMonitoringGranted = State(initialValue: initialInputMonitoringGranted)
        _screenRecordingGranted = State(initialValue: initialScreenRecordingGranted)
        _systemAudioGranted = State(initialValue: initialSystemAudioGranted)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: modelStep
                case 2: hotkeyStep
                case 3: permissionsStep
                case 4: dictationTestStep
                case 5: meetingSummaryStep
                case 6: googleCalendarStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(MuesliTheme.surfaceBorder)

            // Bottom bar
            HStack {
                HStack(spacing: 6) {
                    ForEach(Array(orderedSteps.enumerated()), id: \.offset) { _, step in
                        Circle()
                            .fill(step == currentStep ? MuesliTheme.accent : MuesliTheme.textTertiary)
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                HStack(spacing: MuesliTheme.spacing12) {
                    if canGoBack {
                        Button(String(localized: "onboarding.navigation.back", defaultValue: "Back", bundle: .module, comment: "Onboarding navigation button title to go back")) {
                            goToPreviousStep()
                        }
                        .buttonStyle(.plain)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .padding(.horizontal, MuesliTheme.spacing16)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    primaryButton
                }
            }
            .padding(.horizontal, MuesliTheme.spacing32)
            .padding(.vertical, MuesliTheme.spacing16)
        }
        .background(MuesliTheme.backgroundBase)
        .preferredColorScheme(.dark)
        .onAppear {
            saveProgress(atStep: currentStep)
        }
        .onChange(of: currentStep) { _, step in
            saveProgress(atStep: step)
        }
        .onChange(of: userName) { _, _ in
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedUseCase) { _, _ in
            if !orderedSteps.contains(currentStep) {
                currentStep = OnboardingFlow.normalizedStep(currentStep, for: selectedUseCase)
            }
            resetModelDownloadForBackendChange()
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedBackend) { _, _ in
            resetModelDownloadForBackendChange()
            saveProgress(atStep: currentStep)
        }
        .onChange(of: selectedCohereLanguage) { _, _ in
            saveProgress(atStep: currentStep)
        }
        .onChange(of: modelReadyBackend) { _, _ in
            startDictationTestMonitorIfReady()
        }
        .onChange(of: isModelStillDownloading) { _, _ in
            startDictationTestMonitorIfReady()
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowModelDownloadIndicator {
                modelDownloadIndicator
                    .padding(.top, MuesliTheme.spacing16)
                    .padding(.trailing, MuesliTheme.spacing16)
            }
        }
    }

    // MARK: - Primary Button

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case 0:
            onboardingButton(String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue"), enabled: !userName.trimmingCharacters(in: .whitespaces).isEmpty) {
                goToNextStep()
            }
        case 1:
            onboardingButton(selectedBackend.isDownloaded ? String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue") : String(localized: "onboarding.navigation.download_and_continue", defaultValue: "Download & Continue", bundle: .module, comment: "Onboarding navigation button title to download model and continue"), enabled: true) {
                startDownload()
            }
        case 2:
            onboardingButton(String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue"), enabled: true) {
                goToNextStep()
            }
        case 3:
            onboardingButton(currentStepIndex == orderedSteps.count - 1 ? String(localized: "onboarding.navigation.finish", defaultValue: "Finish", bundle: .module, comment: "Onboarding navigation button title to finish setup") : String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue"), enabled: requiredPermissionsGranted) {
                if selectedUseCase.includesPushToTalk {
                    saveProgressAndRestart()
                } else if currentStepIndex == orderedSteps.count - 1 {
                    finishOnboarding(withKey: false)
                } else {
                    goToNextStep()
                }
            }
        case 4:
            if dictationTestResult != nil {
                onboardingButton(selectedUseCase.includesMeetings ? String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue") : String(localized: "onboarding.navigation.finish", defaultValue: "Finish", bundle: .module, comment: "Onboarding navigation button title to finish setup"), enabled: true) {
                    if selectedUseCase.includesMeetings {
                        goToNextStep()
                    } else {
                        finishOnboarding(withKey: false)
                    }
                }
            } else {
                HStack(spacing: MuesliTheme.spacing12) {
                    skipButton {
                        if selectedUseCase.includesMeetings {
                            goToNextStep()
                        } else {
                            finishOnboarding(withKey: false)
                        }
                    }
                    onboardingButton(selectedUseCase.includesMeetings ? String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue") : String(localized: "onboarding.navigation.finish", defaultValue: "Finish", bundle: .module, comment: "Onboarding navigation button title to finish setup"), enabled: false) {
                        if selectedUseCase.includesMeetings {
                            goToNextStep()
                        } else {
                            finishOnboarding(withKey: false)
                        }
                    }
                }
            }
        case 5:
            HStack(spacing: MuesliTheme.spacing12) {
                skipButton { goToNextStep() }
                onboardingButton(String(localized: "onboarding.navigation.continue", defaultValue: "Continue", bundle: .module, comment: "Onboarding navigation button title to continue"), enabled: true) {
                    goToNextStep()
                }
            }
        case 6:
            HStack(spacing: MuesliTheme.spacing12) {
                skipButton { finishOnboarding(withKey: true) }
                onboardingButton(String(localized: "onboarding.navigation.finish", defaultValue: "Finish", bundle: .module, comment: "Onboarding navigation button title to finish setup"), enabled: true) {
                    finishOnboarding(withKey: true)
                }
            }
        default:
            EmptyView()
        }
    }

    private func goToNextStep() {
        guard currentStepIndex < orderedSteps.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = orderedSteps[currentStepIndex + 1]
        }
    }

    private func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = orderedSteps[currentStepIndex - 1]
        }
    }

    @ViewBuilder
    private func onboardingButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, MuesliTheme.spacing20)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(enabled ? MuesliTheme.accent : MuesliTheme.accent.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func skipButton(action: @escaping () -> Void) -> some View {
        Button(String(localized: "onboarding.navigation.skip", defaultValue: "Skip", bundle: .module, comment: "Onboarding navigation button title to skip a step"), action: action)
            .buttonStyle(.plain)
            .font(MuesliTheme.body())
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }

    private var shouldShowModelDownloadIndicator: Bool {
        isModelStillDownloading || modelDownloadError != nil || isShowingModelReadyIndicator
    }

    private var isShowingModelReadyIndicator: Bool {
        modelReadyIndicatorBackend == selectedBackend && !isModelStillDownloading && modelDownloadError == nil
    }

    private var isSelectedModelReadyForDictationTest: Bool {
        modelReadyBackend == selectedBackend && !isModelStillDownloading && modelDownloadError == nil
    }

    private var canGoBack: Bool {
        OnboardingFlow.canGoBack(
            from: currentStep,
            useCase: selectedUseCase,
            dictationTestSucceeded: dictationTestResult != nil
        )
    }

    private var modelDownloadIndicator: some View {
        let progress = modelDownloadProgress.map { min(max($0, 0), 1) }
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MuesliTheme.surfaceBorder)
                    .frame(width: 24, height: 24)

                if isModelPreparingAfterDownload {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                } else if let progress {
                    ModelDownloadProgressShape(progress: progress)
                        .fill(MuesliTheme.accent)
                        .frame(width: 24, height: 24)

                    Circle()
                        .stroke(MuesliTheme.accent.opacity(0.7), lineWidth: 1)
                        .frame(width: 24, height: 24)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(modelDownloadIndicatorTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(modelDownloadError == nil ? MuesliTheme.textSecondary : MuesliTheme.recording)
                    .lineLimit(1)
                Text(modelDownloadIndicatorDetail(progress: progress))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MuesliTheme.backgroundRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
        .frame(width: 260, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.2), value: shouldShowModelDownloadIndicator)
    }

    private var modelDownloadIndicatorTitle: String {
        if let snapshot = modelDownloadSnapshot {
            switch snapshot.phase {
            case .downloading: return String(format: String(localized: "onboarding.model_download.downloading", defaultValue: "Downloading %@", bundle: .module, comment: "Onboarding status text while downloading selected backend model"), "\(selectedBackend.label)")
            case .preparing: return String(format: String(localized: "onboarding.model_download.preparing", defaultValue: "Preparing %@", bundle: .module, comment: "Onboarding status text while preparing selected backend model"), "\(selectedBackend.label)")
            case .ready: return String(format: String(localized: "onboarding.model_download.backend_ready", defaultValue: "%@ ready", bundle: .module, comment: "Onboarding status text when selected backend model is ready"), "\(selectedBackend.label)")
            case .paused: return String(localized: "onboarding.model_download.paused", defaultValue: "Download paused", bundle: .module, comment: "Onboarding status text when model download is paused")
            case .failed: return String(localized: "onboarding.model_download.failed", defaultValue: "Download failed", bundle: .module, comment: "Onboarding status text when model download fails")
            }
        }
        if modelDownloadError != nil {
            return String(localized: "onboarding.model_download.failed_secondary", defaultValue: "Download failed", bundle: .module, comment: "Secondary onboarding status text when model download fails")
        }
        if isShowingModelReadyIndicator {
            return String(format: String(localized: "onboarding.model_download.backend_ready", defaultValue: "%@ ready", bundle: .module, comment: "Onboarding status text when selected backend model is ready"), "\(selectedBackend.label)")
        }
        return String(format: String(localized: "onboarding.model_download.preparing_backend", defaultValue: "Preparing %@", bundle: .module, comment: "Onboarding status text while preparing selected backend model"), "\(selectedBackend.label)")
    }

    private func modelDownloadIndicatorDetail(progress: Double?) -> String {
        if let modelDownloadError {
            return modelDownloadError
        }
        if isShowingModelReadyIndicator {
            return String(localized: "onboarding.model_download.ready_to_test", defaultValue: "Ready to test", bundle: .module, comment: "Onboarding status text when model is ready for dictation test")
        }
        if let snapshot = modelDownloadSnapshot {
            return modelDownloadSnapshotDetail(snapshot)
        }
        if let modelDownloadStatus {
            return modelDownloadStatus
        }
        if let progress {
            return String(format: String(localized: "onboarding.model_download.percent_complete", defaultValue: "%d%% complete", bundle: .module, comment: "Onboarding progress text showing percent complete"), Int((progress * 100).rounded()))
        }
        return String(localized: "onboarding.model_download.downloading_ellipsis", defaultValue: "Downloading...", bundle: .module, comment: "Onboarding status text while model is downloading")
    }

    private func modelDownloadSnapshotDetail(_ snapshot: ModelDownloadProgress) -> String {
        var details: [String] = []
        if let currentFile = snapshot.currentFile?.split(separator: "/").last.map(String.init), !currentFile.isEmpty {
            details.append(currentFile)
        }
        if snapshot.totalFileCount > 0 {
            let completed = min(max(snapshot.completedFileCount, 0), snapshot.totalFileCount)
            let remaining = snapshot.totalFileCount - completed
            details.append(String(format: String(localized: "onboarding.model_download.files_completed", defaultValue: "%d of %d files", bundle: .module, comment: "Onboarding progress text showing completed files out of total"), completed, snapshot.totalFileCount))
            if remaining > 0 {
                details.append(String(format: String(localized: "onboarding.model_download.remaining_time", defaultValue: "%@ left", bundle: .module, comment: "Onboarding progress text showing remaining estimated time"), "\(remaining)"))
            }
        }
        if let total = snapshot.totalBytes, total > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.completedBytes)) / \(ModelDownloadDisplayFormatting.bytes(total))")
            if snapshot.completedBytes < total {
                details.append(String(format: String(localized: "onboarding.model_download.bytes_left_total", defaultValue: "%@ left", bundle: .module, comment: "Onboarding progress text showing total bytes left to download"), "\(ModelDownloadDisplayFormatting.bytes(total - snapshot.completedBytes))"))
            }
        } else if let currentTotal = snapshot.currentFileTotalBytes, currentTotal > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.currentFileCompletedBytes)) / \(ModelDownloadDisplayFormatting.bytes(currentTotal))")
            if snapshot.currentFileCompletedBytes < currentTotal {
                details.append(String(format: String(localized: "onboarding.model_download.current_file_bytes_left", defaultValue: "%@ left", bundle: .module, comment: "Onboarding progress text showing bytes left for current file"), "\(ModelDownloadDisplayFormatting.bytes(currentTotal - snapshot.currentFileCompletedBytes))"))
            }
        }
        if snapshot.phase == .downloading {
            if snapshot.bytesPerSecond > 0 {
                details.append(ModelDownloadDisplayFormatting.rate(snapshot.bytesPerSecond))
            }
            if let eta = snapshot.estimatedSecondsRemaining,
               let formattedETA = ModelDownloadDisplayFormatting.eta(eta) {
                details.append(String(format: String(localized: "onboarding.model_download.eta_left", defaultValue: "%@ left", bundle: .module, comment: "Onboarding progress text showing ETA remaining"), "\(formattedETA)"))
            }
            if snapshot.retryCount > 0 {
                details.append(String(format: String(localized: "onboarding.model_download.retry_status", defaultValue: "retry %d/3", bundle: .module, comment: "Onboarding status text showing current retry count"), snapshot.retryCount))
            }
        } else if let message = snapshot.message, !message.isEmpty {
            details.append(message)
        }
        return details.isEmpty ? (snapshot.message ?? String(localized: "onboarding.model_download.downloading_ellipsis_secondary", defaultValue: "Downloading...", bundle: .module, comment: "Secondary onboarding status text while downloading model")) : details.joined(separator: " · ")
    }

    private var dictationTestSubtitle: AttributedString {
        let markdown: String
        if isSelectedModelReadyForDictationTest {
            markdown = selectedUseCase.includesVoiceNotes
                ? String(format: String(localized: "onboarding.dictation_test.subtitle_voice_note", defaultValue: "Hold **%@** to record a voice note, then release.\nYour words should appear below.", bundle: .module, comment: "Dictation test subtitle instructing user to record a voice note with selected hotkey"), "\(selectedHotkey.label)")
                : String(format: String(localized: "onboarding.dictation_test.subtitle_say_something", defaultValue: "Hold **%@** and say something, then release.\nYour words should appear below.", bundle: .module, comment: "Dictation test subtitle instructing user to speak with selected hotkey"), "\(selectedHotkey.label)")
        } else {
            markdown = dictationTestPreparationSubtitleMarkdown
        }
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown.replacingOccurrences(of: "**", with: ""))
    }

    private var dictationTestPreparationSubtitleMarkdown: String {
        let unlockCopy = selectedUseCase.includesVoiceNotes ? String(localized: "onboarding.dictation_test.unlock_copy.voice_note_test", defaultValue: "Voice note test", bundle: .module, comment: "Unlock copy label for voice note test mode") : String(localized: "onboarding.dictation_test.unlock_copy.dictation", defaultValue: "Dictation", bundle: .module, comment: "Unlock copy label for dictation mode")
        if isModelPreparingAfterDownload {
            return String(format: String(localized: "onboarding.dictation_test.preparation.optimizing_subtitle", defaultValue: "Optimizing **%@** for this Mac.\n%@ will unlock when it is ready.", bundle: .module, comment: "Dictation test preparation subtitle shown while optimizing selected backend"), "\(selectedBackend.label)", "\(unlockCopy)")
        }
        return String(format: String(localized: "onboarding.dictation_test.preparation.preparing_subtitle", defaultValue: "Preparing **%@** for your first test.\n%@ will unlock when the model is ready.", bundle: .module, comment: "Dictation test preparation subtitle shown while preparing selected backend"), "\(selectedBackend.label)", "\(unlockCopy)")
    }

    private var modelPreparationHints: [String] {
        if selectedBackend.backend == "whisper" {
            return [
                String(localized: "onboarding.model_preparation.hint.compiling_coreml", defaultValue: "Compiling CoreML files for the Neural Engine", bundle: .module, comment: "Onboarding hint shown while compiling CoreML files for Neural Engine"),
                String(localized: "onboarding.model_preparation.hint.preparing_first_dictation_test", defaultValue: "Preparing the first dictation test", bundle: .module, comment: "Onboarding hint shown while preparing first dictation test"),
                String(localized: "onboarding.model_preparation.hint.future_launches_skip_most", defaultValue: "Future launches will skip most of this", bundle: .module, comment: "Onboarding hint indicating future launches skip most preparation"),
                String(localized: "onboarding.model_preparation.hint.bring_forward_when_ready", defaultValue: "We'll bring Muesli forward when ready", bundle: .module, comment: "Onboarding hint indicating app will be brought forward when ready"),
            ]
        }
        return [
            String(localized: "onboarding.model_preparation.status.preparing_first_dictation_test", defaultValue: "Preparing the first dictation test", bundle: .module, comment: "Onboarding status text while preparing first dictation test"),
            String(localized: "onboarding.model_preparation.status.future_launches_skip_most", defaultValue: "Future launches will skip most of this", bundle: .module, comment: "Onboarding status text indicating future launches skip most preparation"),
            String(localized: "onboarding.model_preparation.status.bring_forward_when_ready", defaultValue: "We'll bring Muesli forward when ready", bundle: .module, comment: "Onboarding status text indicating app will be brought forward when ready"),
        ]
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            Spacer()

            MWaveformIcon(barCount: 13, spacing: 3)
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 80, height: 48)

            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.welcome.title", defaultValue: "Welcome to Muesli", bundle: .module, comment: "Main title on onboarding welcome screen"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(String(localized: "onboarding.welcome.subtitle", defaultValue: "Local-first dictation and meeting transcription for macOS.", bundle: .module, comment: "Subtitle on onboarding welcome screen"))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.welcome.name_label", defaultValue: "Your name", bundle: .module, comment: "Label for user name field on onboarding welcome screen"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                OnboardingTextField(text: $userName, placeholder: String(localized: "onboarding.welcome.name_placeholder", defaultValue: "Enter your name", bundle: .module, comment: "Placeholder for user name field on onboarding welcome screen"), onSubmit: {
                    if !userName.trimmingCharacters(in: .whitespaces).isEmpty {
                        goToNextStep()
                    }
                })
                    .frame(width: 280, height: 32)
            }

            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.welcome.use_case_prompt", defaultValue: "What will you use Muesli for?", bundle: .module, comment: "Prompt asking user use case on onboarding welcome screen"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)

                LazyVGrid(
                    columns: [
                        GridItem(.fixed(132), spacing: MuesliTheme.spacing8),
                        GridItem(.fixed(132), spacing: MuesliTheme.spacing8),
                    ],
                    spacing: MuesliTheme.spacing8
                ) {
                    useCaseCard(
                        icon: "waveform",
                        title: String(localized: "onboarding.welcome.use_case.voice_notes.title", defaultValue: "Voice Notes", bundle: .module, comment: "Use case option title for voice notes"),
                        subtitle: String(localized: "onboarding.welcome.use_case.voice_notes.subtitle", defaultValue: "Record in Muesli", bundle: .module, comment: "Use case option subtitle for voice notes"),
                        selected: selectedUseCase == .voiceNotes
                    ) {
                        selectedUseCase = .voiceNotes
                    }

                    useCaseCard(
                        icon: "keyboard.fill",
                        title: String(localized: "onboarding.welcome.use_case.dictation.title", defaultValue: "Dictation", bundle: .module, comment: "Use case option title for dictation"),
                        subtitle: String(localized: "onboarding.welcome.use_case.dictation.subtitle", defaultValue: "Paste into apps", bundle: .module, comment: "Use case option subtitle for dictation"),
                        selected: selectedUseCase == .dictation
                    ) {
                        selectedUseCase = .dictation
                    }

                    useCaseCard(
                        icon: "person.2.fill",
                        title: String(localized: "onboarding.welcome.use_case.meetings.title", defaultValue: "Meetings", bundle: .module, comment: "Use case option title for meetings"),
                        subtitle: String(localized: "onboarding.welcome.use_case.meetings.subtitle", defaultValue: "Notes and summaries", bundle: .module, comment: "Use case option subtitle for meetings"),
                        selected: selectedUseCase == .meetings
                    ) {
                        selectedUseCase = .meetings
                    }

                    useCaseCard(
                        icon: "rectangle.3.group.fill",
                        title: String(localized: "onboarding.welcome.use_case.everything.title", defaultValue: "Everything", bundle: .module, comment: "Use case option title for everything mode"),
                        subtitle: String(localized: "onboarding.welcome.use_case.everything.subtitle", defaultValue: "Dictation + meetings", bundle: .module, comment: "Use case option subtitle for everything mode"),
                        selected: selectedUseCase == .dictationAndMeetings
                    ) {
                        selectedUseCase = .dictationAndMeetings
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func useCaseCard(
        icon: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? .white.opacity(0.72) : MuesliTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : MuesliTheme.textSecondary)
            .frame(width: 132, height: 74)
            .background(selected ? MuesliTheme.accent : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(selected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Model Selection

    private var modelStep: some View {
        VStack(spacing: MuesliTheme.spacing16) {
            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.model.choose_transcription_model", defaultValue: "Choose your transcription model", bundle: .module, comment: "Onboarding title prompting user to choose transcription model"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(onboardingModelDescription)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, MuesliTheme.spacing24)

            ScrollView {
                VStack(spacing: MuesliTheme.spacing8) {
                    modelCard(option: BackendOption.onboardingDefault)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMoreModels.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(localized: "onboarding.model.other_models", defaultValue: "Other models", bundle: .module, comment: "Section title for additional model choices during onboarding"))
                                .font(MuesliTheme.caption())
                            Image(systemName: showMoreModels ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, MuesliTheme.spacing4)

                    if showMoreModels {
                        ForEach(onboardingAlternativeModels, id: \.model) { option in
                            modelCard(option: option)
                        }

                        Text(String(localized: "onboarding.model.more_models_after_onboarding", defaultValue: "More models are available after onboarding.", bundle: .module, comment: "Hint text indicating additional models are available later"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, MuesliTheme.spacing4)
                    }

                    if selectedBackend.backend == BackendOption.cohereTranscribe.backend {
                        cohereLanguageCard
                    }
                }
                .padding(.horizontal, MuesliTheme.spacing32)
            }

        }
        .frame(maxWidth: .infinity)
    }

    private var cohereLanguageCard: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(String(localized: "onboarding.cohere.language_title", defaultValue: "Cohere language", bundle: .module, comment: "Title for Cohere language selection during onboarding"))
                .font(MuesliTheme.headline())
                .foregroundStyle(MuesliTheme.textPrimary)

            Text(String(localized: "onboarding.cohere.language_description", defaultValue: "Cohere does not auto-detect language, so pick the language you want it to transcribe.", bundle: .module, comment: "Description explaining Cohere language selection requirement"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)

            FixedWidthPopUp(
                selection: selectedCohereLanguage.label,
                options: CohereTranscribeLanguage.allCases.map(\.label)
            ) { label in
                guard let language = CohereTranscribeLanguage.allCases.first(where: { $0.label == label }) else { return }
                selectedCohereLanguage = language
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.top, MuesliTheme.spacing8)
    }

    private func modelCard(option: BackendOption) -> some View {
        let isSelected = selectedBackend == option
        return Button {
            selectedBackend = option
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Circle()
                    .fill(isSelected ? MuesliTheme.accent : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary, lineWidth: 1.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        if option == BackendOption.onboardingDefault {
                            Text(String(localized: "onboarding.model.recommended", defaultValue: "Recommended", bundle: .module, comment: "Badge text indicating recommended model option"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(MuesliTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()
            }
            .padding(MuesliTheme.spacing12)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(isSelected ? MuesliTheme.accent : MuesliTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Permissions (sequential, one at a time)

    /// The ordered list of permissions to grant during onboarding.
    /// Keep this to the core dictation path so first-run setup gets to a
    /// successful transcription before meeting-specific permissions appear.
    private var permissionSteps: [(icon: String, name: String, description: String, granted: Bool, action: () -> Void)] {
        var steps: [(String, String, String, Bool, () -> Void)] = [
            ("mic.fill", "Microphone", String(localized: "onboarding.permissions.step.microphone.description", defaultValue: "Record audio for voice notes, dictation, and meetings", bundle: .module, comment: "Permission step description for microphone access"), micGranted, {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            })
        ]
        if selectedUseCase.includesPushToTalk {
            if selectedUseCase.includesDictation {
                steps += [
                    ("hand.raised.fill", "Accessibility", String(localized: "onboarding.permissions.step.accessibility.description", defaultValue: "Paste transcribed text into other apps", bundle: .module, comment: "Permission step description for accessibility access"), accessibilityGranted, requestAccessibilityPermission),
                ]
            }
            steps += [
            ("keyboard.fill", "Input Monitoring", String(localized: "onboarding.permissions.step.input_monitoring.description", defaultValue: "Detect hotkey for push-to-talk recording", bundle: .module, comment: "Permission step description for input monitoring access"), inputMonitoringGranted, {
                if !CGRequestListenEventAccess() {
                    self.openSystemSettings("Privacy_ListenEvent")
                }
            }),
            ]
        }
        return steps
    }

    /// Index of the current permission being requested.
    private var currentPermissionIndex: Int {
        for (i, step) in permissionSteps.enumerated() {
            if !step.granted { return i }
        }
        return permissionSteps.count
    }

    private var permissionsStep: some View {
        let steps = permissionSteps
        let idx = currentPermissionIndex
        let total = steps.count
        let confirmationIndex = recentlyGrantedPermissionName.flatMap { grantedName in
            steps.firstIndex { $0.name == grantedName }
        }
        let displayIndex = confirmationIndex ?? idx

        return VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            if displayIndex < total {
                let step = steps[displayIndex]
                let isConfirmingGrant = recentlyGrantedPermissionName == step.name

                VStack(spacing: MuesliTheme.spacing8) {
                    Text(String(format: String(localized: "onboarding.permissions.progress.permission_of_total", defaultValue: "Permission %d of %d", bundle: .module, comment: "Progress label showing current permission step out of total"), displayIndex + 1, total))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .textCase(.uppercase)

                    Text(step.name)
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    Text(step.description)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Image(systemName: step.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isConfirmingGrant ? MuesliTheme.success : MuesliTheme.accent)
                    .frame(height: 64)

                Button {
                    if grantingPermissionName == step.name && !isConfirmingGrant {
                        guard !isWaitingForNativePermissionPrompt(step.name) else { return }
                        openSystemSettingsForPermission(at: displayIndex)
                    } else {
                        grantingPermissionName = step.name
                        recentlyGrantedPermissionName = nil
                        saveProgress(atStep: currentStep)
                        step.action()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConfirmingGrant {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(permissionButtonTitle(for: step.name, isConfirmingGrant: isConfirmingGrant))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, MuesliTheme.spacing24)
                    .padding(.vertical, MuesliTheme.spacing12)
                    .background(isConfirmingGrant ? MuesliTheme.success : MuesliTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                }
                .buttonStyle(.plain)
                .disabled(isConfirmingGrant || isWaitingForNativePermissionPrompt(step.name))
                .animation(.easeInOut(duration: 0.2), value: isConfirmingGrant)

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(progressDotColor(
                                index: i,
                                currentIndex: displayIndex,
                                isConfirmingGrant: isConfirmingGrant
                            ))
                            .frame(width: 8, height: 8)
                    }
                }

                if isWaitingForNativePermissionPrompt(step.name) {
                    Text(String(localized: "onboarding.permissions.respond_prompt", defaultValue: "Respond to the macOS permission prompt", bundle: .module, comment: "Instruction to respond to system permission prompt"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                } else {
                    Button {
                        openSystemSettingsForPermission(at: displayIndex)
                    } label: {
                        Text(String(localized: "onboarding.permissions.open_system_settings_hint", defaultValue: "Not seeing a prompt? Open System Settings", bundle: .module, comment: "Hint to open System Settings when permission prompt is not visible"))
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if step.name == "Input Monitoring", grantingPermissionName == step.name {
                    Button {
                        openApplicationsFolder()
                    } label: {
                        Text(String(localized: "onboarding.permissions.manual_add_hint", defaultValue: "Need to add Muesli manually? Open Applications", bundle: .module, comment: "Hint for manually adding app in permissions settings"))
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if selectedUseCase.canSwitchToVoiceNotesOnly && step.name == "Accessibility" {
                    Button {
                        switchToVoiceNotesOnly()
                    } label: {
                        VStack(spacing: 2) {
                            Text(String(localized: "onboarding.permissions.use_voice_notes", defaultValue: "Use Voice Notes instead", bundle: .module, comment: "Action title to switch onboarding path to voice notes"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(String(localized: "onboarding.permissions.voice_notes_subtitle", defaultValue: "Keeps the hotkey, skips paste permission", bundle: .module, comment: "Subtitle describing voice notes path tradeoff"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        .foregroundStyle(MuesliTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            } else {
                // All granted
                VStack(spacing: MuesliTheme.spacing8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(MuesliTheme.success)

                    Text(String(localized: "onboarding.permissions.all_granted", defaultValue: "All permissions granted", bundle: .module, comment: "Status text when all onboarding permissions are granted"))
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { startPermissionPolling() }
        .onDisappear { stopPermissionPolling() }
    }

    private func permissionButtonTitle(for permissionName: String, isConfirmingGrant: Bool) -> String {
        if isConfirmingGrant { return String(localized: "onboarding.permissions.button.granted", defaultValue: "Granted", bundle: .module, comment: "Permission button label when permission is granted") }
        if isWaitingForNativePermissionPrompt(permissionName) { return String(localized: "onboarding.permissions.button.waiting_for_macos", defaultValue: "Waiting for macOS...", bundle: .module, comment: "Permission button label while waiting for macOS prompt result") }
        if grantingPermissionName == permissionName { return String(localized: "onboarding.permissions.button.open_settings", defaultValue: "Open Settings", bundle: .module, comment: "Permission button label to open system settings") }
        return String(localized: "onboarding.permissions.button.grant_permission", defaultValue: "Grant Permission", bundle: .module, comment: "Permission button label to request permission")
    }

    private func isWaitingForNativePermissionPrompt(_ permissionName: String) -> Bool {
        nativePermissionPromptName == permissionName
    }

    private func requestAccessibilityPermission() {
        nativePermissionPromptName = "Accessibility"
        controller.prepareOnboardingForNativePermissionPrompt()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if nativePermissionPromptName == "Accessibility", !accessibilityGranted {
                nativePermissionPromptName = nil
            }
        }
    }

    private func switchToVoiceNotesOnly() {
        grantingPermissionName = nil
        nativePermissionPromptName = nil
        recentlyGrantedPermissionName = nil
        selectedUseCase = .voiceNotes
        currentStep = OnboardingFlow.normalizedStep(currentStep, for: .voiceNotes)
        saveProgress(atStep: currentStep)
    }

    private func systemSettingsPane(for permissionIndex: Int) -> String {
        let steps = permissionSteps
        guard permissionIndex < steps.count else { return "Privacy_Microphone" }
        switch steps[permissionIndex].name {
        case "Microphone": return "Privacy_Microphone"
        case "Accessibility": return "Privacy_Accessibility"
        case "Input Monitoring": return "Privacy_ListenEvent"
        default: return "Privacy_Microphone"
        }
    }

    private func progressDotColor(index: Int, currentIndex: Int, isConfirmingGrant: Bool) -> Color {
        if index < currentIndex || (isConfirmingGrant && index == currentIndex) {
            return MuesliTheme.success
        }
        if index == currentIndex {
            return MuesliTheme.accent
        }
        return MuesliTheme.surfaceBorder
    }

    private func permissionRow(icon: String, name: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: MuesliTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(description)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MuesliTheme.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button(String(localized: "onboarding.permissions.grant_button", defaultValue: "Grant", bundle: .module, comment: "Button title to grant current onboarding permission")) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(MuesliTheme.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing12)
        .animation(.easeInOut(duration: 0.25), value: granted)
    }

    private var requiredPermissionsGranted: Bool {
        OnboardingPermissionGate.hasRequiredPermissions(
            OnboardingPermissionSnapshot(
                microphone: micGranted,
                accessibility: accessibilityGranted,
                inputMonitoring: inputMonitoringGranted,
                systemAudio: systemAudioGranted,
                screenRecording: screenRecordingGranted
            ),
            for: selectedUseCase
        )
    }

    private func startPermissionPolling() {
        refreshPermissions()
        permissionPollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            withAnimation { refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()

        if let grantingPermissionName, isPermissionGranted(named: grantingPermissionName) {
            notePermissionGranted(grantingPermissionName)
        }
    }

    private func isPermissionGranted(named permissionName: String) -> Bool {
        switch permissionName {
        case "Microphone":
            return micGranted
        case "Accessibility":
            return accessibilityGranted
        case "Input Monitoring":
            return inputMonitoringGranted
        default:
            return false
        }
    }

    @MainActor
    private func notePermissionGranted(_ permissionName: String) {
        guard recentlyGrantedPermissionName != permissionName else { return }
        grantingPermissionName = nil
        nativePermissionPromptName = nil
        recentlyGrantedPermissionName = permissionName
        saveProgress(atStep: currentStep)
        controller.bringOnboardingToFront()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            if recentlyGrantedPermissionName == permissionName {
                withAnimation(.easeInOut(duration: 0.2)) {
                    recentlyGrantedPermissionName = nil
                }
            }
        }
    }

    private func saveProgress(atStep step: Int? = nil) {
        guard !hasFinishedOnboarding else { return }
        let progress = OnboardingProgress(
            currentStep: step ?? currentStep,
            userName: userName,
            selectedBackendKey: selectedBackend.backend,
            selectedModelKey: selectedBackend.model,
            selectedCohereLanguageCode: selectedCohereLanguage.rawValue,
            hotkeyKeyCode: selectedHotkey.keyCode,
            hotkeyLabel: selectedHotkey.label,
            systemAudioRequested: systemAudioGranted,
            onboardingUseCaseRawValue: selectedUseCase.rawValue,
            modelDownloadProgress: modelDownloadProgress,
            modelDownloadStatus: modelDownloadStatus
        )
        OnboardingProgress.save(progress)
    }

    private func saveProgressAndRestart() {
        saveProgress(atStep: Self.dictationTestStep)
        controller.relaunchApp()
    }

    private func openSystemSettingsForPermission(at permissionIndex: Int) {
        let steps = permissionSteps
        if permissionIndex < steps.count {
            grantingPermissionName = steps[permissionIndex].name
            nativePermissionPromptName = nil
            recentlyGrantedPermissionName = nil
            saveProgress(atStep: currentStep)
        }
        openSystemSettings(systemSettingsPane(for: permissionIndex))
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            controller.yieldOnboardingFocusToSystemSettings()
            NSWorkspace.shared.open(url)
        }
    }

    private func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    // MARK: - Step 4: Hotkey Configuration

    private var hotkeyStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.hotkey.title", defaultValue: "Dictation Shortcut", bundle: .module, comment: "Title for onboarding hotkey selection step"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(String(localized: "onboarding.hotkey.instructions", defaultValue: "Choose the key you'll hold to dictate. Press and hold the key to record, release to transcribe.", bundle: .module, comment: "Instructions for choosing dictation shortcut key during onboarding"))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: MuesliTheme.spacing16) {
                // Current hotkey display
                Text(selectedHotkey.label)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .padding(.horizontal, MuesliTheme.spacing32)
                    .padding(.vertical, MuesliTheme.spacing16)
                    .background(MuesliTheme.backgroundRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )

                // Change button
                Button {
                    if isRecordingHotkey {
                        stopRecordingHotkey()
                    } else {
                        startRecordingHotkey()
                    }
                } label: {
                    Text(isRecordingHotkey ? String(localized: "onboarding.hotkey.press_modifier_prompt", defaultValue: "Press a modifier key...", bundle: .module, comment: "Prompt shown while waiting for user to press a modifier key") : String(localized: "onboarding.hotkey.change_shortcut", defaultValue: "Change Shortcut", bundle: .module, comment: "Button title to change selected dictation shortcut"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(isRecordingHotkey ? MuesliTheme.accent : MuesliTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MuesliTheme.spacing16)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(isRecordingHotkey ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(isRecordingHotkey ? MuesliTheme.accent.opacity(0.3) : MuesliTheme.surfaceBorder, lineWidth: 1)
                )
            }

            Text(String(localized: "onboarding.hotkey.supported_keys", defaultValue: "Supported: Left Cmd, Right Cmd, Fn, Ctrl, Option, Shift", bundle: .module, comment: "Text listing supported keys for onboarding shortcut selection"))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onDisappear { stopRecordingHotkey() }
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        hotkeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let keyCode = event.keyCode
            if let label = HotkeyConfig.label(for: keyCode) {
                selectedHotkey = HotkeyConfig(keyCode: keyCode, label: label)
                stopRecordingHotkey()
            }
            return event
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyEventMonitor = nil
        }
    }

    // MARK: - Step 5: Dictation Test

    private var dictationTestStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text(selectedUseCase.includesVoiceNotes ? String(localized: "onboarding.dictation_test.voice_note", defaultValue: "Test Voice Note", bundle: .module, comment: "Button title to run voice note test during onboarding") : String(localized: "onboarding.dictation_test.test_dictation", defaultValue: "Test Dictation", bundle: .module, comment: "Button title to test dictation during onboarding"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(dictationTestSubtitle)
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)

                if isSelectedModelReadyForDictationTest {
                    Text(String(localized: "onboarding.dictation_test.try_saying_example", defaultValue: "Try saying: \"testing this one out\"", bundle: .module, comment: "Instructional example phrase for dictation test"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.top, 2)
                }
            }

            if !isSelectedModelReadyForDictationTest {
                VStack(spacing: MuesliTheme.spacing8) {
                    if isModelPreparingAfterDownload {
                        IndeterminatePreparationBar()
                            .frame(width: 260, height: 7)
                        Text(modelDownloadStatus ?? String(format: String(localized: "onboarding.dictation_test.status.preparing_backend", defaultValue: "Preparing %@...", bundle: .module, comment: "Status text while preparing selected backend for dictation test"), "\(selectedBackend.label)"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                        Text(String(localized: "onboarding.dictation_test.first_run_timing", defaultValue: "This usually takes 20-60 seconds the first time.", bundle: .module, comment: "Timing hint for first dictation test preparation"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                        RotatingPreparationHint(messages: modelPreparationHints)
                            .padding(.top, 2)
                    } else if let modelDownloadProgress {
                        ProgressView(value: modelDownloadProgress, total: 1.0)
                            .frame(width: 260)
                        Text(modelDownloadStatus ?? String(format: String(localized: "onboarding.dictation_test.model_download.percent_complete", defaultValue: "%d%% complete", bundle: .module, comment: "Progress text showing percent complete during model download"), Int((modelDownloadProgress * 100).rounded())))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                        Text(modelDownloadStatus ?? String(format: String(localized: "onboarding.dictation_test.status.preparing_backend_secondary", defaultValue: "Preparing %@...", bundle: .module, comment: "Secondary status text while preparing selected backend for dictation test"), "\(selectedBackend.label)"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    Text(String(localized: "onboarding.dictation_test.disabled_until_warmup", defaultValue: "The dictation test is disabled until download and warmup complete.", bundle: .module, comment: "Message indicating dictation test is disabled until model is ready"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .multilineTextAlignment(.center)

                    if let modelDownloadError {
                        Text(modelDownloadError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)

                        Button(String(localized: "onboarding.dictation_test.retry_download", defaultValue: "Retry Download", bundle: .module, comment: "Button title to retry model download during dictation test setup")) {
                            self.modelDownloadError = nil
                            self.modelDownloadSnapshot = nil
                            ensureModelDownloadStarted()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                    }
                }
            } else {
                VStack(spacing: MuesliTheme.spacing16) {
                    Text(dictationTestResult ?? String(localized: "onboarding.dictation_test.placeholder.transcription_output", defaultValue: "Your transcription will appear here...", bundle: .module, comment: "Placeholder text where dictation output appears"))
                        .font(dictationTestResult != nil ? .system(size: 14, design: .monospaced) : .system(size: 13, design: .rounded))
                        .foregroundStyle(dictationTestResult != nil ? MuesliTheme.textPrimary : MuesliTheme.textTertiary)
                        .italic(dictationTestResult == nil)
                        .frame(maxWidth: 400, minHeight: 60, alignment: .topLeading)
                        .padding(MuesliTheme.spacing16)
                        .background(MuesliTheme.backgroundRaised)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                                .strokeBorder(dictationTestResult != nil ? MuesliTheme.success.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: 1)
                        )

                    if isDictationTesting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(format: String(localized: "onboarding.dictation_test.status.listening_release_hotkey", defaultValue: "Listening... release %@ when done", bundle: .module, comment: "Status text while listening, instructing release of selected hotkey"), "\(selectedHotkey.label)"))
                                .font(MuesliTheme.caption())
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }
                    } else if dictationTestResult == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14))
                            Text(String(format: String(localized: "onboarding.dictation_test.status.hold_hotkey_to_start", defaultValue: "Hold %@ to start", bundle: .module, comment: "Status text instructing user to hold selected hotkey to start"), "\(selectedHotkey.label)"))
                                .font(MuesliTheme.body())
                        }
                        .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    if let dictationTestError {
                        Text(dictationTestError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    if dictationTestResult != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MuesliTheme.success)
                            Text(String(localized: "onboarding.dictation_test.success", defaultValue: "Dictation is working!", bundle: .module, comment: "Success message when dictation test works"))
                                .font(MuesliTheme.body())
                                .foregroundStyle(MuesliTheme.success)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            ensureModelDownloadStarted()
            controller.dictationTestBackend = selectedBackend
            controller.dictationTestCohereLanguage = selectedCohereLanguage
            controller.dictationTestRecordingStarted = {
                withAnimation { isDictationTesting = true }
                dictationTestError = nil
            }
            controller.dictationTestCallback = { text in
                if text.isEmpty {
                    dictationTestError = String(localized: "onboarding.dictation_test.no_speech_detected", defaultValue: "No speech detected. Try again.", bundle: .module, comment: "Error message when no speech is detected during dictation test")
                } else {
                    withAnimation { dictationTestResult = text }
                    advanceAfterSuccessfulDictationTest(text: text)
                }
                isDictationTesting = false
            }
            controller.dictationTestFailureCallback = { message in
                dictationTestError = message
                isDictationTesting = false
            }
            startDictationTestMonitorIfReady()
        }
        .onDisappear {
            // Cancel any in-flight recording before clearing callbacks to prevent
            // the transcription Task from falling through to the production paste path
            controller.cancelTestDictation()
            controller.dictationTestCallback = nil
            controller.dictationTestFailureCallback = nil
            controller.dictationTestRecordingStarted = nil
            controller.dictationTestBackend = nil
            controller.dictationTestCohereLanguage = nil
            // Stop the test monitor while moving through onboarding, but leave the
            // production monitor running when finishing from the dictation test.
            if !hasFinishedOnboarding {
                controller.stopHotkeyMonitor()
            }
            isDictationTestMonitorActive = false
        }
    }

    // MARK: - Step 6: Meeting Summaries

    private var meetingSummaryStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.meeting_summary.title", defaultValue: "Meeting Summaries", bundle: .module, comment: "Title for onboarding meeting summaries step"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(String(localized: "onboarding.meeting_summary.connect_llm_description", defaultValue: "Connect an LLM provider to get AI-powered meeting notes.\nYou can set this up later in Settings.", bundle: .module, comment: "Description for connecting LLM provider in meeting summaries onboarding step"))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 0) {
                providerTab(String(localized: "onboarding.meeting_summary.provider.chatgpt", defaultValue: "ChatGPT", bundle: .module, comment: "Provider option title for ChatGPT in meeting summaries onboarding"), selected: summaryBackend == .chatGPT) {
                    summaryBackend = .chatGPT
                    apiKey = ""
                }
                providerTab(String(localized: "onboarding.meeting_summary.provider.openai", defaultValue: "OpenAI", bundle: .module, comment: "Provider option title for OpenAI in meeting summaries onboarding"), selected: summaryBackend == .openAI) {
                    summaryBackend = .openAI
                    apiKey = ""
                }
                providerTab(String(localized: "onboarding.meeting_summary.provider.openrouter", defaultValue: "OpenRouter", bundle: .module, comment: "Provider option title for OpenRouter in meeting summaries onboarding"), selected: summaryBackend == .openRouter) {
                    summaryBackend = .openRouter
                    apiKey = ""
                }
                providerTab(String(localized: "onboarding.meeting_summary.provider.ollama", defaultValue: "Ollama", bundle: .module, comment: "Provider option title for Ollama in meeting summaries onboarding"), selected: summaryBackend == .ollama) {
                    summaryBackend = .ollama
                    apiKey = ""
                }
            }
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(width: 320)

            if summaryBackend == .chatGPT {
                Text(String(localized: "onboarding.meeting_summary.chatgpt_subscription_note", defaultValue: "Use your ChatGPT Plus or Pro subscription.", bundle: .module, comment: "Note about ChatGPT subscription requirement in meeting summaries onboarding"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)

                if appState.isChatGPTAuthenticated || chatGPTSignInDone {
                    HStack(spacing: 6) {
                        OpenAILogoShape()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                        Text(String(localized: "onboarding.meeting_summary.chatgpt_signed_in", defaultValue: "Signed in with ChatGPT", bundle: .module, comment: "Status text when user is signed in with ChatGPT during onboarding"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MuesliTheme.success)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isSigningInChatGPT {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "onboarding.meeting_summary.signing_in", defaultValue: "Signing in...", bundle: .module, comment: "Status text while signing in to ChatGPT during onboarding"))
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                } else {
                    Button {
                        isSigningInChatGPT = true
                        chatGPTSignInError = nil
                        Task {
                            let error = await controller.signInWithChatGPT()
                            isSigningInChatGPT = false
                            chatGPTSignInDone = ChatGPTAuthManager.shared.isAuthenticated
                            chatGPTSignInError = error
                        }
                    } label: {
                        HStack(spacing: 6) {
                            OpenAILogoShape()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                            Text(String(localized: "onboarding.meeting_summary.sign_in_chatgpt", defaultValue: "Sign in with ChatGPT", bundle: .module, comment: "Button title to sign in with ChatGPT during onboarding"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)

                    if let chatGPTSignInError {
                        Text(chatGPTSignInError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            } else if summaryBackend == .ollama {
                Text(String(localized: "onboarding.meeting_summary.ollama_description", defaultValue: "Run AI models locally on your device with Ollama.\nNo API key needed — just install Ollama and pull a model.", bundle: .module, comment: "Description for Ollama option in onboarding meeting summaries step"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Text(String(localized: "onboarding.meeting_summary.ollama_default_url", defaultValue: "Ollama is served by default at http://localhost:11434", bundle: .module, comment: "Hint text showing default Ollama server URL"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(MuesliTheme.success)
                            .frame(width: 6, height: 6)
                        Text(String(localized: "onboarding.meeting_summary.no_auth_required", defaultValue: "No authentication required", bundle: .module, comment: "Hint text indicating no authentication is required"))
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.success)
                    }
                }
            } else {
                if summaryBackend == .openRouter {
                    Text(String(localized: "onboarding.meeting_summary.openrouter_description", defaultValue: "OpenRouter supports many model providers through one API key.", bundle: .module, comment: "Description for OpenRouter option in onboarding meeting summaries step"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    Text(String(localized: "onboarding.meeting_summary.api_key_label", defaultValue: "API Key", bundle: .module, comment: "Label for API key field in onboarding meeting summaries step"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)

                    PastableSecureField(
                        text: apiKey,
                        placeholder: summaryBackend == .openAI ? "sk-..." : "sk-or-...",
                        onChange: { apiKey = $0 }
                    )
                    .frame(width: 320, height: 28)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(apiKey.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                            .frame(width: 6, height: 6)
                        Text(apiKey.isEmpty ? String(localized: "onboarding.meeting_summary.no_api_key", defaultValue: "No API key", bundle: .module, comment: "Status text when no API key is entered") : String(localized: "onboarding.meeting_summary.key_entered", defaultValue: "Key entered", bundle: .module, comment: "Status text when API key is entered"))
                            .font(.system(size: 11))
                            .foregroundStyle(apiKey.isEmpty ? MuesliTheme.textTertiary : MuesliTheme.success)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func providerTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .frame(width: 80)
                .padding(.vertical, MuesliTheme.spacing8)
                .background(selected ? MuesliTheme.surfacePrimary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startDownload() {
        ensureModelDownloadStarted()
        goToNextStep()
    }

    private func startDictationTestMonitorIfReady() {
        let action = OnboardingFlow.dictationTestMonitorAction(
            currentStep: currentStep,
            dictationTestStep: Self.dictationTestStep,
            modelReady: isSelectedModelReadyForDictationTest,
            monitorActive: isDictationTestMonitorActive,
            dictationTesting: isDictationTesting
        )

        switch action {
        case .none:
            return
        case .stop(let cancelTestDictation):
            if cancelTestDictation {
                controller.cancelTestDictation()
                isDictationTesting = false
            }
            controller.stopHotkeyMonitor()
            isDictationTestMonitorActive = false
            return
        case .start:
            dictationTestError = nil
            controller.dictationTestBackend = selectedBackend
            controller.dictationTestCohereLanguage = selectedCohereLanguage
            controller.startHotkeyMonitor(keyCode: selectedHotkey.keyCode)
            isDictationTestMonitorActive = true
        }
    }

    private func advanceAfterSuccessfulDictationTest(text: String) {
        guard selectedUseCase.includesMeetings else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard currentStep == Self.dictationTestStep, dictationTestResult == text else { return }
            goToNextStep()
        }
    }

    private func ensureModelDownloadStarted() {
        if modelReadyBackend == selectedBackend {
            isModelStillDownloading = false
            modelDownloadProgress = 1.0
            isModelPreparingAfterDownload = false
            modelDownloadStatus = String(format: String(localized: "onboarding.model_preparation.selected_backend_ready.primary", defaultValue: "%@ ready", bundle: .module, comment: "Primary onboarding model preparation status when selected backend is ready"), "\(selectedBackend.label)")
            modelDownloadError = nil
            publishModelPreparationStatus(
                title: String(format: String(localized: "onboarding.model_preparation.selected_backend_ready.secondary", defaultValue: "%@ ready", bundle: .module, comment: "Secondary onboarding model preparation status when selected backend is ready"), "\(selectedBackend.label)"),
                detail: String(localized: "onboarding.model_preparation.ready_for_transcription.secondary", defaultValue: "Ready for transcription", bundle: .module, comment: "Secondary onboarding status indicating model is ready for transcription"),
                progress: 1.0,
                isPreparing: false,
                isComplete: true
            )
            return
        }

        if modelDownloadTask != nil {
            guard modelDownloadBackend != selectedBackend else {
                isModelStillDownloading = true
                return
            }
            cancelModelDownload(for: modelDownloadBackend)
            modelDownloadGeneration = UUID()
            modelDownloadTask?.cancel()
            modelDownloadTask = nil
            modelDownloadBackend = nil
        }

        let backend = selectedBackend
        let useCase = selectedUseCase
        let generation = UUID()
        let alreadyDownloaded = backend.isDownloaded
        modelDownloadGeneration = generation
        modelDownloadBackend = backend
        isModelStillDownloading = true
        modelDownloadProgress = alreadyDownloaded ? nil : (modelDownloadProgress ?? 0.02)
        isModelPreparingAfterDownload = alreadyDownloaded
        modelDownloadStatus = alreadyDownloaded
            ? String(format: String(localized: "onboarding.model_preparation.warming_up", defaultValue: "Warming up %@...", bundle: .module, comment: "Onboarding model preparation status while warming up backend"), "\(backend.label)")
            : (modelDownloadStatus ?? initialDownloadStatus(for: backend))
        modelDownloadError = nil
        modelDownloadSnapshot = nil
        publishModelPreparationStatus(
            title: String(format: String(localized: "onboarding.model_preparation.preparing_backend", defaultValue: "Preparing %@", bundle: .module, comment: "Onboarding model preparation status while preparing backend"), "\(backend.label)"),
            detail: modelDownloadStatus,
            progress: modelDownloadProgress,
            isPreparing: isModelPreparingAfterDownload,
            isComplete: false
        )

        modelDownloadTask = Task {
            defer {
                Task { @MainActor in
                    if modelDownloadGeneration == generation, modelDownloadBackend == backend {
                        modelDownloadTask = nil
                        modelDownloadBackend = nil
                    }
                }
            }
            do {
                try await controller.downloadModelForOnboarding(backend, onboardingUseCase: useCase) { progress, status in
                    Task { @MainActor in
                        guard modelDownloadGeneration == generation,
                              modelDownloadBackend == backend,
                              selectedBackend == backend else { return }
                        applyModelPreparationProgress(progress, status: status, backend: backend, generation: generation)
                    }
                } progressSnapshot: { snapshot in
                    Task { @MainActor in
                        guard modelDownloadGeneration == generation,
                              modelDownloadBackend == backend,
                              selectedBackend == backend else { return }
                        applyModelDownloadSnapshot(snapshot, backend: backend, generation: generation)
                    }
                }
                await MainActor.run {
                    guard modelDownloadGeneration == generation,
                          modelDownloadBackend == backend,
                          selectedBackend == backend else { return }
                    modelReadyBackend = backend
                    modelDownloadProgress = 1.0
                    modelDownloadSnapshot = nil
                    isModelPreparingAfterDownload = false
                    modelDownloadStatus = String(format: String(localized: "onboarding.model_preparation.backend_ready.primary", defaultValue: "%@ ready", bundle: .module, comment: "Primary onboarding model preparation status when backend is ready"), "\(backend.label)")
                    modelDownloadError = nil
                    withAnimation { isModelStillDownloading = false }
                    publishModelPreparationStatus(
                        title: String(format: String(localized: "onboarding.model_preparation.backend_ready.secondary", defaultValue: "%@ ready", bundle: .module, comment: "Secondary onboarding model preparation status when backend is ready"), "\(backend.label)"),
                        detail: String(localized: "onboarding.model_preparation.ready_for_transcription.primary", defaultValue: "Ready for transcription", bundle: .module, comment: "Primary onboarding status indicating model is ready for transcription"),
                        progress: 1.0,
                        isPreparing: false,
                        isComplete: true
                    )
                    showModelReadyIndicator(for: backend)
                    controller.notifyOnboardingModelReady()
                    saveProgress(atStep: currentStep)
                }
            } catch is CancellationError {
                // Backend changes cancel the old task; the new selection owns the download UI.
            } catch {
                await MainActor.run {
                    guard modelDownloadGeneration == generation,
                          modelDownloadBackend == backend,
                          selectedBackend == backend else { return }
                    modelDownloadError = modelPreparationFailureMessage(for: backend)
                    modelDownloadStatus = backend.isDownloaded ? String(localized: "onboarding.model_preparation.paused.model_setup", defaultValue: "Model setup paused", bundle: .module, comment: "Onboarding status text when model setup is paused") : String(localized: "onboarding.model_preparation.paused.download", defaultValue: "Download paused", bundle: .module, comment: "Onboarding status text when model download is paused")
                    modelDownloadProgress = nil
                    if let snapshot = modelDownloadSnapshot {
                        modelDownloadSnapshot = snapshot.replacing(
                            phase: .failed,
                            message: modelDownloadError
                        )
                    }
                    isModelPreparingAfterDownload = false
                    isModelStillDownloading = false
                    publishModelPreparationStatus(
                        title: backend.isDownloaded ? String(localized: "onboarding.model_preparation.paused.model_setup.secondary", defaultValue: "Model setup paused", bundle: .module, comment: "Secondary paused state when model setup is paused") : String(localized: "onboarding.model_preparation.paused.download.secondary", defaultValue: "Download paused", bundle: .module, comment: "Secondary paused state when download is paused"),
                        detail: modelDownloadError,
                        progress: nil,
                        isPreparing: false,
                        isComplete: false
                    )
                }
                fputs("[muesli-native] onboarding model download failed: \(error)\n", stderr)
            }
        }
    }

    private func applyModelDownloadSnapshot(
        _ snapshot: ModelDownloadProgress,
        backend: BackendOption,
        generation: UUID
    ) {
        guard modelDownloadGeneration == generation,
              modelDownloadBackend == backend,
              selectedBackend == backend else { return }
        modelDownloadSnapshot = snapshot
        modelDownloadError = nil

        switch snapshot.phase {
        case .downloading:
            isModelStillDownloading = true
            isModelPreparingAfterDownload = false
            if let fraction = snapshot.fractionCompleted {
                modelDownloadProgress = max(modelDownloadProgress ?? 0.02, fraction)
            }
            modelDownloadStatus = modelDownloadSnapshotDetail(snapshot)
        case .preparing:
            isModelStillDownloading = true
            isModelPreparingAfterDownload = true
            modelDownloadProgress = nil
            modelDownloadStatus = snapshot.message ?? String(format: String(localized: "onboarding.model_preparation.progress.preparing_backend.ellipsis", defaultValue: "Preparing %@...", bundle: .module, comment: "Progress text while preparing backend with ellipsis"), "\(backend.label)")
        case .ready:
            modelDownloadStatus = snapshot.message ?? String(format: String(localized: "onboarding.model_preparation.progress.backend_ready", defaultValue: "%@ ready", bundle: .module, comment: "Progress text when backend is ready"), "\(backend.label)")
        case .paused:
            isModelStillDownloading = false
            isModelPreparingAfterDownload = false
            modelDownloadStatus = snapshot.message ?? String(localized: "onboarding.model_download.paused.progress", defaultValue: "Download paused", bundle: .module, comment: "Model download progress state paused")
        case .failed:
            isModelStillDownloading = false
            isModelPreparingAfterDownload = false
            modelDownloadError = snapshot.message
            modelDownloadStatus = snapshot.message ?? String(localized: "onboarding.model_download.failed", defaultValue: "Download failed", bundle: .module, comment: "Model download failure state")
        }

        publishModelPreparationStatus(
            title: modelDownloadIndicatorTitle,
            detail: modelDownloadStatus,
            progress: modelDownloadProgress,
            isPreparing: isModelPreparingAfterDownload,
            isComplete: snapshot.phase == .ready
        )
    }

    private func applyModelPreparationProgress(
        _ progress: Double,
        status: String?,
        backend: BackendOption,
        generation: UUID
    ) {
        guard modelDownloadGeneration == generation,
              modelDownloadBackend == backend,
              selectedBackend == backend else { return }
        let detail = status ?? String(format: String(localized: "onboarding.model_preparation.status.preparing_backend.ellipsis", defaultValue: "Preparing %@...", bundle: .module, comment: "Model preparation status with backend label and ellipsis"), "\(backend.label)")
        let lowercasedDetail = detail.lowercased()
        let isPreparing = lowercasedDetail.contains("compiling")
            || lowercasedDetail.contains("warming")
            || lowercasedDetail.contains("readying")

        modelDownloadError = nil
        isModelStillDownloading = true

        if isPreparing {
            isModelPreparingAfterDownload = true
            modelDownloadStatus = String(format: String(localized: "onboarding.model_preparation.optimizing_for_mac", defaultValue: "Optimizing %@ for this Mac...", bundle: .module, comment: "Status while optimizing backend for local Mac"), "\(backend.label)")
            publishModelPreparationStatus(
                title: String(format: String(localized: "onboarding.model_preparation.status.preparing_backend", defaultValue: "Preparing %@", bundle: .module, comment: "Status while preparing backend without ellipsis"), "\(backend.label)"),
                detail: modelDownloadStatus,
                progress: nil,
                isPreparing: true,
                isComplete: false
            )
            saveProgress(atStep: currentStep)
            return
        }

        isModelPreparingAfterDownload = false
        let clampedProgress = min(max(progress, 0), 1)
        let currentProgress = modelDownloadProgress ?? 0
        let isZeroReset = clampedProgress <= 0.001 && currentProgress > 0.03

        guard !isZeroReset else { return }
        modelDownloadProgress = max(currentProgress, max(clampedProgress, 0.02))
        modelDownloadStatus = detail
        publishModelPreparationStatus(
            title: String(format: String(localized: "onboarding.model_preparation.detail.preparing_backend", defaultValue: "Preparing %@", bundle: .module, comment: "Detail text while preparing backend"), "\(backend.label)"),
            detail: detail,
            progress: modelDownloadProgress,
            isPreparing: false,
            isComplete: false
        )
        saveProgress(atStep: currentStep)
    }

    private func resetModelDownloadForBackendChange() {
        cancelModelDownload(for: modelDownloadBackend)
        modelDownloadGeneration = UUID()
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        modelReadyIndicatorTask?.cancel()
        modelReadyIndicatorTask = nil
        modelReadyBackend = nil
        modelReadyIndicatorBackend = nil
        modelDownloadBackend = nil
        modelDownloadProgress = nil
        modelDownloadSnapshot = nil
        isModelPreparingAfterDownload = false
        modelDownloadStatus = nil
        modelDownloadError = nil
        isModelStillDownloading = false
    }

    private func cancelModelDownload(for backend: BackendOption?) {
        guard let backend else { return }
        Task {
            await ManagedASRModelDownloader.cancel(modelID: backend.model)
        }
    }

    private func initialDownloadStatus(for backend: BackendOption) -> String {
        let size = backend.sizeLabel
            .replacingOccurrences(of: "~", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !size.isEmpty {
            return String(format: String(localized: "onboarding.model_download.initial_status", defaultValue: "0 MB of %@", bundle: .module, comment: "Initial download status showing total size"), "\(size)")
        }
        return String(format: String(localized: "onboarding.model_download.starting_download", defaultValue: "Starting %@ download...", bundle: .module, comment: "Status when backend download starts"), "\(backend.label)")
    }

    private func modelPreparationFailureMessage(for backend: BackendOption) -> String {
        backend.isDownloaded
            ? String(localized: "onboarding.model_preparation.failure_setup", defaultValue: "Model setup failed. Restart Muesli or retry from Models.", bundle: .module, comment: "Model setup failure guidance message")
            : String(localized: "onboarding.model_download.failure_check_connection", defaultValue: "Download failed. Check your connection and retry.", bundle: .module, comment: "Download failure guidance to check connection")
    }

    private func publishModelPreparationStatus(
        title: String,
        detail: String?,
        progress: Double?,
        isPreparing: Bool,
        isComplete: Bool
    ) {
        appState.modelPreparationTitle = title
        appState.modelPreparationDetail = detail
        appState.modelPreparationProgress = progress.map { min(max($0, 0), 1) }
        appState.isModelPreparingAfterDownload = isPreparing
        appState.modelPreparationIsComplete = isComplete
        if isComplete {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard appState.modelPreparationTitle == title,
                      appState.modelPreparationIsComplete else { return }
                appState.modelPreparationTitle = nil
                appState.modelPreparationDetail = nil
                appState.modelPreparationProgress = nil
                appState.isModelPreparingAfterDownload = false
                appState.modelPreparationIsComplete = false
            }
        } else if !isPreparing && progress == nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                guard appState.modelPreparationTitle == title,
                      appState.modelPreparationProgress == nil,
                      !appState.isModelPreparingAfterDownload,
                      !appState.modelPreparationIsComplete else { return }
                appState.modelPreparationTitle = nil
                appState.modelPreparationDetail = nil
            }
        }
    }

    private func showModelReadyIndicator(for backend: BackendOption) {
        modelReadyIndicatorTask?.cancel()
        modelReadyIndicatorBackend = backend
        modelReadyIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard modelReadyIndicatorBackend == backend else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                modelReadyIndicatorBackend = nil
            }
            modelReadyIndicatorTask = nil
        }
    }

    private var googleCalendarStep: some View {
        VStack(spacing: MuesliTheme.spacing24) {
            Spacer()

            VStack(spacing: MuesliTheme.spacing8) {
                Text(String(localized: "onboarding.google_calendar.title", defaultValue: "Google Calendar", bundle: .module, comment: "Google Calendar onboarding section title"))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)

                Text(String(localized: "onboarding.google_calendar.connect_description", defaultValue: "Connect Google Calendar to see upcoming meetings.\nYou can set this up later in Settings.", bundle: .module, comment: "Description for connecting Google Calendar during onboarding"))
                    .font(MuesliTheme.body())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: MuesliTheme.spacing12) {
                if googleCalSignInDone {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MuesliTheme.success)
                        Text(String(localized: "onboarding.google_calendar.connected", defaultValue: "Google Calendar connected", bundle: .module, comment: "State label when Google Calendar is connected"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                } else if isSigningInGoogleCal {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "onboarding.google_calendar.connecting", defaultValue: "Connecting...", bundle: .module, comment: "State label while connecting Google Calendar"))
                            .font(MuesliTheme.body())
                            .foregroundStyle(MuesliTheme.textSecondary)
                    }
                } else if appState.isGoogleCalendarAvailable && !appState.isGoogleCalendarVerified {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 14))
                            Text(String(localized: "onboarding.google_calendar.connect_action", defaultValue: "Connect Google Calendar", bundle: .module, comment: "Action button to start Google Calendar connection"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, MuesliTheme.spacing16)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.textTertiary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))

                        Text(String(localized: "onboarding.google_calendar.oauth_verification_pending", defaultValue: "Google OAuth verification pending", bundle: .module, comment: "Info message when Google OAuth app verification is pending"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                } else if appState.isGoogleCalendarAvailable {
                    Button {
                        isSigningInGoogleCal = true
                        googleCalSignInError = nil
                        Task {
                            let error = await controller.signInWithGoogleCalendar()
                            isSigningInGoogleCal = false
                            if let error {
                                googleCalSignInError = error
                            } else {
                                googleCalSignInDone = true
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 14))
                            Text(String(localized: "onboarding.google_calendar.connect_action.secondary", defaultValue: "Connect Google Calendar", bundle: .module, comment: "Secondary action button to connect Google Calendar"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, MuesliTheme.spacing16)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }
                    .buttonStyle(.plain)

                    if let googleCalSignInError {
                        Text(googleCalSignInError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text(String(localized: "onboarding.google_calendar.credentials_not_configured", defaultValue: "Google Calendar credentials not configured.", bundle: .module, comment: "Message shown when Google Calendar credentials are missing"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, MuesliTheme.spacing32)
    }

    private func finishOnboarding(withKey: Bool) {
        hasFinishedOnboarding = true
        OnboardingProgress.clear()
        let shouldContinueModelPreparation = modelDownloadTask != nil && modelReadyBackend != selectedBackend
        if shouldContinueModelPreparation {
            modelDownloadGeneration = UUID()
            modelDownloadTask?.cancel()
            modelDownloadTask = nil
            modelDownloadBackend = nil
            controller.continueModelPreparationAfterOnboarding(
                selectedBackend,
                onboardingUseCase: selectedUseCase,
                initialProgress: modelDownloadProgress,
                initialStatus: modelDownloadStatus,
                isPreparing: isModelPreparingAfterDownload
            )
        } else if isModelStillDownloading || modelReadyBackend == selectedBackend {
            publishModelPreparationStatus(
                title: modelReadyBackend == selectedBackend ? String(format: String(localized: "onboarding.model_preparation.ready", defaultValue: "%@ ready", bundle: .module, comment: "Model preparation state when selected backend is ready"), "\(selectedBackend.label)") : String(format: String(localized: "onboarding.model_preparation.preparing", defaultValue: "Preparing %@", bundle: .module, comment: "Model preparation state while preparing selected backend"), "\(selectedBackend.label)"),
                detail: modelReadyBackend == selectedBackend ? String(localized: "onboarding.model_preparation.ready_for_transcription", defaultValue: "Ready for transcription", bundle: .module, comment: "Model preparation state when transcription is ready") : modelDownloadStatus,
                progress: modelReadyBackend == selectedBackend ? 1.0 : modelDownloadProgress,
                isPreparing: isModelPreparingAfterDownload,
                isComplete: modelReadyBackend == selectedBackend
            )
        }
        controller.completeOnboarding(
            userName: userName.trimmingCharacters(in: .whitespaces),
            backend: selectedBackend,
            cohereLanguage: selectedCohereLanguage,
            hotkey: selectedHotkey,
            onboardingUseCase: selectedUseCase,
            summaryBackend: summaryBackend,
            apiKey: withKey ? apiKey : nil
        )
    }
}

private struct ModelDownloadProgressShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        guard clampedProgress > 0 else { return path }
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + (360 * clampedProgress)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct IndeterminatePreparationBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let segmentWidth = max(trackWidth * 0.32, 64)
            let travel = max(trackWidth - segmentWidth, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MuesliTheme.surfaceBorder)

                Capsule()
                    .fill(MuesliTheme.textSecondary.opacity(0.9))
                    .frame(width: segmentWidth)
                    .offset(x: isAnimating ? travel : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct RotatingPreparationHint: View {
    let messages: [String]
    @State private var index = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(messages.isEmpty ? "" : messages[index % messages.count])
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(MuesliTheme.textTertiary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .id(index)
            .transition(.opacity)
            .onReceive(timer) { _ in
                guard messages.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    index = (index + 1) % messages.count
                }
            }
            .onChange(of: messages) { _, _ in
                index = 0
            }
    }
}

// MARK: - Text Field

/// NSTextField subclass that handles Cmd+V/C/X/A without needing a standard Edit menu.
class EditableNSTextField: NSTextField {
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

struct OnboardingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> EditableNSTextField {
        let field = EditableNSTextField()
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 14)
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
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - OpenAI Logo

struct OpenAILogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        var p = Path()
        p.move(to: CGPoint(x: 22.2819 * sx, y: 9.8211 * sy))
        p.addCurve(to: CGPoint(x: 21.7662 * sx, y: 4.9103 * sy), control1: CGPoint(x: 22.8248 * sx, y: 8.1862 * sy), control2: CGPoint(x: 22.6369 * sx, y: 6.3967 * sy))
        p.addCurve(to: CGPoint(x: 15.2564 * sx, y: 2.0103 * sy), control1: CGPoint(x: 20.4571 * sx, y: 2.6316 * sy), control2: CGPoint(x: 17.8260 * sx, y: 1.4595 * sy))
        p.addCurve(to: CGPoint(x: 4.9807 * sx, y: 4.1818 * sy), control1: CGPoint(x: 12.1364 * sx, y: -1.4602 * sy), control2: CGPoint(x: 6.4298 * sx, y: -0.2543 * sy))
        p.addCurve(to: CGPoint(x: 0.9830 * sx, y: 7.0818 * sy), control1: CGPoint(x: 3.2928 * sx, y: 4.5279 * sy), control2: CGPoint(x: 1.8360 * sx, y: 5.5847 * sy))
        p.addCurve(to: CGPoint(x: 1.7257 * sx, y: 14.1784 * sy), control1: CGPoint(x: -0.3404 * sx, y: 9.3568 * sy), control2: CGPoint(x: -0.0401 * sx, y: 12.2267 * sy))
        p.addCurve(to: CGPoint(x: 2.2367 * sx, y: 19.0891 * sy), control1: CGPoint(x: 1.1808 * sx, y: 15.8125 * sy), control2: CGPoint(x: 1.3670 * sx, y: 17.6022 * sy))
        p.addCurve(to: CGPoint(x: 8.7513 * sx, y: 21.9892 * sy), control1: CGPoint(x: 3.5475 * sx, y: 21.3686 * sy), control2: CGPoint(x: 6.1803 * sx, y: 22.5406 * sy))
        p.addCurve(to: CGPoint(x: 13.2599 * sx, y: 24.0000 * sy), control1: CGPoint(x: 9.8948 * sx, y: 23.2770 * sy), control2: CGPoint(x: 11.5377 * sx, y: 24.0097 * sy))
        p.addCurve(to: CGPoint(x: 19.0317 * sx, y: 19.7942 * sy), control1: CGPoint(x: 15.8937 * sx, y: 24.0024 * sy), control2: CGPoint(x: 18.2271 * sx, y: 22.3021 * sy))
        p.addCurve(to: CGPoint(x: 23.0294 * sx, y: 16.8941 * sy), control1: CGPoint(x: 20.7194 * sx, y: 19.4475 * sy), control2: CGPoint(x: 22.1760 * sx, y: 18.3908 * sy))
        p.addCurve(to: CGPoint(x: 22.2819 * sx, y: 9.8212 * sy), control1: CGPoint(x: 24.3368 * sx, y: 14.6231 * sy), control2: CGPoint(x: 24.0351 * sx, y: 11.7688 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 13.2599 * sx, y: 22.4292 * sy))
        p.addCurve(to: CGPoint(x: 10.3835 * sx, y: 21.3884 * sy), control1: CGPoint(x: 12.2086 * sx, y: 22.4309 * sy), control2: CGPoint(x: 11.1903 * sx, y: 22.0624 * sy))
        p.addLine(to: CGPoint(x: 10.5254 * sx, y: 21.3080 * sy))
        p.addLine(to: CGPoint(x: 15.3037 * sx, y: 18.5498 * sy))
        p.addCurve(to: CGPoint(x: 15.6964 * sx, y: 17.8685 * sy), control1: CGPoint(x: 15.5456 * sx, y: 18.4079 * sy), control2: CGPoint(x: 15.6949 * sx, y: 18.1490 * sy))
        p.addLine(to: CGPoint(x: 15.6964 * sx, y: 11.1316 * sy))
        p.addLine(to: CGPoint(x: 17.7164 * sx, y: 12.3002 * sy))
        p.addCurve(to: CGPoint(x: 17.7544 * sx, y: 12.3522 * sy), control1: CGPoint(x: 17.7367 * sx, y: 12.3105 * sy), control2: CGPoint(x: 17.7508 * sx, y: 12.3298 * sy))
        p.addLine(to: CGPoint(x: 17.7544 * sx, y: 17.9348 * sy))
        p.addCurve(to: CGPoint(x: 13.2599 * sx, y: 22.4292 * sy), control1: CGPoint(x: 17.7491 * sx, y: 20.4148 * sy), control2: CGPoint(x: 15.7399 * sx, y: 22.4240 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 3.5992 * sx, y: 18.3038 * sy))
        p.addCurve(to: CGPoint(x: 3.0646 * sx, y: 15.2901 * sy), control1: CGPoint(x: 3.0720 * sx, y: 17.3934 * sy), control2: CGPoint(x: 2.8827 * sx, y: 16.3263 * sy))
        p.addLine(to: CGPoint(x: 3.2066 * sx, y: 15.3753 * sy))
        p.addLine(to: CGPoint(x: 7.9896 * sx, y: 18.1335 * sy))
        p.addCurve(to: CGPoint(x: 8.7702 * sx, y: 18.1335 * sy), control1: CGPoint(x: 8.2306 * sx, y: 18.2749 * sy), control2: CGPoint(x: 8.5292 * sx, y: 18.2749 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 14.7650 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 17.0974 * sy))
        p.addCurve(to: CGPoint(x: 14.5798 * sx, y: 17.1589 * sy), control1: CGPoint(x: 14.6119 * sx, y: 17.1219 * sy), control2: CGPoint(x: 14.5997 * sx, y: 17.1445 * sy))
        p.addLine(to: CGPoint(x: 9.7400 * sx, y: 19.9502 * sy))
        p.addCurve(to: CGPoint(x: 3.5992 * sx, y: 18.3038 * sy), control1: CGPoint(x: 7.5893 * sx, y: 21.1891 * sy), control2: CGPoint(x: 4.8416 * sx, y: 20.4525 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 2.3408 * sx, y: 7.8956 * sy))
        p.addCurve(to: CGPoint(x: 4.7063 * sx, y: 5.9228 * sy), control1: CGPoint(x: 2.8717 * sx, y: 6.9794 * sy), control2: CGPoint(x: 3.7096 * sx, y: 6.2805 * sy))
        p.addLine(to: CGPoint(x: 4.7063 * sx, y: 11.6000 * sy))
        p.addCurve(to: CGPoint(x: 5.0942 * sx, y: 12.2765 * sy), control1: CGPoint(x: 4.7026 * sx, y: 11.8793 * sy), control2: CGPoint(x: 4.8513 * sx, y: 12.1386 * sy))
        p.addLine(to: CGPoint(x: 10.9086 * sx, y: 15.6308 * sy))
        p.addLine(to: CGPoint(x: 8.8885 * sx, y: 16.7993 * sy))
        p.addCurve(to: CGPoint(x: 8.8175 * sx, y: 16.7993 * sy), control1: CGPoint(x: 8.8663 * sx, y: 16.8111 * sy), control2: CGPoint(x: 8.8397 * sx, y: 16.8111 * sy))
        p.addLine(to: CGPoint(x: 3.9872 * sx, y: 14.0128 * sy))
        p.addCurve(to: CGPoint(x: 2.3408 * sx, y: 7.8720 * sy), control1: CGPoint(x: 1.8408 * sx, y: 12.7686 * sy), control2: CGPoint(x: 1.1047 * sx, y: 10.0230 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 18.9371 * sx, y: 11.7514 * sy))
        p.addLine(to: CGPoint(x: 13.1038 * sx, y: 8.3640 * sy))
        p.addLine(to: CGPoint(x: 15.1192 * sx, y: 7.2000 * sy))
        p.addCurve(to: CGPoint(x: 15.1902 * sx, y: 7.2000 * sy), control1: CGPoint(x: 15.1414 * sx, y: 7.1882 * sy), control2: CGPoint(x: 15.1680 * sx, y: 7.1882 * sy))
        p.addLine(to: CGPoint(x: 20.0205 * sx, y: 9.9913 * sy))
        p.addCurve(to: CGPoint(x: 19.3440 * sx, y: 18.0955 * sy), control1: CGPoint(x: 23.3136 * sx, y: 11.8915 * sy), control2: CGPoint(x: 22.9065 * sx, y: 16.7676 * sy))
        p.addLine(to: CGPoint(x: 19.3440 * sx, y: 12.4183 * sy))
        p.addCurve(to: CGPoint(x: 18.9370 * sx, y: 11.7513 * sy), control1: CGPoint(x: 19.3355 * sx, y: 12.1397 * sy), control2: CGPoint(x: 19.1808 * sx, y: 11.8863 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 20.9478 * sx, y: 8.7283 * sy))
        p.addLine(to: CGPoint(x: 20.8058 * sx, y: 8.6431 * sy))
        p.addLine(to: CGPoint(x: 16.0323 * sx, y: 5.8613 * sy))
        p.addCurve(to: CGPoint(x: 15.2469 * sx, y: 5.8613 * sy), control1: CGPoint(x: 15.7898 * sx, y: 5.7190 * sy), control2: CGPoint(x: 15.4894 * sx, y: 5.7190 * sy))
        p.addLine(to: CGPoint(x: 9.4090 * sx, y: 9.2297 * sy))
        p.addLine(to: CGPoint(x: 9.4090 * sx, y: 6.8974 * sy))
        p.addCurve(to: CGPoint(x: 9.4374 * sx, y: 6.8359 * sy), control1: CGPoint(x: 9.4065 * sx, y: 6.8732 * sy), control2: CGPoint(x: 9.4174 * sx, y: 6.8496 * sy))
        p.addLine(to: CGPoint(x: 14.2677 * sx, y: 4.0493 * sy))
        p.addCurve(to: CGPoint(x: 20.9479 * sx, y: 8.7093 * sy), control1: CGPoint(x: 17.5693 * sx, y: 2.1473 * sy), control2: CGPoint(x: 21.5928 * sx, y: 4.9539 * sy))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.3065 * sx, y: 12.8630 * sy))
        p.addLine(to: CGPoint(x: 6.2865 * sx, y: 11.6992 * sy))
        p.addCurve(to: CGPoint(x: 6.2485 * sx, y: 11.6425 * sy), control1: CGPoint(x: 6.2660 * sx, y: 11.6869 * sy), control2: CGPoint(x: 6.2521 * sx, y: 11.6661 * sy))
        p.addLine(to: CGPoint(x: 6.2485 * sx, y: 6.0742 * sy))
        p.addCurve(to: CGPoint(x: 13.6242 * sx, y: 2.6205 * sy), control1: CGPoint(x: 6.2535 * sx, y: 2.2647 * sy), control2: CGPoint(x: 10.6950 * sx, y: 0.1849 * sy))
        p.addLine(to: CGPoint(x: 13.4822 * sx, y: 2.7010 * sy))
        p.addLine(to: CGPoint(x: 8.7040 * sx, y: 5.4590 * sy))
        p.addCurve(to: CGPoint(x: 8.3113 * sx, y: 6.1403 * sy), control1: CGPoint(x: 8.4621 * sx, y: 5.6009 * sy), control2: CGPoint(x: 8.3128 * sx, y: 5.8598 * sy))
        p.closeSubpath()
        // Inner hexagon
        p.move(to: CGPoint(x: 9.4041 * sx, y: 10.4976 * sy))
        p.addLine(to: CGPoint(x: 12.0061 * sx, y: 8.9978 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 10.4976 * sy))
        p.addLine(to: CGPoint(x: 14.6130 * sx, y: 13.4970 * sy))
        p.addLine(to: CGPoint(x: 12.0156 * sx, y: 14.9967 * sy))
        p.addLine(to: CGPoint(x: 9.4089 * sx, y: 13.4970 * sy))
        p.closeSubpath()
        return p
    }
}
