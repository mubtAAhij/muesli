import AppIntents
import MuesliNativeApp

@available(macOS 13.0, *)
struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = String(localized: "app_intents.start_dictation.title", defaultValue: "Start Dictation", comment: "")
    static var description = IntentDescription(String(localized: "app_intents.start_dictation.description", defaultValue: "Starts hands-free Muesli dictation, same as double-tapping the dictation hotkey.", comment: ""))
    // Ask the system to launch Muesli before performing so the in-process
    // controller exists; without this a closed app makes the wait time out.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let controller = try await MuesliShortcutsRuntime.waitForController()
        return .result(value: controller.startDictationForShortcuts())
    }
}
