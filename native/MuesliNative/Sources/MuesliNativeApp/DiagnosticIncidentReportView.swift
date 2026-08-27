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
                    Text(isManualReport ? String(localized: "diagnostic_incident_report.title.report_problem", defaultValue: "Report a Problem", bundle: .module, comment: "Title for manual diagnostic report sheet.") : String(localized: "diagnostic_incident_report.title.failure_detected", defaultValue: "Diagnostic Failure Detected", bundle: .module, comment: "Title for automatic diagnostic failure report sheet."))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(isManualReport ? String(format: String(localized: "diagnostic_incident_report.body.manual_prompt", defaultValue: "%@ can prepare an anonymized GitHub issue for you to review before opening it.", bundle: .module, comment: "Body copy for manual report flow with app name."), "\(AppIdentity.displayName)") : String(format: String(localized: "diagnostic_incident_report.body.failure_detected", defaultValue: "%@ detected a hard failure in %@. You can review the anonymized report before opening a GitHub issue.", bundle: .module, comment: "Body copy for automatic failure report flow with app and stage."), "\(AppIdentity.displayName)", "\(incident.stage.rawValue)"))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !isManualReport {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.failure", defaultValue: "Failure", bundle: .module, comment: "Summary row label for failure kind."), value: incident.kind.title)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.stage", defaultValue: "Stage", bundle: .module, comment: "Summary row label for pipeline stage."), value: incident.stage.rawValue)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.model", defaultValue: "Model", bundle: .module, comment: "Summary row label for model."), value: incident.model)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.error", defaultValue: "Error", bundle: .module, comment: "Summary row label for error signature."), value: incident.errorDisplayIdentifier)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.meaning", defaultValue: "Meaning", bundle: .module, comment: "Summary row label for error meaning."), value: incident.errorFingerprint.summary)
                }
                .padding(MuesliTheme.spacing12)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .stroke(Color.orange.opacity(0.24), lineWidth: 1)
                )
            }

            Text(String(localized: "diagnostic_incident_report.privacy.explanation", defaultValue: "Only allowlisted diagnostic categories and a random incident ID are included. No transcript, audio, meeting title, calendar title, clipboard contents, screen text, API keys, auth tokens, local file paths, raw error messages, raw logs, or database contents are included.", bundle: .module, comment: "Privacy disclosure for included and excluded report data."))
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
                Button(String(localized: "diagnostic_incident_report.action.not_now", defaultValue: "Not Now", bundle: .module, comment: "Dismiss button title for report sheet.")) {
                    onDismiss()
                }
                Button(String(localized: "diagnostic_incident_report.action.open_github_issue", defaultValue: "Open GitHub Issue", bundle: .module, comment: "Primary action button to open GitHub issue.")) {
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
