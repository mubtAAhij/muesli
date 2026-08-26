import AppKit
import CloudKit
import Foundation
import Sparkle
import TelemetryDeck
import MuesliCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MuesliController?
    private var terminationTask: Task<Void, Never>?
    private(set) var updaterController: SPUStandardUpdaterController?
    private let sparkleUpdateDelegate = SparkleUpdateDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStandardEditMenu()

        let runtimeTelemetry = TelemetryRuntimeConfiguration.current()
        let telemetryConfig = TelemetryDeck.Config(appID: runtimeTelemetry.sdkAppID)
        telemetryConfig.analyticsDisabled = !runtimeTelemetry.isEnabled
        telemetryConfig.defaultParameters = { runtimeTelemetry.defaultParameters }
        TelemetryDeck.initialize(config: telemetryConfig)
        if runtimeTelemetry.isEnabled {
            TelemetryDeck.signal("app.launched")
        }
        // Always drain a pending marker. TelemetryDeck's global privacy gate
        // suppresses the signal when analytics are disabled.
        DiarizerPreloadDiagnostics().reportInterruptedAttemptIfNeeded()

        do {
            let runtime = try RuntimePaths.resolve()
            AppFonts.registerIfNeeded(runtime: runtime)
            if let appIcon = runtime.appIcon, let image = NSImage(contentsOf: appIcon) {
                NSApplication.shared.applicationIconImage = image
            }
            let controller = MuesliController(runtime: runtime)
            sparkleUpdateDelegate.appState = controller.appState
            if Self.hasConfiguredSparkleFeed {
                let updaterController = SPUStandardUpdaterController(
                    startingUpdater: true,
                    updaterDelegate: sparkleUpdateDelegate,
                    userDriverDelegate: sparkleUpdateDelegate
                )
                controller.updaterController = updaterController
                self.updaterController = updaterController
            }
            self.controller = controller
            controller.start()
            NSApplication.shared.registerForRemoteNotifications()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(format: String(localized: "app.startup.failed_to_start", defaultValue: "%@ failed to start", comment: "Startup failure message including app display name."), "\(AppIdentity.displayName)")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        fputs("[muesli-native] registered for remote notifications\n", stderr)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        fputs("[muesli-native] failed to register for remote notifications: \(error)\n", stderr)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        controller?.handleICloudRemoteNotification(userInfo: userInfo)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationTask != nil {
            return .terminateLater
        }
        if controller?.shouldTerminateApplication() == false {
            return .terminateCancel
        }
        guard let controller else { return .terminateNow }

        terminationTask = Task { @MainActor [weak self] in
            await controller.shutdown()
            self?.terminationTask = nil
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static var hasConfiguredSparkleFeed: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }
        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc func openPreferences(_ sender: Any?) {
        controller?.openSettingsTab()
    }

    @objc func focusSearch(_ sender: Any?) {
        controller?.focusSearchField()
    }

    @objc func showWhatsNew(_ sender: Any?) {
        controller?.showWhatsNew()
    }

    @objc func showDictations(_ sender: Any?) {
        controller?.openHistoryWindow(tab: .dictations)
    }

    @objc func showMeetings(_ sender: Any?) {
        controller?.openHistoryWindow(tab: .meetings)
    }

    private func installStandardEditMenu() {
        let menus = standardMenus()
        NSApp.windowsMenu = menus.windowMenu
        NSApp.mainMenu = menus.mainMenu
    }

    func standardMenus() -> (mainMenu: NSMenu, windowMenu: NSMenu) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: String(localized: "app_menu.settings", defaultValue: "Settings…", comment: "Application menu item title for opening settings."),
            action: #selector(AppDelegate.openPreferences(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        let whatsNewItem = NSMenuItem(
            title: String(localized: "app_menu.whats_new", defaultValue: "What's New in Muesli", comment: "Application menu item title for what's new content."),
            action: #selector(AppDelegate.showWhatsNew(_:)),
            keyEquivalent: ""
        )
        whatsNewItem.target = self
        appMenu.addItem(whatsNewItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(format: String(localized: "app_menu.hide_app", defaultValue: "Hide %@", comment: "Application menu item title to hide the app."), "\(AppIdentity.displayName)"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = NSMenuItem(
            title: String(localized: "app_menu.hide_others", defaultValue: "Hide Others", comment: "Application menu item title to hide other apps."),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            withTitle: String(localized: "app_menu.show_all", defaultValue: "Show All", comment: "Application menu item title to show all apps."),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(format: String(localized: "app_menu.quit_app", defaultValue: "Quit %@", comment: "Application menu item title to quit the app."), "\(AppIdentity.displayName)"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "app_menu.edit", defaultValue: "Edit", comment: "Top-level Edit menu title."))
        editMenu.addItem(withTitle: String(localized: "app_menu.undo", defaultValue: "Undo", comment: "Edit menu item title for undo."), action: Selector(("undo:")), keyEquivalent: "z")

        let redo = NSMenuItem(title: String(localized: "app_menu.redo", defaultValue: "Redo", comment: "Edit menu item title for redo."), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "app_menu.cut", defaultValue: "Cut", comment: "Edit menu item title for cut."), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "app_menu.copy", defaultValue: "Copy", comment: "Edit menu item title for copy."), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "app_menu.paste", defaultValue: "Paste", comment: "Edit menu item title for paste."), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "app_menu.delete", defaultValue: "Delete", comment: "Edit menu item title for delete."), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "app_menu.select_all", defaultValue: "Select All", comment: "Edit menu item title for select all."), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = NSMenuItem(
            title: String(localized: "app_menu.find", defaultValue: "Find", comment: "Edit menu item title for find submenu."),
            action: #selector(AppDelegate.focusSearch(_:)),
            keyEquivalent: "f"
        )
        findItem.target = self
        editMenu.addItem(findItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem(title: String(localized: "app_menu.view_top_level", defaultValue: "View", comment: "Top-level View menu title in main menu bar."), action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: String(localized: "app_menu.view", defaultValue: "View", comment: "View submenu title."))
        let dictationsItem = NSMenuItem(
            title: String(localized: "app_menu.dictations", defaultValue: "Dictations", comment: "View menu item title to show dictations window."),
            action: #selector(AppDelegate.showDictations(_:)),
            keyEquivalent: "1"
        )
        dictationsItem.target = self
        viewMenu.addItem(dictationsItem)
        let meetingsItem = NSMenuItem(
            title: String(localized: "app_menu.meetings", defaultValue: "Meetings", comment: "View menu item title to show meetings window."),
            action: #selector(AppDelegate.showMeetings(_:)),
            keyEquivalent: "2"
        )
        meetingsItem.target = self
        viewMenu.addItem(meetingsItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem(title: String(localized: "app_menu.window_top_level", defaultValue: "Window", comment: "Top-level Window menu title in main menu bar."), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: String(localized: "app_menu.window", defaultValue: "Window", comment: "Window submenu title."))
        windowMenu.addItem(
            withTitle: String(localized: "app_menu.minimize", defaultValue: "Minimize", comment: "Window menu item title for minimizing the active window."),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: String(localized: "app_menu.zoom", defaultValue: "Zoom", comment: "Window menu item title for zooming the active window."),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: String(localized: "app_menu.close_window", defaultValue: "Close Window", comment: "Window menu item title for closing the active window."),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: String(localized: "app_menu.bring_all_to_front", defaultValue: "Bring All to Front", comment: "Window menu item title for bringing all app windows to front."),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        return (mainMenu, windowMenu)
    }
}

@MainActor
final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    weak var appState: AppState?
    private var lastPresentedAt: Date?
    private var updateCycleGeneration = 0

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        updateCycleGeneration += 1
        let generation = updateCycleGeneration
        let restoreStatus = recoverableUpdateStatus(appState?.sparkleUpdateStatus ?? .idle)
        appState?.sparkleUpdateStatus = .checking
        restoreStaleUpdateCheck(generation: generation, to: restoreStatus)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        finishUpdateCheck(with: .available(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        if UpdateFailureGuidance.isNoUpdateError(nsError) {
            finishUpdateCheck(with: .upToDate)
        } else {
            finishUpdateCheck(with: .failed(message: nsError.localizedDescription))
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        finishUpdateCheck(with: .downloaded(version: item.displayVersionString))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        finishUpdateCheck(with: .installing(version: item.displayVersionString))
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        switch choice {
        case .install:
            finishUpdateCheck(with: .installing(version: item.displayVersionString))
        case .dismiss where state.stage == .downloaded:
            finishUpdateCheck(with: .downloaded(version: item.displayVersionString))
        case .dismiss:
            finishUpdateCheck(with: .available(version: item.displayVersionString))
        case .skip:
            finishUpdateCheck(with: .idle)
        @unknown default:
            finishUpdateCheck(with: .available(version: item.displayVersionString))
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if UpdateFailureGuidance.isNoUpdateError(nsError) {
            finishUpdateCheck(with: .upToDate)
            return
        }

        finishUpdateCheck(with: .failed(message: nsError.localizedDescription))
        guard UpdateFailureGuidance.shouldShowFallback(for: nsError) else { return }

        // Sparkle shows its own error alert first. Delay briefly so this
        // recovery path appears after the generic updater failure alert.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.showManualInstallGuidance()
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        appState?.sparkleLastCheckedAt = Date()
        guard let error else { return }
        let nsError = error as NSError
        // didAbortWithError is the primary error callback; this keeps the
        // final-cycle handler self-contained for any Sparkle path that ends here.
        if UpdateFailureGuidance.isNoUpdateError(nsError) {
            finishUpdateCheck(with: .upToDate)
        } else {
            finishUpdateCheck(with: .failed(message: nsError.localizedDescription))
        }
    }

    private func finishUpdateCheck(with status: SparkleUpdateStatus) {
        updateCycleGeneration += 1
        appState?.sparkleUpdateStatus = status
    }

    private func restoreStaleUpdateCheck(generation: Int, to restoreStatus: SparkleUpdateStatus) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.updateCycleGeneration == generation else { return }
            guard case .checking = self.appState?.sparkleUpdateStatus else { return }
            self.finishUpdateCheck(with: restoreStatus)
        }
    }

    private func recoverableUpdateStatus(_ status: SparkleUpdateStatus) -> SparkleUpdateStatus {
        switch status {
        case .checking, .busy:
            return .idle
        default:
            return status
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        activateBeforeSparklePresentsUI()
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        activateBeforeSparklePresentsUI()
    }

    private func showManualInstallGuidance() {
        if let lastPresentedAt, Date().timeIntervalSince(lastPresentedAt) < 60 {
            return
        }
        lastPresentedAt = Date()

        let alert = NSAlert()
        alert.messageText = String(localized: "update_guidance.title.update_did_not_finish", defaultValue: "Update did not finish", comment: "Alert title shown when app update cannot complete.")
        alert.informativeText = UpdateFailureGuidance.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update_guidance.action.open_download_page", defaultValue: "Open Download Page", comment: "Alert action to open manual download page after update failure."))
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK", comment: "Default confirmation button title."))

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: UpdateFailureGuidance.downloadPageURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    private nonisolated func activateBeforeSparklePresentsUI() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                Self.activateApplicationForSparkle()
            }
        } else {
            // Sparkle calls this immediately before presenting update UI.
            // Complete activation before returning so LSUIElement update
            // prompts are ordered in front of the current app. This block only
            // performs AppKit activation and does not wait on Sparkle work.
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    Self.activateApplicationForSparkle()
                }
            }
        }
    }

    @MainActor
    private static func activateApplicationForSparkle() {
        // Sparkle UI is opened from an LSUIElement menu-bar app. This is a
        // user-initiated update action, so use strong activation even though
        // AppKit deprecated the argumented API on macOS 14.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

enum UpdateFailureGuidance {
    private static let noUpdateErrorCode = 1001

    static let downloadPageURLString = "https://muesli-hq.github.io/muesli/"

    static let message = String(
        localized: "update_guidance.message.manual_install_instructions",
        defaultValue: """
        Please quit Muesli, reopen it from Applications, and try the update once more.

        If this keeps happening, download the latest DMG and replace Muesli manually. This can happen when the local updater cannot finish preparing or replacing the app.
        """,
        comment: "Detailed guidance shown when update completion fails and manual install may be needed."
    )

    static func isNoUpdateError(_ error: NSError) -> Bool {
        guard error.domain == SUSparkleErrorDomain else { return false }
        if error.code == noUpdateErrorCode { return true }
        return error.userInfo[SPUNoUpdateFoundReasonKey] != nil
    }

    static func shouldShowFallback(for error: NSError) -> Bool {
        guard error.domain == SUSparkleErrorDomain else { return false }

        let installStageCodes: Set<Int> = [
            4000, // SUFileCopyFailure
            4001, // SUAuthenticationFailure
            4002, // SUMissingUpdateError
            4003, // SUMissingInstallerToolError
            4004, // SURelaunchError
            4005, // SUInstallationError
            4009, // SUNotValidUpdateError
            4010, // SUAgentInvalidationError
            4012, // SUInstallationWriteNoPermissionError
            4013, // SUInstallationTranslocationError
        ]

        return installStageCodes.contains(error.code)
    }
}
