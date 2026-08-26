import AVFoundation
import CoreMedia
import Foundation
import MuesliCore
import Speech

struct AppleSpeechTranscriptAccumulator: Sendable {
    private var accumulatedText = ""
    private(set) var segments: [SpeechSegment] = []

    var text: String {
        accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func receive(text rawText: String, isFinal: Bool, start: Double, end: Double) {
        guard isFinal else { return }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        accumulatedText.append(rawText)

        let safeStart = start.isFinite ? max(0, start) : 0
        let safeEnd = end.isFinite ? max(safeStart, end) : safeStart
        segments.append(SpeechSegment(start: safeStart, end: safeEnd, text: trimmed))
    }
}

struct AppleSpeechLanguageOption: Identifiable, Hashable, Sendable {
    static let systemIdentifier = "system"

    let id: String
    let label: String

    static func normalize(_ identifier: String?) -> String {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? systemIdentifier : trimmed
    }

    static func requestedLocale(for identifier: String) -> Locale {
        let normalized = normalize(identifier)
        return normalized == systemIdentifier ? .current : Locale(identifier: normalized)
    }

    static var system: AppleSpeechLanguageOption {
        let locale = Locale.current
        let localeName = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return AppleSpeechLanguageOption(
            id: systemIdentifier,
            label: String(format: String(localized: "apple_speech.language_option.system_language", defaultValue: "System Language - %@", comment: "Language option label showing the system language name."), "\(localeName)")
        )
    }

    static func locale(_ locale: Locale) -> AppleSpeechLanguageOption {
        let identifier = locale.identifier(.bcp47)
        return AppleSpeechLanguageOption(
            id: identifier,
            label: Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        )
    }
}

enum AppleSpeechInitialReservationPolicy {
    static func localesToRelease(_ reservations: [Locale], keeping locale: Locale) -> [Locale] {
        let keptIdentifier = locale.identifier(.bcp47)
        return reservations.filter { $0.identifier(.bcp47) != keptIdentifier }
    }
}

struct AppleSpeechLocaleResolver: Sendable {
    let supportedLocale: @Sendable (Locale) async -> Locale?

    func resolve(_ requestedLocale: Locale) async throws -> Locale {
        if let locale = await supportedLocale(requestedLocale) {
            return locale
        }

        if let languageCode = requestedLocale.language.languageCode?.identifier,
           let languageLocale = await supportedLocale(Locale(identifier: languageCode)) {
            return languageLocale
        }

        throw AppleSpeechAnalyzerError.unsupportedLocale(requestedLocale.identifier(.bcp47))
    }
}

actor AppleSpeechPreparationTaskCache {
    private var tasks: [String: Task<Locale, Error>] = [:]

    func value(
        for localeIdentifier: String,
        operation: @escaping @Sendable () async throws -> Locale
    ) async throws -> Locale {
        if let task = tasks[localeIdentifier] {
            return try await task.value
        }

        let task = Task { try await operation() }
        tasks[localeIdentifier] = task
        do {
            let locale = try await task.value
            tasks.removeValue(forKey: localeIdentifier)
            return locale
        } catch {
            tasks.removeValue(forKey: localeIdentifier)
            throw error
        }
    }
}

enum AppleSpeechAnalyzerError: LocalizedError, Sendable {
    case unavailable
    case unsupportedLocale(String)
    case assetUnavailable(String)
    case reservationUnavailable(Int)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "apple_speech.error.requires_supported_os_and_hardware", defaultValue: "Apple Speech requires macOS 26 and compatible Apple hardware.", comment: "Error when Apple Speech backend is unavailable on unsupported OS or hardware.")
        case .unsupportedLocale(let identifier):
            return String(format: String(localized: "apple_speech.error.locale_not_supported", defaultValue: "Apple Speech does not support the %@ locale on this Mac.", comment: "Error when selected locale is not supported by Apple Speech."), "\(identifier)")
        case .assetUnavailable(let identifier):
            return String(format: String(localized: "apple_speech.error.model_unavailable", defaultValue: "The Apple Speech model for %@ is unavailable.", comment: "Error when model for selected Apple Speech locale cannot be loaded."), "\(identifier)")
        case .reservationUnavailable(let maximum):
            return String(format: String(localized: "apple_speech.error.language_reservation_limit_reached", defaultValue: "Apple Speech cannot reserve another language on this Mac (limit: %@).", comment: "Error when Apple Speech has reached the language reservation limit."), "\(maximum)")
        case .emptyTranscript:
            return String(localized: "apple_speech.error.no_transcript_produced", defaultValue: "Apple Speech completed without producing a transcript.", comment: "Error when Apple Speech finishes but returns no transcript text.")
        }
    }
}

@available(macOS 26.0, *)
extension AppleSpeechLocaleResolver {
    static let live = AppleSpeechLocaleResolver { locale in
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }
}

@available(macOS 26.0, *)
extension AppleSpeechLanguageOption {
    static func supportedOptions() async -> [AppleSpeechLanguageOption] {
        let localeOptions = await SpeechTranscriber.supportedLocales
            .map(AppleSpeechLanguageOption.locale)
            .reduce(into: [String: AppleSpeechLanguageOption]()) { options, option in
                options[option.id] = option
            }
            .values
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [.system] + localeOptions
    }
}

@available(macOS 26.0, *)
actor AppleSpeechAnalyzerTranscriber {
    static let modelID = "apple-speech-transcriber"

    static var isSupportedOnCurrentSystem: Bool {
        SpeechTranscriber.isAvailable
    }

    private let localeResolver: AppleSpeechLocaleResolver
    private let preparationTasks = AppleSpeechPreparationTaskCache()
    private var preparedLocale: Locale?
    private var initialReservationReconciliationTask: Task<Void, Never>?
    private var didReconcileInitialReservations = false

    init(localeResolver: AppleSpeechLocaleResolver = .live) {
        self.localeResolver = localeResolver
    }

    func prepare(
        requestedLocale: Locale = .current,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechAnalyzerError.unavailable
        }

        let locale = try await localeResolver.resolve(requestedLocale)
        let callbacks = AppleSpeechPreparationCallbacks(
            progress: progress,
            progressSnapshot: progressSnapshot
        )
        let prepared = try await preparationTasks.value(
            for: locale.identifier(.bcp47)
        ) { [self, callbacks] in
            try await performPrepare(locale: locale, callbacks: callbacks)
        }
        callbacks.progress?(1, String(localized: "apple_speech.status.ready", defaultValue: "Apple Speech ready", comment: "Status shown when Apple Speech backend is ready."))
        callbacks.progressSnapshot?(readySnapshot())
        return prepared
    }

    private func performPrepare(
        locale: Locale,
        callbacks: AppleSpeechPreparationCallbacks
    ) async throws -> Locale {
        let transcriber = makeTranscriber(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])

        if preparedLocale == locale, status == .installed {
            return locale
        }

        callbacks.progress?(0.05, String(format: String(localized: "apple_speech.status.preparing_for_locale", defaultValue: "Preparing Apple Speech for %@...", comment: "Status shown while Apple Speech prepares a specific locale."), "\(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)"))
        callbacks.progressSnapshot?(ModelDownloadProgress.preparing(
            modelID: Self.modelID,
            message: String(localized: "apple_speech.status.preparing_generic", defaultValue: "Preparing Apple Speech...", comment: "Generic status shown while Apple Speech is preparing.")
        ))

        await reconcileInitialReservations(keeping: locale)
        do {
            _ = try await AssetInventory.reserve(locale: locale)
        } catch {
            let reservedCount = (await AssetInventory.reservedLocales).count
            if reservedCount >= AssetInventory.maximumReservedLocales {
                throw AppleSpeechAnalyzerError.reservationUnavailable(AssetInventory.maximumReservedLocales)
            }
            throw error
        }
        try Task.checkCancellation()

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progressBox = AppleSpeechProgressBox(request.progress)
            let progressTask = Task { [callbacks] in
                while !Task.isCancelled && !progressBox.progress.isFinished {
                    let fraction = min(max(progressBox.progress.fractionCompleted, 0), 1)
                    let mappedFraction = 0.1 + (fraction * 0.8)
                    callbacks.progress?(mappedFraction, String(localized: "apple_speech.status.downloading", defaultValue: "Downloading Apple Speech...", comment: "Status shown while Apple Speech resources are downloading."))
                    callbacks.progressSnapshot?(downloadSnapshot(fraction: fraction))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { progressTask.cancel() }

            try await withTaskCancellationHandler {
                try await request.downloadAndInstall()
            } onCancel: {
                progressBox.progress.cancel()
            }
        }

        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw AppleSpeechAnalyzerError.assetUnavailable(locale.identifier(.bcp47))
        }

        preparedLocale = locale
        fputs("[muesli-native] Apple Speech ready for \(locale.identifier(.bcp47))\n", stderr)
        return locale
    }

    private func reconcileInitialReservations(keeping locale: Locale) async {
        if didReconcileInitialReservations { return }
        if let task = initialReservationReconciliationTask {
            await task.value
            return
        }

        let task = Task {
            let reservations = await AssetInventory.reservedLocales
            for reservedLocale in AppleSpeechInitialReservationPolicy.localesToRelease(
                reservations,
                keeping: locale
            ) {
                _ = await AssetInventory.release(reservedLocale: reservedLocale)
            }
        }
        initialReservationReconciliationTask = task
        await task.value
        didReconcileInitialReservations = true
        initialReservationReconciliationTask = nil
    }

    func releaseReservations() async {
        for locale in await AssetInventory.reservedLocales {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
        preparedLocale = nil
    }

    func transcribe(wavURL: URL, requestedLocale: Locale = .current) async throws -> SpeechTranscriptionResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let locale = try await prepare(requestedLocale: requestedLocale)
        let transcriber = makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        )
        let audioFile = try AVAudioFile(forReading: wavURL)

        async let collected = collectResults(from: transcriber)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await collected
        guard !result.text.isEmpty else {
            throw AppleSpeechAnalyzerError.emptyTranscript
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        let elapsedText = String(format: "%.3f", elapsed)
        fputs(
            "[muesli-native] Apple Speech completed \(result.text.count) characters in \(elapsedText)s (locale \(locale.identifier(.bcp47)))\n",
            stderr
        )
        return result
    }

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    private func collectResults(from transcriber: SpeechTranscriber) async throws -> SpeechTranscriptionResult {
        var accumulator = AppleSpeechTranscriptAccumulator()
        for try await result in transcriber.results {
            let start = CMTimeGetSeconds(result.range.start)
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
            accumulator.receive(
                text: String(result.text.characters),
                isFinal: result.isFinal,
                start: start,
                end: end
            )
        }
        return SpeechTranscriptionResult(text: accumulator.text, segments: accumulator.segments)
    }

    private func downloadSnapshot(fraction: Double) -> ModelDownloadProgress {
        let total: Int64 = 10_000
        return ModelDownloadProgress(
            modelID: Self.modelID,
            phase: .downloading,
            currentFile: nil,
            completedBytes: Int64(Double(total) * fraction),
            totalBytes: total,
            currentFileCompletedBytes: 0,
            currentFileTotalBytes: nil,
            bytesPerSecond: 0,
            estimatedSecondsRemaining: nil,
            retryCount: 0,
            message: String(localized: "apple_speech.status.downloading", defaultValue: "Downloading Apple Speech...", comment: "Status shown while Apple Speech resources are downloading.")
        )
    }

    private func readySnapshot() -> ModelDownloadProgress {
        ModelDownloadProgress.preparing(
            modelID: Self.modelID,
            message: String(localized: "apple_speech.status.ready", defaultValue: "Apple Speech ready", comment: "Status shown when Apple Speech backend is ready.")
        ).replacing(phase: .ready, message: String(localized: "apple_speech.status.ready", defaultValue: "Apple Speech ready", comment: "Status shown when Apple Speech backend is ready."))
    }
}

@available(macOS 26.0, *)
private final class AppleSpeechProgressBox: @unchecked Sendable {
    let progress: Progress

    init(_ progress: Progress) {
        self.progress = progress
    }
}

private final class AppleSpeechPreparationCallbacks: @unchecked Sendable {
    let progress: ((Double, String?) -> Void)?
    let progressSnapshot: ModelDownloadProgressHandler?

    init(
        progress: ((Double, String?) -> Void)?,
        progressSnapshot: ModelDownloadProgressHandler?
    ) {
        self.progress = progress
        self.progressSnapshot = progressSnapshot
    }
}
