import Foundation
import MuesliCore

enum ComputerUseTraceFormatter {
    static func debugText(for record: DictationRecord) -> String {
        guard let trace = record.computerUseTrace else {
            return record.rawText
        }

        var lines: [String] = [
            String(localized: "computer_use_trace_formatter.cua_command", defaultValue: "CUA Command", comment: "Label for CUA command field in computer use trace summary"),
            record.rawText,
            "",
            String(localized: "computer_use_trace_formatter.final_status", defaultValue: "Final Status", comment: "Label for final status field in computer use trace summary"),
            displayFinalStatus(trace.finalStatus),
            "",
            String(localized: "computer_use_trace_formatter.final_message", defaultValue: "Final Message", comment: "Label for final message field in computer use trace summary"),
            trace.finalMessage,
            "",
            String(localized: "computer_use_trace_formatter.step_trail", defaultValue: "Step Trail", comment: "Label for ordered step trail in computer use trace summary"),
        ]

        for event in trace.events {
            let step = event.step.map { String(format: String(localized: "computer_use_trace_formatter.step_number", defaultValue: "Step %@", comment: "Label template for individual step number in computer use trace summary"), "\($0)") } ?? String(localized: "computer_use_trace_formatter.run", defaultValue: "Run", comment: "Label for execution run metadata in computer use trace summary")
            let status = displayStatus(for: event).map { " [\($0)]" } ?? ""
            lines.append("\(step) - \(event.title)\(status)")
            lines.append(event.body)
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayStatus(for event: ComputerUseTraceEvent) -> String? {
        guard let status = event.status?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else { return nil }
        let normalizedStatus = status.lowercased()
        let normalizedTitle = event.title.lowercased()
        if normalizedStatus == normalizedTitle {
            return nil
        }
        switch (event.kind, normalizedStatus) {
        case ("observation", "observed"),
             ("planning", "planning"),
             ("tool_call", "executing"),
             ("model_output", "planned"):
            return nil
        default:
            return status
        }
    }

    static func displayFinalStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done":
            return "done"
        case "timed_out", "timedout":
            return "timed_out"
        case "failed", "fail":
            return "failed"
        case "confirm", "needsconfirmation", "needs_confirmation":
            return "confirm"
        case "cancelled", "canceled":
            return "cancelled"
        default:
            return status
        }
    }
}
