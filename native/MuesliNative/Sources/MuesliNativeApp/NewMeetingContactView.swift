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
                Text(String(localized: "new_meeting_contact.title", defaultValue: "Create New Contact", bundle: .module, comment: "Title for new meeting contact creation sheet"))
                    .font(MuesliTheme.title2())
                Text(String(localized: "new_meeting_contact.subtitle", defaultValue: "Save this person to Apple Contacts and add them to the meeting.", bundle: .module, comment: "Subtitle explaining contact save behavior for meeting participant"))
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
            }

            Grid(alignment: .leading, horizontalSpacing: MuesliTheme.spacing12, verticalSpacing: MuesliTheme.spacing12) {
                contactField(String(localized: "new_meeting_contact.field.first_name", defaultValue: "First name", bundle: .module, comment: "Field label for first name in new meeting contact form"), text: $draft.givenName, field: .firstName)
                contactField(String(localized: "new_meeting_contact.field.last_name", defaultValue: "Last name", bundle: .module, comment: "Field label for last name in new meeting contact form"), text: $draft.familyName, field: .lastName)
                contactField(String(localized: "new_meeting_contact.field.email", defaultValue: "Email", bundle: .module, comment: "Field label for email in new meeting contact form"), text: $draft.emailAddress, field: .email)
            }

            HStack(spacing: MuesliTheme.spacing12) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "new_meeting_contact.status.saving", defaultValue: "Saving to Contacts…", bundle: .module, comment: "Progress status text while saving new contact to Apple Contacts"))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textSecondary)
                }

                Spacer()

                Button(String(localized: "common.cancel", defaultValue: "Cancel", bundle: .module, comment: "Common cancel button label")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "new_meeting_contact.action.save_contact", defaultValue: "Save Contact", bundle: .module, comment: "Primary action button label to save new meeting contact")) {
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
        .alert(String(localized: "new_meeting_contact.alert.couldnt_save_contact.title", defaultValue: "Couldn't Save Contact", bundle: .module, comment: "Alert title when contact save fails"), isPresented: errorBinding) {
            if isAccessDenied {
                Button(String(localized: "new_meeting_contact.alert.open_system_settings", defaultValue: "Open System Settings", bundle: .module, comment: "Alert action button to open System Settings for permissions")) {
                    openContactsPrivacyPane()
                    errorMessage = nil
                }
            }
            Button(String(localized: "common.ok", defaultValue: "OK", bundle: .module, comment: "Common confirmation button label"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: "new_meeting_contact.alert.couldnt_save_contact.message", defaultValue: "The contact could not be saved.", bundle: .module, comment: "Alert message describing generic contact save failure"))
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
