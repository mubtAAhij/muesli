import Foundation

enum ComputerUseBrowserAutomation {
    static var runAppleScriptForTests: ((String) throws -> String)?

    static func listTabs(appBundleID: String) async -> ComputerUseExecutionResult {
        guard supportsBrowser(appBundleID) else {
            return .unsupported(String(localized: "computer_use.browser.error.chrome_only_supported", defaultValue: "Browser tools currently support Google Chrome only", bundle: .module, comment: "Error indicating browser automation supports only Google Chrome."))
        }
        let script = """
        set output to ""
        tell application id "\(appleScriptString(appBundleID))"
          repeat with w from 1 to count of windows
            set activeIndex to active tab index of window w
            repeat with t from 1 to count of tabs of window w
              set tabTitle to title of tab t of window w
              set tabURL to URL of tab t of window w
              set isActive to (t is activeIndex)
              set output to output & w & tab & t & tab & isActive & tab & tabTitle & tab & tabURL & linefeed
            end repeat
          end repeat
        end tell
        return output
        """
        do {
            let output = try await runAppleScript(script)
            let tabs = parseTabs(output: output, appBundleID: appBundleID)
            guard !tabs.isEmpty else {
                return .executed(String(localized: "computer_use.browser.tabs.none", defaultValue: "No browser tabs", bundle: .module, comment: "Result message when no browser tabs are available."))
            }
            return .executed(tabs.map { tab in
                "\(tab.windowIndex):\(tab.tabIndex) \(tab.isActive ? "active " : "")\(tab.title) - \(tab.url)"
            }.joined(separator: "\n"))
        } catch is CancellationError {
            return .cancelled()
        } catch {
            return .failed(browserScriptError(error))
        }
    }

    static func activateTab(appBundleID: String, windowIndex: Int, tabIndex: Int) async -> ComputerUseExecutionResult {
        guard supportsBrowser(appBundleID) else {
            return .unsupported(String(localized: "computer_use.browser.error.chrome_only_supported", defaultValue: "Browser tools currently support Google Chrome only", bundle: .module, comment: "Error indicating browser automation supports only Google Chrome."))
        }
        let script = """
        tell application id "\(appleScriptString(appBundleID))"
          activate
          set active tab index of window \(max(1, windowIndex)) to \(max(1, tabIndex))
          set index of window \(max(1, windowIndex)) to 1
        end tell
        """
        do {
            _ = try await runAppleScript(script)
            return .executed(String(format: String(localized: "computer_use.browser.tab.activate.success", defaultValue: "Activated browser tab %d:%d", bundle: .module, comment: "Success message after activating a specific browser tab."), windowIndex, tabIndex))
        } catch is CancellationError {
            return .cancelled()
        } catch {
            return .failed(browserScriptError(error))
        }
    }

    static func openNewTab(appBundleID: String) async -> ComputerUseExecutionResult {
        guard supportsBrowser(appBundleID) else {
            return .unsupported(String(localized: "computer_use.browser.error.chrome_only_supported", defaultValue: "Browser tools currently support Google Chrome only", bundle: .module, comment: "Error indicating browser automation supports only Google Chrome."))
        }
        let script = """
        tell application id "\(appleScriptString(appBundleID))"
          activate
          if (count of windows) is 0 then
            make new window
          else
            set index of front window to 1
            tell front window to make new tab
            set active tab index of front window to (count of tabs of front window)
          end if
        end tell
        """
        do {
            _ = try await runAppleScript(script)
            return .executed(String(localized: "computer_use.browser.tab.opened", defaultValue: "Opened new browser tab", bundle: .module, comment: "Success message after opening a new browser tab."))
        } catch is CancellationError {
            return .cancelled()
        } catch {
            return .failed(browserScriptError(error))
        }
    }

    static func navigate(appBundleID: String, windowIndex: Int?, tabIndex: Int?, url: String) async -> ComputerUseExecutionResult {
        guard supportsBrowser(appBundleID) else {
            return .unsupported(String(localized: "computer_use.browser.error.chrome_only_supported", defaultValue: "Browser tools currently support Google Chrome only", bundle: .module, comment: "Error indicating browser automation supports only Google Chrome."))
        }
        guard let safeURL = ComputerUseToolInvocation.safeHTTPURL(url) else {
            return .needsConfirmation(String(localized: "computer_use.browser.navigate.confirm_unsafe_url", defaultValue: "Confirm: unsafe navigation URL", bundle: .module, comment: "Confirmation prompt for navigating to an unsafe URL."))
        }
        let script = navigateScript(
            appBundleID: appBundleID,
            windowIndex: windowIndex,
            tabIndex: tabIndex,
            url: safeURL.absoluteString
        )
        do {
            let output = try await runAppleScript(script)
            let suffix = output.isEmpty ? "" : " (\(output))"
            return .executed(String(format: String(localized: "computer_use.browser.navigate.success", defaultValue: "Navigated to %@%@", bundle: .module, comment: "Success message after navigating browser to a URL with optional suffix."), "\(safeURL.absoluteString)", "\(suffix)"))
        } catch is CancellationError {
            return .cancelled()
        } catch {
            return .failed(browserScriptError(error))
        }
    }

    static func navigateScript(appBundleID: String, windowIndex: Int?, tabIndex: Int?, url: String) -> String {
        let requestedWindow = max(1, windowIndex ?? 1)
        let requestedTab = max(1, tabIndex ?? 1)
        let hasWindowHint = windowIndex != nil
        let hasTabHint = tabIndex != nil
        return """
        tell application id "\(appleScriptString(appBundleID))"
          activate
          if (count of windows) is 0 then make new window
          set targetWindow to front window
          set usedFallback to false
          if \(appleScriptBool(hasWindowHint)) then
            if \(requestedWindow) <= (count of windows) then
              set targetWindow to window \(requestedWindow)
            else
              set usedFallback to true
            end if
          end if
          set targetTab to active tab of targetWindow
          if \(appleScriptBool(hasTabHint)) then
            if \(requestedTab) <= (count of tabs of targetWindow) then
              set targetTab to tab \(requestedTab) of targetWindow
            else
              set usedFallback to true
            end if
          end if
          set URL of targetTab to "\(appleScriptString(url))"
          if usedFallback then
            return "used active tab fallback"
          end if
          return ""
        end tell
        """
    }

    static func pageText(appBundleID: String, windowIndex: Int?, tabIndex: Int?) async -> ComputerUseExecutionResult {
        await runReadOnlyJavaScript(
            appBundleID: appBundleID,
            windowIndex: windowIndex,
            tabIndex: tabIndex,
            javascript: """
            (() => {
              const text = document.body ? document.body.innerText : document.documentElement.innerText;
              return String(text || '').slice(0, 12000);
            })()
            """,
            successPrefix: "Page text"
        )
    }

    static func queryDOM(
        appBundleID: String,
        windowIndex: Int?,
        tabIndex: Int?,
        selector: String,
        attributes: [String]
    ) async -> ComputerUseExecutionResult {
        let selectorJSON = jsonString(selector)
        let selectedAttributes = Array(attributes.prefix(12))
        let attributesJSON = jsonArray(selectedAttributes)
        return await runReadOnlyJavaScript(
            appBundleID: appBundleID,
            windowIndex: windowIndex,
            tabIndex: tabIndex,
            javascript: """
            (() => {
              const selector = \(selectorJSON);
              const attrs = \(attributesJSON);
              const nodes = Array.from(document.querySelectorAll(selector)).slice(0, 80);
              return JSON.stringify(nodes.map((node, index) => {
                const out = {
                  index,
                  tag: node.tagName ? node.tagName.toLowerCase() : '',
                  text: (node.innerText || node.textContent || '').trim().slice(0, 500)
                };
                for (const attr of attrs) {
                  out[attr] = node.getAttribute(attr) || '';
                }
                return out;
              }));
            })()
            """,
            successPrefix: "DOM query"
        )
    }

    static func parseTabs(output: String, appBundleID: String) -> [ComputerUseBrowserTabInfo] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 5,
                      let windowIndex = Int(parts[0]),
                      let tabIndex = Int(parts[1])
                else { return nil }
                return ComputerUseBrowserTabInfo(
                    appBundleID: appBundleID,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: parts[3],
                    url: parts[4],
                    isActive: parts[2].lowercased() == "true"
                )
            }
    }

    private static func runReadOnlyJavaScript(
        appBundleID: String,
        windowIndex: Int?,
        tabIndex: Int?,
        javascript: String,
        successPrefix: String
    ) async -> ComputerUseExecutionResult {
        guard supportsBrowser(appBundleID) else {
            return .unsupported(String(localized: "computer_use.browser.error.chrome_only_supported", defaultValue: "Browser tools currently support Google Chrome only", bundle: .module, comment: "Error indicating browser automation supports only Google Chrome."))
        }
        let target = browserTabReference(windowIndex: windowIndex, tabIndex: tabIndex)
        let script = """
        tell application id "\(appleScriptString(appBundleID))"
          execute javascript \(jsonString(javascript)) in \(target)
        end tell
        """
        do {
            let output = try await runAppleScript(script)
            return .executed("\(successPrefix): \(String(output.prefix(12000)))")
        } catch is CancellationError {
            return .cancelled()
        } catch {
            return .failed(browserScriptError(error))
        }
    }

    private static func browserTabReference(windowIndex: Int?, tabIndex: Int?) -> String {
        if let windowIndex, let tabIndex {
            return "tab \(max(1, tabIndex)) of window \(max(1, windowIndex))"
        }
        if let windowIndex {
            return "active tab of window \(max(1, windowIndex))"
        }
        return "active tab of front window"
    }

    private static func supportsBrowser(_ appBundleID: String) -> Bool {
        appBundleID == "com.google.Chrome"
    }

    private static func runAppleScript(_ script: String) async throws -> String {
        if let runAppleScriptForTests {
            return try runAppleScriptForTests(script)
        }

        let processBox = AppleScriptProcessBox()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        process.arguments = ["-e", script]
                        let output = Pipe()
                        let error = Pipe()
                        process.standardOutput = output
                        process.standardError = error
                        guard processBox.set(process) else {
                            throw CancellationError()
                        }
                        try process.run()
                        process.waitUntilExit()

                        let wasCancelled = processBox.clear()
                        if wasCancelled {
                            throw CancellationError()
                        }

                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        let errorData = error.fileHandleForReading.readDataToEndOfFile()
                        if process.terminationStatus != 0 {
                            let message = String(data: errorData, encoding: .utf8) ?? String(localized: "computer_use.browser.error.apple_events_failed", defaultValue: "Apple Events failed", bundle: .module, comment: "Error message when Apple Events automation call fails.")
                            throw NSError(domain: "ComputerUseBrowserAutomation", code: Int(process.terminationStatus), userInfo: [
                                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines),
                            ])
                        }
                        continuation.resume(returning: (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    } catch {
                        _ = processBox.clear()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private static func browserScriptError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("not allowed") || message.localizedCaseInsensitiveContains("javascript") {
            return String(localized: "computer_use.browser.error.chrome_permission_required", defaultValue: "Chrome Apple Events JavaScript permission is required for browser page tools", bundle: .module, comment: "Error explaining required Chrome automation permission.")
        }
        return message.isEmpty ? String(localized: "computer_use.browser.error.automation_failed", defaultValue: "Browser automation failed", bundle: .module, comment: "Generic browser automation failure message.") : message
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{0}", with: "")
    }

    private static func appleScriptBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return text
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}

private final class AppleScriptProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let currentProcess = process
        lock.unlock()
        currentProcess?.terminate()
    }

    @discardableResult
    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasCancelled = cancelled
        process = nil
        return wasCancelled
    }
}
