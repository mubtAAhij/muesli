import SwiftUI
import MuesliCore

struct MeetingTemplatesManagerView: View {
    let appState: AppState
    let controller: MuesliController
    let onClose: () -> Void

    @State private var isCreatingTemplate = false
    @State private var editingTemplateID: String?
    @State private var draftTemplateName = ""
    @State private var draftTemplatePrompt = ""
    @State private var draftTemplateIcon = MeetingTemplates.customIconFallback
    @State private var showNameValidationError = false
    @State private var showPromptValidationError = false
    @State private var templateToDelete: CustomMeetingTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "meeting_templates_manager.title", defaultValue: "Manage Templates", comment: "Title for meeting templates manager view."))
                        .font(MuesliTheme.title2())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(String(localized: "meeting_templates_manager.subtitle", defaultValue: "Create reusable prompt-based note formats for meetings.", comment: "Subtitle describing purpose of meeting templates manager."))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: MuesliTheme.spacing8) {
                    if isCreatingTemplate || editingTemplateID != nil {
                        actionButton(String(localized: "meeting_templates_manager.toolbar.cancel", defaultValue: "Cancel", comment: "Toolbar button title to cancel template editing."), systemImage: "xmark") {
                            resetTemplateEditor()
                        }
                    } else {
                        actionButton(String(localized: "meeting_templates_manager.toolbar.new_template", defaultValue: "New template", comment: "Toolbar button title to start creating a new meeting template."), systemImage: "plus") {
                            beginCreatingTemplate()
                        }
                    }

                    actionButton("Done", systemImage: "checkmark") {
                        onClose()
                    }
                    .disabled(isEditingTemplateInProgress)
                    .opacity(isEditingTemplateInProgress ? 0.55 : 1)
                    .help(isEditingTemplateInProgress ? String(localized: "meeting_templates_manager.close.help.editing_in_progress", defaultValue: "Finish or cancel template editing before closing.", comment: "Help text when close action is disabled due to template editing in progress.") : String(localized: "meeting_templates_manager.close.help", defaultValue: "Close template manager", comment: "Help text for done button in templates manager."))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
                    if controller.customMeetingTemplates().isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: MuesliTheme.spacing8) {
                            ForEach(controller.customMeetingTemplates()) { template in
                                customTemplateRow(template)
                            }
                        }
                    }

                    if isCreatingTemplate || editingTemplateID != nil {
                        customTemplateEditor
                    }
                }
                .padding(.bottom, MuesliTheme.spacing4)
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(minWidth: 760, minHeight: 520)
        .background(MuesliTheme.backgroundBase)
        .alert(
            String(format: String(localized: "meeting_templates_manager.delete_template.confirmation", defaultValue: "Delete \"%@\"?", comment: "Confirmation alert title for deleting a meeting template."), "\(templateToDelete?.name ?? "")"),
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )
        ) {
            Button(String(localized: "meeting_templates_manager.cancel.button", defaultValue: "Cancel", comment: "Cancel button title in delete-template confirmation alert."), role: .cancel) {
                templateToDelete = nil
            }
            Button(String(localized: "meeting_templates_manager.delete.button", defaultValue: "Delete", comment: "Delete button title in delete-template confirmation alert."), role: .destructive) {
                guard let template = templateToDelete else { return }
                controller.deleteCustomMeetingTemplate(id: template.id)
                if editingTemplateID == template.id {
                    resetTemplateEditor()
                }
                templateToDelete = nil
            }
        } message: {
            Text(String(localized: "meeting_templates_manager.delete.warning_message", defaultValue: "This template will be permanently removed. Existing meetings will keep their saved template snapshot.", comment: "Warning message shown when deleting a meeting template."))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: MeetingTemplates.customIconFallback)
                .font(.system(size: 11))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(String(localized: "meeting_templates_manager.empty_state.no_custom_templates", defaultValue: "No custom templates yet.", comment: "Empty-state message when no custom meeting templates exist."))
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

    @ViewBuilder
    private func customTemplateRow(_ template: CustomMeetingTemplate) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: template.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(MuesliTheme.accent)
                        Text(template.name)
                            .font(MuesliTheme.captionMedium())
                            .foregroundStyle(MuesliTheme.textPrimary)
                    }
                    Text(template.prompt)
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: MuesliTheme.spacing8) {
                    actionButton(String(localized: "meeting_templates_manager.template_row.edit", defaultValue: "Edit", comment: "Action button title to edit a meeting template."), systemImage: "pencil") {
                        beginEditingTemplate(template)
                    }
                    actionButton(String(localized: "meeting_templates_manager.template_row.delete", defaultValue: "Delete", comment: "Action button title to delete a meeting template."), systemImage: "trash", role: .destructive) {
                        templateToDelete = template
                    }
                }
            }
        }
        .padding(MuesliTheme.spacing12)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customTemplateEditor: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Text(isCreatingTemplate ? String(localized: "meeting_templates_manager.editor.new_template", defaultValue: "New template", comment: "Editor title when creating a new meeting template.") : String(localized: "meeting_templates_manager.editor.edit_template", defaultValue: "Edit template", comment: "Editor title when modifying an existing meeting template."))
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "meeting_templates_manager.editor.name_label", defaultValue: "Name", comment: "Label for meeting template name field."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextField(String(localized: "meeting_templates_manager.editor.name_placeholder", defaultValue: "Customer follow-up", comment: "Placeholder text for meeting template name field."), text: $draftTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                showNameValidationError ? MuesliTheme.recording.opacity(0.75) : .clear,
                                lineWidth: 1
                            )
                    }
                    .onChange(of: draftTemplateName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showNameValidationError = false
                        }
                    }
                if showNameValidationError {
                    Text(String(localized: "meeting_templates_manager.editor.name_validation", defaultValue: "Enter a template name.", comment: "Validation message when template name is empty."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "meeting_templates_manager.editor.icon_label", defaultValue: "Icon", comment: "Label for icon selection in template editor."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                customIconPicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "meeting_templates_manager.editor.prompt_label", defaultValue: "Prompt", comment: "Label for template prompt instructions editor."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
                TextEditor(text: $draftTemplatePrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
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
                    .onChange(of: draftTemplatePrompt) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showPromptValidationError = false
                        }
                    }
                if showPromptValidationError {
                    Text(String(localized: "meeting_templates_manager.editor.prompt_help", defaultValue: "Enter the prompt instructions for this template.", comment: "Helper text below prompt editor in template editor."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.recording)
                }
            }

            HStack {
                Spacer()
                actionButton(
                    isCreatingTemplate ? String(localized: "meeting_templates_manager.editor.create_template", defaultValue: "Create template", comment: "Primary button title when creating a new template.") : String(localized: "meeting_templates_manager.editor.save_changes", defaultValue: "Save changes", comment: "Primary button title when saving template edits."),
                    systemImage: isCreatingTemplate ? "plus.circle" : "checkmark.circle"
                ) {
                    saveTemplateEditor()
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

    private func beginCreatingTemplate() {
        isCreatingTemplate = true
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func beginEditingTemplate(_ template: CustomMeetingTemplate) {
        isCreatingTemplate = false
        editingTemplateID = template.id
        draftTemplateName = template.name
        draftTemplatePrompt = template.prompt
        draftTemplateIcon = MeetingTemplates.normalizedCustomIcon(named: template.icon)
        clearValidationErrors()
    }

    private func resetTemplateEditor() {
        isCreatingTemplate = false
        editingTemplateID = nil
        draftTemplateName = ""
        draftTemplatePrompt = ""
        draftTemplateIcon = MeetingTemplates.customIconFallback
        clearValidationErrors()
    }

    private func saveTemplateEditor() {
        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = draftTemplatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        showNameValidationError = trimmedName.isEmpty
        showPromptValidationError = trimmedPrompt.isEmpty
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if let editingTemplateID {
            controller.updateCustomMeetingTemplate(
                id: editingTemplateID,
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        } else {
            controller.createCustomMeetingTemplate(
                name: trimmedName,
                prompt: trimmedPrompt,
                icon: draftTemplateIcon
            )
        }
        resetTemplateEditor()
    }

    private var isEditingTemplateInProgress: Bool {
        isCreatingTemplate || editingTemplateID != nil
    }

    private func clearValidationErrors() {
        showNameValidationError = false
        showPromptValidationError = false
    }

    @ViewBuilder
    private var customIconPicker: some View {
        let columns = [
            GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 6)
        ]

        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(spacing: MuesliTheme.spacing8) {
                Image(systemName: draftTemplateIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MuesliTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(MuesliTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                Text(selectedIconLabel)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(MeetingTemplates.customIconOptions) { icon in
                    Button {
                        draftTemplateIcon = icon.symbolName
                    } label: {
                        Image(systemName: icon.symbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                draftTemplateIcon == icon.symbolName
                                    ? MuesliTheme.accent
                                    : MuesliTheme.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .fill(
                                        draftTemplateIcon == icon.symbolName
                                            ? MuesliTheme.accent.opacity(0.12)
                                            : MuesliTheme.backgroundRaised
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                    .strokeBorder(
                                        draftTemplateIcon == icon.symbolName
                                            ? MuesliTheme.accent.opacity(0.35)
                                            : MuesliTheme.surfaceBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(icon.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedIconLabel: String {
        MeetingTemplates.customIconOptions.first(where: { $0.symbolName == draftTemplateIcon })?.label ?? String(localized: "meeting_templates_manager.editor.icon_label.custom", defaultValue: "Custom", comment: "Label for custom icon option in template icon picker.")
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isDestructive ? MuesliTheme.recording : MuesliTheme.textPrimary)
            .padding(.horizontal, MuesliTheme.spacing12)
            .padding(.vertical, 7)
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
