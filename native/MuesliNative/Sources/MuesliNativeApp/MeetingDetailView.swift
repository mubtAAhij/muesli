import SwiftUI
import MuesliCore

private enum MeetingDocumentMode: Hashable {
    case notes
    case transcript
}

private enum RecordingContentMode: Hashable {
    case notes
    case live
}

private enum ManualNotesSaveStatus {
    case saved
    case saving

    var label: String {
        switch self {
        case .saved: return String(localized: "meeting_detail.save_state.saved", defaultValue: "Saved", bundle: .module, comment: "Save status label when notes are saved")
        case .saving: return String(localized: "meeting_detail.save_state.saving", defaultValue: "Saving...", bundle: .module, comment: "Save status label while notes are saving")
        }
    }
}

enum MeetingHeaderLayout {
    static let contextControlHeight: CGFloat = 28
}

// Wrapper views that isolate observation of liveMeetingTranscript.
// Without these, MeetingDetailView.body would observe the property and
// re-evaluate on every chunk (every ~5s), re-rendering the entire detail view.
// Each wrapper is the sole observer — MeetingDetailView passes appState by
// reference and never reads liveMeetingTranscript in its own body.
private struct LiveTranscriptSection: View {
    let appState: AppState
    let transcriptPrefix: String

    var body: some View {
        LiveTranscriptView(
            transcript: MeetingResumePolicy.combinedResumeTranscript(
                prior: transcriptPrefix,
                new: appState.liveMeetingTranscript
            ),
            partialYou: appState.liveMeetingPartialYou,
            partialOthers: appState.liveMeetingPartialOthers
        )
    }
}

struct MeetingDetailView: View {
    let meeting: MeetingRecord?
    let controller: MuesliController
    let appState: AppState
    let onBack: (() -> Void)?
    let backLabel: String
    @State private var isSummarizing = false
    @State private var isRetranscribing = false
    @State private var isEditingNotes = false
    @State private var isEditingTranscript = false
    @State private var editableTitle: String
    @State private var editableNotes: String
    @State private var editableTranscript: String
    @State private var editableManualNotes: String
    @State private var loadedMeetingID: Int64?
    @State private var manualNotesSaveStatus: ManualNotesSaveStatus = .saved
    @State private var manualEditorCommand: MarkdownEditorCommand?
    @State private var pendingTemplateID: String
    @State private var documentMode: MeetingDocumentMode
    @State private var recordingMode: RecordingContentMode = .notes
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var notesSaveTask: DispatchWorkItem?
    @State private var transcriptSaveTask: DispatchWorkItem?
    @State private var manualNotesSaveStatusTask: DispatchWorkItem?
    @State private var summaryErrorMessage: String?
    @State private var retranscriptionErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var transcriptResummaryPromptMeetingID: Int64?
    @State private var transcriptEditOriginalTranscript: String?
    @State private var transcriptEditHadStructuredNotes = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""
    @State private var threadContext: MeetingThreadContext?

    init(
        meeting: MeetingRecord?,
        controller: MuesliController,
        appState: AppState,
        onBack: (() -> Void)? = nil,
        backLabel: String = String(localized: "meeting_detail.navigation.back_to_meetings", defaultValue: "Back to Meetings", bundle: .module, comment: "Navigation title for returning to meetings list")
    ) {
        self.meeting = meeting
        self.controller = controller
        self.appState = appState
        self.onBack = onBack
        self.backLabel = backLabel
        let initialTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        _editableTitle = State(initialValue: meeting?.title ?? "")
        _editableNotes = State(initialValue: meeting.map { Self.notesContent(for: $0) } ?? "")
        _editableTranscript = State(initialValue: meeting?.rawTranscript ?? "")
        _editableManualNotes = State(initialValue: meeting?.manualNotes ?? "")
        _loadedMeetingID = State(initialValue: meeting?.id)
        _pendingTemplateID = State(initialValue: initialTemplateID)
        _documentMode = State(initialValue: meeting.map(Self.defaultDocumentMode(for:)) ?? .notes)
    }

    var body: some View {
        Group {
            if let meeting {
                VStack(alignment: .leading, spacing: 0) {
                    header(meeting)

                    Divider()
                        .background(MuesliTheme.surfaceBorder)

                    content(for: meeting)
                }
                .background(MuesliTheme.backgroundBase)
                .onAppear {
                    threadContext = controller.meetingThreadContext(for: meeting.id)
                }
                .onChange(of: meeting.id) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: meeting.status) { _, _ in
                    syncLocalState(with: meeting)
                }
                .onChange(of: appState.meetingNotesFocusRequest) { _, _ in
                    recordingMode = .notes
                }
                .onChange(of: meeting.manualNotes) { _, _ in
                    syncManualNotesState(with: meeting)
                }
                .onChange(of: appState.config.customMeetingTemplates) { _, _ in
                    syncPendingTemplateSelectionIfNeeded(for: meeting)
                }
            } else {
                VStack(spacing: MuesliTheme.spacing12) {
                    Text(String(localized: "meeting_detail.empty_state.no_meeting_selected", defaultValue: "No meeting selected", bundle: .module, comment: "Empty state title when no meeting is selected"))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textSecondary)
                    Text(String(localized: "meeting_detail.empty_state.choose_meeting_message", defaultValue: "Choose a meeting from the Meetings browser to open it here.", bundle: .module, comment: "Empty state guidance to select a meeting from browser"))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuesliTheme.backgroundBase)
            }
        }
        .alert(String(localized: "meeting_detail.alert.couldnt_save_summary", defaultValue: "Couldn't Save Summary", bundle: .module, comment: "Alert title when summary save fails"), isPresented: summaryErrorBinding) {
            Button(String(localized: "meeting_detail.alert.ok.save_summary", defaultValue: "OK", bundle: .module, comment: "Confirmation button title for save summary failure alert"), role: .cancel) {
                summaryErrorMessage = nil
            }
        } message: {
            Text(summaryErrorMessage ?? String(localized: "meeting_detail.alert.couldnt_save_summary.message", defaultValue: "The updated meeting notes could not be saved.", bundle: .module, comment: "Alert message when summary save fails"))
        }
        .alert(String(localized: "meeting_detail.alert.couldnt_retranscribe_meeting", defaultValue: "Couldn't Re-transcribe Meeting", bundle: .module, comment: "Alert title when re-transcription fails"), isPresented: retranscriptionErrorBinding) {
            Button(String(localized: "meeting_detail.alert.ok.retranscribe", defaultValue: "OK", bundle: .module, comment: "Confirmation button title for retranscribe failure alert"), role: .cancel) {
                retranscriptionErrorMessage = nil
            }
        } message: {
            Text(retranscriptionErrorMessage ?? String(localized: "meeting_detail.alert.couldnt_retranscribe_meeting.message", defaultValue: "The saved recording could not be re-transcribed.", bundle: .module, comment: "Alert message when re-transcription fails"))
        }
        .alert(String(localized: "meeting_detail.alert.resummarize_notes_title", defaultValue: "Re-summarize Notes?", bundle: .module, comment: "Alert title asking to re-summarize notes"), isPresented: transcriptResummaryPromptBinding) {
            Button(String(localized: "meeting_detail.alert.resummarize_action", defaultValue: "Re-summarize", bundle: .module, comment: "Primary action title to trigger re-summarization")) {
                resummarizeAfterTranscriptEdit()
            }
            Button(String(localized: "meeting_detail.alert.not_now", defaultValue: "Not Now", bundle: .module, comment: "Secondary action title to defer re-summarization"), role: .cancel) {
                transcriptResummaryPromptMeetingID = nil
            }
        } message: {
            Text(String(localized: "meeting_detail.alert.resummarize_notes_message", defaultValue: "Your transcript edits may change the generated notes. Re-summarize now to update them from the edited transcript.", bundle: .module, comment: "Alert message explaining why re-summarization is recommended"))
        }
        .alert(String(localized: "meeting_detail.alert.delete_meeting_title", defaultValue: "Delete Meeting", bundle: .module, comment: "Alert title for deleting a meeting"), isPresented: $showDeleteConfirmation) {
            Button(String(localized: "common.delete", defaultValue: "Delete", bundle: .module, comment: "Destructive action title used for delete actions"), role: .destructive) {
                if let meeting {
                    controller.deleteMeeting(id: meeting.id)
                }
            }
            Button(String(localized: "meeting_detail.alert.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel action title in delete meeting alert"), role: .cancel) {}
        } message: {
            Text(String(localized: "meeting_detail.alert.delete_meeting_message", defaultValue: "Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed.", bundle: .module, comment: "Confirmation message describing delete meeting consequences"))
        }
    }

    @ViewBuilder
    private func header(_ meeting: MeetingRecord) -> some View {
        let appliedTemplate = controller.meetingTemplateSnapshot(for: meeting)
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(backLabel)
                            .font(MuesliTheme.callout())
                    }
                    .foregroundStyle(MuesliTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: MuesliTheme.spacing24) {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    MarqueeTitleTextField(
                        text: $editableTitle,
                        onSubmit: {
                            controller.updateMeetingTitle(id: meeting.id, title: editableTitle)
                        },
                        onTextChange: {
                            debounceSaveTitle(meetingID: meeting.id)
                        }
                    )

                    HStack(spacing: MuesliTheme.spacing8) {
                        metadataItem(systemImage: "calendar", text: MeetingBrowserLogic.formatStartTime(meeting.startTime))
                        metadataDivider
                        metadataItem(systemImage: "clock", text: formatDuration(meeting.durationSeconds))
                        metadataDivider
                        metadataItem(systemImage: "doc.text", text: String(format: String(localized: "meeting_detail.metadata.word_count", defaultValue: "%d words", bundle: .module, comment: "Meeting metadata label showing transcript word count"), meeting.wordCount))
                        if let label = SyncOriginDisplay.badgeLabel(forMeetingSource: meeting.source) {
                            SyncOriginBadge(label: label)
                        }
                    }
                }

                Spacer(minLength: MuesliTheme.spacing16)

                VStack(alignment: .trailing, spacing: 10) {
                    if showsManualNotesEditor(for: meeting) {
                        recordingControlGroup(for: meeting)
                    } else {
                        compactHeaderActions(for: meeting, appliedTemplate: appliedTemplate)
                    }
                }
            }

            HStack(alignment: .center, spacing: MuesliTheme.spacing12) {
                meetingContextStrip(for: meeting)
                    .layoutPriority(1)
                Spacer(minLength: MuesliTheme.spacing12)
                detailModePicker(for: meeting)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(MuesliTheme.spacing8)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
            .overlay {
                RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            }

            threadBreadcrumb

            if let savedRecordingPath = meeting.savedRecordingPath,
               FileManager.default.fileExists(atPath: savedRecordingPath) {
                MeetingRecordingPlayerView(recordingPath: savedRecordingPath)
            }

            activeMeetingAudioWarningBanner(for: meeting)

            if !showsManualNotesEditor(for: meeting), isRawTranscript(meeting), documentMode == .notes {
                transcriptCTA
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func meetingContextStrip(for meeting: MeetingRecord) -> some View {
        HStack(alignment: .center, spacing: MuesliTheme.spacing16) {
            folderPill(for: meeting)
            Divider()
                .frame(height: 20)
            MeetingParticipantsView(
                meetingID: meeting.id,
                controller: controller
            )
        }
    }

    private func metadataItem(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(MuesliTheme.callout())
        }
        .foregroundStyle(MuesliTheme.textSecondary)
    }

    private var metadataDivider: some View {
        Text("·")
            .font(MuesliTheme.callout())
            .foregroundStyle(MuesliTheme.textTertiary)
    }

    @ViewBuilder
    private func detailModePicker(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording, showsManualNotesEditor(for: meeting) {
            recordingModePicker
        } else if !showsManualNotesEditor(for: meeting) {
            documentModePicker
        }
    }

    @ViewBuilder
    private func content(for meeting: MeetingRecord) -> some View {
        if showsManualNotesEditor(for: meeting) {
            if meeting.status == .recording {
                let isManualNotesEditable = canEditManualNotes(for: meeting)
                let persistedNotes = Self.notesContent(for: meeting)
                let hasPersistedNotes = !meeting.formattedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ZStack {
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                        if hasPersistedNotes {
                            MeetingNotesView(markdown: persistedNotes)
                                .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                                .background(MuesliTheme.backgroundBase)
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                            manualNotesToolbar(for: meeting)
                                .disabled(!isManualNotesEditable)
                            MarkdownRichTextEditor(
                                text: $editableManualNotes,
                                command: $manualEditorCommand,
                                shouldFocus: isManualNotesEditable,
                                isEditable: isManualNotesEditable,
                                onTextChange: { notes in
                                    guard isManualNotesEditable else { return }
                                    saveManualNotes(meetingID: meeting.id, notes: notes)
                                }
                            )
                            .background(MuesliTheme.backgroundBase)
                            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                            .overlay(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                            )
                            .frame(maxHeight: hasPersistedNotes ? 260 : .infinity)
                        }
                        .frame(maxWidth: 980, maxHeight: hasPersistedNotes ? nil : .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(recordingMode == .notes ? 1 : 0)
                    .allowsHitTesting(recordingMode == .notes)
                    .accessibilityHidden(recordingMode != .notes)

                    LiveTranscriptSection(appState: appState, transcriptPrefix: meeting.rawTranscript)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(recordingMode == .live ? 1 : 0)
                        .allowsHitTesting(recordingMode == .live)
                        .accessibilityHidden(recordingMode != .live)

                }
            } else {
                let isManualNotesEditable = canEditManualNotes(for: meeting)
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    manualNotesToolbar(for: meeting)
                        .disabled(!isManualNotesEditable)

                    MarkdownRichTextEditor(
                        text: $editableManualNotes,
                        command: $manualEditorCommand,
                        shouldFocus: false,
                        isEditable: isManualNotesEditable,
                        onTextChange: { notes in
                            guard isManualNotesEditable else { return }
                            saveManualNotes(meetingID: meeting.id, notes: notes)
                        }
                    )
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else if isEditingNotes {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                contentToolbar(for: meeting)

                TextEditor(text: $editableNotes)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(MuesliTheme.spacing24)
                    .background(MuesliTheme.backgroundBase)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: editableNotes) { _, _ in
                        debounceSaveNotes(meetingID: meeting.id)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if isEditingTranscript {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                contentToolbar(for: meeting)

                TextEditor(text: $editableTranscript)
                    .font(.system(size: 14))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(MuesliTheme.spacing24)
                    .background(MuesliTheme.backgroundBase)
                    .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: editableTranscript) { _, _ in
                        debounceSaveTranscript(meetingID: meeting.id)
                    }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                contentToolbar(for: meeting)

                ZStack(alignment: .topLeading) {
                    MeetingNotesView(markdown: Self.notesContent(for: meeting))
                        .opacity(documentMode == .notes ? 1 : 0)
                        .allowsHitTesting(documentMode == .notes)
                        .accessibilityHidden(documentMode != .notes)

                    MeetingTranscriptView(transcript: meeting.rawTranscript)
                        .opacity(documentMode == .transcript ? 1 : 0)
                        .allowsHitTesting(documentMode == .transcript)
                        .accessibilityHidden(documentMode != .transcript)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 1080, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var documentModePicker: some View {
        Picker("", selection: $documentMode) {
            Text(String(localized: "meeting_detail.document_mode.notes", defaultValue: "Notes", bundle: .module, comment: "Document mode label for notes view")).tag(MeetingDocumentMode.notes)
            Text(String(localized: "meeting_detail.document_mode.transcript", defaultValue: "Transcript", bundle: .module, comment: "Document mode label for transcript view")).tag(MeetingDocumentMode.transcript)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 220)
        .disabled(isEditingNotes || isEditingTranscript)
    }

    private var recordingModePicker: some View {
        Picker("", selection: $recordingMode) {
            Text(String(localized: "meeting_detail.recording_mode.live-notes", defaultValue: "Notes", bundle: .module, comment: "Recording mode label for notes mode")).tag(RecordingContentMode.notes)
            Text(String(localized: "meeting_detail.recording_mode.live", defaultValue: "Live", bundle: .module, comment: "Recording mode label for live mode")).tag(RecordingContentMode.live)
        }
        .pickerStyle(.segmented)
        .tint(MuesliTheme.accent)
        .frame(width: 180)
    }

    private func showsManualNotesEditor(for meeting: MeetingRecord) -> Bool {
        switch meeting.status {
        case .recording, .processing, .noteOnly, .failed:
            return true
        case .completed:
            return false
        }
    }

    private func canEditManualNotes(for meeting: MeetingRecord) -> Bool {
        meeting.status == .recording || meeting.status == .noteOnly || meeting.status == .failed
    }

    private func isPreparingThisMeeting(_ meeting: MeetingRecord) -> Bool {
        meeting.status == .recording
            && appState.isMeetingStarting
            && !appState.isMeetingRecording
    }

    @ViewBuilder
    private func compactHeaderActions(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            resumeChooserIfAvailable(for: meeting)
            exportMenu(for: meeting)

            if isSummarizing {
                ProgressView()
                    .controlSize(.small)
                    .help(String(localized: "meeting_detail.header.summarizing_meeting_help", defaultValue: "Summarizing meeting", bundle: .module, comment: "Header help text shown while meeting summary is generating"))
            }

            if isEditingNotes || isEditingTranscript {
                editButton(for: meeting)
            } else {
                compactMoreActionsMenu(for: meeting, appliedTemplate: appliedTemplate)
            }
        }
    }

    private func beginSummary(for meeting: MeetingRecord) {
        guard !isSummarizing else { return }
        isSummarizing = true
        let completion: (Result<Void, Error>) -> Void = { [meeting] result in
            isSummarizing = false
            switch result {
            case .success:
                if let updated = controller.meeting(id: meeting.id) {
                    syncLocalState(with: updated)
                }
            case .failure(let error):
                syncPendingTemplateSelectionIfNeeded(
                    for: controller.meeting(id: meeting.id) ?? meeting
                )
                summaryErrorMessage = error.localizedDescription
            }
        }
        if hasPendingTemplateChange(for: meeting) {
            controller.applyMeetingTemplate(id: pendingTemplateID, to: meeting, completion: completion)
        } else {
            controller.resummarize(meeting: meeting, completion: completion)
        }
    }

    @ViewBuilder
    private func editButton(for meeting: MeetingRecord) -> some View {
        iconButton(
            isEditingNotes || isEditingTranscript ? "checkmark.circle" : "pencil",
            label: editButtonLabel
        ) {
            toggleEditing(for: meeting)
        }
        .disabled(isRetranscribing && !isEditingNotes && !isEditingTranscript)
    }

    private func toggleEditing(for meeting: MeetingRecord) {
        if isEditingNotes {
            notesSaveTask?.cancel()
            notesSaveTask = nil
            controller.updateMeetingNotes(id: meeting.id, notes: editableNotes)
            isEditingNotes = false
        } else if isEditingTranscript {
            guard !isRetranscribing else { return }
            transcriptSaveTask?.cancel()
            transcriptSaveTask = nil
            let shouldPromptForResummary = Self.shouldPromptForTranscriptResummary(
                hadStructuredNotes: transcriptEditHadStructuredNotes,
                originalTranscript: transcriptEditOriginalTranscript,
                editedTranscript: editableTranscript
            )
            controller.updateMeetingTranscript(id: meeting.id, transcript: editableTranscript)
            isEditingTranscript = false
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
            if shouldPromptForResummary {
                transcriptResummaryPromptMeetingID = meeting.id
            }
        } else if documentMode == .transcript {
            editableTranscript = meeting.rawTranscript
            transcriptEditOriginalTranscript = meeting.rawTranscript
            transcriptEditHadStructuredNotes = meeting.notesState == .structuredNotes
            isEditingTranscript = true
        } else {
            documentMode = .notes
            editableNotes = Self.notesContent(for: meeting)
            isEditingNotes = true
        }
    }

    @ViewBuilder
    private func retranscribeAction(for meeting: MeetingRecord) -> some View {
        if meeting.savedRecordingPath != nil {
            if isRetranscribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "meeting_detail.actions.retranscribing", defaultValue: "Re-transcribing...", bundle: .module, comment: "Action label while retranscription is in progress"))
                        .font(.system(size: 11))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .padding(.horizontal, MuesliTheme.spacing8)
            } else {
                iconButton("arrow.clockwise", label: String(localized: "meeting_detail.actions.retranscribe", defaultValue: "Re-transcribe", bundle: .module, comment: "Action label to start retranscribing a meeting")) {
                    startRetranscription(for: meeting)
                }
                .disabled(meeting.status == .recording || meeting.status == .processing || isEditingNotes || isEditingTranscript)
            }
        }
    }

    private func startRetranscription(for meeting: MeetingRecord) {
        isRetranscribing = true
        controller.retranscribe(meeting: meeting) { [meeting] result in
            isRetranscribing = false
            switch result {
            case .success:
                if let updated = controller.meeting(id: meeting.id) {
                    syncLocalState(with: updated)
                }
            case .failure(let error):
                retranscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func templateMenuItems(for meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> some View {
            Button {
                pendingTemplateID = MeetingTemplates.autoID
            } label: {
                templateMenuItem(
                    title: MeetingTemplates.auto.title,
                    systemImage: MeetingTemplates.auto.icon,
                    isSelected: pendingTemplateID == MeetingTemplates.autoID
                )
            }

            Section(String(localized: "meeting_detail.templates.custom_section", defaultValue: "Built-in Templates", bundle: .module, comment: "Section title for built-in summary templates")) {
                ForEach(controller.builtInMeetingTemplates()) { template in
                    Button {
                        pendingTemplateID = template.id
                    } label: {
                        templateMenuItem(
                            title: template.title,
                            systemImage: template.icon,
                            isSelected: pendingTemplateID == template.id
                        )
                    }
                }
            }

            if !controller.customMeetingTemplates().isEmpty {
                Section(String(localized: "meeting_detail.templates.built_in_section", defaultValue: "Custom Templates", bundle: .module, comment: "Section title for custom summary templates")) {
                    ForEach(controller.customMeetingTemplates()) { template in
                        Button {
                            pendingTemplateID = template.id
                        } label: {
                            let resolved = MeetingTemplates.customDefinition(from: template)
                            templateMenuItem(
                                title: template.name,
                                systemImage: resolved.icon,
                                isSelected: pendingTemplateID == template.id
                            )
                        }
                    }
                }
            }

            Divider()

            Button(String(localized: "meeting_detail.template_menu.manage_templates", defaultValue: "Manage Templates…", bundle: .module, comment: "Menu item title to open template management")) {
                controller.showMeetingTemplatesManager()
            }
    }

    @ViewBuilder
    private func contentToolbar(for meeting: MeetingRecord) -> some View {
        HStack {
            Spacer()

            retranscribeAction(for: meeting)

            Button(action: {
                controller.copyToClipboard(activeCopyText(for: meeting))
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(copyButtonLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MuesliTheme.textPrimary)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .fill(MuesliTheme.accent.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    @ViewBuilder
    private func manualNotesToolbar(for meeting: MeetingRecord) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if canEditManualNotes(for: meeting) {
                Text(manualNotesSaveStatus.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
            }

            Spacer()

            markdownToolbarButton(systemImage: "textformat.size", label: String(localized: "meeting_detail.notes_toolbar.heading", defaultValue: "Heading", bundle: .module, comment: "Notes editor toolbar button label for heading style")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .heading)
            }
            markdownToolbarButton(systemImage: "bold", label: String(localized: "meeting_detail.notes_toolbar.bold", defaultValue: "Bold", bundle: .module, comment: "Notes editor toolbar button label for bold style")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bold)
            }
            markdownToolbarButton(systemImage: "list.bullet", label: String(localized: "meeting_detail.notes_toolbar.bullet", defaultValue: "Bullet", bundle: .module, comment: "Notes editor toolbar button label for bullet list")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .bullet)
            }
            markdownToolbarButton(systemImage: "checklist", label: String(localized: "meeting_detail.notes_toolbar.checkbox", defaultValue: "Checkbox", bundle: .module, comment: "Notes editor toolbar button label for checklist item")) {
                manualEditorCommand = MarkdownEditorCommand(kind: .checkbox)
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    @ViewBuilder
    private func statusChip(for meeting: MeetingRecord) -> some View {
        let isPreparing = isPreparingThisMeeting(meeting)
        let isPaused = meeting.status == .recording && appState.isMeetingRecordingPaused
        let label = isPreparing ? String(localized: "meeting_detail.preparation.preparing", defaultValue: "Preparing", bundle: .module, comment: "Preparation status label while resources are preparing") : isPaused ? String(localized: "meeting_detail.preparation.paused", defaultValue: "Paused", bundle: .module, comment: "Preparation status label when preparation is paused") : meeting.status.displayLabel
        let color = isPreparing || isPaused ? MuesliTheme.transcribing : meeting.status.displayColor
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
        }
        .padding(.horizontal, MuesliTheme.spacing8)
        .padding(.vertical, 6)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recordingControlGroup(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording {
            if isPreparingThisMeeting(meeting) {
                meetingPreparationControlGroup(for: meeting)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: MuesliTheme.spacing8) {
                        statusChip(for: meeting)
                        pauseResumeRecordingButton
                        stopRecordingButton
                        discardRecordingButton
                    }
                    .recordingControlsBackground()

                    VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                        statusChip(for: meeting)
                        HStack(spacing: MuesliTheme.spacing8) {
                            pauseResumeRecordingButton
                            stopRecordingButton
                            discardRecordingButton
                        }
                        .recordingControlsBackground()
                    }
                }
            }
        } else if controller.canDeleteMeeting(meeting), meeting.status == .noteOnly || meeting.status == .failed {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                deleteButton
            }
        } else {
            statusChip(for: meeting)
        }
    }

    /// The resume control only makes sense on a finished meeting when no other
    /// recording/editing workflow is active.
    @ViewBuilder
    private func resumeChooserIfAvailable(for meeting: MeetingRecord) -> some View {
        if controller.canResumeFinishedMeeting(meeting),
           !appState.isMeetingRecording,
           !appState.isMeetingStarting,
           !isEditingNotes,
           !isEditingTranscript,
           !isSummarizing,
           !isRetranscribing {
            resumeRecordingButton(for: meeting)
        }
    }

    @ViewBuilder
    private func meetingPreparationControlGroup(for meeting: MeetingRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                meetingPreparationStatus
                cancelMeetingPreparationButton
            }
            .recordingControlsBackground()

            VStack(alignment: .trailing, spacing: MuesliTheme.spacing8) {
                statusChip(for: meeting)
                HStack(spacing: MuesliTheme.spacing8) {
                    meetingPreparationStatus
                    cancelMeetingPreparationButton
                }
                .recordingControlsBackground()
            }
        }
    }

    @ViewBuilder
    private func markdownToolbarButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MuesliTheme.textSecondary)
            .frame(width: 34, height: 30)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func exportMenu(for meeting: MeetingRecord) -> some View {
        let currentContent: MeetingExportContent = documentMode == .transcript ? .transcript : .notes
        let currentLabel = documentMode == .transcript ? String(localized: "meeting_detail.export.transcript", defaultValue: "Export Transcript", bundle: .module, comment: "Export menu action title for transcript export") : String(localized: "meeting_detail.export.notes", defaultValue: "Export Notes", bundle: .module, comment: "Export menu action title for notes export")
        Menu {
            Button {
                MeetingExporter.export(meeting: meeting, content: currentContent)
            } label: {
                Label(currentLabel, systemImage: documentMode == .transcript ? "text.quote" : "doc.text")
            }
            Button {
                MeetingExporter.export(meeting: meeting, content: .fullMeeting)
            } label: {
                Label(String(localized: "meeting_detail.export.full_meeting", defaultValue: "Export Full Meeting", bundle: .module, comment: "Export menu action title for full meeting export"), systemImage: "doc.on.doc")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(localized: "meeting_detail.export.title", defaultValue: "Export", bundle: .module, comment: "Toolbar or menu title for export actions"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.accent.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isEditingNotes || isEditingTranscript)
    }

    private func compactMoreActionsMenu(
        for meeting: MeetingRecord,
        appliedTemplate: MeetingTemplateSnapshot
    ) -> some View {
        Menu {
            Menu {
                templateMenuItems(for: meeting, appliedTemplate: appliedTemplate)
            } label: {
                Label(
                    String(format: String(localized: "meeting_detail.template.current_selection", defaultValue: "Template: %@", bundle: .module, comment: "Current selected template label in meeting detail header"), "\(labelForSelection(on: meeting, appliedTemplate: appliedTemplate))"),
                    systemImage: iconName(forSelectionOn: meeting, appliedTemplate: appliedTemplate)
                )
            }

            Button {
                beginSummary(for: meeting)
            } label: {
                Label(primarySummaryActionLabel(for: meeting), systemImage: "sparkles")
            }
            .disabled(isSummarizing || isRetranscribing)

            Button {
                toggleEditing(for: meeting)
            } label: {
                Label(editButtonLabel, systemImage: "pencil")
            }
            .disabled(isRetranscribing)

            if meeting.savedRecordingPath != nil || controller.canDeleteMeeting(meeting) {
                Divider()

                if let savedRecordingPath = meeting.savedRecordingPath {
                    Button {
                        controller.revealMeetingRecordingInFinder(path: savedRecordingPath)
                    } label: {
                        Label(String(localized: "meeting_detail.menu.show_recording", defaultValue: "Show Recording", bundle: .module, comment: "Menu action title to show recording section"), systemImage: "folder")
                    }
                }

                if controller.canDeleteMeeting(meeting) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "meeting_detail.menu.delete_meeting", defaultValue: "Delete Meeting", bundle: .module, comment: "Menu action title to delete current meeting"), systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 30, height: 28)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "meeting_detail.menu.more_actions_help", defaultValue: "More actions", bundle: .module, comment: "Accessibility/help label for more actions menu"))
    }

    private func templateMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : systemImage)
                .frame(width: 12)
            Text(title)
        }
    }

    @ViewBuilder
    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .padding(.vertical, 5)
            .background(MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        iconButton("trash", label: String(localized: "common.delete", defaultValue: "Delete", bundle: .module, comment: "Common destructive action title used for delete button")) {
            showDeleteConfirmation = true
        }
    }

    private var meetingPreparationStatus: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .accessibilityLabel(String(localized: "meeting_detail.preparation.preparing_transcription_accessibility", defaultValue: "Preparing transcription", bundle: .module, comment: "Accessibility label while transcription preparation is in progress"))
            Text(appState.meetingStartStatus ?? String(localized: "meeting_detail.preparation.starts_shortly_message", defaultValue: "Meeting transcription will start shortly.", bundle: .module, comment: "Status message indicating transcription will begin soon"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 7)
        .background(MuesliTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var cancelMeetingPreparationButton: some View {
        iconButton("xmark", label: String(localized: "common.cancel", defaultValue: "Cancel", bundle: .module, comment: "Common cancel action title")) {
            controller.cancelMeetingPreparation()
        }
        .help(String(localized: "meeting_detail.preparation.cancel_help", defaultValue: "Cancel meeting preparation", bundle: .module, comment: "Accessibility/help label for canceling meeting preparation"))
    }

    private var pauseResumeRecordingButton: some View {
        let isPaused = appState.isMeetingRecordingPaused
        return Button {
            controller.toggleMeetingRecordingPause()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(isPaused ? String(localized: "meeting_detail.recording.resume", defaultValue: "Resume", bundle: .module, comment: "Recording control button title to resume recording") : String(localized: "meeting_detail.recording.pause", defaultValue: "Pause", bundle: .module, comment: "Recording control button title to pause recording"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isPaused ? Color.white : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(isPaused ? MuesliTheme.accent : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(isPaused ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(isPaused ? String(localized: "meeting_detail.recording.resume_help.primary", defaultValue: "Resume recording", bundle: .module, comment: "Primary accessibility/help label for resume recording action") : String(localized: "meeting_detail.recording.pause_help", defaultValue: "Pause recording", bundle: .module, comment: "Accessibility/help label for pause recording action"))
    }

    /// Shown on a finished meeting when no recording is active. A split control:
    /// the left segment resumes recording into this meeting artifact; the right
    /// chevron opens a menu that also offers starting a linked follow-up meeting.
    /// (Not `Menu(primaryAction:)` — with a plain custom label on macOS the
    /// chevron segment doesn't render, leaving the menu unreachable.)
    @ViewBuilder
    private func resumeRecordingButton(for meeting: MeetingRecord) -> some View {
        HStack(spacing: 1) {
            Button {
                controller.resumeFinishedMeeting(meetingID: meeting.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(localized: "meeting_detail.recording.resume_button", defaultValue: "Resume", bundle: .module, comment: "Secondary resume button title for recording controls"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, MuesliTheme.spacing12)
                .padding(.vertical, 7)
                .background(MuesliTheme.accent)
            }
            .buttonStyle(.plain)
            .help(String(localized: "meeting_detail.recording.resume_help.secondary", defaultValue: "Resume recording", bundle: .module, comment: "Secondary accessibility/help label for resume recording action"))

            Menu {
                Button {
                    controller.resumeFinishedMeeting(meetingID: meeting.id)
                } label: {
                    Label(String(localized: "meeting_detail.recording.resume_help.tertiary", defaultValue: "Resume recording", bundle: .module, comment: "Tertiary accessibility/help label for resume recording action"), systemImage: "record.circle")
                }
                Button {
                    controller.startFollowUpMeeting(fromMeetingID: meeting.id)
                } label: {
                    Label(String(localized: "meeting_detail.recording.start_follow_up", defaultValue: "Start a follow-up", bundle: .module, comment: "Button title to start a follow-up meeting from recording controls"), systemImage: "arrow.turn.down.right")
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(MuesliTheme.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .help(String(localized: "meeting_detail.recording.resume_or_follow_up_help", defaultValue: "Resume recording, or start a follow-up meeting", bundle: .module, comment: "Accessibility/help text describing resume or follow-up options"))
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var stopRecordingButton: some View {
        Button {
            if let meeting {
                flushTitleSave(meetingID: meeting.id)
            }
            controller.stopMeetingRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(localized: "meeting_detail.recording.stop", defaultValue: "Stop", bundle: .module, comment: "Recording control button title to stop recording"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
            .background(MuesliTheme.recording)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        }
        .buttonStyle(.plain)
        .disabled(!appState.isMeetingRecording)
        .help(String(localized: "meeting_detail.recording.stop_help", defaultValue: "Stop recording", bundle: .module, comment: "Accessibility/help label for stop recording action"))
    }

    private var discardRecordingButton: some View {
        iconButton("xmark", label: String(localized: "common.discard", defaultValue: "Discard", bundle: .module, comment: "Common discard action title")) {
            controller.discardMeetingWithConfirmation()
        }
    }

    /// Breadcrumb strip shown when this meeting is part of a follow-up thread:
    /// a link to the direct predecessor, total thread size, and direct follow-ups
    /// in chronological order. Root meetings show no predecessor link.
    @ViewBuilder
    private var threadBreadcrumb: some View {
        if let threadContext {
            VStack(alignment: .leading, spacing: 4) {
                if let predecessor = threadContext.predecessor {
                    threadLink(
                        icon: "arrow.turn.left.up",
                        text: String(format: String(localized: "meeting_detail.thread.follow_up_to", defaultValue: "Follow-up to: %@ · %@", bundle: .module, comment: "Thread context label showing predecessor meeting title and start time"), "\(predecessor.title)", "\(MeetingBrowserLogic.formatStartTime(predecessor.startTime))"),
                        targetID: predecessor.id
                    )
                }
                Text(String(format: String(localized: "meeting_detail.thread.count_meetings", defaultValue: "Thread · %d meetings", bundle: .module, comment: "Thread context summary label showing meeting count in thread"), threadContext.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuesliTheme.textTertiary)
                switch threadContext.successors.count {
                case 0:
                    EmptyView()
                case 1:
                    if let successor = threadContext.successors.first {
                        threadLink(
                            icon: "arrow.turn.left.down",
                            text: String(format: String(localized: "meeting_detail.thread.followed_by", defaultValue: "Followed by: %@ · %@", bundle: .module, comment: "Thread context label showing successor meeting title and start time"), "\(successor.title)", "\(MeetingBrowserLogic.formatStartTime(successor.startTime))"),
                            targetID: successor.id
                        )
                    }
                default:
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: String(localized: "meeting_detail.thread.follow_ups_count", defaultValue: "Follow-ups (%d)", bundle: .module, comment: "Section header label showing number of follow-up meetings"), threadContext.successors.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MuesliTheme.textTertiary)
                        ForEach(threadContext.successors) { successor in
                            threadLink(
                                icon: "arrow.turn.left.down",
                                text: String(format: String(localized: "meeting_detail.thread.successor_title_time", defaultValue: "%@ · %@", bundle: .module, comment: "Successor row label showing meeting title and start time"), "\(successor.title)", "\(MeetingBrowserLogic.formatStartTime(successor.startTime))"),
                                targetID: successor.id
                            )
                        }
                    }
                }
            }
        }
    }

    private func threadLink(icon: String, text: String, targetID: Int64) -> some View {
        Button {
            if appState.meetingDetailReturnDestination == .timeline {
                controller.showTimelineMeetingDocument(id: targetID)
            } else {
                controller.showMeetingDocument(id: targetID)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(MuesliTheme.accent)
        }
        .buttonStyle(.plain)
        .help(String(localized: "meeting_detail.thread_link.open_this_meeting_help", defaultValue: "Open this meeting", bundle: .module, comment: "Accessibility/help label for thread link that opens selected meeting"))
    }

    @ViewBuilder
    private func folderPill(for meeting: MeetingRecord) -> some View {
        let currentFolder = meeting.folderID.flatMap { fid in
            appState.folders.first(where: { $0.id == fid })
        }
        let hasFolder = currentFolder != nil
        Button {
            showFolderPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hasFolder ? "folder.fill" : "folder.badge.plus")
                    .font(.system(size: 10))
                Text(currentFolder?.name ?? String(localized: "meeting_detail.folder_pill.add_to_folder", defaultValue: "Add to folder", bundle: .module, comment: "Folder pill action title to add meeting to a folder"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hasFolder ? MuesliTheme.accent : MuesliTheme.textSecondary)
            .padding(.horizontal, MuesliTheme.spacing8)
            .frame(height: MeetingHeaderLayout.contextControlHeight)
            .background(hasFolder ? MuesliTheme.accentSubtle : MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(hasFolder ? Color.clear : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(hasFolder ? String(localized: "meeting_detail.folder_pill.change_folder_help", defaultValue: "Change folder", bundle: .module, comment: "Accessibility/help label for changing assigned folder") : String(localized: "meeting_detail.folder_pill.add_to_folder.help", defaultValue: "Add to folder", bundle: .module, comment: "Accessibility/help label for adding meeting to folder"))
        .popover(isPresented: $showFolderPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if !appState.folders.isEmpty {
                    ForEach(appState.folders) { folder in
                        let isActive = meeting.folderID == folder.id
                        folderPopoverRow(icon: "folder", label: folder.name, isActive: isActive) {
                            controller.moveMeeting(id: meeting.id, toFolder: isActive ? nil : folder.id)
                            showFolderPopover = false
                        }
                    }
                    Divider().padding(.vertical, 4)
                }
                folderPopoverRow(icon: "folder.badge.plus", label: String(localized: "meeting_detail.folder_pill.new_folder_row", defaultValue: "New Folder...", bundle: .module, comment: "Menu row title to create a new folder from folder picker")) {
                    showFolderPopover = false
                    newFolderName = ""
                    showNewFolderPrompt = true
                }
            }
            .padding(8)
            .frame(minWidth: 200)
        }
        .alert(String(localized: "meeting_detail.folder_pill.new_folder_title", defaultValue: "New Folder", bundle: .module, comment: "Alert title for creating a new folder"), isPresented: $showNewFolderPrompt) {
            TextField(String(localized: "meeting_detail.folder_pill.folder_name", defaultValue: "Folder name", bundle: .module, comment: "Prompt/title for entering a new folder name"), text: $newFolderName)
            Button(String(localized: "common.create", defaultValue: "Create", bundle: .module, comment: "Common create action title")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                controller.createFolderAndMoveMeeting(name: trimmed, meetingID: meeting.id)
            }
            Button(String(localized: "meeting_detail.folder_pill.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel action title in new folder alert"), role: .cancel) {}
        } message: {
            Text(String(localized: "meeting_detail.folder_pill.create_folder_description", defaultValue: "Create a new folder and move this meeting into it.", bundle: .module, comment: "Description text in new folder creation alert"))
        }
    }

    @ViewBuilder
    private func folderPopoverRow(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(label)
                    .font(MuesliTheme.callout())
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transcriptCTA: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            if hasApiKey {
                Image(systemName: "sparkles")
                    .foregroundStyle(MuesliTheme.accent)
                Text(String(format: String(localized: "meeting_detail.transcript_cta.use_primary_summary_action", defaultValue: "Use %@ to turn this raw transcript into AI meeting notes and a cleaned-up title.", bundle: .module, comment: "Call-to-action message using primary summary action label"), "\(primarySummaryActionLabel)"))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            } else {
                Image(systemName: "key.fill")
                    .foregroundStyle(MuesliTheme.accent)
                Text(String(localized: "meeting_detail.transcript_cta.add_api_key_message", defaultValue: "Add your API key in Settings to generate meeting notes", bundle: .module, comment: "Call-to-action message prompting user to add API key in settings"))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                Spacer()
                Button(String(localized: "common.open_settings", defaultValue: "Open Settings", bundle: .module, comment: "Common action title to open settings")) {
                    controller.openHistoryWindow(tab: .settings)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
    }

    @ViewBuilder
    private func activeMeetingAudioWarningBanner(for meeting: MeetingRecord) -> some View {
        if meeting.status == .recording,
           let warning = appState.activeMeetingAudioWarning,
           warning.meetingID == meeting.id {
            HStack(alignment: .top, spacing: MuesliTheme.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text(warning.message)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer(minLength: MuesliTheme.spacing8)
            }
            .padding(MuesliTheme.spacing12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var hasApiKey: Bool {
        let config = appState.config
        if appState.selectedMeetingSummaryBackend == .chatGPT {
            return appState.isChatGPTAuthenticated
        } else if appState.selectedMeetingSummaryBackend == .openAI {
            return !config.openAIAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
        } else if appState.selectedMeetingSummaryBackend == .ollama {
            return true
        } else if appState.selectedMeetingSummaryBackend == .lmStudio {
            return MeetingSummaryClient.lmStudioHasRequiredSettings(config: config)
        } else if appState.selectedMeetingSummaryBackend == .customLLM {
            return MeetingSummaryClient.customLLMHasRequiredSettings(config: config)
        } else {
            return !config.openRouterAPIKey.isEmpty || ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil
        }
    }

    private var primarySummaryActionLabel: String {
        guard let meeting else { return String(localized: "meeting_detail.transcript_cta.re_summarize", defaultValue: "Re-summarize", bundle: .module, comment: "Call-to-action button title to re-summarize meeting notes") }
        return primarySummaryActionLabel(for: meeting)
    }

    private var copyButtonLabel: String {
        String(localized: "common.copy", defaultValue: "Copy", bundle: .module, comment: "Common copy action title")
    }

    private var editButtonLabel: String {
        if isEditingNotes || isEditingTranscript {
            return String(localized: "common.done", defaultValue: "Done", bundle: .module, comment: "Common done action title")
        }
        return documentMode == .transcript ? String(localized: "meeting_detail.edit_button.edit_transcript", defaultValue: "Edit Transcript", bundle: .module, comment: "Edit button title when transcript is active") : String(localized: "meeting_detail.edit_button.edit_notes", defaultValue: "Edit Notes", bundle: .module, comment: "Edit button title when notes are active")
    }

    private func primarySummaryActionLabel(for meeting: MeetingRecord) -> String {
        hasPendingTemplateChange(for: meeting) ? String(localized: "meeting_detail.summary.primary_action.apply_template", defaultValue: "Apply Template", bundle: .module, comment: "Primary summary action title to apply template") : String(localized: "meeting_detail.summary.primary_action.re_summarize", defaultValue: "Re-summarize", bundle: .module, comment: "Primary summary action title to regenerate summary")
    }

    private func activeCopyText(for meeting: MeetingRecord) -> String {
        switch documentMode {
        case .notes:
            return isEditingNotes ? editableNotes : Self.notesContent(for: meeting)
        case .transcript:
            return isEditingTranscript ? editableTranscript : meeting.rawTranscript
        }
    }

    private func isRawTranscript(_ meeting: MeetingRecord) -> Bool {
        meeting.notesState != .structuredNotes
    }

    private func hasPendingTemplateChange(for meeting: MeetingRecord) -> Bool {
        resolvedPendingTemplateDefinition(for: meeting).id != controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func labelForSelection(on meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return appliedTemplate.name
        }
        return resolvedPendingTemplateDefinition(for: meeting).title
    }

    private func iconName(forSelectionOn meeting: MeetingRecord, appliedTemplate: MeetingTemplateSnapshot) -> String {
        if pendingTemplateID == appliedTemplate.id {
            return iconName(for: appliedTemplate)
        }
        return resolvedPendingTemplateDefinition(for: meeting).icon
    }

    private func iconName(for snapshot: MeetingTemplateSnapshot) -> String {
        switch snapshot.kind {
        case .auto:
            return MeetingTemplates.auto.icon
        case .builtin, .custom:
            return MeetingTemplates.resolveDefinition(
                id: snapshot.id,
                customTemplates: appState.config.customMeetingTemplates
            ).icon
        }
    }

    static func notesContent(for meeting: MeetingRecord) -> String {
        if meeting.status == .noteOnly {
            return meeting.manualNotes
        }
        if meeting.notesState != .structuredNotes {
            return "# \(meeting.title)\n\n## Raw Transcript\n\n\(meeting.rawTranscript)"
        }
        return meeting.formattedNotes
    }

    private static func defaultDocumentMode(for meeting: MeetingRecord) -> MeetingDocumentMode {
        if meeting.status == .noteOnly || meeting.status == .recording || meeting.status == .processing || meeting.status == .failed {
            return .notes
        }
        return meeting.notesState == .structuredNotes
            ? MeetingDocumentMode.notes
            : MeetingDocumentMode.transcript
    }

    private func debounceSaveTitle(meetingID: Int64) {
        titleSaveTask?.cancel()
        let title = editableTitle
        let c = controller
        c.cacheMeetingTitle(id: meetingID, title: title)
        let item = DispatchWorkItem { c.updateMeetingTitle(id: meetingID, title: title) }
        titleSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func flushTitleSave(meetingID: Int64) {
        titleSaveTask?.cancel()
        titleSaveTask = nil
        controller.updateMeetingTitle(id: meetingID, title: editableTitle)
    }

    private func debounceSaveNotes(meetingID: Int64) {
        notesSaveTask?.cancel()
        let notes = editableNotes
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingNotes(id: meetingID, notes: notes) }
        notesSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func debounceSaveTranscript(meetingID: Int64) {
        transcriptSaveTask?.cancel()
        let transcript = editableTranscript
        let c = controller
        let item = DispatchWorkItem { c.updateMeetingTranscript(id: meetingID, transcript: transcript) }
        transcriptSaveTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private func saveManualNotes(meetingID: Int64, notes: String) {
        manualNotesSaveStatus = .saving
        controller.cacheMeetingManualNotes(id: meetingID, notes: notes)
        scheduleManualNotesSaveStatusCheck(meetingID: meetingID, notes: notes)
    }

    private func scheduleManualNotesSaveStatusCheck(meetingID: Int64, notes: String) {
        manualNotesSaveStatusTask?.cancel()
        let item = DispatchWorkItem {
            guard loadedMeetingID == meetingID else { return }
            guard editableManualNotes == notes else { return }
            if controller.hasPersistedMeetingManualNotes(id: meetingID, notes: notes) {
                manualNotesSaveStatus = .saved
            }
        }
        manualNotesSaveStatusTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    private var summaryErrorBinding: Binding<Bool> {
        Binding(
            get: { summaryErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    summaryErrorMessage = nil
                }
            }
        )
    }

    private var retranscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { retranscriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    retranscriptionErrorMessage = nil
                }
            }
        )
    }

    private var transcriptResummaryPromptBinding: Binding<Bool> {
        Binding(
            get: { transcriptResummaryPromptMeetingID != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptResummaryPromptMeetingID = nil
                }
            }
        )
    }

    private static func shouldPromptForTranscriptResummary(
        hadStructuredNotes: Bool,
        originalTranscript: String?,
        editedTranscript: String
    ) -> Bool {
        guard hadStructuredNotes, let originalTranscript else { return false }
        return originalTranscript != editedTranscript
    }

    private func resummarizeAfterTranscriptEdit() {
        guard let meetingID = transcriptResummaryPromptMeetingID else { return }
        transcriptResummaryPromptMeetingID = nil
        guard let updatedMeeting = controller.meeting(id: meetingID) else { return }
        isSummarizing = true
        controller.resummarize(meeting: updatedMeeting) { [meetingID] result in
            isSummarizing = false
            switch result {
            case .success:
                if let refreshed = controller.meeting(id: meetingID) {
                    syncLocalState(with: refreshed)
                }
            case .failure(let error):
                summaryErrorMessage = error.localizedDescription
            }
        }
    }

    private func resolvedPendingTemplateDefinition(for meeting: MeetingRecord) -> MeetingTemplateDefinition {
        if let resolved = MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) {
            return resolved
        }
        return MeetingTemplates.resolveDefinition(
            id: controller.meetingTemplateSnapshot(for: meeting).id,
            customTemplates: appState.config.customMeetingTemplates
        )
    }

    private func syncPendingTemplateSelectionIfNeeded(for meeting: MeetingRecord?) {
        guard let meeting else { return }
        guard MeetingTemplates.resolveExactDefinition(
            id: pendingTemplateID,
            customTemplates: appState.config.customMeetingTemplates
        ) == nil else {
            return
        }
        pendingTemplateID = controller.meetingTemplateSnapshot(for: meeting).id
    }

    private func syncLocalState(with meeting: MeetingRecord?) {
        let previousMeetingID = loadedMeetingID
        let meetingChanged = previousMeetingID != meeting?.id
        loadedMeetingID = meeting?.id
        threadContext = meeting.flatMap { controller.meetingThreadContext(for: $0.id) }
        editableTitle = meeting?.title ?? ""
        if meetingChanged || !isEditingNotes {
            editableNotes = meeting.map { Self.notesContent(for: $0) } ?? ""
        }
        if meetingChanged || !isEditingTranscript {
            editableTranscript = meeting?.rawTranscript ?? ""
        }
        if meetingChanged {
            editableManualNotes = meeting?.manualNotes ?? ""
            manualNotesSaveStatus = .saved
            transcriptResummaryPromptMeetingID = nil
            transcriptEditOriginalTranscript = nil
            transcriptEditHadStructuredNotes = false
        } else {
            syncManualNotesState(with: meeting)
        }
        pendingTemplateID = meeting.map { controller.meetingTemplateSnapshot(for: $0).id } ?? controller.defaultMeetingTemplate().id
        if meetingChanged {
            documentMode = meeting.map(Self.defaultDocumentMode(for:)) ?? .notes
            isEditingNotes = false
            isEditingTranscript = false
            showFolderPopover = false
            showNewFolderPrompt = false
            newFolderName = ""
        }
    }

    private func syncManualNotesState(with meeting: MeetingRecord?) {
        let persistedManualNotes = meeting?.manualNotes ?? ""
        if manualNotesSaveStatus == .saving, editableManualNotes != persistedManualNotes {
            return
        }
        editableManualNotes = persistedManualNotes
        manualNotesSaveStatus = .saved
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return String(format: String(localized: "meeting_detail.duration.hours_minutes", defaultValue: "%dh %dm", bundle: .module, comment: "Duration label shown as hours and minutes"), rounded / 3600, (rounded % 3600) / 60)
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? String(format: String(localized: "meeting_detail.duration.minutes_only", defaultValue: "%dm", bundle: .module, comment: "Duration label shown as minutes only"), m) : String(format: String(localized: "meeting_detail.duration.minutes_seconds", defaultValue: "%dm %ds", bundle: .module, comment: "Duration label shown as minutes and seconds"), m, s)
        }
        return String(format: String(localized: "meeting_detail.duration.seconds_only", defaultValue: "%ds", bundle: .module, comment: "Duration label shown as seconds only"), rounded)
    }
}

private extension View {
    func recordingControlsBackground() -> some View {
        padding(5)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
    }
}

private struct MarqueeTitleTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onTextChange: () -> Void

    @State private var isHovering = false
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0
    @State private var marqueeRunID = UUID()
    @FocusState private var isTitleFocused: Bool

    private let titleFont = Font.system(size: 30, weight: .bold)

    var body: some View {
        ZStack(alignment: .leading) {
            TextField(String(localized: "meeting_detail.title_editor.meeting_title.primary", defaultValue: "Meeting Title", bundle: .module, comment: "Primary placeholder/title for meeting title editor"), text: $text)
                .font(titleFont)
                .foregroundStyle(MuesliTheme.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .opacity(shouldShowMarquee ? 0 : 1)
                .focused($isTitleFocused)
                .onSubmit(onSubmit)
                .onChange(of: text) { _, _ in
                    onTextChange()
                    restartMarqueeIfNeeded()
                }
                .onChange(of: isTitleFocused) { _, _ in
                    restartMarqueeIfNeeded()
                }

            Text(text.isEmpty ? String(localized: "meeting_detail.title_editor.meeting_title.secondary", defaultValue: "Meeting Title", bundle: .module, comment: "Secondary placeholder/title for meeting title editor") : text)
                .font(titleFont)
                .fontWeight(.bold)
                .foregroundStyle(MuesliTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: marqueeOffset)
                .opacity(shouldShowMarquee ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TitleContainerWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .overlay(
            Text(text.isEmpty ? String(localized: "meeting_detail.title_editor.meeting_title.tertiary", defaultValue: "Meeting Title", bundle: .module, comment: "Tertiary placeholder/title for meeting title editor") : text)
                .font(titleFont)
                .fontWeight(.bold)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TitleContentWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
                .allowsHitTesting(false)
        )
        .onTapGesture {
            isTitleFocused = true
        }
        .onPreferenceChange(TitleContainerWidthPreferenceKey.self) { width in
            guard abs(containerWidth - width) > 0.5 else { return }
            containerWidth = width
            restartMarqueeIfNeeded()
        }
        .onPreferenceChange(TitleContentWidthPreferenceKey.self) { width in
            guard abs(contentWidth - width) > 0.5 else { return }
            contentWidth = width
            restartMarqueeIfNeeded()
        }
        .onHover { hovering in
            isHovering = hovering
            restartMarqueeIfNeeded()
        }
    }

    private var overflowDistance: CGFloat {
        max(contentWidth - containerWidth, 0)
    }

    private var shouldShowMarquee: Bool {
        containerWidth > 0 && isHovering && !isTitleFocused && overflowDistance > 24
    }

    private func restartMarqueeIfNeeded() {
        guard shouldShowMarquee else {
            if marqueeOffset != 0 {
                let runID = UUID()
                marqueeRunID = runID
                withAnimation(.easeOut(duration: 0.18)) {
                    marqueeOffset = 0
                }
            }
            return
        }

        let runID = UUID()
        marqueeRunID = runID

        marqueeOffset = 0
        let distance = overflowDistance + 28
        let duration = min(max(Double(distance) / 42.0, 3.0), 12.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard marqueeRunID == runID, shouldShowMarquee else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                marqueeOffset = -distance
            }
        }
    }
}

private struct TitleContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TitleContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranscriptChatMessage: Identifiable, Equatable {
    let id: Int
    let timestamp: String?
    let speaker: String?
    let text: String

    var isUser: Bool {
        speaker?.localizedCaseInsensitiveCompare("You") == .orderedSame
    }

    static func messages(from transcript: String, startingAt firstID: Int = 0) -> [TranscriptChatMessage] {
        let normalized = transcript.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var messages: [TranscriptChatMessage] = []
        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parsed = parseLine(line, id: firstID + messages.count)
            messages.append(parsed)
        }

        return messages
    }

    private static func parseLine(_ line: String, id: Int) -> TranscriptChatMessage {
        if line.hasPrefix("["),
           let timestampEnd = line.firstIndex(of: "]") {
            let timestamp = String(line[line.index(after: line.startIndex)..<timestampEnd])
            let remainderStart = line.index(after: timestampEnd)
            let remainder = line[remainderStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let speakerText = splitSpeakerAndText(remainder)
            return TranscriptChatMessage(
                id: id,
                timestamp: timestamp.isEmpty ? nil : timestamp,
                speaker: speakerText.speaker,
                text: speakerText.text
            )
        }

        let speakerText = splitSpeakerAndText(line)
        return TranscriptChatMessage(
            id: id,
            timestamp: nil,
            speaker: speakerText.speaker,
            text: speakerText.text
        )
    }

    private static func splitSpeakerAndText(_ text: String) -> (speaker: String?, text: String) {
        guard let separator = text.firstIndex(of: ":") else {
            return (nil, text)
        }

        let candidate = text[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelySpeakerLabel(candidate) else {
            return (nil, text)
        }

        let bodyStart = text.index(after: separator)
        let body = text[bodyStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidate, body.isEmpty ? text : body)
    }

    private static func isLikelySpeakerLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 32 else { return false }
        if label.localizedCaseInsensitiveCompare("You") == .orderedSame { return true }
        if label.localizedCaseInsensitiveCompare(String(localized: "meeting_detail.transcript.speaker_others", defaultValue: "Others", bundle: .module, comment: "Transcript speaker label for other participants")) == .orderedSame { return true }
        if label.range(of: #"^Speaker\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }
}

private struct MeetingTranscriptView: View {
    let transcript: String
    @State private var messages: [TranscriptChatMessage]

    init(transcript: String) {
        self.transcript = transcript
        _messages = State(initialValue: TranscriptChatMessage.messages(from: transcript))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                if messages.isEmpty {
                    Text(String(localized: "meeting_detail.transcript.no_transcript_available", defaultValue: "No transcript available", bundle: .module, comment: "Empty state text when transcript content is unavailable"))
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(maxWidth: 860, alignment: .leading)
                        .padding(MuesliTheme.spacing24)
                } else {
                    ForEach(messages) { message in
                        TranscriptChatBubble(message: message)
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, MuesliTheme.spacing24)
            .padding(.vertical, MuesliTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: transcript) { _, newTranscript in
            messages = TranscriptChatMessage.messages(from: newTranscript)
        }
    }
}

struct TranscriptChatBubble: View {
    let message: TranscriptChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: MuesliTheme.spacing8) {
            if message.isUser {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let metadata = metadata {
                    Text(metadata)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .textSelection(.enabled)
                }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 8)
            .background(message.isUser ? MuesliTheme.accent.opacity(0.18) : MuesliTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(message.isUser ? MuesliTheme.accent.opacity(0.25) : MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .frame(maxWidth: 680, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer(minLength: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var metadata: String? {
        switch (message.speaker, message.timestamp) {
        case let (speaker?, timestamp?):
            return "\(speaker) \(timestamp)"
        case let (speaker?, nil):
            return speaker
        case let (nil, timestamp?):
            return timestamp
        case (nil, nil):
            return nil
        }
    }
}
