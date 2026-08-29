import SwiftUI
import MuesliCore

struct SidebarView: View {
    private let sidebarIconColumnWidth: CGFloat = 20
    private let meetingsTrailingColumnWidth: CGFloat = 24
    private let sidebarRowHorizontalPadding: CGFloat = 16
    private let sidebarRowOuterPadding: CGFloat = 8
    private let folderDepthIndent: CGFloat = 8

    let appState: AppState
    let controller: MuesliController
    @Environment(\.colorScheme) private var colorScheme
    @State private var meetingsExpanded = true
    @State private var renamingFolderID: Int64?
    @State private var renamingFolderName = ""
    @State private var folderToDelete: MeetingFolder?
    @State private var showDeleteConfirmation = false
    @State private var draggingFolderID: Int64?
    @State private var dragOrderedFolders: [MeetingFolder]?
    @State private var collapsedFolderIDs: Set<Int64> = []
    @FocusState private var isSearchFieldFocused: Bool

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { appState.searchQuery },
            set: { controller.performSearch(query: $0) }
        )
    }

    private var userName: String {
        appState.config.userName
    }

    private struct UpdateCTA {
        let label: String
        let icon: String
        let foreground: Color
        let accessibilityLabel: String
        let tooltip: String
    }

    private var pendingUpdateCTA: UpdateCTA? {
        switch appState.sparkleUpdateStatus {
        case .available:
            return UpdateCTA(
                label: String(localized: "sidebar.update.cta_title", defaultValue: "Update", bundle: .module, comment: "Call-to-action title for update button."),
                icon: "arrow.down",
                foreground: updateCTAForeground,
                accessibilityLabel: String(localized: "sidebar.update.available", defaultValue: "Update available", bundle: .module, comment: "Status text indicating an app update is available."),
                tooltip: String(localized: "sidebar.update.open_about_for_instructions", defaultValue: "Open About for update instructions", bundle: .module, comment: "Guidance text telling user where to find update instructions.")
            )
        case .downloaded:
            return UpdateCTA(
                label: String(localized: "sidebar.update.ready_title", defaultValue: "Ready", bundle: .module, comment: "Status title indicating update is ready."),
                icon: "arrow.clockwise",
                foreground: updateCTAForeground,
                accessibilityLabel: String(localized: "sidebar.update.ready_message", defaultValue: "Update ready to install", bundle: .module, comment: "Status message indicating update is ready to install."),
                tooltip: String(localized: "sidebar.update.open_about_for_instructions", defaultValue: "Open About for update instructions", bundle: .module, comment: "Guidance text telling user where to find update instructions.")
            )
        case .idle, .checking, .busy, .installing, .upToDate, .disabled, .failed:
            return nil
        }
    }

    private var updateCTAForeground: Color {
        let accentHex = appState.config.recordingColorHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()

        let defaultAccentHex = colorScheme == .dark
            ? MuesliTheme.defaultAccentDarkHex
            : MuesliTheme.defaultAccentLightHex

        let value: UInt64
        if accentHex == "1e1e2e" {
            value = UInt64(defaultAccentHex)
        } else {
            guard accentHex.count == 6,
                  let parsedValue = UInt64(accentHex, radix: 16) else {
                value = UInt64(defaultAccentHex)
                return foregroundColor(forAccentHex: value)
            }
            value = parsedValue
        }

        return foregroundColor(forAccentHex: value)
    }

    private func foregroundColor(forAccentHex value: UInt64) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        // 0.45 on raw sRGB approximates the WCAG 0.18 threshold on linearized luminance.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.45 ? Color.black.opacity(0.88) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            sidebarHeader
            searchBar

            sidebarItem(tab: .timeline, icon: "clock.fill", label: String(localized: "sidebar.timeline", defaultValue: "Timeline", bundle: .module, comment: "Sidebar navigation label for timeline section."))
            sidebarItem(tab: .dictations, icon: "mic.fill", label: String(localized: "sidebar.dictations", defaultValue: "Dictations", bundle: .module, comment: "Sidebar navigation label for dictations section."))
            meetingsSection
            sidebarItem(tab: .dictionary, icon: "character.book.closed", label: String(localized: "sidebar.dictionary", defaultValue: "Dictionary", bundle: .module, comment: "Sidebar navigation label for dictionary section."))
            sidebarItem(tab: .models, icon: "square.and.arrow.down", label: String(localized: "sidebar.models", defaultValue: "Models", bundle: .module, comment: "Sidebar navigation label for models section."))
            sidebarItem(tab: .shortcuts, icon: "keyboard", label: String(localized: "sidebar.shortcuts", defaultValue: "Shortcuts", bundle: .module, comment: "Sidebar navigation label for shortcuts section."))

            Spacer()

            modelPreparationStatus
            spreadTheWordSection
            sidebarItem(tab: .settings, icon: "gearshape", label: String(localized: "sidebar.settings", defaultValue: "Settings", bundle: .module, comment: "Sidebar navigation label for settings section."))
            sidebarItem(tab: .about, icon: "info.circle", label: String(localized: "sidebar.about", defaultValue: "About", bundle: .module, comment: "Sidebar navigation label for about section."), updateCTA: pendingUpdateCTA)
            darkModeToggle
                .padding(.bottom, MuesliTheme.spacing16)
        }
        .frame(maxHeight: .infinity)
        .background(MuesliTheme.backgroundDeep)
        .onChange(of: appState.selectedTab) { _, tab in
            if tab == .meetings {
                meetingsExpanded = true
            }
            // Reset drag state if user navigates away during a drag
            if draggingFolderID != nil {
                draggingFolderID = nil
                dragOrderedFolders = nil
            }
        }
        .alert(
            String(format: String(localized: "sidebar.folder.delete.confirmation_title", defaultValue: "Delete \"%@\"?", bundle: .module, comment: "Delete-folder confirmation dialog title with folder name."), "\(folderToDelete?.name ?? "")"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "common.cancel", defaultValue: "Cancel", bundle: .module, comment: "Cancel button title in delete confirmation dialog."), role: .cancel) {
                folderToDelete = nil
            }
            Button(String(localized: "sidebar.folder.delete.confirmation_action", defaultValue: "Delete", bundle: .module, comment: "Destructive action title in delete confirmation dialog."), role: .destructive) {
                if let folder = folderToDelete {
                    controller.deleteFolder(id: folder.id)
                    controller.showMeetingsHome(folderID: appState.selectedFolderID)
                }
                folderToDelete = nil
            }
        } message: {
            let directCount = folderToDelete.map { folder in
                appState.directMeetingCountsByFolder[folder.id] ?? 0
            } ?? 0
            if directCount > 0 {
                Text(String(format: String(localized: "sidebar.folder.delete.move_to_unfiled_message", defaultValue: "%d meeting in this folder will be moved to Unfiled. Subfolders will be kept.", bundle: .module, comment: "Delete-folder warning about moving direct meetings to Unfiled."), directCount))
            } else {
                Text(String(localized: "sidebar.folder.delete.warning", defaultValue: "This folder will be permanently removed. Subfolders will be kept.", bundle: .module, comment: "Additional delete-folder warning message."))
            }
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing4) {
            HStack(spacing: MuesliTheme.spacing12) {
                Group {
                    if appState.config.menuBarIcon == "muesli",
                       let img = MenuBarIconRenderer.make(choice: "muesli") {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: appState.config.menuBarIcon)
                    }
                }
                .frame(width: 22, height: 22)
                .foregroundStyle(MuesliTheme.accent)
                Text("muesli")
                    .font(MuesliTheme.title2())
                    .foregroundStyle(MuesliTheme.textPrimary)
            }
            if !userName.isEmpty {
                Text(String(format: String(localized: "sidebar.greeting.with_name", defaultValue: "Hi, %@", bundle: .module, comment: "Sidebar greeting with user name."), "\(userName)"))
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, MuesliTheme.spacing16)
        .padding(.top, MuesliTheme.spacing24)
        .padding(.bottom, MuesliTheme.spacing20)
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MuesliTheme.textTertiary)
            TextField(String(localized: "sidebar.search.placeholder", defaultValue: "Search...", bundle: .module, comment: "Placeholder text for sidebar search field."), text: searchTextBinding)
                .textFieldStyle(.plain)
                .font(MuesliTheme.callout())
                .foregroundStyle(MuesliTheme.textPrimary)
                .focused($isSearchFieldFocused)
            if !appState.searchQuery.isEmpty {
                Button {
                    controller.clearSearch()
                    isSearchFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, sidebarRowOuterPadding)
        .padding(.bottom, MuesliTheme.spacing8)
        .onChange(of: appState.focusSearchField) { _, shouldFocus in
            if shouldFocus {
                isSearchFieldFocused = true
                appState.focusSearchField = false
            }
        }
    }

    @ViewBuilder
    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            let isSelected = appState.selectedTab == .meetings
            HStack(spacing: MuesliTheme.spacing12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded = true
                    }
                    controller.showMeetingsHome()
                } label: {
                    HStack(spacing: MuesliTheme.spacing12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                            .frame(width: sidebarIconColumnWidth)
                        Text(String(localized: "sidebar.meetings.title", defaultValue: "Meetings", bundle: .module, comment: "Section title for meetings area in sidebar."))
                            .font(MuesliTheme.headline())
                            .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        meetingsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: meetingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)

                Button(action: createNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                        .frame(width: meetingsTrailingColumnWidth, height: 18)
                }
                .buttonStyle(.plain)
                .help(String(localized: "sidebar.meetings.new_folder.help", defaultValue: "New Meeting Folder", bundle: .module, comment: "Help/action text for creating a new meeting folder."))
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, sidebarRowOuterPadding)
            .featureTourTarget(.meetingsSidebar)

            if meetingsExpanded {
                let folderTree = folderTreePresentation
                VStack(alignment: .leading, spacing: 2) {
                    meetingFilterRow(
                        icon: "tray.2",
                        label: String(localized: "sidebar.meetings.filter.all", defaultValue: "All Meetings", bundle: .module, comment: "Filter label for showing all meetings."),
                        count: appState.totalMeetingCount,
                        isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == nil
                    ) {
                        controller.showMeetingsHome()
                    }

                    ForEach(folderTree.visibleFolders) { folder in
                        let depth = folderTree.depth(of: folder)
                        let hasChildren = folderTree.hasChildren(folder.id)
                        let isCollapsed = collapsedFolderIDs.contains(folder.id)
                        if renamingFolderID == folder.id {
                            folderRenameField(folder: folder)
                                .padding(.leading, CGFloat(depth) * folderDepthIndent)
                        } else {
                            meetingFilterRow(
                                icon: hasChildren ? "folder.fill" : "folder",
                                label: folder.name,
                                count: appState.meetingCountsByFolder[folder.id] ?? 0,
                                isSelected: appState.selectedTab == .meetings && appState.selectedFolderID == folder.id,
                                disclosureIcon: hasChildren ? (isCollapsed ? "chevron.right" : "chevron.down") : nil,
                                disclosureAction: hasChildren ? { toggleFolderCollapse(folder.id) } : nil
                            ) {
                                controller.showMeetingsHome(folderID: folder.id)
                            }
                            .padding(.leading, CGFloat(depth) * folderDepthIndent)
                            .opacity(draggingFolderID == folder.id ? 0.1 : 1)
                            .onDrag {
                                draggingFolderID = folder.id
                                dragOrderedFolders = appState.folders
                                return NSItemProvider(object: "\(folder.id)" as NSString)
                            }
                            .onDrop(of: [.text], delegate: FolderDropDelegate(
                                folderID: folder.id,
                                dragOrderedFolders: $dragOrderedFolders,
                                draggingFolderID: $draggingFolderID,
                                commitOrder: { ids in controller.reorderFolders(ids: ids) }
                            ))
                            .contextMenu {
                                Button(String(localized: "sidebar.folder.new_subfolder", defaultValue: "New Subfolder", bundle: .module, comment: "Context menu action to create a new subfolder.")) {
                                    createNewSubfolder(parentID: folder.id)
                                }
                                Button(String(localized: "sidebar.meetings.rename", defaultValue: "Rename", bundle: .module, comment: "Context menu action to rename a folder or section.")) {
                                    renamingFolderID = folder.id
                                    renamingFolderName = folder.name
                                }
                                if folder.parentID != nil {
                                    Button(String(localized: "sidebar.folder.move_to_top_level", defaultValue: "Move to Top Level", bundle: .module, comment: "Context menu action to move folder to top level.")) {
                                        controller.moveFolder(id: folder.id, toParent: nil)
                                    }
                                }
                                Divider()
                                Button(String(localized: "sidebar.folder.delete.context_action", defaultValue: "Delete", bundle: .module, comment: "Context menu action to delete a folder."), role: .destructive) {
                                    folderToDelete = folder
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, sidebarRowOuterPadding)
            }
        }
    }

    @ViewBuilder
    private var modelPreparationStatus: some View {
        if let title = appState.modelPreparationTitle {
            HStack(spacing: MuesliTheme.spacing8) {
                Group {
                    if appState.modelPreparationIsComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MuesliTheme.success)
                    } else if appState.isModelPreparingAfterDownload || appState.modelPreparationProgress == nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        ProgressView(value: appState.modelPreparationProgress ?? 0, total: 1)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MuesliTheme.textSecondary)
                        .lineLimit(1)
                    if let detail = appState.modelPreparationDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MuesliTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(MuesliTheme.backgroundRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .strokeBorder(MuesliTheme.surfaceBorder, lineWidth: 1)
            )
            .padding(.horizontal, sidebarRowOuterPadding)
            .padding(.bottom, MuesliTheme.spacing4)
        }
    }

    @ViewBuilder
    private var spreadTheWordSection: some View {
        let wordMilestone = ContributionSocialShare.completedWordMilestone(
            totalWords: appState.dictationStats.totalWords
        )
        if wordMilestone != nil {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "sidebar.spread_the_word.title", defaultValue: "Spread the Word", bundle: .module, comment: "Title for share/promote section in sidebar."))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuesliTheme.textTertiary)
                    .padding(.horizontal, sidebarRowHorizontalPadding)
                    .padding(.bottom, 2)

                socialShareRow(
                    imageName: "x-logo",
                    fallbackIcon: "bubble.left.and.bubble.right.fill",
                    label: String(localized: "sidebar.spread_the_word.tweet", defaultValue: "Tweet about Muesli", bundle: .module, comment: "Action label to share about Muesli on X/Twitter."),
                    action: { controller.openContributionSidebarShare(.tweetAboutMuesli) }
                )
                socialShareRow(
                    imageName: "linkedin-logo",
                    fallbackIcon: "person.crop.square.fill",
                    label: String(localized: "sidebar.spread_the_word.linkedin", defaultValue: "Post on LinkedIn", bundle: .module, comment: "Action label to share about Muesli on LinkedIn."),
                    action: { controller.openContributionSidebarShare(.postOnLinkedIn) }
                )
            }
            .padding(.horizontal, sidebarRowOuterPadding)
            .padding(.bottom, MuesliTheme.spacing8)
        }
    }

    @ViewBuilder
    private func socialShareRow(
        imageName: String,
        fallbackIcon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MuesliTheme.spacing12) {
                socialLogo(imageName: imageName, fallbackIcon: fallbackIcon)
                    .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth, alignment: .center)
                Text(label)
                    .font(MuesliTheme.callout())
                    .foregroundStyle(MuesliTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func socialLogo(imageName: String, fallbackIcon: String) -> some View {
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(MuesliTheme.textTertiary)
        } else {
            Image(systemName: fallbackIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MuesliTheme.textTertiary)
        }
    }

    @ViewBuilder
    private func sidebarItem(tab: DashboardTab, icon: String, label: String, updateCTA: UpdateCTA? = nil) -> some View {
        let isSelected = appState.selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if tab == .timeline {
                    controller.showTimelineHome()
                } else {
                    appState.selectedTab = tab
                }
            }
        } label: {
            HStack(spacing: MuesliTheme.spacing12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textSecondary)
                    .frame(width: sidebarIconColumnWidth, height: sidebarIconColumnWidth, alignment: .center)
                    .offset(y: icon == "square.and.arrow.down" ? -1 : 0)
                Text(label)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                Spacer()
                if let updateCTA {
                    HStack(spacing: 4) {
                        Image(systemName: updateCTA.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(updateCTA.label)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(updateCTA.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MuesliTheme.accent)
                    .clipShape(Capsule())
                    .shadow(color: MuesliTheme.accent.opacity(0.35), radius: 8, x: 0, y: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(updateCTA.accessibilityLabel)
                    .help(updateCTA.tooltip)
                }
            }
            .padding(.horizontal, sidebarRowHorizontalPadding)
            .padding(.vertical, MuesliTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                    .fill(isSelected ? MuesliTheme.surfaceSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, sidebarRowOuterPadding)
        .featureTourTarget(tab == .timeline ? .timelineSidebar : nil)
    }

    @ViewBuilder
    private var darkModeToggle: some View {
        let isDark = appState.config.darkMode
        HStack(spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.updateConfig { $0.darkMode = false }
                }
            } label: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(!isDark ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(!isDark ? MuesliTheme.surfaceSelected : Color.clear)
                    )
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.updateConfig { $0.darkMode = true }
                }
            } label: {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isDark ? MuesliTheme.accent : MuesliTheme.textTertiary)
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? MuesliTheme.surfaceSelected : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(MuesliTheme.backgroundRaised)
        )
        .padding(.horizontal, sidebarRowOuterPadding)
        .padding(.leading, sidebarRowHorizontalPadding)
        .padding(.bottom, MuesliTheme.spacing4)
    }

    @ViewBuilder
    private func meetingFilterRow(
        icon: String,
        label: String,
        count: Int,
        isSelected: Bool,
        disclosureIcon: String? = nil,
        disclosureAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? MuesliTheme.accent : MuesliTheme.textTertiary)
                .frame(width: sidebarIconColumnWidth)
            Text(label)
                .font(MuesliTheme.callout())
                .foregroundStyle(isSelected ? MuesliTheme.textPrimary : MuesliTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(formattedCount(count))
                .font(MuesliTheme.caption())
                .monospacedDigit()
                .foregroundStyle(MuesliTheme.textTertiary)
                .frame(minWidth: meetingsTrailingColumnWidth, alignment: .center)
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(isSelected ? MuesliTheme.surfaceSelected.opacity(0.6) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .overlay(alignment: .leading) {
            if let disclosureIcon, let disclosureAction {
                Button(action: disclosureAction) {
                    Image(systemName: disclosureIcon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MuesliTheme.textTertiary)
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 4)
            }
        }
    }

    @ViewBuilder
    private func folderRenameField(folder: MeetingFolder) -> some View {
        HStack(spacing: MuesliTheme.spacing8) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuesliTheme.accent)
                .frame(width: sidebarIconColumnWidth)
            TextField(String(localized: "sidebar.folder.rename.placeholder", defaultValue: "Folder name", bundle: .module, comment: "Placeholder text in folder rename field."), text: $renamingFolderName)
                .font(MuesliTheme.callout())
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = renamingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.renameFolder(id: folder.id, name: trimmed)
                    }
                    renamingFolderID = nil
                }
        }
        .padding(.horizontal, sidebarRowHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerSmall)
                .fill(MuesliTheme.surfaceSelected.opacity(0.6))
        )
    }

    private func formattedCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", Double(Int(k * 10)) / 10.0)
        }
        return "\(count / 1000)k"
    }

    private var folderTreePresentation: FolderTreePresentation {
        FolderTreePresentation(
            folders: dragOrderedFolders ?? appState.folders,
            collapsedFolderIDs: collapsedFolderIDs
        )
    }

    private func toggleFolderCollapse(_ folderID: Int64) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if collapsedFolderIDs.contains(folderID) {
                collapsedFolderIDs.remove(folderID)
            } else {
                collapsedFolderIDs.insert(folderID)
            }
        }
    }

    private func createNewFolder() {
        if let id = controller.createFolder(name: String(localized: "sidebar.folder.new_folder.title.primary", defaultValue: "New Folder", bundle: .module, comment: "Primary title text for new folder creation UI.")) {
            withAnimation(.easeInOut(duration: 0.15)) {
                meetingsExpanded = true
            }
            renamingFolderID = id
            renamingFolderName = String(localized: "sidebar.folder.new_folder.title.secondary", defaultValue: "New Folder", bundle: .module, comment: "Secondary title text for new folder creation UI.")
            controller.showMeetingsHome(folderID: id)
        }
    }

    private func createNewSubfolder(parentID: Int64) {
        if let id = controller.createSubfolder(name: String(localized: "sidebar.folder.new_folder.title.tertiary", defaultValue: "New Folder", bundle: .module, comment: "Tertiary title text for new folder creation UI."), parentID: parentID) {
            withAnimation(.easeInOut(duration: 0.15)) {
                meetingsExpanded = true
                collapsedFolderIDs.remove(parentID)
            }
            renamingFolderID = id
            renamingFolderName = String(localized: "sidebar.folder.new_folder.title.quaternary", defaultValue: "New Folder", bundle: .module, comment: "Quaternary title text for new folder creation UI.")
            controller.showMeetingsHome(folderID: id)
        }
    }
}

private struct FolderTreePresentation {
    let visibleFolders: [MeetingFolder]
    let depthByID: [Int64: Int]
    let childrenByParent: [Int64: [Int64]]

    init(folders: [MeetingFolder], collapsedFolderIDs: Set<Int64>) {
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var childrenByParent: [Int64: [Int64]] = [:]
        for folder in folders {
            if let parentID = folder.parentID {
                childrenByParent[parentID, default: []].append(folder.id)
            }
        }

        var depthCache: [Int64: Int] = [:]
        func depth(for folder: MeetingFolder, visited: Set<Int64> = []) -> Int {
            if let cached = depthCache[folder.id] { return cached }
            guard let parentID = folder.parentID,
                  let parent = byID[parentID],
                  !visited.contains(folder.id) else {
                depthCache[folder.id] = 0
                return 0
            }
            var nextVisited = visited
            nextVisited.insert(folder.id)
            let value = 1 + depth(for: parent, visited: nextVisited)
            depthCache[folder.id] = value
            return value
        }

        var hiddenCache: [Int64: Bool] = [:]
        func isHidden(_ folder: MeetingFolder, visited: Set<Int64> = []) -> Bool {
            if let cached = hiddenCache[folder.id] { return cached }
            guard let parentID = folder.parentID,
                  let parent = byID[parentID],
                  !visited.contains(folder.id) else {
                hiddenCache[folder.id] = false
                return false
            }
            if collapsedFolderIDs.contains(parentID) {
                hiddenCache[folder.id] = true
                return true
            }
            var nextVisited = visited
            nextVisited.insert(folder.id)
            let hidden = isHidden(parent, visited: nextVisited)
            hiddenCache[folder.id] = hidden
            return hidden
        }

        var computedDepths: [Int64: Int] = [:]
        for folder in folders {
            computedDepths[folder.id] = depth(for: folder)
        }

        self.visibleFolders = folders.filter { !isHidden($0) }
        self.depthByID = computedDepths
        self.childrenByParent = childrenByParent
    }

    func depth(of folder: MeetingFolder) -> Int {
        depthByID[folder.id] ?? 0
    }

    func hasChildren(_ folderID: Int64) -> Bool {
        !(childrenByParent[folderID] ?? []).isEmpty
    }
}

private struct FolderDropDelegate: DropDelegate {
    let folderID: Int64
    @Binding var dragOrderedFolders: [MeetingFolder]?
    @Binding var draggingFolderID: Int64?
    let commitOrder: ([Int64]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragID = draggingFolderID, dragID != folderID,
              var folders = dragOrderedFolders else { return }
        guard canReorder(dragID: dragID, targetID: folderID, folders: folders),
              let fromIndex = folders.firstIndex(where: { $0.id == dragID }),
              let toIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }

        let draggedSubtree = subtreeIDs(rootedAt: dragID, folders: folders)
        let movedFolders = folders.filter { draggedSubtree.contains($0.id) }
        folders.removeAll { draggedSubtree.contains($0.id) }
        guard let adjustedTargetIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let insertionIndex: Int
        if toIndex > fromIndex {
            let targetSubtree = subtreeIDs(rootedAt: folderID, folders: folders)
            let lastTargetIndex = folders.indices.last { targetSubtree.contains(folders[$0].id) } ?? adjustedTargetIndex
            insertionIndex = lastTargetIndex + 1
        } else {
            insertionIndex = adjustedTargetIndex
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            folders.insert(contentsOf: movedFolders, at: insertionIndex)
            dragOrderedFolders = folders
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let folders = dragOrderedFolders {
            commitOrder(folders.map(\.id))
        }
        draggingFolderID = nil
        dragOrderedFolders = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragID = draggingFolderID,
              let folders = dragOrderedFolders,
              canReorder(dragID: dragID, targetID: folderID, folders: folders) else {
            return nil
        }
        return DropProposal(operation: .move)
    }

    private func canReorder(dragID: Int64, targetID: Int64, folders: [MeetingFolder]) -> Bool {
        guard dragID != targetID,
              let dragged = folders.first(where: { $0.id == dragID }),
              let target = folders.first(where: { $0.id == targetID }) else {
            return false
        }
        return dragged.parentID == target.parentID
    }

    private func subtreeIDs(rootedAt rootID: Int64, folders: [MeetingFolder]) -> Set<Int64> {
        var childrenByParent: [Int64: [Int64]] = [:]
        for folder in folders {
            if let parentID = folder.parentID {
                childrenByParent[parentID, default: []].append(folder.id)
            }
        }

        var result: Set<Int64> = []
        func visit(_ id: Int64) {
            guard result.insert(id).inserted else { return }
            for childID in childrenByParent[id] ?? [] {
                visit(childID)
            }
        }
        visit(rootID)
        return result
    }
}
