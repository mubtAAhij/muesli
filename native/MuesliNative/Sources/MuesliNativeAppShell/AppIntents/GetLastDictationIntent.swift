import AppIntents

@available(macOS 13.0, *)
struct GetLastDictationIntent: AppIntent {
    static var title: LocalizedStringResource = String(localized: "app_intents.get_last_dictation.title", defaultValue: "Get Last Dictation", comment: "")
    static var description = IntentDescription(String(localized: "app_intents.get_last_dictation.description", defaultValue: "Returns the text of your most recent Muesli dictation.", comment: ""))

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = try MuesliShortcutsStore.open()
        guard let dictation = try store.recentDictations(limit: 1).first else {
            throw MuesliShortcutsError.noDictations
        }
        return .result(value: dictation.rawText)
    }
}
