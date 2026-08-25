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
                    Text(isManualReport ? String(localized: "diagnostic_incident_report.title.report_problem", defaultValue: "Report a Problem", comment: "Dialog title for manually reporting a problem") : String(localized: "diagnostic_incident_report.title.failure_detected", defaultValue: "Diagnostic Failure Detected", comment: "Dialog title shown when a diagnostic failure is detected"))
                        .font(MuesliTheme.title3())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(isManualReport ? String(format: String(localized: "diagnostic_incident_report.description.prepare_anonymized_issue", defaultValue: "%@ can prepare an anonymized GitHub issue for you to review before opening it.", comment: "Description explaining anonymized GitHub issue preparation for manual reports"), "\(AppIdentity.displayName)") : String(format: String(localized: "diagnostic_incident_report.description.detected_failure", defaultValue: "%@ detected a hard failure in %@. You can review the anonymized report before opening a GitHub issue.", comment: "Description explaining detected failure and anonymized report review flow"), "\(AppIdentity.displayName)", "\(incident.stage.rawValue)"))
                        .font(MuesliTheme.callout())
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !isManualReport {
                VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.failure", defaultValue: "Failure", comment: "Summary field label for failure type in diagnostic incident report"), value: incident.kind.title)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.stage", defaultValue: "Stage", comment: "Summary field label for incident stage in diagnostic incident report"), value: incident.stage.rawValue)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.model", defaultValue: "Model", comment: "Summary field label for model in diagnostic incident report"), value: incident.model)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.error", defaultValue: "Error", comment: "Summary field label for error signature in diagnostic incident report"), value: incident.errorDisplayIdentifier)
                    diagnosticSummaryRow(String(localized: "diagnostic_incident_report.summary.meaning", defaultValue: "Meaning", comment: "Summary field label for interpreted error meaning in diagnostic incident report"), value: incident.errorFingerprint.summary)
                }
                .padding(MuesliTheme.spacing12)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .stroke(Color.orange.opacity(0.24), lineWidth: 1)
                )
            }

            Text(String(localized: "diagnostic_incident_report.privacy.explanation", defaultValue: "Only allowlisted diagnostic categories and a random incident ID are included. No transcript, audio, meeting title, calendar title, clipboard contents, screen text, API keys, auth tokens, local file paths, raw error messages, raw logs, or database contents are included.", comment: "Privacy explanation describing what is excluded from diagnostic incident reports"))
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
                Button(String(localized: "diagnostic_incident_report.action.not_now", defaultValue: "Not Now", comment: "Action button title to defer opening a diagnostic GitHub issue")) {
                    onDismiss()
                }
                Button(String(localized: "diagnostic_incident_report.action.open_github_issue", defaultValue: "Open GitHub Issue", comment: "Action button title to open the generated diagnostic GitHub issue")) {
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
