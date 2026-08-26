import AppKit
import MuesliCore
import SwiftUI

struct NewMeetingContactView: View {
    let onCreated: (MeetingParticipantDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewMeetingContactDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isAccessDenied = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case firstName
        case lastName
        case email
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "new_meeting_contact.title", defaultValue: "Create New Contact", comment: "Title for creating a new meeting contact."))
                    .font(MuesliTheme.title2())
                Text(String(localized: "new_meeting_contact.subtitle", defaultValue: "Save this person to Apple Contacts and add them to the meeting.", comment: "Subtitle explaining new contact creation behavior."))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Grid(alignment: .leading, horizontalSpacing: MuesliTheme.spacing12, verticalSpacing: MuesliTheme.spacing12) {
                contactField(String(localized: "new_meeting_contact.field.first_name", defaultValue: "First name", comment: "Field label for contact first name."), text: $draft.givenName, field: .firstName)
                contactField(String(localized: "new_meeting_contact.field.last_name", defaultValue: "Last name", comment: "Field label for contact last name."), text: $draft.familyName, field: .lastName)
                contactField(String(localized: "new_meeting_contact.field.email", defaultValue: "Email", comment: "Field label for contact email address."), text: $draft.emailAddress, field: .email)
            }

            HStack(spacing: MuesliTheme.spacing12) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "new_meeting_contact.status.saving", defaultValue: "Saving to Contacts…", comment: "Status text shown while saving a contact."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action label.")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "new_meeting_contact.action.save_contact", defaultValue: "Save Contact", comment: "Button title to save the new contact.")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave || isSaving)
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(width: 430)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            focusedField = .firstName
        }
        .alert(String(localized: "new_meeting_contact.alert.couldnt_save_contact.title", defaultValue: "Couldn't Save Contact", comment: "Alert title when saving a contact fails."), isPresented: errorBinding) {
            if isAccessDenied {
                Button(String(localized: "new_meeting_contact.alert.open_system_settings", defaultValue: "Open System Settings", comment: "Alert button to open system settings for permissions.")) {
                    openContactsPrivacyPane()
                    errorMessage = nil
                }
            }
            Button(String(localized: "common.ok", defaultValue: "OK", comment: "Common confirmation action label."), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: "new_meeting_contact.alert.could_not_save_contact.message", defaultValue: "The contact could not be saved.", comment: "Alert message shown when contact saving fails."))
        }
    }

    private func contactField(_ label: String, text: Binding<String>, field: Field) -> some View {
        GridRow {
            Text(label)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textSecondary)
                .frame(width: 78, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
                .frame(minWidth: 270)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { presented in
                if !presented {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        guard draft.canSave, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let participant = try await MeetingContactCreator.create(draft)
                dismiss()
                onCreated(participant)
            } catch {
                isAccessDenied = (error as? MeetingContactCreatorError) == .accessDenied
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openContactsPrivacyPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
