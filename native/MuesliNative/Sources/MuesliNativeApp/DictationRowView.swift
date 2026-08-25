import SwiftUI
import MuesliCore

struct DictationRowView: View {
    let record: DictationRecord
    let timeOnly: String
    let onCopy: () -> Void
    var onCopyTrace: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showDeleteConfirmation = false
    @State private var isExpanded = false

    private var isComputerUseCommand: Bool {
        record.source == "cua"
    }

    private var syncOriginBadgeLabel: String? {
        SyncOriginDisplay.badgeLabel(forDictationSource: record.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing20) {
                Text(timeOnly)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .frame(width: 80, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing8) {
                        if isComputerUseCommand {
                            Text("CUA")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(MuesliTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MuesliTheme.accentSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let syncOriginBadgeLabel {
                            SyncOriginBadge(label: syncOriginBadgeLabel)
                        }

                        Text(record.rawText)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let trace = record.computerUseTrace {
                            Text(Self.displayFinalStatus(trace.finalStatus))
                                .font(MuesliTheme.captionMedium())
                                .foregroundStyle(statusColor(trace.finalStatus))
                        }
                    }

                    if isExpanded, let trace = record.computerUseTrace {
                        computerUseTraceView(trace)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let targetAppName = record.targetAppName {
                    TargetApplicationIconView(
                        appName: targetAppName,
                        bundleIdentifier: record.targetAppBundleID
                    )
                }

                HStack(spacing: 8) {
                    if record.computerUseTrace != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    if record.computerUseTrace != nil, let onCopyTrace {
                        Button(action: onCopyTrace) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.system(size: 12))
                                .foregroundStyle(MuesliTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "dictation_row.copy_cua_trace.help", defaultValue: "Copy CUA trace", comment: "Help text for action that copies the CUA trace"))
                    }

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(MuesliTheme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    if onDelete != nil {
                        Button { showDeleteConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(isHovered || isExpanded || record.computerUseTrace != nil ? 1 : 0)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing20)
        .padding(.vertical, MuesliTheme.spacing16)
        .background(isHovered ? MuesliTheme.backgroundHover : MuesliTheme.backgroundRaised)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if record.computerUseTrace != nil {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } else {
                onCopy()
            }
        }
        .alert(String(localized: "dictation_row.delete_dictation.alert_title", defaultValue: "Delete Dictation", comment: "Alert title when confirming dictation deletion"), isPresented: $showDeleteConfirmation) {
            Button(String(localized: "dictation_row.delete_dictation.confirm_button", defaultValue: "Delete", comment: "Confirmation button title for deleting a dictation"), role: .destructive) { onDelete?() }
            Button(String(localized: "dictation_row.delete_dictation.cancel_button", defaultValue: "Cancel", comment: "Cancel button title for dictation deletion alert"), role: .cancel) {}
        } message: {
            Text(String(localized: "dictation_row.delete_dictation.alert_message", defaultValue: "Are you sure you want to delete this dictation? This cannot be undone.", comment: "Alert message warning about permanent dictation deletion"))
        }
    }

    @ViewBuilder
    private func computerUseTraceView(_ trace: ComputerUseTraceRecord) -> some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                ForEach(trace.events) { event in
                    VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                        HStack(spacing: MuesliTheme.spacing8) {
                            Text(event.step.map { String(format: String(localized: "dictation_row.computer_use_trace.step_title", defaultValue: "Step %@", comment: "Title for a specific step in the computer use trace"), "\($0)") } ?? String(localized: "dictation_row.computer_use_trace.run_label", defaultValue: "Run", comment: "Fallback label used for the computer use trace run"))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(MuesliTheme.textTertiary)
                                .frame(width: 48, alignment: .leading)

                            Text(event.title)
                                .font(MuesliTheme.captionMedium())
                                .foregroundStyle(MuesliTheme.textSecondary)

                            if let status = ComputerUseTraceFormatter.displayStatus(for: event) {
                                Text(status)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(statusColor(status))
                            }
                        }

                        Text(event.body)
                            .font(.system(size: 12, weight: .regular, design: event.kind == "model_output" ? .monospaced : .default))
                            .foregroundStyle(MuesliTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .padding(.top, MuesliTheme.spacing4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "executed":
            return MuesliTheme.success
        case "confirm", "needsconfirmation":
            return MuesliTheme.transcribing
        case "timed_out", "timedout":
            return MuesliTheme.transcribing
        case "failed", "unsupported":
            return MuesliTheme.recording
        default:
            return MuesliTheme.textTertiary
        }
    }

    private static func displayFinalStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done":
            return "Done"
        case "timed_out", "timedout":
            return String(localized: "dictation_row.status.timed_out", defaultValue: "Timed out", comment: "Status label indicating dictation action timed out")
        case "failed", "fail":
            return String(localized: "dictation_row.status.failed", defaultValue: "Failed", comment: "Status label indicating dictation action failed")
        case "confirm", "needsconfirmation", "needs_confirmation":
            return "Confirm"
        case "cancelled", "canceled":
            return String(localized: "dictation_row.status.cancelled", defaultValue: "Cancelled", comment: "Status label indicating dictation action was cancelled")
        default:
            return status.capitalized
        }
    }
}
