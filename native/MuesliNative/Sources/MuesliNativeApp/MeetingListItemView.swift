import SwiftUI
import MuesliCore

struct MeetingListItemView: View {
    let record: MeetingRecord
    let isSelected: Bool
    let hasFollowUps: Bool
    let folders: [MeetingFolder]
    private let folderByID: [Int64: MeetingFolder]
    private let folderIDsWithChildren: Set<Int64>
    let onSelect: () -> Void
    let onMove: (Int64?) -> Void
    let onCreateFolderAndMove: ((String) -> Void)?
    let onDelete: (() -> Void)?
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false
    @State private var showFolderPopover = false
    @State private var showNewFolderPrompt = false
    @State private var newFolderName = ""

    init(
        record: MeetingRecord,
        isSelected: Bool,
        hasFollowUps: Bool,
        folders: [MeetingFolder],
        onSelect: @escaping () -> Void,
        onMove: @escaping (Int64?) -> Void,
        onCreateFolderAndMove: ((String) -> Void)?,
        onDelete: (() -> Void)?
    ) {
        self.record = record
        self.isSelected = isSelected
        self.hasFollowUps = hasFollowUps
        self.folders = folders
        self.folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        self.folderIDsWithChildren = Set(folders.compactMap(\.parentID))
        self.onSelect = onSelect
        self.onMove = onMove
        self.onCreateFolderAndMove = onCreateFolderAndMove
        self.onDelete = onDelete
    }

    private var currentFolderName: String? {
        guard let fid = record.folderID else { return nil }
        guard let folder = folderByID[fid] else { return nil }
        // Build breadcrumb path: "Grandparent / Parent / Folder"
        var parts: [String] = [folder.name]
        var current = folder.parentID
        var seen: Set<Int64> = [folder.id]
        while let pid = current, let parent = folderByID[pid], seen.insert(pid).inserted {
            parts.insert(parent.name, at: 0)
            current = parent.parentID
        }
        return parts.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MuesliTheme.spacing8) {
            HStack(alignment: .top) {
                Text(record.title)
                    .font(MuesliTheme.headline())
                    .foregroundStyle(MuesliTheme.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    relationshipIndicators
                    if !folders.isEmpty {
                        folderMenuButton
                    }
                    if onDelete != nil {
                        deleteButton
                    }
                }
            }

            HStack(spacing: MuesliTheme.spacing4) {
                if record.status != .completed {
                    statusBadge
                    Text("\u{2022}")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                }
                Text(formatMeta())
                    .font(MuesliTheme.caption())
                    .foregroundStyle(MuesliTheme.textSecondary)

                if let sourceIndicator = sourceIndicator {
                    sourceIndicator
                }

                // Current folder badge
                if let name = currentFolderName {
                    Text("\u{2022}")
                        .font(MuesliTheme.caption())
                        .foregroundStyle(MuesliTheme.textTertiary)
                    HStack(spacing: 2) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(name)
                            .font(MuesliTheme.caption())
                    }
                    .foregroundStyle(MuesliTheme.accent.opacity(0.8))
                }
            }

            Text(previewText())
                .font(MuesliTheme.caption())
                .foregroundStyle(MuesliTheme.textTertiary)
                .lineLimit(2)
        }
        .padding(MuesliTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MuesliTheme.surfaceSelected : MuesliTheme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: MuesliTheme.cornerLarge)
                .strokeBorder(
                    isSelected ? MuesliTheme.accent.opacity(0.35) : MuesliTheme.surfaceBorder,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .alert(String(localized: "meeting_list_item.delete_meeting.alert_title", defaultValue: "Delete Meeting", comment: "Alert title for confirming meeting deletion."), isPresented: $showDeleteConfirmation) {
            Button(String(localized: "common.delete", defaultValue: "Delete", comment: "Common destructive action button title."), role: .destructive) { onDelete?() }
            Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action button title."), role: .cancel) {}
        } message: {
            Text(String(localized: "meeting_list_item.delete_meeting.alert_message", defaultValue: "Are you sure you want to delete this meeting? Saved notes, transcript, and any retained recording will be removed.", comment: "Alert body text describing consequences of deleting a meeting."))
        }
    }

    // MARK: - Folder menu button

    @ViewBuilder
    private var relationshipIndicators: some View {
        if record.followUpToID != nil || hasFollowUps {
            HStack(spacing: 4) {
                if record.followUpToID != nil {
                    relationshipIcon(
                        "arrow.turn.down.right",
                        help: String(localized: "meeting_list_item.relationship.follow_up_meeting", defaultValue: "Follow-up meeting", comment: "Relationship label indicating this meeting is a follow-up.")
                    )
                }
                if hasFollowUps {
                    relationshipIcon(
                        "arrow.triangle.branch",
                        help: String(localized: "meeting_list_item.relationship.has_follow_up_meetings", defaultValue: "Has follow-up meetings", comment: "Relationship label indicating this meeting has follow-up meetings.")
                    )
                }
            }
        }
    }

    private func relationshipIcon(_ systemName: String, help: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MuesliTheme.accent.opacity(0.9))
            .frame(width: 24, height: 24)
            .help(help)
            .accessibilityLabel(help)
    }

    private func folderBreadcrumb(_ folder: MeetingFolder) -> String {
        var parts: [String] = [folder.name]
        var current = folder.parentID
        var seen: Set<Int64> = [folder.id]
        while let pid = current, let parent = folderByID[pid], seen.insert(pid).inserted {
            parts.insert(parent.name, at: 0)
            current = parent.parentID
        }
        return parts.joined(separator: " / ")
    }

    @ViewBuilder
    private var folderMenuButton: some View {
        Button {
            showFolderPopover.toggle()
        } label: {
            Image(systemName: record.folderID != nil ? "folder.fill" : "folder.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(
                    record.folderID != nil
                        ? MuesliTheme.accent
                        : (isHovering ? MuesliTheme.textSecondary : MuesliTheme.textTertiary)
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "meeting_list_item.folder_menu.move_to_folder.help", defaultValue: "Move to folder", comment: "Help text for move-to-folder menu in meeting list item."))
        .popover(isPresented: $showFolderPopover, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                folderPopoverRow(icon: "tray", label: String(localized: "meeting_list_item.folder.unfiled", defaultValue: "Unfiled", comment: "Folder label for meetings not assigned to a folder."), isActive: record.folderID == nil) {
                    onMove(nil)
                    showFolderPopover = false
                }
                Divider().padding(.vertical, 4)
                ForEach(folders) { folder in
                    let hasChildren = folderIDsWithChildren.contains(folder.id)
                    folderPopoverRow(
                        icon: hasChildren ? "folder.fill" : String(localized: "meeting_list_item.folder.generic_name", defaultValue: "folder", comment: "Generic fallback folder name used when folder name is unavailable."),
                        label: folderBreadcrumb(folder),
                        isActive: record.folderID == folder.id
                    ) {
                        onMove(folder.id)
                        showFolderPopover = false
                    }
                }
                if onCreateFolderAndMove != nil {
                    Divider().padding(.vertical, 4)
                    folderPopoverRow(icon: "folder.badge.plus", label: String(localized: "meeting_list_item.folder.new_folder_menu", defaultValue: "New Folder...", comment: "Menu item title for creating a new folder from meeting list item.")) {
                        showFolderPopover = false
                        newFolderName = ""
                        showNewFolderPrompt = true
                    }
                }
            }
            .padding(8)
        }
        .alert(String(localized: "meeting_list_item.new_folder.alert_title", defaultValue: "New Folder", comment: "Alert title for creating a new folder."), isPresented: $showNewFolderPrompt) {
            TextField(String(localized: "meeting_list_item.folder_name.placeholder", defaultValue: "Folder name", comment: "Text field placeholder for entering a new folder name."), text: $newFolderName)
            Button(String(localized: "common.create", defaultValue: "Create", comment: "Common create action button title.")) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCreateFolderAndMove?(trimmed)
                }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Common cancel action button title."), role: .cancel) {}
        } message: {
            Text(String(localized: "meeting_list_item.folder_menu.create_and_move.description", defaultValue: "Create a new folder and move this meeting into it.", comment: "Description text in new-folder dialog from meeting list item."))
        }
    }

    @ViewBuilder
    private func folderPopoverRow(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(label)
                    .font(MuesliTheme.callout())
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuesliTheme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(
                    isHovering
                        ? MuesliTheme.recording.opacity(0.85)
                        : MuesliTheme.textTertiary
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .help(String(localized: "meeting_list_item.delete_button.help", defaultValue: "Delete meeting", comment: "Help text for delete meeting button."))
    }

    // MARK: - Formatting

    private var statusBadge: some View {
        Text(record.status.displayLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(record.status.displayColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(record.status.displayColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var sourceIndicator: AnyView? {
        if let label = SyncOriginDisplay.badgeLabel(forMeetingSource: record.source) {
            return AnyView(SyncOriginBadge(label: label))
        }
        if isImportedAudio {
            return AnyView(sourceBadge(icon: "square.and.arrow.down", label: String(localized: "meeting_list_item.source.imported.badge", defaultValue: "Imported", comment: "Badge text indicating meeting content was imported."), help: String(localized: "meeting_list_item.source.imported_audio.label", defaultValue: "Imported audio", comment: "Accessibility label for imported meeting source badge.")))
        }
        if hasSavedRecording {
            return AnyView(sourceBadge(icon: "waveform", label: String(localized: "meeting_list_item.source.recording.badge", defaultValue: "Recording", comment: "Badge text indicating meeting has a recording source."), help: String(localized: "meeting_list_item.source.saved_recording_available", defaultValue: "Saved recording available", comment: "Accessibility label for recording source badge.")))
        }
        return nil
    }

    private var isImportedAudio: Bool {
        record.source == .audioImport || hasLegacyImportedRecordingPath
    }

    private var hasLegacyImportedRecordingPath: Bool {
        guard let savedRecordingPath = record.savedRecordingPath else { return false }
        let filename = URL(fileURLWithPath: savedRecordingPath).lastPathComponent
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}_.+_[0-9A-Fa-f]{8}\.wav$"#
        return filename.range(of: pattern, options: .regularExpression) != nil
    }

    private var hasSavedRecording: Bool {
        guard let savedRecordingPath = record.savedRecordingPath else { return false }
        return !savedRecordingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sourceBadge(icon: String, label: String, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isImportedAudio ? MuesliTheme.accent : MuesliTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isImportedAudio ? MuesliTheme.accent : MuesliTheme.textSecondary).opacity(0.12))
        .clipShape(Capsule())
        .help(help)
        .accessibilityLabel(help)
    }

    private func formatMeta() -> String {
        let time = MeetingBrowserLogic.formatStartTime(record.startTime)
        let duration = formatDuration(record.durationSeconds)
        return String(format: String(localized: "meeting_list_item.meta.time_duration_format", defaultValue: "%@  •  %@", comment: "Meeting metadata line showing time and duration separated by a bullet."), "\(time)", "\(duration)")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 {
            return String(format: String(localized: "meeting_list_item.duration.hours_minutes_format", defaultValue: "%dh %dm", comment: "Duration format showing hours and minutes."), rounded / 3600, (rounded % 3600) / 60)
        }
        if rounded >= 60 {
            let m = rounded / 60
            let s = rounded % 60
            return s == 0 ? String(format: String(localized: "meeting_list_item.duration.minutes_format", defaultValue: "%dm", comment: "Duration format showing only minutes."), m) : String(format: String(localized: "meeting_list_item.duration.minutes_seconds_format", defaultValue: "%dm %ds", comment: "Duration format showing minutes and seconds."), m, s)
        }
        return String(format: String(localized: "meeting_list_item.duration.seconds_format", defaultValue: "%ds", comment: "Duration format showing only seconds."), rounded)
    }

    private func previewText() -> String {
        let source: String
        if !record.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           record.status != .completed {
            source = record.manualNotes
        } else {
            source = record.formattedNotes.isEmpty ? record.rawTranscript : record.formattedNotes
        }
        return MeetingPreviewText.snippet(from: source)
    }

}
