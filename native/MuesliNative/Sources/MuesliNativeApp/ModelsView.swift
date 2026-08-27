import FluidAudio
import MuesliCore
import SwiftUI

struct ModelDownloadGenerationState: Equatable {
    private(set) var current: UUID?

    mutating func begin() -> UUID {
        let generation = UUID()
        current = generation
        return generation
    }

    func contains(_ generation: UUID) -> Bool {
        current == generation
    }

    @discardableResult
    mutating func clear(_ generation: UUID) -> Bool {
        guard current == generation else { return false }
        current = nil
        return true
    }
}

struct ModelsView: View {
    let appState: AppState
    let controller: MuesliController

    @State private var nemotron35UpdateAvailable = false
    @State private var downloadingModels: Set<String> = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var downloadMessages: [String: String] = [:]
    @State private var downloadSnapshots: [String: ModelDownloadProgress] = [:]
    @State private var downloadGenerations: [String: UUID] = [:]
    @State private var downloadedModels: Set<String> = []
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]
    @State private var modelToDelete: BackendOption?
    @State private var selectedParakeetModel: String
    @State private var selectedWhisperModel: String
    @State private var showExperimental: Bool
    @State private var appleSpeechLanguageOptions: [AppleSpeechLanguageOption] = [.system]
    @State private var isLiveCaptionModelDownloaded = false
    @State private var isDownloadingLiveCaptionModel = false
    @State private var isCancellingLiveCaptionModelDownload = false
    @State private var liveCaptionDownloadProgress = 0.0
    @State private var liveCaptionDownloadTask: Task<Void, Never>?
    @State private var liveCaptionDownloadGeneration = ModelDownloadGenerationState()
    @State private var showDeleteLiveCaptionModelConfirmation = false

    // Post-processor state
    @State private var downloadingPostProcModels: Set<String> = []
    @State private var downloadProgressPostProc: [String: Double] = [:]
    @State private var downloadedPostProcModels: Set<String> = []
    @State private var downloadTasksPostProc: [String: Task<Void, Never>] = [:]
    @State private var postProcModelToDelete: PostProcessorOption?

    init(appState: AppState, controller: MuesliController) {
        self.appState = appState
        self.controller = controller

        let active = appState.selectedBackend
        _selectedParakeetModel = State(initialValue: BackendOption.parakeetFamily.contains(active) ? active.model : BackendOption.parakeetMultilingual.model)
        _selectedWhisperModel = State(initialValue: BackendOption.whisperFamily.contains(active) ? active.model : BackendOption.whisperSmall.model)
        _showExperimental = State(initialValue: appState.activeFeatureTourTarget == .experimentalModels)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                    Text(String(localized: "models.title", defaultValue: "Models", bundle: .module, comment: "Title for models settings view"))
                        .font(MuesliTheme.title1())
                        .foregroundStyle(MuesliTheme.textPrimary)

                    Text(String(localized: "models.subtitle.description", defaultValue: "Choose the transcription and cleanup models that fit how you speak and work.", bundle: .module, comment: "Subtitle describing models configuration purpose"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textSecondary)

                    Picker(String(localized: "models.picker.category_label", defaultValue: "Model category", bundle: .module, comment: "Label for model category picker"), selection: modelsCategorySelection) {
                        ForEach(ModelsCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                    .id(FeatureTourTarget.modelLibrary.rawValue)
                    .featureTourTarget(.modelLibrary)

                    selectedCategoryContent
                }
                .padding(MuesliTheme.spacing32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                revealFeatureTourTargetIfNeeded(using: proxy)
            }
            .onChange(of: activeFeatureTourTarget) { _, target in
                guard target == .modelLibrary
                        || target == .appleSpeechCard
                        || target == .streamingModels
                        || target == .experimentalModels else { return }
                revealFeatureTourTargetIfNeeded(using: proxy)
            }
        }
        .background(MuesliTheme.backgroundBase)
        .onAppear {
            checkDownloadedModels()
            checkDownloadedPostProcModels()
            isLiveCaptionModelDownloaded = MeetingLiveCaptionModelStore.isDownloaded()
            syncSelectionsFromActiveBackend()
            checkNemotron35Update()
            loadAppleSpeechLanguageOptions()
        }
        .onChange(of: appState.selectedBackend.model) { _, _ in
            syncSelectionsFromActiveBackend()
        }
        .alert(
            String(format: String(localized: "models.alert.delete_transcription_model_title", defaultValue: "Delete \"%@\"?", bundle: .module, comment: "Confirmation alert title for deleting a transcription model"), "\(modelToDelete?.label ?? "")"),
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )
        ) {
            Button(String(localized: "models.alert.cancel.delete_transcription_model", defaultValue: "Cancel", bundle: .module, comment: "Cancel action for delete transcription model alert"), role: .cancel) {
                modelToDelete = nil
            }
            Button(String(localized: "models.alert.delete_action.transcription_model", defaultValue: "Delete", bundle: .module, comment: "Delete action for transcription model deletion alert"), role: .destructive) {
                guard let option = modelToDelete else { return }
                deleteModel(option)
                modelToDelete = nil
            }
        } message: {
            Text(String(localized: "models.alert.delete_model_message.transcription", defaultValue: "The downloaded model files will be removed from this Mac. You can download the model again later.", bundle: .module, comment: "Warning message shown before deleting downloaded transcription model files"))
        }
        .alert(
            String(format: String(localized: "models.alert.delete_cleanup_model_title", defaultValue: "Delete \"%@\"?", bundle: .module, comment: "Confirmation alert title for deleting a cleanup model"), "\(postProcModelToDelete?.label ?? "")"),
            isPresented: Binding(
                get: { postProcModelToDelete != nil },
                set: { if !$0 { postProcModelToDelete = nil } }
            )
        ) {
            Button(String(localized: "models.alert.cancel.delete_cleanup_model", defaultValue: "Cancel", bundle: .module, comment: "Cancel action for delete cleanup model alert"), role: .cancel) {
                postProcModelToDelete = nil
            }
            Button(String(localized: "models.alert.delete_action.cleanup_model", defaultValue: "Delete", bundle: .module, comment: "Delete action for cleanup model deletion alert"), role: .destructive) {
                guard let option = postProcModelToDelete else { return }
                deletePostProcModel(option)
                postProcModelToDelete = nil
            }
        } message: {
            Text(String(localized: "models.alert.delete_model_message.cleanup", defaultValue: "The downloaded model files will be removed from this Mac. You can download the model again later.", bundle: .module, comment: "Warning message shown before deleting downloaded cleanup model files"))
        }
        .alert(
            String(format: String(localized: "models.alert.delete_live_meeting_model_title", defaultValue: "Delete \"%@\"?", bundle: .module, comment: "Confirmation alert title for deleting live meetings model"), "\(MeetingLiveCaptionModelStore.label)"),
            isPresented: $showDeleteLiveCaptionModelConfirmation
        ) {
            Button(String(localized: "models.alert.cancel.delete_live_meeting_model", defaultValue: "Cancel", bundle: .module, comment: "Cancel action for delete live meetings model alert"), role: .cancel) {}
            Button(String(localized: "models.alert.delete_action.live_meeting_model", defaultValue: "Delete", bundle: .module, comment: "Delete action for live meetings model deletion alert"), role: .destructive) {
                deleteLiveCaptionModel()
            }
        } message: {
            Text(String(localized: "models.live_meetings.fallback_warning", defaultValue: "Live meetings will fall back to standard chunk-by-chunk captions until this model is downloaded again.", bundle: .module, comment: "Warning message shown when live meetings model is removed"))
        }
    }

    private var modelsCategorySelection: Binding<ModelsCategory> {
        Binding(
            get: { appState.selectedModelsCategory },
            set: { appState.selectedModelsCategory = $0 }
        )
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch appState.selectedModelsCategory {
        case .dictation:
            ForEach(BackendOption.systemManaged, id: \.model) { option in
                let featureTourTarget: FeatureTourTarget? = option.backend == BackendOption.appleSpeechAnalyzer.backend
                    ? .appleSpeechCard
                    : nil
                modelCard(
                    option: option,
                    logo: logoForBackend(option),
                    downloadedLabel: String(localized: "models.status.available", defaultValue: "Available", bundle: .module, comment: "Status label indicating a model is available")
                )
                .id(featureTourTarget?.rawValue ?? option.model)
                .featureTourTarget(featureTourTarget)
            }

            familyCard(
                title: String(localized: "models.family.parakeet.title", defaultValue: "Parakeet Family", bundle: .module, comment: "Family section title for Parakeet models"),
                subtitle: String(localized: "models.family.parakeet.description", defaultValue: "The most responsive choices for everyday dictation, with multilingual and English-only options.", bundle: .module, comment: "Family section description for Parakeet models"),
                defaultBadge: String(localized: "models.family.default_v3", defaultValue: "Default: v3", bundle: .module, comment: "Badge label indicating default model version"),
                logo: "nvidia-logo",
                selection: $selectedParakeetModel,
                options: BackendOption.parakeetFamily
            )

            modelCard(option: .qwen3Asr, logo: "qwen-logo")

            familyCard(
                title: String(localized: "models.family.whisper.title", defaultValue: "Whisper", bundle: .module, comment: "Family section title for Whisper models"),
                subtitle: String(localized: "models.family.whisper.description", defaultValue: "Dependable alternatives when you prefer Whisper's transcription style or need broader multilingual coverage.", bundle: .module, comment: "Description for Whisper model family section"),
                defaultBadge: String(localized: "models.family.default_small", defaultValue: "Default: Small", bundle: .module, comment: "Default badge text for Whisper family"),
                logo: "openai-logo",
                selection: $selectedWhisperModel,
                options: BackendOption.whisperFamily
            )

            modelCard(option: .cohereTranscribe, logo: "cohere-logo")
            experimentalSection
            comingSoonSection
        case .streaming:
            streamingSection
        case .postProcessing:
            postProcessorSection
        }
    }

    @ViewBuilder
    private var comingSoonSection: some View {
        if !BackendOption.comingSoon.isEmpty {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                Text(String(localized: "models.coming_soon.section_title", defaultValue: "COMING SOON", bundle: .module, comment: "Section title for upcoming models"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)
                    .padding(.top, MuesliTheme.spacing8)

                VStack(spacing: MuesliTheme.spacing12) {
                    ForEach(BackendOption.comingSoon, id: \.model) { option in
                        comingSoonCard(option: option)
                    }
                }
            }
        }
    }

    private var activeFeatureTourTarget: FeatureTourTarget? {
        appState.activeFeatureTourTarget
    }

    private func revealFeatureTourTargetIfNeeded(using proxy: ScrollViewProxy) {
        let target: FeatureTourTarget
        switch activeFeatureTourTarget {
        case .modelLibrary:
            target = .modelLibrary
            appState.selectedModelsCategory = .dictation
        case .appleSpeechCard:
            target = .appleSpeechCard
            appState.selectedModelsCategory = .dictation
        case .streamingModels:
            target = .streamingModels
            appState.selectedModelsCategory = .streaming
        case .experimentalModels:
            target = .experimentalModels
            appState.selectedModelsCategory = .dictation
            showExperimental = true
        default:
            return
        }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(target.rawValue, anchor: .center)
        }
    }

    private var streamingSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(String(localized: "models.live_meetings.section_title", defaultValue: "LIVE MEETINGS", bundle: .module, comment: "Section title for live meetings models"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)

                Text(String(localized: "models.streaming.description", defaultValue: "Choose how words appear while a meeting is in progress. Nemotron also creates the saved transcript; Parakeet prioritizes a faster English preview.", bundle: .module, comment: "Description for streaming behavior options in live meetings"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }
            .padding(.leading, 2)
            .padding(.top, MuesliTheme.spacing8)
            .id(FeatureTourTarget.streamingModels.rawValue)
            .featureTourTarget(.streamingModels)

            ForEach(BackendOption.streaming, id: \.model) { option in
                if let liveCaptionBackend = MeetingLiveCaptionBackend(rawValue: option.backend) {
                    modelCard(
                        option: option,
                        logo: logoForBackend(option),
                        isActive: appState.config.enableLiveStreamingPartials
                            && appState.config.resolvedMeetingLiveCaptionBackend == liveCaptionBackend,
                        onSetActive: {
                            controller.updateConfig {
                                $0.meetingLiveCaptionBackend = liveCaptionBackend.rawValue
                                $0.enableLiveStreamingPartials = true
                            }
                        }
                    )
                }
            }

            liveCaptionModelCard
        }
    }

    private var liveCaptionModelCard: some View {
        let isActive = isLiveCaptionModelDownloaded
            && appState.config.enableLiveStreamingPartials
            && appState.config.resolvedMeetingLiveCaptionBackend == .parakeetRealtimeEOU

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo("nvidia-logo")
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(MeetingLiveCaptionModelStore.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(MeetingLiveCaptionModelStore.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    Text(String(localized: "models.live_caption.description", defaultValue: "Fast English captions while a meeting is in progress. They are a provisional preview; your regular meeting model creates the transcript you keep.", bundle: .module, comment: "Description for live caption model behavior"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Text(String(localized: "models.status.active", defaultValue: "Active", bundle: .module, comment: "Status label indicating currently active model"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isLiveCaptionModelDownloaded {
                    Text(String(localized: "models.status.ready", defaultValue: "Ready", bundle: .module, comment: "Status label indicating model is ready"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isDownloadingLiveCaptionModel {
                downloadProgressView(
                    for: MeetingLiveCaptionModelStore.modelID,
                    fallbackProgress: liveCaptionDownloadProgress
                )
            }

            HStack(spacing: MuesliTheme.spacing8) {
                if isDownloadingLiveCaptionModel {
                    Button(isCancellingLiveCaptionModelDownload ? String(localized: "models.actions.pausing", defaultValue: "Pausing…", bundle: .module, comment: "Action label shown while pausing download") : String(localized: "models.actions.cancel.pausing", defaultValue: "Cancel", bundle: .module, comment: "Cancel action label during pausing state")) {
                        guard !isCancellingLiveCaptionModelDownload else { return }
                        let task = liveCaptionDownloadTask
                        task?.cancel()
                        let cancellationGeneration = liveCaptionDownloadGeneration.begin()
                        isCancellingLiveCaptionModelDownload = true
                        Task {
                            let shouldCancel = await MainActor.run {
                                liveCaptionDownloadGeneration.contains(cancellationGeneration)
                            }
                            guard shouldCancel else { return }
                            await ManagedASRModelDownloader.cancelAndWait(
                                modelID: MeetingLiveCaptionModelStore.modelID
                            )
                            _ = await task?.value
                            await MainActor.run {
                                guard liveCaptionDownloadGeneration.clear(cancellationGeneration) else { return }
                                liveCaptionDownloadTask = nil
                                isDownloadingLiveCaptionModel = false
                                isCancellingLiveCaptionModelDownload = false
                                liveCaptionDownloadProgress = 0
                            }
                        }
                        liveCaptionDownloadProgress = 0
                        if let snapshot = downloadSnapshots[MeetingLiveCaptionModelStore.modelID] {
                            downloadSnapshots[MeetingLiveCaptionModelStore.modelID] = snapshot.replacing(
                                phase: .paused,
                                message: String(localized: "models.live_caption.paused_resume_hint", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Hint text explaining how to resume paused live caption download")
                            )
                        }
                    }
                    .disabled(isCancellingLiveCaptionModelDownload)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                } else if isLiveCaptionModelDownloaded {
                    if !isActive {
                        Button(String(localized: "models.actions.set_active", defaultValue: "Set Active", bundle: .module, comment: "Action label to set selected model as active")) {
                            controller.updateConfig {
                                $0.meetingLiveCaptionBackend = MeetingLiveCaptionBackend.parakeetRealtimeEOU.rawValue
                                $0.enableLiveStreamingPartials = true
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }

                    Button {
                        showDeleteLiveCaptionModelConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "models.live_caption.delete_help", defaultValue: "Delete live caption model", bundle: .module, comment: "Accessibility/help label for deleting live caption model"))
                } else {
                    Button(String(localized: "models.actions.download", defaultValue: "Download", bundle: .module, comment: "Action label to download model")) {
                        startLiveCaptionModelDownload()
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
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.6) : MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func startLiveCaptionModelDownload() {
        guard !isDownloadingLiveCaptionModel else { return }
        isCancellingLiveCaptionModelDownload = false
        isDownloadingLiveCaptionModel = true
        liveCaptionDownloadProgress = 0
        downloadSnapshots.removeValue(forKey: MeetingLiveCaptionModelStore.modelID)
        let generation = liveCaptionDownloadGeneration.begin()
        liveCaptionDownloadTask = Task {
            do {
                try await MeetingLiveCaptionModelStore.download { progress in
                    Task { @MainActor in
                        guard liveCaptionDownloadGeneration.contains(generation) else { return }
                        liveCaptionDownloadProgress = progress
                    }
                } progressSnapshot: { snapshot in
                    Task { @MainActor in
                        guard liveCaptionDownloadGeneration.contains(generation) else { return }
                        downloadSnapshots[MeetingLiveCaptionModelStore.modelID] = snapshot
                        if let fraction = snapshot.fractionCompleted {
                            liveCaptionDownloadProgress = fraction
                        }
                    }
                }
                guard !Task.isCancelled,
                      liveCaptionDownloadGeneration.contains(generation)
                else { return }
                isLiveCaptionModelDownloaded = true
            } catch is CancellationError {
                // Cancellation is an expected user action.
            } catch {
                fputs("[muesli-native] live caption model download failed: \(error)\n", stderr)
            }
            guard liveCaptionDownloadGeneration.clear(generation) else { return }
            isDownloadingLiveCaptionModel = false
            isCancellingLiveCaptionModelDownload = false
            liveCaptionDownloadProgress = 0
            liveCaptionDownloadTask = nil
            if isLiveCaptionModelDownloaded {
                downloadSnapshots.removeValue(forKey: MeetingLiveCaptionModelStore.modelID)
            }
        }
    }

    private func deleteLiveCaptionModel() {
        do {
            try MeetingLiveCaptionModelStore.delete()
            isLiveCaptionModelDownloaded = false
            if appState.config.resolvedMeetingLiveCaptionBackend == .parakeetRealtimeEOU {
                controller.updateConfig { $0.enableLiveStreamingPartials = false }
            }
        } catch {
            fputs("[muesli-native] live caption model delete failed: \(error)\n", stderr)
        }
    }

    private var experimentalSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Button {
                showExperimental.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing12) {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        HStack(spacing: 6) {
                            Image(systemName: showExperimental ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textTertiary)

                            Text(String(localized: "models.experimental.title", defaultValue: "Experimental", bundle: .module, comment: "Section title for experimental models"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textSecondary)
                        }

                        Text(String(localized: "models.experimental.description", defaultValue: "Early models for specific languages and evaluation. Expect less consistent transcripts, and try them with your own voice before relying on them.", bundle: .module, comment: "Description for experimental models section"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .opacity(0.8)
                    }

                    Spacer()

                    Text(String(localized: "models.experimental.badge_early_access", defaultValue: "Early access", bundle: .module, comment: "Badge label marking early access models"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .featureTourTarget(.experimentalModels)

            if showExperimental {
                VStack(spacing: MuesliTheme.spacing12) {
                    ForEach(BackendOption.experimental, id: \.model) { option in
                        if !appState.selectedPostProcessorBackend.isCompatible(with: option) {
                            modelCard(
                                option: option,
                                logo: logoForBackend(option),
                                downloadedLabel: String(localized: "models.experimental.used_for_cleanup", defaultValue: "Used for Cleanup", bundle: .module, comment: "Status label indicating model is selected for cleanup"),
                                activationDisabledReason: String(localized: "models.experimental.unavailable_due_to_cleanup_selection", defaultValue: "Unavailable while Gemma 4 is selected for cleanup. Choose another cleanup backend first.", bundle: .module, comment: "Message explaining why model is unavailable while cleanup backend is selected")
                            )
                        } else {
                            modelCard(option: option, logo: logoForBackend(option))
                        }
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .id(FeatureTourTarget.experimentalModels.rawValue)
    }

    private var cohereLanguageSelection: Binding<CohereTranscribeLanguage> {
        Binding(
            get: { appState.config.resolvedCohereLanguage },
            set: { controller.selectCohereLanguage($0) }
        )
    }

    private var indicASRLanguageSelection: Binding<IndicASRLanguage> {
        Binding(
            get: { appState.config.resolvedIndicASRLanguage },
            set: { controller.selectIndicASRLanguage($0) }
        )
    }

    private var nemotron35LanguageSelection: Binding<Nemotron35Language> {
        Binding(
            get: { appState.config.resolvedNemotron35Language },
            set: { language in
                Task { await controller.setNemotron35Language(language) }
            }
        )
    }

    private var whisperLanguageSelection: Binding<WhisperKitLanguage> {
        Binding(
            get: { appState.config.resolvedWhisperLanguage },
            set: { controller.selectWhisperLanguage($0) }
        )
    }

    private var appleSpeechLanguageSelection: Binding<String> {
        Binding(
            get: { appState.config.resolvedAppleSpeechLanguage },
            set: { controller.selectAppleSpeechLanguage($0) }
        )
    }

    private var postProcessorSection: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                Text(String(localized: "models.cleanup.title", defaultValue: "CLEANUP", bundle: .module, comment: "Section title for cleanup models"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.leading, 2)

                Text(String(localized: "models.cleanup.description", defaultValue: "Optional cleanup after transcription. Use it to remove filler words, follow spoken corrections, format lists, and fix obvious dictation errors.", bundle: .module, comment: "Description for cleanup models section"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.leading, 2)
            }
            .padding(.top, MuesliTheme.spacing8)

            VStack(spacing: MuesliTheme.spacing12) {
                gemmaCleanupModelCard

                ForEach(PostProcessorOption.all) { option in
                    postProcModelCard(option)
                }
            }
        }
    }

    private var gemmaCleanupModelCard: some View {
        let option = BackendOption.gemma4E2BLiteRT
        let isDownloaded = downloadedModels.contains(option.model)
        let isCompatible = TranscriptCleanupBackendOption.gemma4LiteRT
            .isCompatible(with: appState.selectedBackend)

        return modelCard(
            option: option,
            logo: "google-logo",
            isActive: isDownloaded && appState.selectedPostProcessorBackend == .gemma4LiteRT,
            onSetActive: {
                controller.selectPostProcessorBackend(.gemma4LiteRT)
            },
            description: String(localized: "models.cleanup.gemma.description", defaultValue: "An experimental local option for filler removal, formatting, and obvious transcript errors. It uses the same download as Gemma 4 dictation.", bundle: .module, comment: "Description for Gemma cleanup option"),
            activeLabel: String(localized: "models.cleanup.status.active", defaultValue: "Cleanup Active", bundle: .module, comment: "Status label indicating selected model is active for cleanup"),
            downloadedLabel: isCompatible ? String(localized: "models.status.downloaded", defaultValue: "Downloaded", bundle: .module, comment: "Status label indicating model is downloaded") : String(localized: "models.cleanup.used_for_dictation", defaultValue: "Used for Dictation", bundle: .module, comment: "Status label indicating model is currently used for dictation"),
            actionTitle: String(localized: "models.cleanup.action_use_for_cleanup", defaultValue: "Use for Cleanup", bundle: .module, comment: "Action label to select model for cleanup"),
            activationDisabledReason: isCompatible
                ? nil
                : String(localized: "models.cleanup.unavailable_due_to_dictation_selection", defaultValue: "Unavailable while Gemma 4 is selected for dictation. Choose another dictation model first.", bundle: .module, comment: "Message explaining cleanup option is unavailable while Gemma 4 dictation is selected")
        )
    }

    private func postProcModelCard(_ option: PostProcessorOption) -> some View {
        let isDownloaded = downloadedPostProcModels.contains(option.id)
        let isActive = appState.activePostProcessor.id == option.id && isDownloaded
        let isDownloading = downloadingPostProcModels.contains(option.id)
        let progress = downloadProgressPostProc[option.id] ?? 0
        let showsDownloadStatus = shouldShowDownloadStatus(for: option.id, isDownloading: isDownloading)

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo("qwen-logo")
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                if isActive {
                    Text(String(localized: "models.status.active.general", defaultValue: "Active", bundle: .module, comment: "General status label indicating model is active"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text(String(localized: "models.status.downloaded.general", defaultValue: "Downloaded", bundle: .module, comment: "General status label indicating model files are downloaded"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if showsDownloadStatus {
                downloadProgressView(
                    for: option.id,
                    fallbackProgress: progress,
                    fallbackMessage: downloadMessages[option.id]
                )
            }

            HStack(spacing: MuesliTheme.spacing8) {
                if isDownloading {
                    Button(String(localized: "models.actions.pause", defaultValue: "Pause", bundle: .module, comment: "Action label to pause model download")) {
                        cancelPostProcDownload(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                } else if isDownloaded {
                    if !isActive {
                        Button(String(localized: "models.actions.set_active.general", defaultValue: "Set Active", bundle: .module, comment: "Action label to set selected model active")) {
                            controller.selectPostProcessor(option)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.accent)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, 4)
                        .background(MuesliTheme.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    }

                    Button {
                        postProcModelToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(String(localized: "models.actions.download.general", defaultValue: "Download", bundle: .module, comment: "Action label to download selected model")) {
                        startPostProcDownload(option)
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
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private func familyCard(
        title: String,
        subtitle: String,
        defaultBadge: String,
        logo: String? = nil,
        selection: Binding<String>,
        options: [BackendOption]
    ) -> some View {
        let selectedOption = options.first(where: { $0.model == selection.wrappedValue }) ?? options[0]
        let isActive = appState.selectedBackend == selectedOption
        let isDownloaded = downloadedModels.contains(selectedOption.model)
        let isDownloading = downloadingModels.contains(selectedOption.model)
        let progress = downloadProgress[selectedOption.model] ?? 0
        let showsDownloadStatus = shouldShowDownloadStatus(for: selectedOption.model, isDownloading: isDownloading)

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo(logo)
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(title)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        Text(defaultBadge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MuesliTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MuesliTheme.accentSubtle)
                            .clipShape(Capsule())
                    }

                    Text(subtitle)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                familyStatusBadge(isActive: isActive, isDownloaded: isDownloaded)
            }

            HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                Text(String(localized: "models.family.variant_label", defaultValue: "Variant", bundle: .module, comment: "Label for model variant field"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 52, alignment: .leading)

                Picker("", selection: selection) {
                    ForEach(options, id: \.model) { option in
                        Text(option.label).tag(option.model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220, alignment: .leading)

                Text(selectedOption.sizeLabel)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            Text(selectedOption.description)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)

            if selectedOption.supportsWhisperLanguageSelection {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.family.language_label", defaultValue: "Language", bundle: .module, comment: "Label for model language field"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: whisperLanguageSelection) {
                        ForEach(WhisperKitLanguage.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            if showsDownloadStatus {
                downloadProgressView(
                    for: selectedOption.model,
                    fallbackProgress: progress,
                    fallbackMessage: downloadMessages[selectedOption.model]
                )
            }

            actionButtons(for: selectedOption, isActive: isActive, isDownloaded: isDownloaded, isDownloading: isDownloading)
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private func familyStatusBadge(isActive: Bool, isDownloaded: Bool) -> some View {
        if isActive {
            Text(String(localized: "models.status.active.variant", defaultValue: "Active", bundle: .module, comment: "Status label indicating variant is active"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuesliTheme.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MuesliTheme.success.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if isDownloaded {
            Text(String(localized: "models.status.downloaded.variant", defaultValue: "Downloaded", bundle: .module, comment: "Status label indicating variant is downloaded"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func downloadProgressView(for modelID: String, fallbackProgress: Double, fallbackMessage: String? = nil) -> some View {
        if let snapshot = downloadSnapshots[modelID] {
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.phase != .preparing {
                    ProgressView(value: snapshot.fractionCompleted ?? fallbackProgress)
                        .tint(MuesliTheme.accent)
                }

                if let currentFile = snapshot.currentFile?.split(separator: "/").last.map(String.init), !currentFile.isEmpty {
                    Text("\(downloadPhaseLabel(snapshot.phase)): \(currentFile)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                } else {
                    Text(snapshot.message ?? downloadPhaseLabel(snapshot.phase))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                if let detail = downloadDetailText(snapshot), !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fallbackProgress)
                    .tint(MuesliTheme.accent)
                Text(fallbackMessage ?? String(format: String(localized: "models.download.progress.percent_downloading", defaultValue: "%d%% downloading...", bundle: .module, comment: "Progress label showing integer percent while model is downloading"), Int(fallbackProgress * 100)))
                    .font(.system(size: 11))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }
        }
    }

    private func downloadPhaseLabel(_ phase: ModelDownloadPhase) -> String {
        switch phase {
        case .downloading: return String(localized: "models.download.phase.downloading", defaultValue: "Downloading", bundle: .module, comment: "Download phase label for downloading state")
        case .preparing: return String(localized: "models.download.phase.preparing", defaultValue: "Preparing", bundle: .module, comment: "Download phase label for preparing state")
        case .ready: return String(localized: "models.download.phase.ready", defaultValue: "Ready", bundle: .module, comment: "Download phase label for ready state")
        case .paused: return String(localized: "models.download.phase.paused", defaultValue: "Download paused", bundle: .module, comment: "Download phase label for paused state")
        case .failed: return "Failed"
        }
    }

    private func downloadDetailText(_ snapshot: ModelDownloadProgress) -> String? {
        var details: [String] = []
        if snapshot.totalFileCount > 0 {
            let completed = min(max(snapshot.completedFileCount, 0), snapshot.totalFileCount)
            let remaining = snapshot.totalFileCount - completed
            details.append(String(format: String(localized: "models.download.detail.files_completed", defaultValue: "%d of %d %@", bundle: .module, comment: "Download detail text showing completed files out of total with noun"), completed, snapshot.totalFileCount, "\(downloadFileNoun(snapshot.totalFileCount))"))
            if remaining > 0 {
                details.append(String(format: String(localized: "models.download.detail.files_remaining", defaultValue: "%d %@ left", bundle: .module, comment: "Download detail text showing remaining file count with noun"), remaining, "\(downloadFileNoun(remaining))"))
            }
        }
        if let total = snapshot.totalBytes, total > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.completedBytes)) / \(ModelDownloadDisplayFormatting.bytes(total))")
            if snapshot.completedBytes < total {
                details.append(String(format: String(localized: "models.download.detail.bytes_remaining", defaultValue: "%@ left", bundle: .module, comment: "Download detail text showing remaining bytes"), "\(ModelDownloadDisplayFormatting.bytes(total - snapshot.completedBytes))"))
            }
        } else if let currentTotal = snapshot.currentFileTotalBytes, currentTotal > 0 {
            details.append("\(ModelDownloadDisplayFormatting.bytes(snapshot.currentFileCompletedBytes)) / \(ModelDownloadDisplayFormatting.bytes(currentTotal))")
            if snapshot.currentFileCompletedBytes < currentTotal {
                details.append(String(format: String(localized: "models.download.detail.current_file_remaining", defaultValue: "%@ left in file", bundle: .module, comment: "Download detail text showing remaining bytes in current file"), "\(ModelDownloadDisplayFormatting.bytes(currentTotal - snapshot.currentFileCompletedBytes))"))
            }
        }
        if snapshot.phase == .downloading {
            if snapshot.bytesPerSecond > 0 {
                details.append("\(ModelDownloadDisplayFormatting.rate(snapshot.bytesPerSecond))")
            }
            if let eta = snapshot.estimatedSecondsRemaining,
               let formattedETA = ModelDownloadDisplayFormatting.eta(eta) {
                details.append(String(format: String(localized: "models.download.detail.eta_left", defaultValue: "%@ left", bundle: .module, comment: "Download detail text showing remaining time estimate"), "\(formattedETA)"))
            }
            if snapshot.retryCount > 0 {
                details.append(String(format: String(localized: "models.download.detail.retry_count", defaultValue: "retry %d/3", bundle: .module, comment: "Download detail text showing retry attempt count"), snapshot.retryCount))
            }
        } else if let message = snapshot.message, !message.isEmpty {
            details.append(message)
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func downloadFileNoun(_ count: Int) -> String {
        count == 1 ? String(localized: "models.download.noun.file_singular", defaultValue: "file", bundle: .module, comment: "Singular noun used in download file count labels") : String(localized: "models.download.noun.file_plural", defaultValue: "files", bundle: .module, comment: "Plural noun used in download file count labels")
    }

    private func shouldShowDownloadStatus(for modelID: String, isDownloading: Bool) -> Bool {
        guard let phase = downloadSnapshots[modelID]?.phase else {
            return isDownloading || downloadMessages[modelID] != nil
        }
        return isDownloading || phase == .paused || phase == .failed
    }

    @ViewBuilder
    private func brandLogo(_ name: String?) -> some View {
        if name == "apple-system-logo" {
            Image(systemName: "apple.logo")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(MuesliTheme.textPrimary)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
        } else if let name,
           let url = Bundle.main.url(forResource: name, withExtension: "png")
                ?? Bundle.main.url(forResource: name, withExtension: "svg"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 2)
        }
    }

    private func logoForBackend(_ option: BackendOption) -> String? {
        switch option.backend {
        case "fluidaudio": return "nvidia-logo"
        case "whisper": return "openai-logo"
        case "cohere": return "cohere-logo"
        case "qwen": return "qwen-logo"
        case "nemotron35": return "nvidia-logo"
        case "indicasr": return "ai4bharat-logo"
        case "sensevoice": return "qwen-logo"
        case "gemma4-litert": return "google-logo"
        case "apple-speech": return "apple-system-logo"
        default: return nil
        }
    }

    @ViewBuilder
    private func actionButtons(
        for option: BackendOption,
        isActive: Bool,
        isDownloaded: Bool,
        isDownloading: Bool,
        actionTitle: String = String(localized: "models.actions.set_active", defaultValue: "Set Active", bundle: .module, comment: "Action label to set selected model active"),
        activationDisabledReason: String? = nil,
        onSetActive: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if isDownloading {
                Button(String(localized: "models.actions.pause.general", defaultValue: "Pause", bundle: .module, comment: "General pause action label")) {
                    cancelDownload(option)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.textSecondary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 4)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            } else if isDownloaded {
                if !isActive {
                    Button(actionTitle) {
                        if let onSetActive {
                            onSetActive()
                        } else {
                            controller.selectBackend(option)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(activationDisabledReason == nil ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, 4)
                    .background(activationDisabledReason == nil ? MuesliTheme.accentSubtle : MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .disabled(activationDisabledReason != nil)
                    .help(activationDisabledReason ?? actionTitle)
                }

                if !option.isSystemManaged {
                    Button {
                        modelToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(String(localized: "models.actions.download.fallback", defaultValue: "Download", bundle: .module, comment: "Fallback download action label")) {
                    startDownload(option)
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
    }

    private func modelCard(
        option: BackendOption,
        logo: String? = nil,
        isActive activeOverride: Bool? = nil,
        onSetActive: (() -> Void)? = nil,
        description: String? = nil,
        activeLabel: String = String(localized: "models.status.active", defaultValue: "Active", bundle: .module, comment: "Status label indicating active model"),
        downloadedLabel: String = String(localized: "models.status.downloaded", defaultValue: "Downloaded", bundle: .module, comment: "Status label indicating downloaded model"),
        actionTitle: String = String(localized: "models.actions.set_active", defaultValue: "Set Active", bundle: .module, comment: "Action label to set model as active"),
        activationDisabledReason: String? = nil
    ) -> some View {
        let isActive = activeOverride ?? (appState.selectedBackend == option)
        let isDownloaded = downloadedModels.contains(option.model)
        let isDownloading = downloadingModels.contains(option.model)
        let progress = downloadProgress[option.model] ?? 0
        let showsDownloadStatus = shouldShowDownloadStatus(for: option.model, isDownloading: isDownloading)

        return VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                brandLogo(logo)
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textPrimary)

                        if option.recommended {
                            Text(String(localized: "models.badge.recommended", defaultValue: "Recommended", bundle: .module, comment: "Badge label indicating recommended model"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MuesliTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }

                    Text(description ?? option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                // Status badge
                if isActive {
                    Text(activeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuesliTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isDownloaded {
                    Text(downloadedLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if option.backend == BackendOption.cohereTranscribe.backend {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.family.language_label.primary", defaultValue: "Language", bundle: .module, comment: "Primary language field label in models UI"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: cohereLanguageSelection) {
                        ForEach(CohereTranscribeLanguage.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            if option.backend == BackendOption.indicASR.backend {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.family.language_label.secondary", defaultValue: "Language", bundle: .module, comment: "Secondary language field label in models UI"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: indicASRLanguageSelection) {
                        ForEach(IndicASRLanguage.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            if option.backend == BackendOption.appleSpeechAnalyzer.backend {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.family.language_label.tertiary", defaultValue: "Language", bundle: .module, comment: "Tertiary language field label in models UI"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: appleSpeechLanguageSelection) {
                        ForEach(appleSpeechLanguageOptions) { language in
                            Text(language.label).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            if option.supportsWhisperLanguageSelection {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.language_label.inline", defaultValue: "Language", bundle: .module, comment: "Inline language label in model option row"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: whisperLanguageSelection) {
                        ForEach(WhisperKitLanguage.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }
            }

            if option.backend == BackendOption.nemotron35Multilingual.backend {
                HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "models.language_label", defaultValue: "Language", bundle: .module, comment: "Language field label for model configuration"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 64, alignment: .leading)

                    Picker("", selection: nemotron35LanguageSelection) {
                        ForEach(Nemotron35Language.allCases, id: \.self) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                }

                if isDownloaded && nemotron35UpdateAvailable && !isDownloading {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(String(localized: "models.update_available.message", defaultValue: "A newer model build is available.", bundle: .module, comment: "Message indicating a model update is available"))
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textSecondary)
                        Button(String(localized: "common.actions.update", defaultValue: "Update", bundle: .module, comment: "Common update action label")) { updateNemotron35(option) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MuesliTheme.accent)
                    }
                }
            }

            // Progress bar when downloading
            if showsDownloadStatus {
                downloadProgressView(
                    for: option.model,
                    fallbackProgress: progress,
                    fallbackMessage: downloadMessages[option.model]
                )
            }

            if let activationDisabledReason, isDownloaded, !isActive {
                Label(activationDisabledReason, systemImage: "exclamationmark.lock")
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            actionButtons(
                for: option,
                isActive: isActive,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading,
                actionTitle: actionTitle,
                activationDisabledReason: activationDisabledReason,
                onSetActive: onSetActive
            )
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.5) : MuesliTheme.surfaceBorder, lineWidth: isActive ? 1.5 : 1)
        )
    }

    private func comingSoonCard(option: BackendOption) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        Text(option.label)
                            .font(MuesliTheme.headline())
                            .foregroundStyle(MuesliTheme.textTertiary)

                        Text(String(localized: "models.coming_soon.card_title", defaultValue: "Coming soon", bundle: .module, comment: "Card title for upcoming model features"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MuesliTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(option.sizeLabel)
                            .font(MuesliTheme.caption())
                            .foregroundStyle(MuesliTheme.textTertiary.opacity(0.6))
                    }

                    Text(option.description)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(MuesliTheme.spacing16)
        .background(MuesliTheme.backgroundRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder.opacity(0.5), lineWidth: 1)
        )
        .opacity(0.6)
    }

    // MARK: - Post-Processor Actions

    private func startPostProcDownload(_ option: PostProcessorOption) {
        withAnimation { _ = downloadingPostProcModels.insert(option.id) }
        downloadProgressPostProc[option.id] = 0.02
        downloadMessages.removeValue(forKey: option.id)
        downloadSnapshots.removeValue(forKey: option.id)
        let generation = UUID()
        downloadGenerations[option.id] = generation

        let task = Task {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: option.cacheDirectory, withIntermediateDirectories: true)

                try await downloadPostProcModel(option, generation: generation)
                try Task.checkCancellation()

                await MainActor.run {
                    guard downloadGenerations[option.id] == generation, !Task.isCancelled else { return }
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadedPostProcModels.insert(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadMessages.removeValue(forKey: option.id)
                        downloadSnapshots.removeValue(forKey: option.id)
                        if downloadGenerations[option.id] == generation {
                            downloadGenerations.removeValue(forKey: option.id)
                        }
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                    if appState.config.enablePostProcessor && !appState.activePostProcessor.isDownloaded {
                        controller.selectPostProcessor(option)
                        controller.preloadExperimentalTranscriptionFeatures()
                    }
                }
            } catch {
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                await MainActor.run {
                    guard downloadGenerations[option.id] == generation else { return }
                    withAnimation {
                        downloadingPostProcModels.remove(option.id)
                        downloadProgressPostProc.removeValue(forKey: option.id)
                        downloadMessages[option.id] = isCancelled
                            ? String(localized: "models.download.paused_resume_hint.inline", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for resumable download state")
                            : error.localizedDescription
                        if let snapshot = downloadSnapshots[option.id] {
                            downloadSnapshots[option.id] = snapshot.replacing(
                                phase: isCancelled ? .paused : .failed,
                                message: downloadMessages[option.id]
                            )
                        }
                        if downloadGenerations[option.id] == generation {
                            downloadGenerations.removeValue(forKey: option.id)
                        }
                        downloadTasksPostProc.removeValue(forKey: option.id)
                    }
                }
                if !isCancelled {
                    fputs("[muesli-native] Post-processor download failed: \(error)\n", stderr)
                }
            }
        }
        downloadTasksPostProc[option.id] = task
    }

    private func downloadPostProcModel(_ option: PostProcessorOption, generation: UUID) async throws {
        let manifest = ModelDownloadManifest(
            id: option.id,
            version: "main",
            files: [ModelDownloadFile(relativePath: option.filename, remoteURL: option.downloadURL)],
            maximumConcurrency: 1
        )
        try await ModelDownloadCoordinator.shared.download(manifest, to: option.cacheDirectory) { snapshot in
            DispatchQueue.main.async {
                guard downloadGenerations[option.id] == generation else { return }
                downloadProgressPostProc[option.id] = max(snapshot.fractionCompleted ?? 0.02, 0.02)
                downloadSnapshots[option.id] = snapshot
            }
        }
        try Task.checkCancellation()
        do {
            try validateGGUFHeader(at: option.modelURL)
        } catch {
            try? FileManager.default.removeItem(at: option.modelURL)
            throw error
        }
    }

    private func validateGGUFHeader(at url: URL) throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let header = try fh.read(upToCount: 4) ?? Data()
        guard header == Data([0x47, 0x47, 0x55, 0x46]) else {
            throw NSError(domain: "PostProcDownload", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "models.errors.invalid_gguf_model", defaultValue: "Downloaded post-processor file is not a GGUF model", bundle: .module, comment: "Error text when downloaded post-processor file is invalid GGUF"),
            ])
        }
    }

    private func cancelPostProcDownload(_ option: PostProcessorOption) {
        let task = downloadTasksPostProc[option.id]
        let cancellationGeneration = UUID()
        task?.cancel()
        Task {
            await ModelDownloadCoordinator.shared.cancel(modelID: option.id)
            _ = await task?.value
            await MainActor.run {
                guard downloadGenerations[option.id] == cancellationGeneration else { return }
                if option.isDownloaded {
                    downloadedPostProcModels.insert(option.id)
                    downloadMessages.removeValue(forKey: option.id)
                    downloadSnapshots.removeValue(forKey: option.id)
                } else {
                    downloadMessages[option.id] = String(localized: "models.download.paused_resume_hint.primary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for first resumable download context")
                }
                downloadGenerations.removeValue(forKey: option.id)
            }
        }
        withAnimation {
            downloadingPostProcModels.remove(option.id)
            downloadProgressPostProc.removeValue(forKey: option.id)
            // Invalidate callbacks from the cancelled task, but retain a
            // generation until it has fully unwound so a race that finalizes
            // the file can refresh the card immediately.
            downloadGenerations[option.id] = cancellationGeneration
            if let snapshot = downloadSnapshots[option.id] {
                downloadSnapshots[option.id] = snapshot.replacing(phase: .paused, message: String(localized: "models.download.paused_resume_hint.secondary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for second resumable download context"))
            }
            downloadTasksPostProc.removeValue(forKey: option.id)
        }
    }

    private func deletePostProcModel(_ option: PostProcessorOption) {
        if appState.activePostProcessor.id == option.id {
            let remainingDownloadedIDs = downloadedPostProcModels.subtracting([option.id])
            if let fallback = PostProcessorOption.firstDownloaded(excluding: option.id, downloadedIDs: remainingDownloadedIDs) {
                controller.selectPostProcessor(fallback)
            } else {
                controller.setPostProcessorEnabled(false)
            }
        }
        try? FileManager.default.removeItem(at: option.cacheDirectory)
        downloadedPostProcModels.remove(option.id)
        downloadSnapshots.removeValue(forKey: option.id)
        downloadGenerations.removeValue(forKey: option.id)
    }

    private func checkDownloadedPostProcModels() {
        downloadedPostProcModels.removeAll()
        for option in PostProcessorOption.all {
            if option.isDownloaded {
                downloadedPostProcModels.insert(option.id)
            }
        }
    }

    // MARK: - Actions

    private func startDownload(_ option: BackendOption) {
        withAnimation { _ = downloadingModels.insert(option.model) }
        downloadProgress[option.model] = 0.05  // Show initial progress immediately
        downloadMessages.removeValue(forKey: option.model)
        downloadSnapshots.removeValue(forKey: option.model)
        let generation = UUID()
        downloadGenerations[option.model] = generation

        let startTime = Date()
        let task = Task {
            do {
                try await controller.transcriptionCoordinator.preloadRequired(
                    backend: option,
                    includeMeetingHelpers: false,
                    meetingHelperTrigger: .modelLibrary,
                    appleSpeechLanguage: appState.config.resolvedAppleSpeechLanguage
                ) { progress, message in
                    DispatchQueue.main.async {
                        guard downloadGenerations[option.model] == generation else { return }
                        downloadProgress[option.model] = max(progress, 0.05)
                        if let message { downloadMessages[option.model] = message }
                    }
                } progressSnapshot: { snapshot in
                    DispatchQueue.main.async {
                        guard downloadGenerations[option.model] == generation else { return }
                        downloadSnapshots[option.model] = snapshot
                        if let fraction = snapshot.fractionCompleted {
                            downloadProgress[option.model] = max(fraction, 0.05)
                        }
                    }
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard downloadGenerations[option.model] == generation else { return }
                        withAnimation {
                            downloadingModels.remove(option.model)
                            downloadProgress.removeValue(forKey: option.model)
                            downloadMessages[option.model] = String(localized: "models.download.paused_resume_hint.tertiary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for third resumable download context")
                            if let snapshot = downloadSnapshots[option.model] {
                                downloadSnapshots[option.model] = snapshot.replacing(
                                    phase: .paused,
                                    message: String(localized: "models.download.paused_resume_hint.quaternary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for fourth resumable download context")
                                )
                            }
                            downloadGenerations.removeValue(forKey: option.model)
                            downloadTasks.removeValue(forKey: option.model)
                        }
                    }
                    return
                }
                guard isModelDownloaded(option, fm: FileManager.default) else {
                    throw NSError(
                        domain: "MuesliModelDownload",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "models.errors.download_failed_with_label", defaultValue: "%@ was not downloaded successfully.", bundle: .module, comment: "Error message indicating download failed for a specific model option"), "\(option.label)")]
                    )
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard downloadGenerations[option.model] == generation else { return }
                        withAnimation {
                            downloadingModels.remove(option.model)
                            downloadProgress.removeValue(forKey: option.model)
                            downloadMessages[option.model] = String(localized: "models.download.paused_resume_hint.quinary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for fifth resumable download context")
                            if let snapshot = downloadSnapshots[option.model] {
                                downloadSnapshots[option.model] = snapshot.replacing(
                                    phase: .paused,
                                    message: String(localized: "models.download.paused_resume_hint.senary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for sixth resumable download context")
                                )
                            }
                            downloadGenerations.removeValue(forKey: option.model)
                            downloadTasks.removeValue(forKey: option.model)
                        }
                    }
                    return
                }
                // Ensure the downloading state is visible for at least 1.5s
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed < 1.5 {
                    try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    guard downloadGenerations[option.model] == generation, !Task.isCancelled else { return }
                    withAnimation {
                        downloadingModels.remove(option.model)
                        downloadedModels.insert(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        downloadMessages.removeValue(forKey: option.model)
                        downloadSnapshots.removeValue(forKey: option.model)
                        downloadGenerations.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                    }
                }
            } catch {
                let isCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                await MainActor.run {
                    withAnimation {
                        guard downloadGenerations[option.model] == generation else { return }
                        downloadingModels.remove(option.model)
                        downloadProgress.removeValue(forKey: option.model)
                        if isCancelled {
                            if let snapshot = downloadSnapshots[option.model] {
                                downloadSnapshots[option.model] = snapshot.replacing(
                                    phase: .paused,
                                    message: String(localized: "models.download.paused_resume_hint.septenary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for seventh resumable download context")
                                )
                            }
                        } else {
                            downloadMessages[option.model] = error.localizedDescription
                            if let snapshot = downloadSnapshots[option.model] {
                                downloadSnapshots[option.model] = snapshot.replacing(
                                    phase: .failed,
                                    message: error.localizedDescription
                                )
                            }
                        }
                        downloadGenerations.removeValue(forKey: option.model)
                        downloadTasks.removeValue(forKey: option.model)
                    }
                }
                if !isCancelled {
                    fputs("[muesli-native] model download failed for \(option.backend)/\(option.model): \(error)\n", stderr)
                }
            }
        }
        downloadTasks[option.model] = task
    }

    private func loadAppleSpeechLanguageOptions() {
        guard #available(macOS 26.0, *), AppleSpeechAnalyzerTranscriber.isSupportedOnCurrentSystem else {
            appleSpeechLanguageOptions = [.system]
            return
        }

        Task {
            var options = await AppleSpeechLanguageOption.supportedOptions()
            let selectedIdentifier = appState.config.resolvedAppleSpeechLanguage
            if selectedIdentifier != AppleSpeechLanguageOption.systemIdentifier,
               !options.contains(where: { $0.id == selectedIdentifier }) {
                options.append(.locale(Locale(identifier: selectedIdentifier)))
            }
            appleSpeechLanguageOptions = options
        }
    }

    private func cancelDownload(_ option: BackendOption) {
        let modelID = option.model
        let task = downloadTasks[modelID]
        let cancellationGeneration = UUID()
        task?.cancel()
        withAnimation {
            downloadingModels.remove(modelID)
            downloadProgress.removeValue(forKey: modelID)
            downloadMessages[modelID] = String(localized: "models.download.paused_resume_hint.octonary", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "Paused hint shown for eighth resumable download context")
            // Keep a cancellation generation until the caller task has fully
            // unwound. If a replacement starts first, this generation changes
            // and the old cancellation must not stop the replacement transfer.
            downloadGenerations[modelID] = cancellationGeneration
            downloadTasks.removeValue(forKey: modelID)
            if let snapshot = downloadSnapshots[modelID] {
                downloadSnapshots[modelID] = snapshot.replacing(
                    phase: .paused,
                    message: String(localized: "models.download.paused_resume_hint.general", defaultValue: "Paused — select Download to resume", bundle: .module, comment: "General paused hint shown for resumable download state")
                )
            }
        }
        Task {
            let shouldCancel = await MainActor.run {
                downloadGenerations[modelID] == cancellationGeneration
            }
            guard shouldCancel else { return }

            await ManagedASRModelDownloader.cancel(modelID: modelID)
            _ = await task?.value

            await MainActor.run {
                guard downloadGenerations[modelID] == cancellationGeneration else { return }
                downloadGenerations.removeValue(forKey: modelID)
            }
        }
    }

    /// Re-download Nemotron 3.5 to pick up a newer upstream build: delete the cached
    /// files (so the download isn't skipped), then start a fresh download.
    private func updateNemotron35(_ option: BackendOption) {
        Task {
            do {
                await controller.transcriptionCoordinator.unloadNemotron35Transcriber()
                try await deleteModelFiles(option)
                await MainActor.run {
                    downloadedModels.remove(option.model)
                    nemotron35UpdateAvailable = false
                    startDownload(option)
                }
            } catch {
                fputs("[muesli-native] model update cleanup failed for \(option.backend)/\(option.model): \(error)\n", stderr)
            }
        }
    }

    private func deleteModel(_ option: BackendOption) {
        if option == .nemotron35Multilingual,
           appState.config.resolvedMeetingLiveCaptionBackend == .nemotron35 {
            controller.updateConfig { $0.enableLiveStreamingPartials = false }
        }
        if !appState.selectedPostProcessorBackend.isCompatible(with: option) {
            controller.selectPostProcessorBackend(.local)
        }
        if appState.selectedBackend == option {
            let fallback = downloadedModels
                .compactMap { model in BackendOption.all.first(where: { $0.model == model && $0 != option }) }
                .first ?? .parakeetMultilingual
            controller.selectBackend(fallback)
        }
        let task = downloadTasks[option.model]
        task?.cancel()
        let deletionGeneration = UUID()
        downloadGenerations[option.model] = deletionGeneration
        downloadTasks.removeValue(forKey: option.model)

        // Stop any transfer before removing files so a late write cannot recreate
        // part of the model after the deletion has completed.
        Task {
            let deletionToken = await ManagedASRModelDownloader.beginDeletion(
                modelID: option.model
            )
            do {
                _ = await task?.value
                let shouldDelete = await MainActor.run {
                    downloadGenerations[option.model] == deletionGeneration
                }
                guard shouldDelete else {
                    await ManagedASRModelDownloader.endDeletion(deletionToken)
                    return
                }
                try await deleteModelFiles(option)
                await MainActor.run {
                    _ = downloadedModels.remove(option.model)
                    if appState.selectedMeetingTranscriptionBackend == option {
                        controller.refreshMeetingTranscriptionSelectionForAvailability()
                    }
                    downloadSnapshots.removeValue(forKey: option.model)
                    downloadMessages.removeValue(forKey: option.model)
                    downloadGenerations.removeValue(forKey: option.model)
                }
            } catch {
                fputs("[muesli-native] model delete failed for \(option.backend)/\(option.model): \(error)\n", stderr)
            }
            await ManagedASRModelDownloader.endDeletion(deletionToken)
        }
    }

    private func deleteModelFiles(_ option: BackendOption) async throws {
        let fm = FileManager.default
        switch option.backend {
        case "whisper":
            WhisperKitTranscriber.deleteModel(option.model)
        case "nemotron35":
            try removeItemIfPresent(at: Nemotron35ModelStore.cacheDirectory(fileManager: fm), fileManager: fm)
        case "cohere":
            try removeItemIfPresent(at: CohereTranscribeModelStore.cacheDirectory(), fileManager: fm)
        case "indicasr":
            if IndicASRModelStore.localOverrideDirectory() == nil {
                try removeItemIfPresent(at: IndicASRModelStore.cacheDirectory(), fileManager: fm)
            }
        case "sensevoice":
            SenseVoiceTranscriber.deleteModelFiles(fileManager: fm)
        case "gemma4-litert":
            await controller.transcriptionCoordinator.unloadGemma4LiteRTTranscriber()
            try Gemma4LiteRTModelStore.deleteModelFiles(fileManager: fm)
        case "fluidaudio":
            let version: AsrModelVersion = option.model.contains("v2") ? .v2 : .v3
            await controller.transcriptionCoordinator.unloadFluidAudioTranscriber(
                ifLoadedVersion: version
            )
            let plan = version == .v2
                ? ManagedASRModelPlans.parakeetV2()
                : ManagedASRModelPlans.parakeetV3()
            try plan.delete(fileManager: fm)
        case "qwen":
            await controller.transcriptionCoordinator.unloadQwen3Transcriber()
            try Qwen3AsrModelStore.deleteModelFiles(fileManager: fm)
        default:
            break
        }
    }

    private func removeItemIfPresent(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Check Downloaded Status

    private func checkDownloadedModels() {
        let fm = FileManager.default
        for option in BackendOption.all {
            if isModelDownloaded(option, fm: fm) {
                downloadedModels.insert(option.model)
            }
        }
    }

    /// Background check: does FluidInference's repo have a newer commit than what's
    /// installed for Nemotron 3.5? Never auto-downloads — just surfaces a badge.
    private func checkNemotron35Update() {
        guard #available(macOS 15, *),
              isModelDownloaded(.nemotron35Multilingual, fm: FileManager.default) else { return }
        Task {
            let available = await Nemotron35StreamingTranscriber.updateAvailable()
            await MainActor.run { nemotron35UpdateAvailable = available }
        }
    }

    private func syncSelectionsFromActiveBackend() {
        let active = appState.selectedBackend
        if BackendOption.parakeetFamily.contains(active) {
            selectedParakeetModel = active.model
        }
        if BackendOption.whisperFamily.contains(active) {
            selectedWhisperModel = active.model
        }
        if BackendOption.experimental.contains(active) {
            showExperimental = true
        }
    }

    private func isModelDownloaded(_ option: BackendOption, fm: FileManager) -> Bool {
        switch option.backend {
        case "whisper":
            return WhisperKitTranscriber.isModelDownloaded(option.model)
        case "nemotron35":
            return Nemotron35ModelStore.isModelDownloaded(fileManager: fm)
        case "fluidaudio":
            let plan = option.model.contains("v2")
                ? ManagedASRModelPlans.parakeetV2()
                : ManagedASRModelPlans.parakeetV3()
            return plan.isAvailableLocally(fileManager: fm)
        case "qwen":
            return Qwen3AsrModelStore.isModelDownloaded(fileManager: fm)
        case "cohere":
            return CohereTranscribeModelStore.isAvailableLocally()
        case "indicasr":
            return IndicASRModelStore.isAvailableLocally()
        case "sensevoice":
            return SenseVoiceTranscriber.isModelDownloaded(fileManager: fm)
        case "gemma4-litert":
            return Gemma4LiteRTModelStore.isAvailableLocally(fileManager: fm)
        case "apple-speech":
            if #available(macOS 26.0, *) {
                return AppleSpeechAnalyzerTranscriber.isSupportedOnCurrentSystem
            }
            return false
        default:
            return false
        }
    }
}
