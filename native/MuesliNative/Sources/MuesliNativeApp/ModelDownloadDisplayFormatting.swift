import Foundation

/// Shared, compact formatting for model download status shown in the native UI.
enum ModelDownloadDisplayFormatting {
    static func bytes(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        if value >= 1_000_000_000 { return String(format: String(localized: "model_download_display.bytes.gb", defaultValue: "%.1f GB", comment: "Formatted size string for gigabytes in model download display"), value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: String(localized: "model_download_display.bytes.mb", defaultValue: "%.1f MB", comment: "Formatted size string for megabytes in model download display"), value / 1_000_000) }
        if value >= 1_000 { return String(format: String(localized: "model_download_display.bytes.kb", defaultValue: "%.1f KB", comment: "Formatted size string for kilobytes in model download display"), value / 1_000) }
        return String(format: String(localized: "model_download_display.bytes.b", defaultValue: "%d B", comment: "Formatted size string for bytes in model download display"), bytes)
    }

    static func eta(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let roundedSeconds = seconds.rounded()
        // An ETA beyond one year is not useful to display and must not be
        // converted to Int, where an extreme finite Double can overflow.
        let maximumDisplayableSeconds = Double(365 * 24 * 60 * 60)
        guard roundedSeconds <= maximumDisplayableSeconds else { return nil }
        let totalSeconds = Int(roundedSeconds)
        if totalSeconds < 60 { return String(format: String(localized: "model_download_display.eta.seconds", defaultValue: "%ds", comment: "Estimated remaining time string in seconds for model download"), totalSeconds) }
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes < 60 { return String(format: String(localized: "model_download_display.eta.minutes_seconds", defaultValue: "%dm %02ds", comment: "Estimated remaining time string in minutes and seconds for model download"), minutes, String(format: "%02d", remainingSeconds)) }
        let hours = minutes / 60
        return String(format: String(localized: "model_download_display.eta.hours_minutes", defaultValue: "%dh %02dm", comment: "Estimated remaining time string in hours and minutes for model download"), hours, String(format: "%02d", minutes % 60))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "" }
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: String(localized: "model_download_display.rate.gb_per_second", defaultValue: "%.1f GB/s", comment: "Formatted transfer rate string in gigabytes per second for model download"), bytesPerSecond / 1_000_000_000)
        }
        return String(format: String(localized: "model_download_display.rate.mb_per_second", defaultValue: "%.1f MB/s", comment: "Formatted transfer rate string in megabytes per second for model download"), bytesPerSecond / 1_000_000)
    }
}
