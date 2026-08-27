import AppKit
import SwiftUI
import MuesliCore

@MainActor
private enum TargetApplicationIconResolver {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }

        let key = bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let runningURL = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .bundleURL
        guard let applicationURL = runningURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

struct TargetApplicationIconView: View {
    let appName: String
    let bundleIdentifier: String?
    var size: CGFloat = 20

    private var accessibilityText: String {
        String(format: String(localized: "target_application_icon_view.accessibility.dictated_into_app", defaultValue: "Dictated into %@", bundle: .module, comment: "Accessibility label describing destination app for a dictation."), "\(appName)")
    }

    var body: some View {
        Group {
            if let icon = TargetApplicationIconResolver.icon(bundleIdentifier: bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.13)
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .background(MuesliTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }
}

struct TargetApplicationFilterMenu: View {
    let applications: [DictationTargetApplication]
    let selection: DictationTargetApplication?
    let onSelect: (DictationTargetApplication?) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                HStack {
                    Text(String(localized: "target_application_icon_view.all_apps", defaultValue: "All apps", bundle: .module, comment: "Filter option representing all destination applications."))
                    if selection == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !applications.isEmpty {
                Divider()
                ForEach(applications) { application in
                    Button {
                        onSelect(application)
                    } label: {
                        HStack {
                            Text(application.name)
                            if selection?.id == application.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let selection {
                    TargetApplicationIconView(
                        appName: selection.name,
                        bundleIdentifier: selection.bundleID,
                        size: 16
                    )
                    Text(selection.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11))
                    Text(String(localized: "target_application_icon_view.apps", defaultValue: "Apps", bundle: .module, comment: "Section header for destination application filter."))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(selection == nil ? MuesliTheme.textTertiary : MuesliTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selection == nil ? Color.clear : MuesliTheme.accent.opacity(0.12))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(selection.map { String(format: String(localized: "target_application_icon_view.accessibility_value.showing_dictations_for_app", defaultValue: "Showing dictations for %@", bundle: .module, comment: "Accessibility value indicating currently selected destination app filter."), "\($0.name)") } ?? String(localized: "target_application_icon_view.filter_help", defaultValue: "Filter by destination app", bundle: .module, comment: "Help text for filtering dictations by destination application."))
        .accessibilityLabel(String(localized: "target_application_icon_view.accessibility.destination_filter", defaultValue: "Destination application filter", bundle: .module, comment: "Accessibility label for destination application filter control."))
        .accessibilityValue(selection?.name ?? String(localized: "target_application_icon_view.all_apps", defaultValue: "All apps", bundle: .module, comment: "Filter option representing all destination applications."))
    }
}
