import Foundation

struct MarketingVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let numericPrefix = value.split(separator: "-", maxSplits: 1).first ?? Substring(value)
        let parts = numericPrefix.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        var parsedComponents: [Int] = []
        parsedComponents.reserveCapacity(parts.count)
        for part in parts {
            guard let component = Int(part) else { return nil }
            parsedComponents.append(component)
        }
        components = parsedComponents
    }

    static func == (lhs: MarketingVersion, rhs: MarketingVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: MarketingVersion, rhs: MarketingVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum FeatureTourTarget: String, Hashable {
    case timelineSidebar
    case timelineApplications
    case appleSpeechCard
    case meetingPeople
    case timelineFilters
    case modelLibrary
    case insightsEntry
    case dictionarySuggestions
    case meetingsSidebar
    case liveCaptionsSetting
    case cloudCleanupSetting
    case streamingModels
    case experimentalModels

    var modelsCategory: ModelsCategory? {
        switch self {
        case .modelLibrary, .appleSpeechCard:
            return .dictation
        case .streamingModels:
            return .streaming
        case .experimentalModels:
            return .dictation
        case .timelineSidebar, .timelineApplications, .meetingPeople, .timelineFilters, .insightsEntry, .dictionarySuggestions, .meetingsSidebar, .liveCaptionsSetting, .cloudCleanupSetting:
            return nil
        }
    }
}

struct FeatureTourStep: Identifiable, Equatable {
    let id: String
    let eyebrow: String
    let title: String
    let message: String
    let systemImage: String
    let target: FeatureTourTarget
}

struct FeatureTour: Equatable {
    let version: String
    let steps: [FeatureTourStep]

    var displayVersion: String {
        guard let marketingVersion = MarketingVersion(version) else { return version }
        var components = marketingVersion.components
        while components.count > 2, components.last == 0 {
            components.removeLast()
        }
        return components.map(String.init).joined(separator: ".")
    }
}

extension AppState {
    var activeFeatureTourTarget: FeatureTourTarget? {
        guard let activeFeatureTour,
              activeFeatureTour.steps.indices.contains(featureTourStepIndex) else { return nil }
        return activeFeatureTour.steps[featureTourStepIndex].target
    }
}

enum FeatureTourCatalog {
    static var latest: FeatureTour {
        latest(
            includeApplicationFilter: false,
            includeAppleSpeech: false,
            includeMeetingPeople: false
        )
    }

    static func latest(
        includeApplicationFilter: Bool,
        includeAppleSpeech: Bool,
        includeMeetingPeople: Bool
    ) -> FeatureTour {
        var steps = [
            FeatureTourStep(
                id: "timeline",
                eyebrow: String(localized: "feature_tour.timeline.heading", defaultValue: "ONE TIMELINE", bundle: .module, comment: "Feature tour heading introducing the unified timeline feature."),
                title: String(localized: "feature_tour.timeline.title", defaultValue: "Dictations and meetings, together", bundle: .module, comment: "Feature tour title describing combined dictation and meeting timeline."),
                message: String(localized: "feature_tour.timeline.body", defaultValue: "Timeline puts your recent work in one chronological view. Open it from the sidebar whenever you want to retrace what you dictated or discussed.", bundle: .module, comment: "Feature tour body text explaining the timeline view and where to access it."),
                systemImage: "clock.arrow.circlepath",
                target: .timelineSidebar
            )
        ]

        if includeApplicationFilter {
            steps.append(FeatureTourStep(
                id: "timeline-apps",
                eyebrow: String(localized: "feature_tour.timeline_apps.heading", defaultValue: "FILTER BY APP", bundle: .module, comment: "Feature tour heading for app-based filtering in timeline."),
                title: String(localized: "feature_tour.timeline_apps.title", defaultValue: "Find dictations by destination app", bundle: .module, comment: "Feature tour title for filtering timeline dictations by destination app."),
                message: String(localized: "feature_tour.timeline_apps.body", defaultValue: "Use Apps to narrow Timeline to dictations sent to a specific destination, such as Mail, Notes, or your browser.", bundle: .module, comment: "Feature tour body text explaining how to filter timeline by destination app."),
                systemImage: "square.grid.2x2",
                target: .timelineApplications
            ))
        }

        if includeAppleSpeech {
            steps.append(FeatureTourStep(
                id: "apple-speech",
                eyebrow: String(localized: "feature_tour.apple_speech.heading", defaultValue: "ON-DEVICE SPEECH", bundle: .module, comment: "Feature tour heading for Apple on-device speech feature."),
                title: String(localized: "feature_tour.apple_speech.title", defaultValue: "Try Apple's native on-device speech model", bundle: .module, comment: "Feature tour title inviting users to try Apple native on-device speech model."),
                message: String(localized: "feature_tour.apple_speech.body", defaultValue: "On macOS 26, Apple Speech can transcribe without a separate model download. Use your system language or choose another supported language in Models.", bundle: .module, comment: "Feature tour body text explaining Apple Speech on-device transcription and language selection."),
                systemImage: "apple.logo",
                target: .appleSpeechCard
            ))
        }

        if includeMeetingPeople {
            steps.append(FeatureTourStep(
                id: "meeting-people",
                eyebrow: String(localized: "feature_tour.meeting_attendees.heading", defaultValue: "MEETING ATTENDEES", bundle: .module, comment: "Feature tour heading for meeting attendees feature."),
                title: String(localized: "feature_tour.meeting_attendees.title", defaultValue: "Meeting attendees are now available!", bundle: .module, comment: "Feature tour title announcing meeting attendees feature availability."),
                message: String(localized: "feature_tour.meeting_attendees.body", defaultValue: "See organizers and attendees from calendar events, or add people from Apple Contacts directly to a meeting.", bundle: .module, comment: "Feature tour body text explaining attendee data from calendar and contacts integration."),
                systemImage: "person.2.fill",
                target: .meetingPeople
            ))
        }

        return FeatureTour(version: "0.8.2", steps: steps)
    }
}

enum FeatureTourPresentationPolicy {
    static func shouldPresentAutomatically(
        currentVersion: String,
        previousVersion: String?,
        lastPresentedTourVersion: String?,
        hasCompletedOnboarding: Bool,
        tour: FeatureTour
    ) -> Bool {
        guard hasCompletedOnboarding,
              let current = MarketingVersion(currentVersion),
              let target = MarketingVersion(tour.version),
              current >= target else {
            return false
        }

        let lastPresented = lastPresentedTourVersion.flatMap(MarketingVersion.init)
        if let lastPresented, lastPresented >= target {
            return false
        }

        guard let previousVersion else {
            // A completed onboarding with no version marker identifies an
            // existing install rather than a fresh install.
            return true
        }
        guard let previous = MarketingVersion(previousVersion) else { return true }
        if previous < target {
            return true
        }

        // Prerelease builds can share a marketing version even when a newer
        // walkthrough first ships between those builds. A prior tour marker
        // distinguishes that upgrade from a fresh install at the same version.
        return previous == target && lastPresented != nil
    }
}

final class FeatureTourStore {
    private enum Key {
        static let lastLaunchedVersion = "featureTour.lastLaunchedVersion"
        static let lastPresentedVersion = "featureTour.lastPresentedVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func automaticTour(
        currentVersion: String,
        hasCompletedOnboarding: Bool,
        canPresent: Bool,
        tour: FeatureTour = FeatureTourCatalog.latest
    ) -> FeatureTour? {
        if !hasCompletedOnboarding {
            defaults.set(currentVersion, forKey: Key.lastLaunchedVersion)
            return nil
        }

        // Permission-repair onboarding owns the foreground. Leave the previous
        // version untouched so the tour remains eligible on the next healthy launch.
        guard canPresent else { return nil }

        let shouldPresent = FeatureTourPresentationPolicy.shouldPresentAutomatically(
            currentVersion: currentVersion,
            previousVersion: defaults.string(forKey: Key.lastLaunchedVersion),
            lastPresentedTourVersion: defaults.string(forKey: Key.lastPresentedVersion),
            hasCompletedOnboarding: true,
            tour: tour
        )
        defaults.set(currentVersion, forKey: Key.lastLaunchedVersion)
        return shouldPresent ? tour : nil
    }

    func markOffered(_ tour: FeatureTour) {
        defaults.set(tour.version, forKey: Key.lastPresentedVersion)
    }
}
