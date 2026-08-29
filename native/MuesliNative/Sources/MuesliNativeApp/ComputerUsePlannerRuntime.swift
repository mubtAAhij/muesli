import Foundation
import MuesliCore

struct ComputerUsePlannerRuntimeResult: Equatable {
    enum Status: Equatable {
        case done
        case timedOut
        case needsConfirmation
        case failed
        case cancelled
    }

    let status: Status
    let message: String
    let traceEvents: [ComputerUseTraceEvent]

    init(status: Status, message: String, traceEvents: [ComputerUseTraceEvent] = []) {
        self.status = status
        self.message = message
        self.traceEvents = traceEvents
    }
}

@MainActor
final class ComputerUsePlannerRuntime {
    typealias StatusHandler = @MainActor (ComputerUseStatusIdentity) -> Void
    typealias ObserveHandler = @MainActor (ComputerUseElementRegistry, Bool, ComputerUseObservationTarget?) -> ComputerUseObservation
    typealias PlanHandler = (ComputerUsePlannerRequest) async throws -> ComputerUsePlannerResponse
    typealias ExecuteHandler = @MainActor (ComputerUseToolCall, ComputerUseElementRegistry) async -> ComputerUseExecutionResult

    private let config: AppConfig
    private let maxSteps: Int?
    private let timeoutSeconds: TimeInterval
    private let registry = ComputerUseElementRegistry()
    private let onStatus: StatusHandler
    private let observe: ObserveHandler
    private let plan: PlanHandler
    private let execute: ExecuteHandler
    private let maxPlannerRetries = 1
    private let maxUnchangedObservationLoops = 4

    init(
        config: AppConfig,
        maxSteps: Int? = 100,
        timeoutSeconds: TimeInterval? = nil,
        onStatus: @escaping StatusHandler = { _ in },
        observe: @escaping ObserveHandler = { registry, includeScreenshot, target in
            ComputerUseObservationCapture.capture(
                registry: registry,
                includeScreenshot: includeScreenshot,
                target: target
            )
        },
        plan: PlanHandler? = nil,
        execute: @escaping ExecuteHandler = { toolCall, registry in
            await ComputerUseToolExecutor.execute(toolCall, registry: registry)
        }
    ) {
        self.config = config
        self.maxSteps = maxSteps
        self.timeoutSeconds = timeoutSeconds ?? TimeInterval(max(config.computerUseTimeoutSeconds, 1))
        self.onStatus = onStatus
        self.observe = observe
        self.plan = plan ?? { request in
            try await ComputerUsePlannerClient.planNextTool(request: request, config: config)
        }
        self.execute = execute
    }

    func run(command: String) async -> ComputerUsePlannerRuntimeResult {
        var traceEvents = [
            traceEvent(
                kind: "transcript",
                title: "Command",
                body: command.isEmpty ? "(empty)" : command,
                status: nil,
                step: nil
            ),
        ]

        guard config.enableComputerUsePlanner else {
            let message = "CUA planner is disabled."
            traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.failed.primary", defaultValue: "Failed", bundle: .module, comment: "Computer use runtime status when an operation fails at primary status site"), body: message, status: "failed", step: nil))
            return .init(status: .failed, message: message, traceEvents: traceEvents)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var priorResults: [ComputerUseToolOutcome] = []
        var unchangedActionCounts: [String: Int] = [:]
        var unchangedObservationCounts: [String: Int] = [:]
        var invalidToolCallRepairCount = 0
        let maxInvalidToolCallRepairs = 2
        // V1 keeps foreground activation, but state is scoped to a target app.
        // Later Codex-style work should replace this with background key-window tracking,
        // synthetic focus enforcement, and user-frontmost-app preservation.
        var currentTarget: ComputerUseObservationTarget?

        onStatus(.observingScreen)
        var observation = observe(registry, true, currentTarget)
        traceEvents.append(observationEvent(observation, step: nil))

        var step = 1
        while true {
            if Task.isCancelled {
                return cancelledResult(traceEvents: traceEvents, step: step)
            }
            if Date() >= deadline {
                traceEvents.append(traceEvent(kind: "timed_out", title: "Timed out", body: "CUA timed out", status: "timed_out", step: step))
                return .init(status: .timedOut, message: String(localized: "computer_use.runtime.status.cua_timed_out", defaultValue: "CUA timed out", bundle: .module, comment: "Computer use runtime status when CUA times out"), traceEvents: traceEvents)
            }
            if let maxSteps, step > maxSteps {
                traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.failed.secondary", defaultValue: "Failed", bundle: .module, comment: "Computer use runtime status when an operation fails at secondary status site"), body: String(localized: "computer_use.runtime.status.cua_step_limit_reached", defaultValue: "CUA reached its step limit", bundle: .module, comment: "Computer use runtime status when CUA step limit is reached"), status: "failed", step: maxSteps))
                return .init(status: .failed, message: String(localized: "computer_use.runtime.status.cua_step_limit_reached", defaultValue: "CUA reached its step limit", bundle: .module, comment: "Computer use runtime status when CUA step limit is reached"), traceEvents: traceEvents)
            }
            defer { step += 1 }

            let request = ComputerUsePlannerRequest(
                command: command,
                step: step,
                maxSteps: maxSteps,
                latestWindowState: ComputerUseWindowState(observation: observation),
                priorOutcomes: priorResults
            )

            let response: ComputerUsePlannerResponse
            do {
                response = try await planWithRetry(request, traceEvents: &traceEvents)
            } catch is CancellationError {
                return cancelledResult(traceEvents: traceEvents, step: step)
            } catch ComputerUsePlannerError.invalidToolCall(let name, let arguments, let message) {
                let repairMessage = "Invalid tool call \(name): \(message). Raw arguments: \(String(arguments.prefix(800))). Choose exactly one valid tool from the current catalog and follow that tool's schema."
                traceEvents.append(traceEvent(
                    kind: "planner_repair",
                    title: "Planner schema repair",
                    body: repairMessage,
                    status: "repair",
                    step: step
                ))
                priorResults.append(ComputerUseToolOutcome(
                    step: step,
                    tool: .fail,
                    status: "invalid_schema",
                    message: repairMessage,
                    appName: observation.appName,
                    bundleID: observation.bundleID,
                    windowTitle: observation.windowTitle,
                    snapshotID: observation.screenshot?.screenshotID
                ))
                invalidToolCallRepairCount += 1
                if invalidToolCallRepairCount <= maxInvalidToolCallRepairs {
                    continue
                }
                traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.planner_failed", defaultValue: "Planner failed", bundle: .module, comment: "Computer use runtime status when planner fails"), body: repairMessage, status: "failed", step: step))
                return .init(status: .failed, message: repairMessage, traceEvents: traceEvents)
            } catch {
                traceEvents.append(traceEvent(
                    kind: "failed",
                    title: String(localized: "computer_use.runtime.status.planner_failed", defaultValue: "Planner failed", bundle: .module, comment: "Computer use runtime status when planner fails"),
                    body: error.localizedDescription,
                    status: "failed",
                    step: step
                ))
                return .init(status: .failed, message: error.localizedDescription, traceEvents: traceEvents)
            }

            let toolCall = response.toolCall
            invalidToolCallRepairCount = 0
            if let target = target(from: toolCall, fallback: currentTarget) {
                currentTarget = target
            }
            traceEvents.append(traceEvent(
                kind: "model_output",
                title: "Model output",
                body: response.rawModelOutput ?? formatToolCall(toolCall),
                status: "planned",
                step: step
            ))
            if let validationFailure = toolCall.validationFailure() {
                traceEvents.append(traceEvent(kind: "failed", title: "Schema rejected", body: validationFailure, status: "failed", step: step))
                return .init(status: .failed, message: validationFailure, traceEvents: traceEvents)
            }
            if toolCall.requiresConfirmation {
                onStatus(.confirm)
                let message = String(format: String(localized: "computer_use.runtime.confirmation.message", defaultValue: "Confirm: %@", bundle: .module, comment: "Computer use confirmation prompt including tool call summary"), "\(toolCall.summary)")
                traceEvents.append(traceEvent(kind: "confirm", title: "Confirmation required", body: message, status: "confirm", step: step))
                return .init(status: .needsConfirmation, message: message, traceEvents: traceEvents)
            }

            switch toolCall.tool {
            case .finish:
                onStatus(.done)
                let message = toolCall.reason?.isEmpty == false ? toolCall.reason! : "Done"
                if finishIndicatesFailure(message) {
                    let blockedMessage = "Planner attempted to finish with an incomplete or blocked result: \(message)"
                    traceEvents.append(traceEvent(kind: "failed", title: "Final output blocked", body: blockedMessage, status: "failed", step: step))
                    return .init(status: .failed, message: blockedMessage, traceEvents: traceEvents)
                }
                traceEvents.append(traceEvent(kind: "finish", title: "Final output", body: message, status: "done", step: step))
                return .init(status: .done, message: message, traceEvents: traceEvents)
            case .fail:
                onStatus(.failed)
                let message = toolCall.reason?.isEmpty == false ? toolCall.reason! : String(localized: "computer_use.runtime.status.failed.quaternary", defaultValue: "Failed", bundle: .module, comment: "Computer use runtime status when an operation fails at quaternary status site")
                traceEvents.append(traceEvent(kind: "failed", title: "Final output", body: message, status: "failed", step: step))
                return .init(status: .failed, message: message, traceEvents: traceEvents)
            case .getAppState, .getWindowState:
                onStatus(.observingScreen)
                let beforeObservation = observation
                let result = await execute(toolCall, registry)
                if Task.isCancelled || result.status == .cancelled {
                    return cancelledResult(traceEvents: traceEvents, step: step)
                }
                if result.status == .failed || result.status == .unsupported {
                    let outcomeMessage = recoverableFallbackMessage(for: toolCall, result: result) ?? result.message
                    priorResults.append(outcome(
                        step: step,
                        toolCall: toolCall,
                        result: result,
                        message: outcomeMessage,
                        observation: beforeObservation,
                        delta: nil
                    ))
                    traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.failed", defaultValue: "Failed", bundle: .module, comment: "Computer use runtime generic failed status"), body: result.message, status: "failed", step: step))
                    return .init(status: .failed, message: result.message, traceEvents: traceEvents)
                }
                onStatus(.observingScreen)
                observation = observe(registry, true, currentTarget)
                traceEvents.append(observationEvent(observation, step: step))
                let feedback = observationToolFeedback(
                    before: beforeObservation,
                    after: observation,
                    toolCall: toolCall,
                    result: result,
                    counts: &unchangedObservationCounts
                )
                priorResults.append(outcome(
                    step: step,
                    toolCall: toolCall,
                    result: result,
                    message: feedback.message,
                    observation: observation,
                    delta: nil
                ))
                if let blocked = feedback.blocked {
                    traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.repeated_action_stopped", defaultValue: "Repeated action stopped", bundle: .module, comment: "Computer use runtime status when repeated action is halted"), body: blocked, status: "failed", step: step))
                    return .init(status: .failed, message: blocked, traceEvents: traceEvents)
                }
                continue
            default:
                unchangedObservationCounts.removeAll()
                onStatus(statusTitle(for: toolCall))
                traceEvents.append(traceEvent(
                    kind: "tool_call",
                    title: "Executing",
                    body: executionTraceBody(toolCall: toolCall, observation: observation),
                    status: "executing",
                    step: step
                ))
                let beforeObservation = observation
                let result = await execute(toolCall, registry)
                traceEvents.append(traceEvent(
                    kind: "tool_result",
                    title: "Tool result",
                    body: result.message,
                    status: "\(result.status)",
                    step: step
                ))

                if Task.isCancelled || result.status == .cancelled {
                    return cancelledResult(traceEvents: traceEvents, step: step)
                }

                switch result.status {
                case .executed:
                    if let resultTitle = resultStatusTitle(for: toolCall, result: result) {
                        onStatus(resultTitle)
                    }
                    var delta: ComputerUseStateDelta?
                    if toolCall.isMutating {
                        onStatus(.observingScreen)
                        observation = observe(registry, true, currentTarget)
                        traceEvents.append(observationEvent(observation, step: step))
                        delta = stateDelta(
                            before: beforeObservation,
                            after: observation,
                            toolCall: toolCall,
                            result: result
                        )
                    }
                    let outcomeMessage = verifiedOutcomeMessage(
                        base: recoverableFallbackMessage(for: toolCall, result: result) ?? result.message,
                        delta: delta
                    )
                    priorResults.append(outcome(
                        step: step,
                        toolCall: toolCall,
                        result: result,
                        message: outcomeMessage,
                        observation: observation,
                        delta: delta
                    ))
                    if let blocked = repeatedUnchangedMessage(
                        toolCall: toolCall,
                        delta: delta,
                        counts: &unchangedActionCounts
                    ) {
                        traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.repeated_action_stopped", defaultValue: "Repeated action stopped", bundle: .module, comment: "Computer use runtime status when repeated action is halted"), body: blocked, status: "failed", step: step))
                        return .init(status: .failed, message: blocked, traceEvents: traceEvents)
                    }
                case .needsConfirmation:
                    priorResults.append(outcome(
                        step: step,
                        toolCall: toolCall,
                        result: result,
                        message: result.message,
                        observation: beforeObservation,
                        delta: nil
                    ))
                    traceEvents.append(traceEvent(kind: "confirm", title: "Confirmation required", body: result.message, status: "confirm", step: step))
                    return .init(status: .needsConfirmation, message: result.message, traceEvents: traceEvents)
                case .unsupported, .failed:
                    if let fallbackMessage = recoverableFallbackMessage(for: toolCall, result: result) {
                        priorResults.append(outcome(
                            step: step,
                            toolCall: toolCall,
                            result: result,
                            message: fallbackMessage,
                            observation: beforeObservation,
                            delta: nil
                        ))
                        onStatus(.screenFallback)
                        traceEvents.append(traceEvent(
                            kind: "fallback",
                            title: "Screen fallback",
                            body: fallbackMessage,
                            status: "fallback",
                            step: step
                        ))
                        onStatus(.observingScreen)
                        observation = observe(registry, true, currentTarget)
                        traceEvents.append(observationEvent(observation, step: step))
                        continue
                    }
                    priorResults.append(outcome(
                        step: step,
                        toolCall: toolCall,
                        result: result,
                        message: result.message,
                        observation: beforeObservation,
                        delta: nil
                    ))
                    traceEvents.append(traceEvent(kind: "failed", title: String(localized: "computer_use.runtime.status.failed.tertiary", defaultValue: "Failed", bundle: .module, comment: ""), body: result.message, status: "failed", step: step))
                    return .init(status: .failed, message: result.message, traceEvents: traceEvents)
                case .cancelled:
                    return cancelledResult(traceEvents: traceEvents, step: step)
                }
            }
        }
    }

    private func cancelledResult(traceEvents: [ComputerUseTraceEvent], step: Int) -> ComputerUsePlannerRuntimeResult {
        var events = traceEvents
        events.append(traceEvent(kind: "cancelled", title: "Cancelled", body: "CUA cancelled", status: "cancelled", step: step))
        return .init(status: .cancelled, message: String(localized: "computer_use.runtime.status.cua_cancelled", defaultValue: "CUA cancelled", bundle: .module, comment: "Computer use runtime status when CUA operation is cancelled"), traceEvents: events)
    }

    private func outcome(
        step: Int,
        toolCall: ComputerUseToolCall,
        result: ComputerUseExecutionResult,
        message: String,
        observation: ComputerUseObservation,
        delta: ComputerUseStateDelta?
    ) -> ComputerUseToolOutcome {
        ComputerUseToolOutcome(
            step: step,
            tool: toolCall.tool,
            status: "\(result.status)",
            message: message,
            appName: observation.appName,
            bundleID: observation.bundleID,
            windowTitle: observation.windowTitle,
            snapshotID: observation.screenshot?.screenshotID,
            verificationStatus: delta?.status,
            beforeStateID: delta?.beforeStateID,
            afterStateID: delta?.afterStateID,
            stateDelta: delta
        )
    }

    private func observationEvent(_ observation: ComputerUseObservation, step: Int?) -> ComputerUseTraceEvent {
        let app = observation.appName.isEmpty ? String(localized: "computer_use_planner.app.unknown", defaultValue: "Unknown app", bundle: .module, comment: "Planner app name label used when frontmost application cannot be resolved") : observation.appName
        let window = observation.windowTitle.isEmpty ? "No focused window" : observation.windowTitle
        var details = ["state \(observation.stateID)", "\(app) - \(window) - \(observation.elements.count) AX candidates"]
        if let screenshot = observation.screenshot {
            details.append("screenshot \(screenshot.screenshotID) \(screenshot.width)x\(screenshot.height)")
        }
        if let focused = observation.focusedElement {
            let text = focused.normalizedText.isEmpty ? focused.role : "\(focused.role) \(focused.normalizedText)"
            details.append("focused \(String(text.prefix(80)))")
        }
        if let selectedText = observation.selectedText, !selectedText.isEmpty {
            details.append("selected \(selectedText.count) chars")
        }
        if let cursor = observation.cursorPosition {
            details.append("cursor \(Int(cursor.x.rounded())),\(Int(cursor.y.rounded()))")
        }
        return traceEvent(
            kind: "observation",
            title: "Observation",
            body: details.joined(separator: " - "),
            status: "observed",
            step: step
        )
    }

    private func stepLimitSuffix(_ maxSteps: Int?) -> String {
        maxSteps.map { " of \($0)" } ?? ""
    }

    private func stateDelta(
        before: ComputerUseObservation,
        after: ComputerUseObservation,
        toolCall: ComputerUseToolCall,
        result: ComputerUseExecutionResult
    ) -> ComputerUseStateDelta {
        if result.status != .executed {
            return ComputerUseStateDelta(
                status: .blocked,
                summary: result.message,
                beforeStateID: before.stateID,
                afterStateID: after.stateID
            )
        }
        if toolCall.tool != .launchApp,
           !before.bundleID.isEmpty,
           !after.bundleID.isEmpty,
           before.bundleID != after.bundleID {
            return ComputerUseStateDelta(
                status: .targetLost,
                summary: String(format: String(localized: "computer_use_planner.state_delta.target_app_changed", defaultValue: "Target app changed from %@ (%@) to %@ (%@); re-query state before acting again.", bundle: .module, comment: "Planner guidance when observed target app changes between states"), "\(before.appName)", "\(before.bundleID)", "\(after.appName)", "\(after.bundleID)"),
                beforeStateID: before.stateID,
                afterStateID: after.stateID
            )
        }

        let beforeSignature = observationSignature(before)
        let afterSignature = observationSignature(after)
        let status: ComputerUseVerificationStatus = beforeSignature == afterSignature ? .unchanged : .changed
        let summary: String
        if status == .changed {
            summary = String(format: String(localized: "computer_use_planner.state_delta.ui_state_changed", defaultValue: "Observed UI state changed after %@.", bundle: .module, comment: "Planner feedback indicating UI state changed after tool call"), "\(toolCall.summary)")
        } else if toolCall.tool == .typeText || toolCall.tool == .pasteText || toolCall.tool == .setValue {
            summary = String(format: String(localized: "computer_use_planner.state_delta.no_text_change_guidance", defaultValue: "%@ executed but no focused value, selected text, or visible AX text change was observed; refocus the editable target or use a different insertion primitive.", bundle: .module, comment: "Planner guidance when text-oriented action produces no observable text change"), "\(toolCall.summary)")
        } else {
            summary = String(format: String(localized: "computer_use_planner.state_delta.no_relevant_change_guidance", defaultValue: "%@ executed but no relevant UI change was observed; choose a different strategy.", bundle: .module, comment: "Planner guidance when action yields no relevant UI change"), "\(toolCall.summary)")
        }
        return ComputerUseStateDelta(
            status: status,
            summary: summary,
            beforeStateID: before.stateID,
            afterStateID: after.stateID
        )
    }

    private func verifiedOutcomeMessage(base: String, delta: ComputerUseStateDelta?) -> String {
        guard let delta else { return base }
        return String(format: String(localized: "computer_use_planner.verified_outcome.message", defaultValue: "%@. Verification: %@", bundle: .module, comment: "Verified planner outcome message combining base result and delta summary"), "\(base)", "\(delta.summary)")
    }

    private func observationToolFeedback(
        before: ComputerUseObservation,
        after: ComputerUseObservation,
        toolCall: ComputerUseToolCall,
        result: ComputerUseExecutionResult,
        counts: inout [String: Int]
    ) -> (message: String, blocked: String?) {
        let base = recoverableFallbackMessage(for: toolCall, result: result) ?? result.message
        let key = repeatedActionKey(toolCall)
        guard observationSignature(before) == observationSignature(after) else {
            counts.removeValue(forKey: key)
            return (
                String(format: String(localized: "computer_use_planner.observation_feedback.captured_fresh_state", defaultValue: "%@. Captured fresh state; continue from the visible AX/screenshot context.", bundle: .module, comment: "Planner feedback after capturing fresh observed state"), "\(base)"),
                nil
            )
        }

        let count = (counts[key] ?? 0) + 1
        counts[key] = count
        let message = String(format: String(localized: "computer_use_planner.message.state_unchanged_choose_action", defaultValue: "%@. State is unchanged after %@; choose a concrete action now and do not call get_app_state/get_window_state again unless the target app or window changes.", bundle: .module, comment: "Planner directive when repeated observations show unchanged state"), "\(base)", "\(toolCall.summary)")
        guard count >= maxUnchangedObservationLoops else {
            return (message, nil)
        }
        return (
            message,
            String(format: String(localized: "computer_use_planner.feedback.repeated_observation_stopped", defaultValue: "CUA stopped repeated %@ after %d unchanged observations with no intervening action. Choose a concrete action instead of observing again.", bundle: .module, comment: "Planner feedback when repeated observe loop is stopped after unchanged iterations"), "\(toolCall.summary)", maxUnchangedObservationLoops)
        )
    }

    private func repeatedUnchangedMessage(
        toolCall: ComputerUseToolCall,
        delta: ComputerUseStateDelta?,
        counts: inout [String: Int]
    ) -> String? {
        guard shouldTrackForRepetition(toolCall.tool), let delta else { return nil }
        let key = repeatedActionKey(toolCall)
        guard delta.status == .unchanged else {
            if delta.status == .changed {
                counts.removeAll()
            } else {
                counts.removeValue(forKey: key)
            }
            return nil
        }
        let count = (counts[key] ?? 0) + 1
        counts[key] = count
        guard count >= 2 else { return nil }
        return String(format: String(localized: "computer_use_planner.feedback.repeated_unchanged_attempts", defaultValue: "CUA stopped repeated %@ after two unchanged attempts: no relevant UI change was observed. Choose a different strategy after running get_app_state.", bundle: .module, comment: "Planner feedback when repeated action is halted after unchanged attempts"), "\(toolCall.summary)")
    }

    private func repeatedActionKey(_ toolCall: ComputerUseToolCall) -> String {
        let parts: [String] = [
            toolCall.tool.rawValue,
            toolCall.elementID ?? "",
            toolCall.elementIndex.map(String.init) ?? "",
            toolCall.appName ?? "",
            toolCall.canonicalBundleID,
            toolCall.label ?? "",
            toolCall.actionName ?? "",
            toolCall.key ?? "",
            toolCall.text ?? "",
            toolCall.value ?? "",
            toolCall.url ?? "",
            toolCall.direction?.rawValue ?? "",
            toolCall.screenshotID ?? "",
            toolCall.x.map { String($0) } ?? "",
            toolCall.y.map { String($0) } ?? "",
        ]
        return parts.joined(separator: "|")
    }

    private func finishIndicatesFailure(_ reason: String) -> Bool {
        let lowered = reason.lowercased()
        let failurePatterns = [
            #"^\s*(blocked|failed|unsupported|incomplete|not completed?)\s*[.!]?\s*$"#,
            #"\b(requires|needs)\s+confirmation\b"#,
            #"\b(task|request|command|workflow)\s+(is\s+)?(blocked|incomplete|not completed?|failed|unsupported)\b"#,
            #"\b(cannot|can't|could not|unable to|was not able to)\s+(complete|finish|perform|do|continue|proceed|access|open|click|type|paste|navigate|find)\b"#,
            #"\b(did not|didn't)\s+(complete|finish|perform|send|post|open|click|type|paste|navigate|find)\b"#,
            #"\b(permission|permissions)\s+(required|needed|denied|missing|not granted)\b"#,
            #"\b(not authorized|not allowed|access denied)\b"#,
            #"\bfailed to\s+(complete|finish|perform|open|click|type|paste|navigate|send|post)\b"#,
        ]
        return failurePatterns.contains { pattern in
            lowered.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func shouldTrackForRepetition(_ tool: ComputerUseToolName) -> Bool {
        switch tool {
        case .moveCursor, .click, .clickElement, .clickPoint, .performSecondaryAction, .drag, .pressKey, .hotkey, .typeText, .pasteText, .setValue, .scroll, .navigateURL, .navigateActiveBrowserTab, .openNewBrowserTab, .activateBrowserTab:
            return true
        case .listApps, .launchApp, .listWindows, .getAppState, .getWindowState, .listBrowserTabs, .pageGetText, .pageQueryDOM, .finish, .fail:
            return false
        }
    }

    private func target(from toolCall: ComputerUseToolCall, fallback: ComputerUseObservationTarget?) -> ComputerUseObservationTarget? {
        if !toolCall.canonicalBundleID.isEmpty {
            return ComputerUseObservationTarget(appName: toolCall.appName, bundleID: toolCall.canonicalBundleID)
        }
        if let appName = toolCall.appName?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty {
            return ComputerUseObservationTarget(appName: appName, bundleID: nil)
        }
        switch toolCall.tool {
        case .moveCursor, .click, .clickElement, .clickPoint, .performSecondaryAction, .setValue, .typeText, .pasteText, .pressKey, .hotkey, .scroll, .drag:
            return fallback
        default:
            return nil
        }
    }

    private func observationSignature(_ observation: ComputerUseObservation) -> String {
        let screenshot = observation.screenshot.map { screenshot in
            [
                "\(screenshot.width)x\(screenshot.height)",
                rectSignature(screenshot.windowFrame),
            ].joined(separator: "@")
        } ?? ""
        let elementSignature = observation.elements.prefix(16).map { element in
            [
                "\(element.elementIndex)",
                element.role,
                element.normalizedText,
                element.frame.map(rectSignature) ?? "",
            ].joined(separator: ":")
        }.joined(separator: ";")
        return [
            observation.bundleID,
            observation.appName,
            observation.windowTitle,
            "\(observation.elements.count)",
            observation.focusedElement?.normalizedText ?? "",
            observation.selectedText ?? "",
            screenshot,
            elementSignature,
        ].joined(separator: "|")
    }

    private func rectSignature(_ rect: ComputerUseRect) -> String {
        [
            Int(rect.x.rounded()),
            Int(rect.y.rounded()),
            Int(rect.width.rounded()),
            Int(rect.height.rounded()),
        ].map(String.init).joined(separator: ",")
    }

    private func formatToolCall(_ toolCall: ComputerUseToolCall) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(toolCall),
              let text = String(data: data, encoding: .utf8) else {
            return toolCall.summary
        }
        return text
    }

    private func resultStatusTitle(
        for toolCall: ComputerUseToolCall,
        result: ComputerUseExecutionResult
    ) -> ComputerUseStatusIdentity? {
        guard result.status == .executed else { return nil }
        switch toolCall.tool {
        case .launchApp:
            return .runningAction(result.message.hasPrefix("Opened") ? result.message : "Opened app")
        case .click, .clickElement, .clickPoint:
            return .runningAction(result.message.hasPrefix("Clicked") ? result.message : "Clicked")
        case .performSecondaryAction:
            return .runningAction(String(localized: "computer_use_planner.result_status.performed_action", defaultValue: "Performed action", bundle: .module, comment: "Planner result status when generic action is performed"))
        case .moveCursor:
            return .runningAction(String(localized: "computer_use_planner.result_status.moving_cursor", defaultValue: "Moving cursor", bundle: .module, comment: "Planner result status when cursor movement action is in progress"))
        case .typeText:
            return .runningAction(String(localized: "computer_use_planner.result_status.typed_text", defaultValue: "Typed text", bundle: .module, comment: "Planner result status when text typing action completed"))
        case .pasteText:
            return .runningAction(String(localized: "computer_use_planner.result_status.pasted_text", defaultValue: "Pasted text", bundle: .module, comment: "Planner result status when text paste action completed"))
        case .openNewBrowserTab:
            return .opening(target: String(localized: "computer_use_planner.result_status.new_tab_target", defaultValue: "new tab", bundle: .module, comment: "Target label for a newly opened browser tab result."))
        case .navigateURL, .navigateActiveBrowserTab:
            return .runningAction(String(localized: "computer_use_planner.result_status.navigated", defaultValue: "Navigated", bundle: .module, comment: "Result status when browser navigation completed."))
        case .pressKey, .hotkey:
            return .runningAction(String(localized: "computer_use_planner.result_status.pressed_key", defaultValue: "Pressed key", bundle: .module, comment: "Result status when a key press action was performed."))
        case .scroll:
            return .runningAction(String(localized: "computer_use_planner.result_status.scrolled", defaultValue: "Scrolled", bundle: .module, comment: "Result status when a scroll action was performed."))
        case .setValue:
            return .runningAction(String(localized: "computer_use_planner.result_status.set_value", defaultValue: "Set value", bundle: .module, comment: "Result status when a value was set."))
        case .drag:
            return .runningAction(String(localized: "computer_use_planner.result_status.dragged", defaultValue: "Dragged", bundle: .module, comment: "Result status when a drag action was performed."))
        case .activateBrowserTab:
            return .runningAction(String(localized: "computer_use_planner.result_status.switched_tab", defaultValue: "Switched tab", bundle: .module, comment: "Result status when switching tabs completed."))
        default:
            return nil
        }
    }

    private func statusTitle(for toolCall: ComputerUseToolCall) -> ComputerUseStatusIdentity {
        switch toolCall.tool {
        case .launchApp:
            let target = toolCall.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .opening(target: target?.isEmpty == false ? target! : String(localized: "computer_use_planner.status.target_app_fallback", defaultValue: "app", bundle: .module, comment: "Fallback target name used when no explicit app target is available."))
        case .click, .clickElement, .clickPoint:
            return .runningAction(String(localized: "computer_use_planner.status.clicking", defaultValue: "Clicking", bundle: .module, comment: "In-progress status while clicking."))
        case .performSecondaryAction:
            return .runningAction(String(localized: "computer_use_planner.status.performing_action", defaultValue: "Performing action", bundle: .module, comment: "In-progress status for a generic action."))
        case .moveCursor:
            return .runningAction(toolCall.label?.isEmpty == false ? String(format: "Moving to %@", "\(toolCall.label!)") : String(localized: "computer_use_planner.status.moving_cursor", defaultValue: "Moving cursor", bundle: .module, comment: "In-progress status while moving the cursor."))
        case .setValue:
            return .runningAction(String(localized: "computer_use_planner.status.setting_value", defaultValue: "Setting value", bundle: .module, comment: "In-progress status while setting a value."))
        case .typeText:
            return .runningAction(String(localized: "computer_use_planner.status.pasting-typing", defaultValue: "Typing", bundle: .module, comment: "In-progress status while typing text."))
        case .pasteText:
            return .runningAction(String(localized: "computer_use_planner.status.pasting", defaultValue: "Pasting", bundle: .module, comment: "In-progress status while pasting text."))
        case .pressKey, .hotkey:
            return .runningAction(String(localized: "computer_use_planner.status.pressing_key", defaultValue: "Pressing key", bundle: .module, comment: "In-progress status while pressing a key."))
        case .scroll:
            return .runningAction(String(localized: "computer_use_planner.status.dragging-scrolling", defaultValue: "Scrolling", bundle: .module, comment: "In-progress status while scrolling."))
        case .drag:
            return .runningAction(String(localized: "computer_use_planner.status.dragging", defaultValue: "Dragging", bundle: .module, comment: "In-progress status while dragging."))
        case .openNewBrowserTab:
            return .opening(target: String(localized: "computer_use_planner.status.new_tab_target", defaultValue: "new tab", bundle: .module, comment: "Target label for opening a new browser tab."))
        case .navigateURL, .navigateActiveBrowserTab:
            return .runningAction(String(localized: "computer_use_planner.status.navigating-opening-new-tab-opening-new-tab", defaultValue: "Navigating", bundle: .module, comment: "In-progress status while navigating."))
        case .activateBrowserTab:
            return .runningAction(String(localized: "computer_use_planner.status.switching_tab", defaultValue: "Switching tab", bundle: .module, comment: "In-progress status while switching tabs."))
        case .listApps, .listWindows, .listBrowserTabs, .pageGetText, .pageQueryDOM:
            return .runningAction(String(localized: "computer_use_planner.status.reading", defaultValue: "Reading", bundle: .module, comment: "In-progress status while reading content."))
        case .getAppState, .getWindowState:
            return .runningAction(String(localized: "computer_use_planner.status.observing", defaultValue: "Observing", bundle: .module, comment: "In-progress status while observing the UI state."))
        case .finish:
            return .done
        case .fail:
            return .failed
        }
    }

    private func planWithRetry(
        _ request: ComputerUsePlannerRequest,
        traceEvents: inout [ComputerUseTraceEvent]
    ) async throws -> ComputerUsePlannerResponse {
        var attempt = 0
        while true {
            onStatus(.planningStep("\(request.step)"))
            traceEvents.append(traceEvent(
                kind: "planning",
                title: "Planning",
                body: "Step \(request.step)\(stepLimitSuffix(request.maxSteps)). Prior tool results: \(request.priorOutcomes.count).",
                status: "planning",
                step: request.step
            ))
            do {
                return try await plan(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maxPlannerRetries, isRecoverablePlannerError(error) else {
                    throw error
                }
                attempt += 1
                let message = String(format: String(localized: "computer_use_planner.message.transient_failure_retrying", defaultValue: "Planner request failed transiently: %@. Retrying once.", bundle: .module, comment: "Message shown when a transient planner failure occurs and a single retry will be attempted."), "\(error.localizedDescription)")
                onStatus(.retryingPlanner)
                traceEvents.append(traceEvent(
                    kind: "planner_retry",
                    title: "Planner retry",
                    body: message,
                    status: "retrying",
                    step: request.step
                ))
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func isRecoverablePlannerError(_ error: Error) -> Bool {
        if let plannerError = error as? ComputerUsePlannerError {
            switch plannerError {
            case .requestFailed:
                return true
            case .backendFailed(let statusCode, _):
                return statusCode == 408 || statusCode == 429 || statusCode >= 500
            case .notAuthenticated, .invalidResponse, .invalidToolCall:
                return false
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("network connection was lost")
            || message.contains("timed out")
            || message.contains("connection reset")
            || message.contains("could not be reached")
    }

    private func recoverableFallbackMessage(
        for toolCall: ComputerUseToolCall,
        result: ComputerUseExecutionResult
    ) -> String? {
        guard result.status == .failed || result.status == .unsupported else { return nil }
        let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if browserToolCanFallBackToScreen(toolCall.tool), isBrowserAutomationPermissionFailure(message) {
            return String(format: String(localized: "computer_use_planner.recovery.browser_automation_permission_guidance", defaultValue: "%@. Continue with get_app_state plus AX/screenshot tools: click_element/click_point, paste_text/type_text, press_key/hotkey, and scroll. Do not retry browser page tools unless the user grants Chrome Apple Events JavaScript permission.", bundle: .module, comment: "Recovery guidance after browser automation permission limitations are encountered."), "\(message)")
        }
        if (toolCall.tool == .typeText || toolCall.tool == .pasteText), isTextFocusFailure(message) {
            return String(format: String(localized: "computer_use_planner.recovery.text_entry_retry_guidance", defaultValue: "%@. Continue with get_app_state and focus an editable target using click_element or set_value before retrying text entry. Prefer paste_text for Apple Notes and native rich-text editors. Do not repeat text entry until the focused target changes.", bundle: .module, comment: "Recovery guidance for retrying text entry after no effective change was detected."), "\(message)")
        }
        return nil
    }

    private func browserToolCanFallBackToScreen(_ tool: ComputerUseToolName) -> Bool {
        switch tool {
        case .listBrowserTabs, .activateBrowserTab, .openNewBrowserTab, .navigateURL, .navigateActiveBrowserTab, .pageGetText, .pageQueryDOM:
            return true
        default:
            return false
        }
    }

    private func isBrowserAutomationPermissionFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("apple events")
            || lowered.contains("javascript permission")
            || lowered.contains("not allowed")
            || lowered.contains("not authorized")
            || lowered.contains("automation")
    }

    private func isTextFocusFailure(_ message: String) -> Bool {
        message.lowercased().contains("no focused editable text target")
    }

    private func executionTraceBody(toolCall: ComputerUseToolCall, observation: ComputerUseObservation) -> String {
        let target = [
            observation.appName,
            observation.bundleID,
            observation.windowTitle,
            observation.screenshot?.screenshotID ?? "",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
        return "\(toolCall.summary)\nTarget: \(target.isEmpty ? "unknown" : target)\nArguments:\n\(formatToolCall(toolCall))"
    }

    private func traceEvent(
        kind: String,
        title: String,
        body: String,
        status: String?,
        step: Int?
    ) -> ComputerUseTraceEvent {
        ComputerUseTraceEvent(kind: kind, title: title, body: body, status: status, step: step)
    }
}
