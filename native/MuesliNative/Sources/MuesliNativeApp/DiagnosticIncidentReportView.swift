import SwiftUI

struct DiagnosticIncidentReportView: View {
    let incident: DiagnosticIncident
    let onOpenIssue: () -> Void
    let onDismiss: () -> Void

    private var isManualReport: Bool {
        incident.kind == .manualReport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing20) {
            HStack(alignment: .top, spacing: MuesliTheme.spacing12) {
                Image(systemName: isManualReport ? "exclamationmark.bubble.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isManualReport ? MuesliTheme.accent : .orange)
                VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
                    Text(isManualReport ? String(localized: "diagnostic_incident_report.title.report_problem", defaultValue: "Report a Problem", comment: "Title shown when user manually reports a problem.") : String(localized: "diagnostic_incident_report.title.failure_detected", defaultValue: "Diagnostic Failure Detected", comment: "Title shown when an automatic diagnostic failure is detected."))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(isManualReport ? String(format: String(localized: "diagnostic_incident_report.description.prepare_anonymized_issue", defaultValue: "%@ can prepare an anonymized GitHub issue for you to review before opening it.", comment: "Description for manual report flow explaining anonymized issue preparation."), "\(AppIdentity.displayName)") : String(format: String(localized: "diagnostic_incident_report.description.detected_failure", defaultValue: "%@ detected a hard failure in %@. You can review the anonymized report before opening a GitHub issue.", comment: "Description for detected failure flow including app name and failure stage."), "\(AppIdentity.displayName)", "\(incident.stage.rawValue)"))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !isManualReport {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.failure", defaultValue: "Failure", comment: "Summary label for diagnostic failure type."), value: incident.kind.title)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.stage", defaultValue: "Stage", comment: "Summary label for diagnostic stage."), value: incident.stage.rawValue)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.model", defaultValue: "Model", comment: "Summary label for model name."), value: incident.model)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.error", defaultValue: "Error", comment: "Summary label for error signature or code."), value: incident.errorDisplayIdentifier)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.meaning", defaultValue: "Meaning", comment: "Summary label for human-readable error meaning."), value: incident.errorFingerprint.summary)
                }
                .padding(MuesliTheme.spacing12)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .stroke(Color.orange.opacity(0.24), lineWidth: 1)
                )
            }

            Text(String(localized: "diagnostic_incident_report.privacy.explanation", defaultValue: "Only allowlisted diagnostic categories and a random incident ID are included. No transcript, audio, meeting title, calendar title, clipboard contents, screen text, API keys, auth tokens, local file paths, raw error messages, raw logs, or database contents are included.", comment: "Privacy explanation for what is excluded from diagnostic reports."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(incident.issueBody)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MuesliTheme.spacing12)
            }
            .frame(minHeight: 240)
            .background(MuesliTheme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .stroke(MuesliTheme.surfaceBorder, lineWidth: 1)
            )

            HStack {
                Spacer()
                Button(String(localized: "diagnostic_incident_report.action.not_now", defaultValue: "Not Now", comment: "Button title to dismiss diagnostic report flow.")) {
                    onDismiss()
                }
                Button(String(localized: "diagnostic_incident_report.action.open_github_issue", defaultValue: "Open GitHub Issue", comment: "Button title to open a prefilled GitHub issue.")) {
                    onOpenIssue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MuesliTheme.spacing24)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 460)
        .background(MuesliTheme.backgroundBase)
    }

    @ViewBuilder
    private func diagnosticSummaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MuesliTheme.spacing12) {
            Text(label)
                .font(MuesliTheme.captionMedium())
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
