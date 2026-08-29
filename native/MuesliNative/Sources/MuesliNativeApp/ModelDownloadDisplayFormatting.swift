import Foundation

/// Shared, compact formatting for model download status shown in the native UI.
enum ModelDownloadDisplayFormatting {
    static func bytes(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        if value >= 1_000_000_000 { return String(format: String(localized: "model_download_display.bytes.gb", defaultValue: "%.1f GB", bundle: .module, comment: "Formatted file size display in gigabytes"), value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: String(localized: "model_download_display.bytes.mb", defaultValue: "%.1f MB", bundle: .module, comment: "Formatted file size display in megabytes"), value / 1_000_000) }
        if value >= 1_000 { return String(format: String(localized: "model_download_display.bytes.kb", defaultValue: "%.1f KB", bundle: .module, comment: "Formatted file size display in kilobytes"), value / 1_000) }
        return String(format: String(localized: "model_download_display.bytes.b", defaultValue: "%d B", bundle: .module, comment: "Formatted file size display in bytes"), bytes)
    }

    static func eta(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let roundedSeconds = seconds.rounded()
        // An ETA beyond one year is not useful to display and must not be
        // converted to Int, where an extreme finite Double can overflow.
        let maximumDisplayableSeconds = Double(365 * 24 * 60 * 60)
        guard roundedSeconds <= maximumDisplayableSeconds else { return nil }
        let totalSeconds = Int(roundedSeconds)
        if totalSeconds < 60 { return String(format: String(localized: "model_download_display.eta.seconds", defaultValue: "%ds", bundle: .module, comment: "Estimated remaining time display in seconds"), totalSeconds) }
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes < 60 { return String(format: String(localized: "model_download_display.eta.minutes_seconds", defaultValue: "%dm %02ds", bundle: .module, comment: "Estimated remaining time display in minutes and seconds"), minutes, String(format: "%02d", remainingSeconds)) }
        let hours = minutes / 60
        return String(format: String(localized: "model_download_display.eta.hours_minutes", defaultValue: "%dh %02dm", bundle: .module, comment: "Estimated remaining time display in hours and minutes"), hours, String(format: "%02d", minutes % 60))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "" }
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: String(localized: "model_download_display.rate.gb_per_second", defaultValue: "%.1f GB/s", bundle: .module, comment: "Download speed display in gigabytes per second"), bytesPerSecond / 1_000_000_000)
        }
        return String(format: String(localized: "model_download_display.rate.mb_per_second", defaultValue: "%.1f MB/s", bundle: .module, comment: "Download speed display in megabytes per second"), bytesPerSecond / 1_000_000)
    }
}
