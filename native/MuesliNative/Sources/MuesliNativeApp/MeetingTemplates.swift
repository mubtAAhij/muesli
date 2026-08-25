import Foundation
import MuesliCore

struct CustomMeetingTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var prompt: String
    var icon: String

    init(
        id: String = UUID().uuidString,
        name: String,
        prompt: String,
        icon: String = MeetingTemplates.customIconFallback
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.icon = MeetingTemplates.normalizedCustomIcon(named: icon)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        icon = MeetingTemplates.normalizedCustomIcon(
            named: try c.decodeIfPresent(String.self, forKey: .icon)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(MeetingTemplates.normalizedCustomIcon(named: icon), forKey: .icon)
    }
}

struct MeetingTemplateSnapshot: Equatable, Sendable {
    let id: String
    let name: String
    let kind: MeetingTemplateKind
    let prompt: String
}

struct MeetingTemplateDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String?
    let icon: String
    let kind: MeetingTemplateKind
    let promptBody: String

    var snapshot: MeetingTemplateSnapshot {
        MeetingTemplateSnapshot(
            id: id,
            name: title,
            kind: kind,
            prompt: promptBody
        )
    }
}

enum MeetingTemplates {
    static let autoID = "auto"
    static let customIconFallback = "square.and.pencil"

    struct CustomIconOption: Identifiable, Equatable, Sendable {
        let symbolName: String
        let label: String

        var id: String { symbolName }
    }

    static let auto = MeetingTemplateDefinition(
        id: autoID,
        title: String(localized: "meeting_templates.auto.title", defaultValue: "Auto", comment: ""),
        category: nil,
        icon: "sparkles",
        kind: .auto,
        promptBody: String(
            localized: "meeting_templates.auto.prompt",
            defaultValue: """
            Use this structure exactly:
    
            ## Meeting Summary
            A 2-3 sentence overview of what was discussed.
    
            ## Key Discussion Points
            - Bullet points of the main topics discussed
    
            ## Decisions Made
            - Bullet points of any decisions reached
    
            ## Action Items
            - [ ] Bullet points of tasks assigned or agreed upon, with owners if mentioned
    
            ## Notable Quotes
            - Any important or notable statements, if applicable
            """,
            comment: ""
        )
    )

    static let builtIns: [MeetingTemplateDefinition] = [
        MeetingTemplateDefinition(
            id: "one-to-one",
            title: String(localized: "meeting_templates.one_to_one.title", defaultValue: "1 to 1", comment: ""),
            category: String(localized: "meeting_templates.one_to_one.category", defaultValue: "Team", comment: ""),
            icon: "person.2.fill",
            kind: .builtin,
            promptBody: String(
                localized: "meeting_templates.one_to_one.prompt",
                defaultValue: """
                Use this structure exactly:
    
                ## Check-In
                A brief summary of how the conversation opened and the overall tone.
    
                ## Topics Discussed
                - Main themes raised by either person
    
                ## Support Needed
                - Blockers, concerns, or asks for help
    
                ## Commitments
                - [ ] Follow-ups or commitments made by either person
    
                ## Manager Notes
                - Coaching, feedback, or context that should be remembered
                """,
                comment: ""
            )
        ),
        MeetingTemplateDefinition(
            id: "customer-discovery",
            title: String(localized: "meeting_templates.customer_discovery.title", defaultValue: "Customer: Discovery", comment: ""),
            category: String(localized: "meeting_templates.customer_discovery.category", defaultValue: "Commercial", comment: ""),
            icon: "person.crop.circle.badge.questionmark",
            kind: .builtin,
            promptBody: String(
                localized: "meeting_templates.customer_discovery.prompt",
                defaultValue: """
                Use this structure exactly:
    
                ## Customer Context
                - Company, role, or situation if mentioned
    
                ## Problems and Pain Points
                - Explicit frustrations, blockers, or unmet needs
    
                ## Current Workflow
                - How they currently solve the problem today
    
                ## Buying Signals
                - Indicators of urgency, budget, timing, or decision process
    
                ## Next Steps
                - [ ] Follow-up actions, owners, and dates if mentioned
                """,
                comment: ""
            )
        ),
        MeetingTemplateDefinition(
            id: "hiring",
            title: String(localized: "meeting_templates.hiring.title", defaultValue: "Hiring", comment: ""),
            category: String(localized: "meeting_templates.hiring.category", defaultValue: "Recruiting", comment: ""),
            icon: "briefcase.fill",
            kind: .builtin,
            promptBody: String(
                localized: "meeting_templates.hiring.prompt",
                defaultValue: """
                Use this structure exactly:
    
                ## Candidate Snapshot
                A concise overview of the candidate and relevant background.
    
                ## Strengths
                - Positive signals from the conversation
    
                ## Concerns
                - Risks, gaps, or open questions
    
                ## Role Fit
                - Why they do or do not fit the role as discussed
    
                ## Decision and Next Steps
                - [ ] Hiring decision, interview progression, or follow-up items
                """,
                comment: ""
            )
        ),
        MeetingTemplateDefinition(
            id: "stand-up",
            title: String(localized: "meeting_templates.stand_up.title", defaultValue: "Stand-Up", comment: ""),
            category: String(localized: "meeting_templates.stand_up.category", defaultValue: "Team", comment: ""),
            icon: "figure.stand",
            kind: .builtin,
            promptBody: String(
                localized: "meeting_templates.stand_up.prompt",
                defaultValue: """
                Use this structure exactly:
    
                ## Yesterday
                - Work completed or progress since the last update
    
                ## Today
                - Planned work or priorities for today
    
                ## Blockers
                - Risks, delays, or dependencies
    
                ## Coordination Notes
                - Decisions, asks, or cross-team alignment points
                """,
                comment: ""
            )
        ),
        MeetingTemplateDefinition(
            id: "weekly-team-meeting",
            title: String(localized: "meeting_templates.weekly_team_meeting.title", defaultValue: "Weekly Team Meeting", comment: ""),
            category: String(localized: "meeting_templates.weekly_team_meeting.category", defaultValue: "Team", comment: ""),
            icon: "calendar",
            kind: .builtin,
            promptBody: String(
                localized: "meeting_templates.weekly_team_meeting.prompt",
                defaultValue: """
                Use this structure exactly:
    
                ## Weekly Overview
                A concise summary of the most important updates from the meeting.
    
                ## Progress Updates
                - Key workstreams and status changes
    
                ## Decisions
                - Decisions made or confirmed
    
                ## Risks and Open Questions
                - Issues that need attention or follow-up
    
                ## Action Items
                - [ ] Tasks, owners, and timing if mentioned
                """,
                comment: ""
            )
        ),
    ]

    static let customIconOptions: [CustomIconOption] = [
        CustomIconOption(symbolName: "square.and.pencil", label: String(localized: "meeting_templates.custom_icon.notes", defaultValue: "Notes", comment: "")),
        CustomIconOption(symbolName: "person.2.fill", label: String(localized: "meeting_templates.custom_icon.one_to_one", defaultValue: "1 to 1", comment: "")),
        CustomIconOption(symbolName: "person.crop.circle.badge.questionmark", label: String(localized: "meeting_templates.custom_icon.discovery", defaultValue: "Discovery", comment: "")),
        CustomIconOption(symbolName: "briefcase.fill", label: String(localized: "meeting_templates.custom_icon.hiring", defaultValue: "Hiring", comment: "")),
        CustomIconOption(symbolName: "calendar", label: String(localized: "meeting_templates.custom_icon.weekly", defaultValue: "Weekly", comment: "")),
        CustomIconOption(symbolName: "figure.stand", label: String(localized: "meeting_templates.custom_icon.stand_up", defaultValue: "Stand-Up", comment: "")),
        CustomIconOption(symbolName: "person.fill.questionmark", label: String(localized: "meeting_templates.custom_icon.interview", defaultValue: "Interview", comment: "")),
        CustomIconOption(symbolName: "person.fill.checkmark", label: String(localized: "meeting_templates.custom_icon.review", defaultValue: "Review", comment: "")),
        CustomIconOption(symbolName: "building.2.fill", label: String(localized: "meeting_templates.custom_icon.business", defaultValue: "Business", comment: "")),
        CustomIconOption(symbolName: "chart.line.uptrend.xyaxis", label: String(localized: "meeting_templates.custom_icon.strategy", defaultValue: "Strategy", comment: "")),
        CustomIconOption(symbolName: "dollarsign.circle", label: String(localized: "meeting_templates.custom_icon.sales", defaultValue: "Sales", comment: "")),
        CustomIconOption(symbolName: "megaphone.fill", label: String(localized: "meeting_templates.custom_icon.marketing", defaultValue: "Marketing", comment: "")),
        CustomIconOption(symbolName: "hammer.fill", label: String(localized: "meeting_templates.custom_icon.execution", defaultValue: "Execution", comment: "")),
        CustomIconOption(symbolName: "shippingbox.fill", label: String(localized: "meeting_templates.custom_icon.ops", defaultValue: "Ops", comment: "")),
        CustomIconOption(symbolName: "doc.text.fill", label: String(localized: "meeting_templates.custom_icon.docs", defaultValue: "Docs", comment: "")),
        CustomIconOption(symbolName: "checklist", label: String(localized: "meeting_templates.custom_icon.checklist", defaultValue: "Checklist", comment: "")),
        CustomIconOption(symbolName: "lightbulb.fill", label: String(localized: "meeting_templates.custom_icon.ideas", defaultValue: "Ideas", comment: "")),
        CustomIconOption(symbolName: "waveform.path.ecg", label: String(localized: "meeting_templates.custom_icon.health", defaultValue: "Health", comment: "")),
        CustomIconOption(symbolName: "graduationcap.fill", label: String(localized: "meeting_templates.custom_icon.learning", defaultValue: "Learning", comment: "")),
        CustomIconOption(symbolName: "globe", label: String(localized: "meeting_templates.custom_icon.global", defaultValue: "Global", comment: "")),
        CustomIconOption(symbolName: "phone.fill", label: String(localized: "meeting_templates.custom_icon.calls", defaultValue: "Calls", comment: "")),
        CustomIconOption(symbolName: "message.fill", label: String(localized: "meeting_templates.custom_icon.conversation", defaultValue: "Conversation", comment: "")),
        CustomIconOption(symbolName: "person.3.fill", label: String(localized: "meeting_templates.custom_icon.team", defaultValue: "Team", comment: "")),
        CustomIconOption(symbolName: "target", label: String(localized: "meeting_templates.custom_icon.goals", defaultValue: "Goals", comment: "")),
        CustomIconOption(symbolName: "flag.fill", label: String(localized: "meeting_templates.custom_icon.milestones", defaultValue: "Milestones", comment: "")),
        CustomIconOption(symbolName: "sparkles", label: String(localized: "meeting_templates.custom_icon.enhanced", defaultValue: "Enhanced", comment: "")),
        CustomIconOption(symbolName: "wand.and.stars", label: String(localized: "meeting_templates.custom_icon.creative", defaultValue: "Creative", comment: "")),
        CustomIconOption(symbolName: "paperplane.fill", label: String(localized: "meeting_templates.custom_icon.launch", defaultValue: "Launch", comment: "")),
        CustomIconOption(symbolName: "gearshape.fill", label: String(localized: "meeting_templates.custom_icon.systems", defaultValue: "Systems", comment: "")),
        CustomIconOption(symbolName: "folder.fill", label: String(localized: "meeting_templates.custom_icon.projects", defaultValue: "Projects", comment: "")),
        CustomIconOption(symbolName: "clock.fill", label: String(localized: "meeting_templates.custom_icon.timeline", defaultValue: "Timeline", comment: "")),
        CustomIconOption(symbolName: "bolt.fill", label: String(localized: "meeting_templates.custom_icon.sprint", defaultValue: "Sprint", comment: "")),
    ]

    static func normalizedCustomIcon(named icon: String?) -> String {
        let trimmed = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return customIconFallback }
        // Older configs stored rocket.fill for launch-style templates; remap it for compatibility.
        if trimmed == "rocket.fill" {
            return "paperplane.fill"
        }
        return customIconOptions.contains(where: { $0.symbolName == trimmed }) ? trimmed : customIconFallback
    }

    static func customDefinition(from customTemplate: CustomMeetingTemplate) -> MeetingTemplateDefinition {
        MeetingTemplateDefinition(
            id: customTemplate.id,
            title: customTemplate.name,
            category: String(localized: "meeting_templates.custom.title", defaultValue: "Custom", comment: ""),
            icon: normalizedCustomIcon(named: customTemplate.icon),
            kind: .custom,
            promptBody: customTemplate.prompt
        )
    }

    static func customDefinitions(from customTemplates: [CustomMeetingTemplate]) -> [MeetingTemplateDefinition] {
        customTemplates.map(customDefinition)
    }

    static func allDefinitions(customTemplates: [CustomMeetingTemplate]) -> [MeetingTemplateDefinition] {
        [auto] + builtIns + customDefinitions(from: customTemplates)
    }

    static func resolveDefinition(
        id: String?,
        customTemplates: [CustomMeetingTemplate],
        defaultTemplateID: String? = nil
    ) -> MeetingTemplateDefinition {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // When no explicit template is set, fall back to the configured default
        // template (if any) before the hardcoded Auto backstop.
        let effectiveID: String
        if normalizedID.isEmpty || normalizedID == autoID {
            let normalizedDefault = defaultTemplateID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            effectiveID = normalizedDefault.isEmpty ? autoID : normalizedDefault
        } else {
            effectiveID = normalizedID
        }
        if effectiveID == autoID {
            return auto
        }
        if let builtIn = builtIns.first(where: { $0.id == effectiveID }) {
            return builtIn
        }
        if let custom = customTemplates.first(where: { $0.id == effectiveID }) {
            return customDefinition(from: custom)
        }
        // Configured default may reference a deleted template; fall back to Auto.
        return auto
    }

    static func resolveExactDefinition(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateDefinition? {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? autoID
        if normalizedID.isEmpty || normalizedID == autoID {
            return auto
        }
        if let builtIn = builtIns.first(where: { $0.id == normalizedID }) {
            return builtIn
        }
        if let custom = customTemplates.first(where: { $0.id == normalizedID }) {
            return customDefinition(from: custom)
        }
        return nil
    }

    static func resolveSnapshot(
        id: String?,
        customTemplates: [CustomMeetingTemplate],
        defaultTemplateID: String? = nil
    ) -> MeetingTemplateSnapshot {
        resolveDefinition(id: id, customTemplates: customTemplates, defaultTemplateID: defaultTemplateID).snapshot
    }

    static func resolveExactSnapshot(id: String?, customTemplates: [CustomMeetingTemplate]) -> MeetingTemplateSnapshot? {
        resolveExactDefinition(id: id, customTemplates: customTemplates)?.snapshot
    }

    static func snapshot(
        for meeting: MeetingRecord,
        customTemplates: [CustomMeetingTemplate],
        defaultTemplateID: String? = nil
    ) -> MeetingTemplateSnapshot {
        let storedID = meeting.selectedTemplateID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedName = meeting.selectedTemplateName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedPrompt = meeting.selectedTemplatePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedID.isEmpty, !storedName.isEmpty, !storedPrompt.isEmpty {
            return MeetingTemplateSnapshot(
                id: storedID,
                name: storedName,
                kind: meeting.selectedTemplateKind ?? .auto,
                prompt: storedPrompt
            )
        }
        return resolveSnapshot(
            id: storedID.isEmpty ? nil : storedID,
            customTemplates: customTemplates,
            defaultTemplateID: defaultTemplateID
        )
    }
}
