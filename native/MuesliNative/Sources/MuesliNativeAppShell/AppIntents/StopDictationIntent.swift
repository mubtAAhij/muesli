import AppIntents
import MuesliNativeApp

@available(macOS 13.0, *)
struct StopDictationIntent: AppIntent {
    static var title: LocalizedStringResource = String(localized: "app_intents.stop_dictation.title", defaultValue: "Stop Dictation", comment: "")
    static var description = IntentDescription(String(localized: "app_intents.stop_dictation.description", defaultValue: "Stops an in-progress hands-free Muesli dictation and pastes/inserts the transcript.", comment: ""))
    // Ask the system to launch Muesli before performing so the in-process
    // controller exists; without this a closed app makes the wait time out.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let controller = try await MuesliShortcutsRuntime.waitForController()
        return .result(value: controller.stopDictationForShortcuts())
    }
}
