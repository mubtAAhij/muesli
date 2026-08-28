import AppKit
import SwiftUI
import MuesliCore
import UniformTypeIdentifiers

private enum DictionaryRowMetrics {
    static let arrowWidth: CGFloat = 14
    static let thresholdWidth: CGFloat = 76
    static let actionButtonSize: CGFloat = 24
    static let actionsWidth: CGFloat = actionButtonSize * 2 + MuesliTheme.spacing8
    static let suggestionPageSize = 10
}

struct DictionaryView: View {
    let appState: AppState
    let controller: MuesliController

    @State private var isAdding = false
    @State private var newWord = ""
    @State private var newReplacement = ""
    @State private var newThreshold = 0.85
    @State private var isShowingAccessibilityPrompt = false
    @State private var suggestionPage = 0
    @State private var dictionaryAlertMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MuesliTheme.spacing24) {
                header
                if !appState.config.dictionarySuggestions.isEmpty {
                    suggestionList
                }
                wordList
            }
            .padding(MuesliTheme.spacing32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MuesliTheme.backgroundBase)
        .onAppear {
            controller.reconcilePendingDictionaryCorrectionAccessibilityEnable()
        }
        .alert(String(localized: "dictionary.accessibility_alert.title", defaultValue: "Enable Accessibility?", bundle: .module, comment: "Title of accessibility permission alert for dictionary suggestions."), isPresented: $isShowingAccessibilityPrompt) {
            Button(String(localized: "common.button.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel button title."), role: .cancel) {
                controller.cancelDictionaryCorrectionAccessibilityEnableRequest()
            }
            Button(String(localized: "dictionary.accessibility_alert.enable", defaultValue: "Enable", bundle: .module, comment: "Enable button title in accessibility permission alert.")) {
                controller.requestDictionaryCorrectionAccessibilityEnable()
            }
        } message: {
            Text(String(localized: "dictionary.accessibility_alert.message", defaultValue: "Dictionary suggestions briefly read focused app text via Accessibility after dictation. Grant access, then relaunch Muesli to turn suggestions on.", bundle: .module, comment: "Message explaining why accessibility permission is needed for dictionary suggestions."))
        }
        .alert(
            String(localized: "dictionary.view.title", defaultValue: "Dictionary", bundle: .module, comment: "Window title for dictionary view."),
            isPresented: Binding(
                get: { dictionaryAlertMessage != nil },
                set: { if !$0 { dictionaryAlertMessage = nil } }
            )
        ) {
            Button(String(localized: "common.button.ok", defaultValue: "OK", bundle: .module, comment: "Confirmation button title."), role: .cancel) { dictionaryAlertMessage = nil }
        } message: {
            Text(dictionaryAlertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack {
                Text(String(localized: "dictionary.title", defaultValue: "Dictionary", bundle: .module, comment: "Main heading for dictionary screen."))
                    .font(MuesliTheme.title1())
                    .foregroundStyle(MuesliTheme.textPrimary)
                Spacer()
                Toggle(
                    String(localized: "dictionary.header.suggestions_toggle", defaultValue: "Dictionary suggestions", bundle: .module, comment: "Label for dictionary suggestions toggle."),
                    isOn: Binding(
                        get: { appState.config.enableDictionaryCorrectionPrompts },
                        set: { handleDictionaryCorrectionPromptsToggle($0) }
                    )
                )
                .toggleStyle(.switch)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textSecondary)
                .help(String(localized: "dictionary.header.help.accessibility_summary", defaultValue: "Briefly reads focused app text after dictation to detect corrections.", bundle: .module, comment: "Help text describing dictionary accessibility behavior."))
                .featureTourTarget(.dictionarySuggestions)
                Button {
                    importDictionary()
                } label: {
                    Label(String(localized: "dictionary.header.import", defaultValue: "Import", bundle: .module, comment: "Import button label in dictionary header."), systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "dictionary.header.import.help", defaultValue: "Import dictionary entries from a JSON file", bundle: .module, comment: "Help text for import action."))
                Button {
                    exportDictionary()
                } label: {
                    Label(String(localized: "dictionary.header.export", defaultValue: "Export", bundle: .module, comment: "Export button label in dictionary header."), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .padding(.horizontal, MuesliTheme.spacing12)
                        .padding(.vertical, MuesliTheme.spacing8)
                        .background(MuesliTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "dictionary.header.export.help", defaultValue: "Export the current dictionary as JSON", bundle: .module, comment: "Help text for export action."))
                Button {
                    isAdding = true
                    newWord = ""
                    newReplacement = ""
                    newThreshold = 0.85
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(localized: "dictionary.header.add_new", defaultValue: "Add new", bundle: .module, comment: "Button label for adding a new dictionary entry."))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .padding(.horizontal, MuesliTheme.spacing12)
                    .padding(.vertical, MuesliTheme.spacing8)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                            .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(String(localized: "dictionary.header.description", defaultValue: "Add custom words for names, brands, and domain terms, and tune how aggressively each entry should fuzzy-match transcription errors.", bundle: .module, comment: "Description text for dictionary customization section."))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
        }
    }

    private func handleDictionaryCorrectionPromptsToggle(_ enabled: Bool) {
        if controller.setDictionaryCorrectionPromptsFromToggle(enabled) == .needsAccessibilityPermission {
            isShowingAccessibilityPrompt = true
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "dictionary.import.panel_title", defaultValue: "Import Muesli Dictionary", bundle: .module, comment: "Title of import open panel.")
        panel.message = String(localized: "dictionary.import.panel_message", defaultValue: "Choose a JSON dictionary file", bundle: .module, comment: "Message of import open panel.")
        panel.prompt = String(localized: "dictionary.import.panel_confirm", defaultValue: "Import", bundle: .module, comment: "Confirm button title in import open panel.")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        presentFilePanel(panel) { url in
            do {
                let data = try Data(contentsOf: url)
                let imported = try CustomWordDictionaryCodec.decode(data)
                let result = CustomWordDictionaryCodec.merge(
                    imported,
                    into: appState.config.customWords
                )
                controller.updateConfig { $0.customWords = result.words }

                let totalChanged = result.addedCount + result.updatedCount
                if totalChanged == 0 {
                    dictionaryAlertMessage = imported.isEmpty
                        ? String(localized: "dictionary.import.result.no_entries", defaultValue: "The selected dictionary did not contain any entries.", bundle: .module, comment: "Import result message when no entries are found.")
                        : String(localized: "dictionary.import.result.already_present", defaultValue: "All dictionary entries were already present.", bundle: .module, comment: "Import result message when all entries already exist.")
                } else {
                    var details = [String(format: String(localized: "dictionary.import.result.added_fragment", defaultValue: "Imported %d new", bundle: .module, comment: "Import summary fragment reporting how many new dictionary entries were added."), result.addedCount), String(format: String(localized: "dictionary.import.result.updated_fragment", defaultValue: "updated %d", bundle: .module, comment: "Import summary fragment reporting how many dictionary entries were updated."), result.updatedCount)]
                    if result.skippedCount > 0 {
                        details.append(String(format: String(localized: "dictionary.import.result.skipped_fragment", defaultValue: "skipped %d", bundle: .module, comment: "Import summary fragment reporting how many dictionary entries were skipped."), result.skippedCount))
                    }
                    dictionaryAlertMessage = details.joined(separator: ", ") + " " + String(localized: "dictionary.import.result.entries_suffix", defaultValue: "dictionary entries.", bundle: .module, comment: "Suffix appended to dictionary import summary sentence.")
                }
            } catch {
                dictionaryAlertMessage = String(format: String(localized: "dictionary.import.error", defaultValue: "Could not import the dictionary. %@", bundle: .module, comment: "Error message shown when dictionary import fails."), "\(error.localizedDescription)")
            }
        }
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.title = String(localized: "dictionary.export.panel_title", defaultValue: "Export Muesli Dictionary", bundle: .module, comment: "Title of export save panel for dictionary.")
        panel.prompt = String(localized: "dictionary.export.panel_confirm", defaultValue: "Export", bundle: .module, comment: "Confirm button title in dictionary export save panel.")
        panel.nameFieldStringValue = "muesli-dictionary.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        presentFilePanel(panel) { url in
            do {
                let data = try CustomWordDictionaryCodec.encode(appState.config.customWords)
                try data.write(to: url, options: .atomic)
                dictionaryAlertMessage = String(format: String(localized: "dictionary.export.success", defaultValue: "Exported %d dictionary entries.", bundle: .module, comment: "Success message shown after exporting dictionary entries."), appState.config.customWords.count)
            } catch {
                dictionaryAlertMessage = String(format: String(localized: "dictionary.export.error", defaultValue: "Could not export the dictionary. %@", bundle: .module, comment: "Error message shown when dictionary export fails."), "\(error.localizedDescription)")
            }
        }
    }

    private func presentFilePanel(_ panel: NSSavePanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "dictionary.suggestions.title", defaultValue: "Suggested Corrections", bundle: .module, comment: "Section title for suggested corrections list."))
                        .font(MuesliTheme.headline())
                        .foregroundStyle(MuesliTheme.textPrimary)
                    Text(String(localized: "dictionary.suggestions.description", defaultValue: "Corrections Muesli noticed by briefly reading focused app text after dictation.", bundle: .module, comment: "Description text explaining suggested corrections source."))
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, MuesliTheme.spacing16)
            .padding(.vertical, MuesliTheme.spacing12)

            Divider().background(MuesliTheme.surfaceBorder)

            ForEach(visibleDictionarySuggestions) { suggestion in
                DictionarySuggestionRow(suggestion: suggestion, controller: controller)
                Divider().background(MuesliTheme.surfaceBorder)
            }

            if suggestionPageCount > 1 {
                suggestionPaginationControls
            }
        }
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var visibleDictionarySuggestions: [DictionarySuggestion] {
        let suggestions = appState.config.dictionarySuggestions
        guard !suggestions.isEmpty else { return [] }
        let startIndex = boundedSuggestionPage * DictionaryRowMetrics.suggestionPageSize
        let endIndex = min(startIndex + DictionaryRowMetrics.suggestionPageSize, suggestions.count)
        return Array(suggestions[startIndex..<endIndex])
    }

    private var suggestionPageCount: Int {
        let count = appState.config.dictionarySuggestions.count
        guard count > 0 else { return 0 }
        return (count + DictionaryRowMetrics.suggestionPageSize - 1) / DictionaryRowMetrics.suggestionPageSize
    }

    private var boundedSuggestionPage: Int {
        min(max(suggestionPage, 0), max(suggestionPageCount - 1, 0))
    }

    private var suggestionRangeText: String {
        let count = appState.config.dictionarySuggestions.count
        guard count > 0 else { return "" }
        let start = boundedSuggestionPage * DictionaryRowMetrics.suggestionPageSize + 1
        let end = min(start + DictionaryRowMetrics.suggestionPageSize - 1, count)
        return String(format: String(localized: "dictionary.suggestions.range", defaultValue: "%d-%d of %d", bundle: .module, comment: "Pagination range text for suggestions list."), start, end, count)
    }

    private var suggestionPaginationControls: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Text(suggestionRangeText)
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)

            Spacer()

            DictionaryIconButton(
                systemName: "chevron.left",
                label: String(localized: "dictionary.suggestions.pagination.previous", defaultValue: "Previous suggestions", bundle: .module, comment: "Button label to show previous page of suggestions."),
                tint: MuesliTheme.textSecondary,
                isDisabled: boundedSuggestionPage == 0
            ) {
                suggestionPage = max(boundedSuggestionPage - 1, 0)
            }

            DictionaryIconButton(
                systemName: "chevron.right",
                label: String(localized: "dictionary.suggestions.pagination.next", defaultValue: "Next suggestions", bundle: .module, comment: "Button label to show next page of suggestions."),
                tint: MuesliTheme.textSecondary,
                isDisabled: boundedSuggestionPage >= suggestionPageCount - 1
            ) {
                suggestionPage = min(boundedSuggestionPage + 1, max(suggestionPageCount - 1, 0))
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    private var wordList: some View {
        VStack(spacing: 0) {
            columnHeader
            Divider().background(MuesliTheme.surfaceBorder)

            if isAdding {
                addWordRow
                Divider().background(MuesliTheme.surfaceBorder)
            }

            if appState.config.customWords.isEmpty && !isAdding {
                emptyState
            } else {
                ForEach(appState.config.customWords) { word in
                    DictionaryWordEditorRow(word: word, controller: controller)
                    Divider().background(MuesliTheme.surfaceBorder)
                }
            }
        }
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerMedium)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(MuesliTheme.textTertiary)
            Text(String(localized: "dictionary.empty_state.title", defaultValue: "No custom words yet", bundle: .module, comment: "Empty state title when no dictionary entries exist."))
                .font(MuesliTheme.body())
                .foregroundStyle(MuesliTheme.textSecondary)
            Text(String(localized: "dictionary.empty_state.subtitle", defaultValue: "Add words that transcription frequently gets wrong", bundle: .module, comment: "Empty state subtitle encouraging adding custom words."))
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(MuesliTheme.spacing32)
    }

    private var columnHeader: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Text(String(localized: "dictionary.table.column.match", defaultValue: "Match", bundle: .module, comment: "Column header for match term in dictionary table."))
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: DictionaryRowMetrics.arrowWidth)
            Text(String(localized: "dictionary.table.column.replace", defaultValue: "Replace", bundle: .module, comment: "Column header for replacement term in dictionary table."))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "dictionary.table.column.threshold", defaultValue: "Threshold", bundle: .module, comment: "Column header for fuzzy match threshold in dictionary table."))
                .frame(width: DictionaryRowMetrics.thresholdWidth, alignment: .leading)
            Color.clear
                .frame(width: DictionaryRowMetrics.actionsWidth)
        }
        .font(MuesliTheme.caption())
        .foregroundStyle(MuesliTheme.textTertiary)
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing8)
    }

    private var addWordRow: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            TextField(String(localized: "dictionary.table.cell.word", defaultValue: "Word", bundle: .module, comment: "Fallback cell value for missing dictionary word."), text: $newWord)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(width: DictionaryRowMetrics.arrowWidth)
            TextField(String(localized: "dictionary.form.replace_with", defaultValue: "Replace with", bundle: .module, comment: "Label for replacement text field in dictionary form."), text: $newReplacement)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            ThresholdEditor(value: $newThreshold)
            DictionaryIconButton(
                systemName: "checkmark",
                label: String(localized: "dictionary.add_word.button", defaultValue: "Add word", bundle: .module, comment: "Primary button title to add a new dictionary word."),
                tint: MuesliTheme.accent,
                isDisabled: newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                let trimmedWord = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedWord.isEmpty else { return }
                let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
                controller.addCustomWord(
                    CustomWord(
                        word: trimmedWord,
                        replacement: replacement.isEmpty ? nil : replacement,
                        matchingThreshold: newThreshold
                    )
                )
                isAdding = false
                newWord = ""
                newReplacement = ""
                newThreshold = 0.85
            }
            DictionaryIconButton(
                systemName: "xmark",
                label: String(localized: "dictionary.add_word.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel button title while adding a dictionary word."),
                tint: MuesliTheme.textTertiary
            ) {
                isAdding = false
                newWord = ""
                newReplacement = ""
                newThreshold = 0.85
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing12)
    }
}

private struct DictionarySuggestionRow: View {
    let suggestion: DictionarySuggestion
    let controller: MuesliController

    var body: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MuesliTheme.spacing8) {
                    Text(suggestion.observed)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                    Text(suggestion.replacement)
                        .font(MuesliTheme.body())
                        .foregroundStyle(MuesliTheme.textPrimary)
                        .lineLimit(1)
                }
                Text(detailText)
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            DictionaryIconButton(
                systemName: "checkmark",
                label: String(localized: "dictionary.suggestion.add_correction", defaultValue: "Add correction", bundle: .module, comment: "Button title to add a suggested correction to dictionary."),
                tint: MuesliTheme.accent
            ) {
                controller.acceptDictionarySuggestion(id: suggestion.id)
            }
            DictionaryIconButton(
                systemName: "xmark",
                label: String(localized: "dictionary.suggestion.dismiss_correction", defaultValue: "Dismiss correction", bundle: .module, comment: "Button title to dismiss a suggested correction."),
                tint: MuesliTheme.textTertiary
            ) {
                controller.dismissDictionarySuggestion(id: suggestion.id)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing12)
    }

    private var detailText: String {
        var parts = [String(format: String(localized: "dictionary.suggestion.seen_count", defaultValue: "Seen %dx", bundle: .module, comment: "Label showing how many times a suggestion has been seen."), suggestion.occurrenceCount)]
        if !suggestion.appDisplayName.isEmpty {
            parts.append(suggestion.appDisplayName)
        }
        return parts.joined(separator: " | ")
    }
}

private struct DictionaryWordEditorRow: View {
    let word: CustomWord
    let controller: MuesliController

    @State private var draftWord: String
    @State private var draftReplacement: String
    @State private var draftThreshold: Double

    init(word: CustomWord, controller: MuesliController) {
        self.word = word
        self.controller = controller
        _draftWord = State(initialValue: word.word)
        _draftReplacement = State(initialValue: word.replacement ?? "")
        _draftThreshold = State(initialValue: word.matchingThreshold)
    }

    private var trimmedWord: String {
        draftWord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReplacement: String {
        draftReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedWord != word.word
            || (trimmedReplacement.isEmpty ? nil : trimmedReplacement) != word.replacement
            || abs(draftThreshold - word.matchingThreshold) > 0.001
    }

    var body: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            TextField(String(localized: "dictionary.form.word", defaultValue: "Word", bundle: .module, comment: "Field label for dictionary word input."), text: $draftWord)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(width: DictionaryRowMetrics.arrowWidth)
            TextField(String(localized: "dictionary.form.replace_with", defaultValue: "Replace with", bundle: .module, comment: "Field label for replacement text input."), text: $draftReplacement)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            ThresholdEditor(value: $draftThreshold)
            DictionaryIconButton(
                systemName: "checkmark",
                label: String(localized: "dictionary.edit_word.save", defaultValue: "Save word", bundle: .module, comment: "Primary button title to save edited dictionary word."),
                tint: hasChanges && !trimmedWord.isEmpty ? MuesliTheme.accent : MuesliTheme.textTertiary,
                isDisabled: trimmedWord.isEmpty || !hasChanges
            ) {
                controller.updateCustomWord(
                    CustomWord(
                        id: word.id,
                        word: trimmedWord,
                        replacement: trimmedReplacement.isEmpty ? nil : trimmedReplacement,
                        matchingThreshold: draftThreshold
                    )
                )
            }
            DictionaryIconButton(
                systemName: "trash",
                label: String(localized: "dictionary.edit_word.delete", defaultValue: "Delete word", bundle: .module, comment: "Button title to delete a dictionary word."),
                tint: MuesliTheme.recording,
                weight: .regular
            ) {
                controller.removeCustomWord(id: word.id)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.vertical, MuesliTheme.spacing12)
    }
}

private struct ThresholdEditor: View {
    @Binding var value: Double

    @State private var isPresented = false
    @State private var draftPercent = ""

    private static let bounds = 0.70...0.99
    private static let sliderTint = Color.adaptive(dark: 0xFFFFFF, light: 0x000000)

    var body: some View {
        Button {
            draftPercent = Self.percentString(for: value)
            isPresented = true
        } label: {
            HStack(spacing: 3) {
                Text(Self.label(for: value))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MuesliTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MuesliTheme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                        .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(width: DictionaryRowMetrics.thresholdWidth, alignment: .leading)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            thresholdPopover
        }
        .help(String(localized: "dictionary.form.matching_threshold", defaultValue: "Matching threshold", bundle: .module, comment: "Label for matching threshold control."))
        .accessibilityLabel(String(localized: "dictionary.form.matching_threshold", defaultValue: "Matching threshold", bundle: .module, comment: "Accessibility/help label for matching threshold control."))
        .accessibilityValue(Self.label(for: value))
    }

    private static func label(for value: Double) -> String {
        "\(Int(round(value * 100)))%"
    }

    private static func percentString(for value: Double) -> String {
        "\(Int(round(clamp(value) * 100)))"
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    private var thresholdPopover: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing12) {
            HStack {
                Text(String(localized: "dictionary.table.column.threshold", defaultValue: "Threshold", bundle: .module, comment: "Column header for threshold value in dictionary table."))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    TextField("85", text: $draftPercent)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 48)
                        .onSubmit(commitDraftPercent)
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuesliTheme.textSecondary)
                }
            }

            ThresholdSlider(
                value: Binding(
                    get: { Self.clamp(value) },
                    set: { newValue in
                        value = Self.clamp(newValue)
                        draftPercent = Self.percentString(for: value)
                    }
                ),
                bounds: Self.bounds,
                tint: Self.sliderTint
            )

            HStack {
                Text("70%")
                Spacer()
                Text("99%")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(MuesliTheme.textTertiary)
        }
        .padding(MuesliTheme.spacing16)
        .frame(width: 240)
        .onAppear {
            draftPercent = Self.percentString(for: value)
        }
        .onChange(of: value) { _, newValue in
            draftPercent = Self.percentString(for: newValue)
        }
    }

    private func commitDraftPercent() {
        let normalized = draftPercent.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard let percent = Double(normalized) else {
            draftPercent = Self.percentString(for: value)
            return
        }
        value = Self.clamp(percent / 100)
        draftPercent = Self.percentString(for: value)
    }
}

private struct ThresholdSlider: View {
    @Binding var value: Double

    let bounds: ClosedRange<Double>
    let tint: Color

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = progress(for: value)
            let thumbX = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MuesliTheme.surfacePrimary)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(thumbX, thumbSize / 2), height: trackHeight)

                Circle()
                    .fill(tint)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: min(max(thumbX - thumbSize / 2, 0), width - thumbSize))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: thumbSize)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "dictionary.form.matching_threshold", defaultValue: "Matching threshold", bundle: .module, comment: "Label for matching threshold in edit form section."))
        .accessibilityValue("\(Int(round(value * 100)))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = clamped(value + 0.01)
            case .decrement:
                value = clamped(value - 0.01)
            @unknown default:
                break
            }
        }
    }

    private func progress(for value: Double) -> CGFloat {
        CGFloat((clamped(value) - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let progress = min(max(Double(locationX / width), 0), 1)
        let rawValue = bounds.lowerBound + progress * (bounds.upperBound - bounds.lowerBound)
        value = clamped((rawValue * 100).rounded() / 100)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

private struct DictionaryIconButton: View {
    let systemName: String
    let label: String
    let tint: Color
    var weight: Font.Weight = .bold
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: weight))
                .foregroundStyle(tint)
                .frame(
                    width: DictionaryRowMetrics.actionButtonSize,
                    height: DictionaryRowMetrics.actionButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
