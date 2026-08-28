import SwiftUI

struct TranscriptCleanupPromptsManagerView: View {
    let appState: AppState
    let controller: MuesliController
    let onClose: () -> Void

    @State private var isCreatingPrompt = false
    @State private var editingPromptID: String?
    @State private var draftPromptName = ""
    @State private var draftPrompt = ""
    @State private var nameValidationMessage: String?
    @State private var showPromptValidationError = false
    @State private var promptToDelete: CustomTranscriptCleanupPrompt?

    private var activePromptID: String {
        appState.config.activeTranscriptCleanupPromptId
    }

    private var builtInPresets: [TranscriptCleanupPromptPreset] {
        TranscriptCleanupPrompts.builtIns
    }

    private var customPresets: [CustomTranscriptCleanupPrompt] {
        appState.config.customTranscriptCleanupPrompts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
                    presetSection(title: String(localized: "transcript_cleanup.prompts.section.built_in", defaultValue: "Built-in Presets", bundle: .module, comment: "Section title for built-in cleanup prompt presets.")) {
                        VStack(spacing: MuesliTheme.spacing8) {
                            ForEach(builtInPresets) { preset in
                                builtInPresetRow(preset)
                            }
                        }
                    }

                    presetSection(title: String(localized: "transcript_cleanup.prompts.section.custom", defaultValue: "Custom Presets", bundle: .module, comment: "Section title for user-created cleanup prompt presets.")) {
                        if customPresets.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: MuesliTheme.spacing8) {
                                ForEach(customPresets) { preset in
                                    customPresetRow(preset)
                                }
                            }
                        }
                    }

                    if isCreatingPrompt || editingPromptID != nil {
                        promptEditor
                    }
                }
                .padding(.bottom, MuesliTheme.spacing4)
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(minWidth: 760, minHeight: 560)
        .background(MuesliTheme.backgroundBase)
        .alert(
            String(format: String(localized: "transcript_cleanup.prompts.delete.confirmation_title", defaultValue: "Delete \"%@\"?", bundle: .module, comment: "Confirmation alert title for deleting a cleanup preset by name."), "\(promptToDelete?.name ?? "")"),
            isPresented: Binding(
                get: { promptToDelete != nil },
                set: { if !$0 { promptToDelete = nil } }
            )
        ) {
            Button(String(localized: "transcript_cleanup.prompts.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel action title in cleanup prompt manager."), role: .cancel) {
                promptToDelete = nil
            }
            Button(String(localized: "transcript_cleanup.prompts.delete", defaultValue: "Delete", bundle: .module, comment: "Delete action title for cleanup preset."), role: .destructive) {
                guard let preset = promptToDelete else { return }
                controller.deleteTranscriptCleanupPrompt(id: preset.id)
                if editingPromptID == preset.id {
                    resetPromptEditor()
                }
                promptToDelete = nil
            }
        } message: {
            Text(String(localized: "transcript_cleanup.prompts.delete_warning", defaultValue: "This prompt preset will be permanently removed. Existing dictations are not affected.", bundle: .module, comment: "Warning message shown before deleting a cleanup preset."))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "transcript_cleanup.prompts.header.title", defaultValue: "Manage Cleanup Presets", bundle: .module, comment: "Main header title for cleanup presets manager."))
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Text(String(localized: "transcript_cleanup.prompts.header.subtitle", defaultValue: "Create reusable prompts for local and cloud dictation cleanup.", bundle: .module, comment: "Subtitle describing purpose of cleanup presets manager."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: MuesliTheme.spacing8) {
                if isCreatingPrompt || editingPromptID != nil {
                    actionButton(String(localized: "transcript_cleanup.prompts.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel action title in cleanup prompt manager."), systemImage: "xmark") {
                        resetPromptEditor()
                    }
                } else {
                    actionButton(String(localized: "transcript_cleanup.prompts.new_preset", defaultValue: "New preset", bundle: .module, comment: "Action title to create a new cleanup preset."), systemImage: "plus") {
                        beginCreatingPrompt()
                    }
                }

                actionButton(String(localized: "transcript_cleanup.prompts.done", defaultValue: "Done", bundle: .module, comment: "Action title to finish managing cleanup presets."), systemImage: "checkmark") {
                    onClose()
                }
                .disabled(isEditingPromptInProgress)
                .opacity(isEditingPromptInProgress ? 0.55 : 1)
                .help(isEditingPromptInProgress ? String(localized: "transcript_cleanup.prompts.help.finish_or_cancel_before_closing", defaultValue: "Finish or cancel prompt editing before closing.", bundle: .module, comment: "Help text explaining editing must be finished before closing manager.") : String(localized: "transcript_cleanup.prompts.help.close_manager", defaultValue: "Close prompt manager", bundle: .module, comment: "Help text label for closing prompt manager action."))
            }
        }
    }

    private func presetSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            Text(title.uppercased())
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textTertiary)
            content()
        }
    }

    private var emptyState: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(String(localized: "transcript_cleanup.prompts.empty_state.none", defaultValue: "No custom cleanup presets yet.", bundle: .module, comment: "Empty state text when no custom cleanup presets exist."))
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .padding(.horizontal, MuesliTheme.spacing12)
        .padding(.vertical, 10)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func builtInPresetRow(_ preset: TranscriptCleanupPromptPreset) -> some View {
        presetRow(
            name: preset.name,
            prompt: preset.prompt,
            isActive: activePromptID == preset.id,
            systemImage: "sparkles"
        ) {
            actionButton(String(localized: "transcript_cleanup.prompts.use", defaultValue: "Use", bundle: .module, comment: "Action title to apply a cleanup preset."), systemImage: "checkmark") {
                controller.selectTranscriptCleanupPrompt(id: preset.id)
            }
            .disabled(activePromptID == preset.id)

            actionButton(String(localized: "transcript_cleanup.prompts.duplicate", defaultValue: "Duplicate", bundle: .module, comment: "Action title to duplicate a cleanup preset."), systemImage: "doc.on.doc") {
                beginDuplicatingPrompt(name: preset.name, prompt: preset.prompt)
            }
        }
    }

    private func customPresetRow(_ preset: CustomTranscriptCleanupPrompt) -> some View {
        presetRow(
            name: preset.name,
            prompt: preset.prompt,
            isActive: activePromptID == preset.id,
            systemImage: "text.badge.checkmark"
        ) {
            actionButton(String(localized: "transcript_cleanup.prompts.use", defaultValue: "Use", bundle: .module, comment: "Action title to apply a cleanup preset."), systemImage: "checkmark") {
                controller.selectTranscriptCleanupPrompt(id: preset.id)
            }
            .disabled(activePromptID == preset.id)

            actionButton(String(localized: "transcript_cleanup.prompts.edit", defaultValue: "Edit", bundle: .module, comment: "Action title to edit a cleanup preset."), systemImage: "pencil") {
                beginEditingPrompt(preset)
            }

            actionButton(String(localized: "transcript_cleanup.prompts.delete", defaultValue: "Delete", bundle: .module, comment: "Action title to delete a cleanup preset."), systemImage: "trash", role: .destructive) {
                promptToDelete = preset
            }
        }
    }

    private func presetRow<Actions: View>(
        name: String,
        prompt: String,
        isActive: Bool,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(name)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                        if isActive {
                            Text(String(localized: "transcript_cleanup.prompts.status.active", defaultValue: "Active", bundle: .module, comment: "Status label indicating currently active cleanup preset."))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MuesliTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MuesliTheme.accentSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        }
                    }
                    Text(prompt)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: MuesliTheme.spacing8) {
                    actions()
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(isActive ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(isCreatingPrompt ? String(localized: "transcript_cleanup.prompts.editor.title.new", defaultValue: "New preset", bundle: .module, comment: "Editor title when creating a new cleanup preset.") : String(localized: "transcript_cleanup.prompts.editor.title.edit", defaultValue: "Edit preset", bundle: .module, comment: "Editor title when editing an existing cleanup preset."))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "transcript_cleanup.prompts.editor.name_label", defaultValue: "Name", bundle: .module, comment: "Label for preset name field in editor."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextField(String(localized: "transcript_cleanup.prompts.editor.name_placeholder", defaultValue: "Context-aware cleanup", bundle: .module, comment: "Placeholder text for preset name input."), text: $draftPromptName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                nameValidationMessage == nil ? .clear : MuesliTheme.recording.opacity(0.75),
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftPromptName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            nameValidationMessage = nil
                        }
                    }
                if let nameValidationMessage {
                    Text(nameValidationMessage)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "transcript_cleanup.prompts.editor.prompt_label", defaultValue: "Prompt", bundle: .module, comment: "Label for prompt instructions editor field."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextEditor(text: $draftPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(MuesliTheme.spacing8)
                    .background(MuesliTheme.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(
                                showPromptValidationError ? MuesliTheme.recording.opacity(0.75) : MuesliTheme.surfaceBorder,
                                lineWidth: 1
                            )
                    )
                    .onChange(of: draftPrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text(String(localized: "transcript_cleanup.prompts.editor.instructions", defaultValue: "Enter cleanup instructions for this preset.", bundle: .module, comment: "Instructional text shown in cleanup preset editor."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingPrompt ? String(localized: "transcript_cleanup.prompts.create_preset", defaultValue: "Create preset", bundle: .module, comment: "Button title to create a new cleanup preset.") : String(localized: "transcript_cleanup.prompts.save_changes", defaultValue: "Save changes", bundle: .module, comment: "Button title to save edits to an existing cleanup preset."),
                    systemImage: isCreatingPrompt ? "plus.circle" : "checkmark.circle"
                ) {
                    savePromptEditor()
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.surfacePrimary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func beginCreatingPrompt() {
        isCreatingPrompt = true
        editingPromptID = nil
        draftPromptName = ""
        draftPrompt = ""
        clearValidationErrors()
    }

    private func beginDuplicatingPrompt(name: String, prompt: String) {
        isCreatingPrompt = true
        editingPromptID = nil
        draftPromptName = suggestedUniqueName(for: String(format: String(localized: "transcript_cleanup.prompts.duplicate_name", defaultValue: "%@ Copy", bundle: .module, comment: "Generated name for duplicated cleanup preset."), "\(name)"))
        draftPrompt = prompt
        clearValidationErrors()
    }

    private func beginEditingPrompt(_ preset: CustomTranscriptCleanupPrompt) {
        isCreatingPrompt = false
        editingPromptID = preset.id
        draftPromptName = preset.name
        draftPrompt = preset.prompt
        clearValidationErrors()
    }

    private func resetPromptEditor() {
        isCreatingPrompt = false
        editingPromptID = nil
        draftPromptName = ""
        draftPrompt = ""
        clearValidationErrors()
    }

    private func savePromptEditor() {
        let trimmedName = draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        nameValidationMessage = nil
        showPromptValidationError = trimmedPrompt.isEmpty
        if trimmedName.isEmpty {
            nameValidationMessage = String(localized: "transcript_cleanup_prompts.validation.enter_preset_name", defaultValue: "Enter a preset name.", bundle: .module, comment: "Validation message when preset name is missing.")
        } else if presetNameExists(trimmedName, excludingID: editingPromptID) {
            nameValidationMessage = String(localized: "transcript_cleanup_prompts.validation.unique_preset_name", defaultValue: "Use a unique preset name.", bundle: .module, comment: "Validation message when preset name is not unique.")
        }
        guard nameValidationMessage == nil, !trimmedPrompt.isEmpty else { return }

        if let editingPromptID {
            controller.updateTranscriptCleanupPrompt(
                id: editingPromptID,
                name: trimmedName,
                prompt: trimmedPrompt
            )
        } else {
            controller.createTranscriptCleanupPrompt(
                name: trimmedName,
                prompt: trimmedPrompt
            )
        }
        resetPromptEditor()
    }

    private var isEditingPromptInProgress: Bool {
        isCreatingPrompt || editingPromptID != nil
    }

    private func clearValidationErrors() {
        nameValidationMessage = nil
        showPromptValidationError = false
    }

    private func presetNameExists(_ name: String, excludingID: String?) -> Bool {
        let normalizedName = normalizedPresetName(name)
        if builtInPresets.contains(where: { normalizedPresetName($0.name) == normalizedName }) {
            return true
        }
        return customPresets.contains { preset in
            preset.id != excludingID && normalizedPresetName(preset.name) == normalizedName
        }
    }

    private func suggestedUniqueName(for baseName: String) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackBase = trimmedBase.isEmpty ? String(localized: "transcript_cleanup_prompts.fallback_base_name", defaultValue: "Custom Cleanup", bundle: .module, comment: "Fallback base name for generated custom cleanup preset names.") : trimmedBase
        if !presetNameExists(fallbackBase, excludingID: nil) {
            return fallbackBase
        }
        for suffix in 2...99 {
            let candidate = "\(fallbackBase) \(suffix)"
            if !presetNameExists(candidate, excludingID: nil) {
                return candidate
            }
        }
        return "\(fallbackBase) \(UUID().uuidString.prefix(4))"
    }

    private func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        return Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .frame(height: 28)
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
}
