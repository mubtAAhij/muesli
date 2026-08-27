import Foundation

struct ComputerUseToolDefinition: Codable, Equatable {
    let name: ComputerUseToolName
    let description: String
    let schema: ComputerUseToolSchema
    let riskPolicy: String
    let mutating: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case schema
        case riskPolicy = "risk_policy"
        case mutating
    }
}

struct ComputerUseToolSchema: Codable, Equatable {
    let type: String
    let properties: [String: ComputerUseToolSchemaProperty]
    let required: [String]
    let additionalProperties: Bool

    init(
        properties: [String: ComputerUseToolSchemaProperty],
        required: [String]
    ) {
        type = "object"
        self.properties = properties
        self.required = required
        additionalProperties = false
    }
}

struct ComputerUseToolSchemaProperty: Codable, Equatable {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: ComputerUseToolSchemaArrayItems?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
        case items
    }

    init(
        type: String,
        description: String,
        enumValues: [String]? = nil,
        items: ComputerUseToolSchemaArrayItems? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

struct ComputerUseToolSchemaArrayItems: Codable, Equatable {
    let type: String
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case enumValues = "enum"
    }
}

enum ComputerUseToolRegistry {
    static let catalogVersion = "muesli-cua-tools-v1"

    static let definitions: [ComputerUseToolDefinition] = [
        definition(.listApps, "List running desktop apps with names, bundle IDs, process IDs, and active state.", required: [], properties: [:], risk: "safe read-only"),
        definition(.launchApp, "Launch or activate a macOS app by app_name or app_bundle_id.", required: [], properties: [
            "app_name": .string("Human app name, for example Google Chrome."),
            "app_bundle_id": .string("Bundle identifier, for example com.google.Chrome."),
        ], risk: "foreground activation allowed"),
        definition(.listWindows, "List visible windows, optionally scoped by app_bundle_id.", required: [], properties: [
            "app_bundle_id": .string("Optional bundle identifier to scope windows."),
        ], risk: "safe read-only"),
        definition(.getAppState, "Capture fresh app/window state: state_id, app/window identity, screenshot metadata/image for the planner, AX candidates, focused element, selected text, cursor, and app hints.", required: [], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.capture.option.app_bundle_hint", defaultValue: "Optional app bundle to activate before capture.", bundle: Bundle.module, comment: "Help text describing optional app bundle parameter before capture.")),
            "window_id": .integer(String(localized: "computer_use.tool_registry.capture.option.window_id_hint", defaultValue: "Optional window id hint.", bundle: Bundle.module, comment: "Help text describing optional window identifier hint parameter.")),
        ], risk: "safe read-only"),
        definition(.getWindowState, "Compatibility alias for get_app_state. Prefer get_app_state for new planner calls.", required: [], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.capture.option.app_bundle_hint", defaultValue: "Optional app bundle to activate before capture.", bundle: Bundle.module, comment: "Help text describing optional app bundle parameter before capture.")),
            "window_id": .integer(String(localized: "computer_use.tool_registry.capture.option.window_id_hint", defaultValue: "Optional window id hint.", bundle: Bundle.module, comment: "Help text describing optional window identifier hint parameter.")),
        ], risk: "safe read-only"),
        definition(.moveCursor, "Move the visible Muesli CUA cursor to a screenshot coordinate without clicking. Use this before uncertain coordinate clicks to show intent.", required: ["screenshot_id", "x", "y"], properties: [
            "screenshot_id": .string(String(localized: "computer_use.tool_registry.option.current_screenshot_id", defaultValue: "Current screenshot id.", bundle: Bundle.module, comment: "Help text describing current screenshot identifier parameter.")),
            "x": .number("Screenshot pixel x coordinate."),
            "y": .number("Screenshot pixel y coordinate."),
            "label": .string("Human target label for live feedback and trace."),
        ], risk: "visual feedback only"),
        definition(.clickElement, "Click an AX element from the latest get_app_state by element_index or element_id. Use this whenever a matching AX candidate exists.", required: [], properties: [
            "element_index": .integer("Temporary element index from the latest state."),
            "element_id": .string("Temporary element id from the latest state, for example e12."),
            "clicks": .integer("1 for single click, 2 for double click."),
            "button": .string("left or right."),
            "label": .string("Human target label for trace and safety."),
        ], risk: "confirmation for risky labels"),
        definition(.clickPoint, "Click a screenshot coordinate when no AX target exists. Requires screenshot_id plus x/y from the latest state.", required: ["screenshot_id", "x", "y"], properties: [
            "screenshot_id": .string(String(localized: "computer_use.tool_registry.option.current_screenshot_id", defaultValue: "Current screenshot id.", bundle: Bundle.module, comment: "Help text describing current screenshot identifier parameter.")),
            "x": .number("Screenshot pixel x coordinate."),
            "y": .number("Screenshot pixel y coordinate."),
            "clicks": .integer("1 for single click, 2 for double click."),
            "button": .string("left or right."),
            "label": .string(String(localized: "computer_use.tool_registry.option.human_target_label_trace_safety", defaultValue: "Human target label for trace and safety.", bundle: Bundle.module, comment: "Help text for human-readable target label used in trace and safety context.")),
        ], risk: "confirmation for risky labels or unknown coordinate targets"),
        definition(.performSecondaryAction, "Perform an advertised AX action other than AXPress on an element from the latest get_app_state. Use only action_name values present on that element's action_names.", required: ["action_name"], properties: [
            "element_index": .integer(String(localized: "computer_use.tool_registry.option.temporary_element_index_latest_state", defaultValue: "Temporary element index from the latest state.", bundle: Bundle.module, comment: "Help text for temporary element index derived from latest UI state.")),
            "element_id": .string(String(localized: "computer_use.tool_registry.option.temporary_element_id_latest_state", defaultValue: "Temporary element id from the latest state.", bundle: Bundle.module, comment: "Help text for temporary element identifier derived from latest UI state.")),
            "action_name": .string("Advertised AX action name, for example AXShowMenu, AXConfirm, AXCancel, AXIncrement, AXDecrement, or AXScrollDownByPage."),
            "label": .string(String(localized: "computer_use.tool_registry.option.human_target_label_trace_safety", defaultValue: "Human target label for trace and safety.", bundle: Bundle.module, comment: "Help text for human-readable target label used in trace and safety context.")),
        ], risk: "only invokes advertised AX actions; confirmation for risky labels"),
        definition(.setValue, "Set an AX element value by element_index/element_id from the latest state.", required: ["value"], properties: [
            "element_index": .integer(String(localized: "computer_use.tool_registry.option.temporary_element_index_latest_state", defaultValue: "Temporary element index from the latest state.", bundle: Bundle.module, comment: "Help text for temporary element index derived from latest UI state.")),
            "element_id": .string(String(localized: "computer_use.tool_registry.option.temporary_element_id_latest_state", defaultValue: "Temporary element id from the latest state.", bundle: Bundle.module, comment: "Help text for temporary element identifier derived from latest UI state.")),
            "value": .string("Value to set."),
            "label": .string(String(localized: "computer_use.tool_registry.option.human_target_label_trace", defaultValue: "Human target label for trace.", bundle: Bundle.module, comment: "Help text for human-readable target label used for trace logging.")),
        ], risk: "local validation only; no send/submit bypass"),
        definition(.typeText, "Type literal text using keyboard input. Prefer app_name/app_bundle_id and, when available, element_index/element_id so Muesli can activate the app and focus the editable target before typing.", required: ["text"], properties: [
            "app_name": .string(String(localized: "computer_use.tool_registry.option.target_app_name_example_notes", defaultValue: "Optional target app name, for example Notes.", bundle: Bundle.module, comment: "Help text for optional target app name with Notes example.")),
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.target_app_bundle_identifier_example_notes", defaultValue: "Optional target app bundle identifier, for example com.apple.Notes.", bundle: Bundle.module, comment: "Help text for optional target app bundle identifier with Notes example.")),
            "element_index": .integer(String(localized: "computer_use.tool_registry.option.temporary_editable_element_index_latest_state", defaultValue: "Optional temporary editable element index from the latest state.", bundle: Bundle.module, comment: "Help text for optional temporary editable element index from latest state.")),
            "element_id": .string(String(localized: "computer_use.tool_registry.option.temporary_editable_element_id_latest_state", defaultValue: "Optional temporary editable element id from the latest state.", bundle: Bundle.module, comment: "Help text for optional temporary editable element identifier from latest state.")),
            "text": .string("Text to type."),
            "label": .string(String(localized: "computer_use.tool_registry.option.human_target_label_trace", defaultValue: "Human target label for trace.", bundle: Bundle.module, comment: "Help text for human-readable target label used for trace logging.")),
        ], risk: "safe primitive; activates optional app target and requires focused editable text"),
        definition(.pasteText, "Paste text into the focused editable field using the clipboard, then restore the user's clipboard. Prefer app_name/app_bundle_id and element_index/element_id when available. Prefer this for Apple Notes, native rich-text editors, and multi-word text insertion after focusing the editable target.", required: ["text"], properties: [
            "app_name": .string(String(localized: "computer_use.tool_registry.option.target_app_name_example_notes", defaultValue: "Optional target app name, for example Notes.", bundle: Bundle.module, comment: "Help text for optional target app name with Notes example.")),
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.target_app_bundle_identifier_example_notes", defaultValue: "Optional target app bundle identifier, for example com.apple.Notes.", bundle: Bundle.module, comment: "Help text for optional target app bundle identifier with Notes example.")),
            "element_index": .integer(String(localized: "computer_use.tool_registry.option.temporary_editable_element_index_latest_state", defaultValue: "Optional temporary editable element index from the latest state.", bundle: Bundle.module, comment: "Help text for optional temporary editable element index from latest state.")),
            "element_id": .string(String(localized: "computer_use.tool_registry.option.temporary_editable_element_id_latest_state", defaultValue: "Optional temporary editable element id from the latest state.", bundle: Bundle.module, comment: "Help text for optional temporary editable element identifier from latest state.")),
            "text": .string("Text to paste."),
            "label": .string("Human target label for trace."),
        ], risk: "safe primitive; temporarily uses clipboard and restores it"),
        definition(.pressKey, "Press one key with optional modifiers.", required: ["key"], properties: [
            "key": .string("Key name, for example enter, tab, l, escape."),
            "modifiers": .array("Optional modifiers.", item: .string(String(localized: "computer_use.tool_registry.option.modifier", defaultValue: "Modifier", bundle: Bundle.module, comment: "Parameter label for keyboard modifier argument."), enumValues: ComputerUseKeyModifier.allCases.map(\.rawValue))),
        ], risk: "confirmation for Cmd-Q and Cmd-W"),
        definition(.hotkey, "Alias for press_key used for keyboard shortcuts.", required: ["key"], properties: [
            "key": .string("Key name."),
            "modifiers": .array("Required or optional modifiers.", item: .string(String(localized: "computer_use.tool_registry.option.modifier", defaultValue: "Modifier", bundle: Bundle.module, comment: "Parameter label for keyboard modifier argument."), enumValues: ComputerUseKeyModifier.allCases.map(\.rawValue))),
        ], risk: "confirmation for Cmd-Q and Cmd-W"),
        definition(.scroll, "Scroll the current view or a scrollable AX element from the latest state.", required: ["direction"], properties: [
            "element_index": .integer("Optional temporary scrollable element index from the latest state."),
            "element_id": .string("Optional temporary scrollable element id from the latest state."),
            "direction": .string("Scroll direction.", enumValues: ["up", "down", "left", "right"]),
            "pages": .number("Approximate page count, default 1."),
        ], risk: "safe primitive"),
        definition(.drag, "Drag from one screenshot coordinate to another.", required: ["screenshot_id", "x", "y", "to_x", "to_y"], properties: [
            "screenshot_id": .string("Current screenshot id."),
            "x": .number("Start screenshot pixel x."),
            "y": .number("Start screenshot pixel y."),
            "to_x": .number("End screenshot pixel x."),
            "to_y": .number("End screenshot pixel y."),
            "label": .string("Human target label for trace and safety."),
        ], risk: "confirmation for risky labels"),
        definition(.listBrowserTabs, "List tabs in Chrome-compatible browser windows.", required: ["app_bundle_id"], properties: [
            "app_bundle_id": .string("Browser bundle identifier, currently com.google.Chrome."),
        ], risk: "safe read-only"),
        definition(.activateBrowserTab, "Activate a browser tab by window_index and tab_index.", required: ["app_bundle_id", "window_index", "tab_index"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
            "window_index": .integer("1-based browser window index."),
            "tab_index": .integer("1-based tab index in the window."),
        ], risk: "foreground activation allowed"),
        definition(.openNewBrowserTab, "Open a new tab in a supported browser and make it active. Prefer this for new or separate web tasks.", required: ["app_bundle_id"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
        ], risk: "foreground activation allowed"),
        definition(.navigateURL, "Navigate the selected browser tab to a safe http/https URL.", required: ["app_bundle_id", "url"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
            "window_index": .integer("Optional 1-based browser window index."),
            "tab_index": .integer("Optional 1-based tab index."),
            "url": .string("http or https URL only."),
        ], risk: "rejects javascript:, file:, data:, shell-like strings, and unsafe URLs"),
        definition(.navigateActiveBrowserTab, "Navigate the active browser tab to a safe http/https URL without tab indexes. Prefer this immediately after open_new_browser_tab.", required: ["app_bundle_id", "url"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
            "url": .string("http or https URL only."),
        ], risk: "rejects javascript:, file:, data:, shell-like strings, and unsafe URLs"),
        definition(.pageGetText, "Read visible/body text from a Chrome tab using read-only Apple Events JavaScript.", required: ["app_bundle_id"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
            "window_index": .integer(String(localized: "computer_use.tool_registry.option.browser_window_index_one_based", defaultValue: "Optional 1-based browser window index.", bundle: Bundle.module, comment: "Help text for optional one-based browser window index argument.")),
            "tab_index": .integer(String(localized: "computer_use.tool_registry.option.tab_index_one_based", defaultValue: "Optional 1-based tab index.", bundle: Bundle.module, comment: "Help text for optional one-based browser tab index argument.")),
        ], risk: "safe read-only"),
        definition(.pageQueryDOM, "Query DOM nodes in a Chrome tab and return text plus selected attributes. Read-only only.", required: ["app_bundle_id", "selector"], properties: [
            "app_bundle_id": .string(String(localized: "computer_use.tool_registry.option.browser_bundle_identifier_currently_chrome", defaultValue: "Browser bundle identifier, currently com.google.Chrome.", bundle: Bundle.module, comment: "Help text describing browser bundle identifier with current Chrome default.")),
            "window_index": .integer(String(localized: "computer_use.tool_registry.option.browser_window_index_one_based", defaultValue: "Optional 1-based browser window index.", bundle: Bundle.module, comment: "Help text for optional one-based browser window index argument.")),
            "tab_index": .integer(String(localized: "computer_use.tool_registry.option.tab_index_one_based", defaultValue: "Optional 1-based tab index.", bundle: Bundle.module, comment: "Help text for optional one-based browser tab index argument.")),
            "selector": .string("CSS selector."),
            "attributes": .array("Attributes to return.", item: .string("Attribute name.")),
        ], risk: "safe read-only"),
        definition(.finish, "Finish when the user task is complete. Use reason for the final answer.", required: [], properties: [
            "reason": .string("Final user-facing result."),
        ], risk: "safe finalization"),
        definition(.fail, "Fail explicitly when blocked, unsupported, unsafe, or incomplete. Use reason to explain.", required: ["reason"], properties: [
            "reason": .string("Failure reason."),
        ], risk: "safe finalization"),
    ]

    static func definition(for tool: ComputerUseToolName) -> ComputerUseToolDefinition? {
        definitions.first { $0.name == tool }
    }

    static func promptDocumentation() -> String {
        definitions.map { definition in
            let required = definition.schema.required.isEmpty ? "none" : definition.schema.required.joined(separator: ", ")
            let properties = definition.schema.properties
                .sorted { $0.key < $1.key }
                .map { key, property in
                    var line = "  - \(key): \(property.type). \(property.description)"
                    if let values = property.enumValues {
                        line += " Allowed: \(values.joined(separator: ", "))."
                    }
                    return line
                }
                .joined(separator: "\n")
            let propertyText = properties.isEmpty ? "  - no arguments" : properties
            return """
            Tool: \(definition.name.rawValue)
            Description: \(definition.description)
            Required: \(required)
            Risk policy: \(definition.riskPolicy)
            Schema properties:
            \(propertyText)
            """
        }.joined(separator: "\n\n")
    }

    static func nativeToolDefinitions() -> [[String: Any]] {
        definitions.map { definition in
            [
                "type": "function",
                "name": definition.name.rawValue,
                "description": "\(definition.description) Risk policy: \(definition.riskPolicy)",
                "parameters": toolParameters(for: definition),
            ]
        }
    }

    private static func toolParameters(for definition: ComputerUseToolDefinition) -> [String: Any] {
        let properties = definition.schema.properties
            .filter { $0.key != "tool" }
            .reduce(into: [String: Any]()) { partial, entry in
                partial[entry.key] = entry.value.jsonSchema
            }
        return [
            "type": definition.schema.type,
            "properties": properties,
            "required": definition.schema.required.filter { $0 != "tool" },
            "additionalProperties": definition.schema.additionalProperties,
        ]
    }

    private static func definition(
        _ name: ComputerUseToolName,
        _ description: String,
        required: [String],
        properties: [String: ComputerUseToolSchemaProperty],
        risk: String
    ) -> ComputerUseToolDefinition {
        ComputerUseToolDefinition(
            name: name,
            description: description,
            schema: ComputerUseToolSchema(
                properties: ["tool": .string("Tool name.", enumValues: [name.rawValue])].merging(properties) { current, _ in current },
                required: ["tool"] + required
            ),
            riskPolicy: risk,
            mutating: ComputerUseToolInvocation(tool: name).isMutating
        )
    }
}

private extension ComputerUseToolSchemaProperty {
    static func string(_ description: String, enumValues: [String]? = nil) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "string", description: description, enumValues: enumValues)
    }

    static func integer(_ description: String) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "integer", description: description)
    }

    static func number(_ description: String) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(type: "number", description: description)
    }

    static func array(_ description: String, item: ComputerUseToolSchemaProperty) -> ComputerUseToolSchemaProperty {
        ComputerUseToolSchemaProperty(
            type: "array",
            description: description,
            items: ComputerUseToolSchemaArrayItems(type: item.type, enumValues: item.enumValues)
        )
    }

    var jsonSchema: [String: Any] {
        var schema: [String: Any] = [
            "type": type,
            "description": description,
        ]
        if let enumValues {
            schema["enum"] = enumValues
        }
        if let items {
            var itemSchema: [String: Any] = ["type": items.type]
            if let enumValues = items.enumValues {
                itemSchema["enum"] = enumValues
            }
            schema["items"] = itemSchema
        }
        return schema
    }
}
