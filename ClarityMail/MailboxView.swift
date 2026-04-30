//
//  MailboxView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct MailboxView: View {
    @ObservedObject var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var selectedEmail: Email?
    @State private var emails = Email.previewEmails
    @State private var accounts: [GmailAccount] = []
    @State private var selectedAccountId: String?
    @State private var selectedFolder: MailboxFolder = .inbox
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingComposer = false
    @State private var isShowingBlockedSenders = false
    @State private var isShowingSettings = false
    @State private var isShowingMorningBrief = false
    @State private var draftToEdit: Email?
    @State private var nextPageToken: String?
    @State private var isLoadingMore = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var morningBriefTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var knownEmailIds = Set<String>()
    @State private var selectedEmailIds = Set<Email.ID>()
    @State private var isSelectionMode = false
    @State private var isPerformingBulkAction = false
    @State private var hasLoadedInitialEmails = false

    private let apiClient = APIClient()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        FluxHeader()
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                        GreetingBlock(name: session.displayName, unreadCount: unreadCount)
                            .padding(.horizontal, 24)

                        AccountSearchBar(
                            accounts: accounts,
                            selectedAccountId: $selectedAccountId,
                            selectedFolder: $selectedFolder,
                            searchText: $searchText,
                            onAddAccount: {
                                Task { await session.signInWithGoogle() }
                            },
                            onRefreshAccounts: {
                                Task {
                                    await loadAccounts()
                                    await loadEmails()
                                }
                            },
                            onManageBlockedSenders: {
                                isShowingBlockedSenders = true
                            },
                            onOpenSettings: {
                                isShowingSettings = true
                            }
                        )
                        .padding(.horizontal, 20)

                        EmailListSection(
                            emails: emails,
                            isLoading: isLoading,
                            isSearchLoading: isLoading && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            isLoadingMore: isLoadingMore,
                            canLoadMore: nextPageToken != nil,
                            errorMessage: errorMessage,
                            selectedEmailIds: selectedEmailIds,
                            isSelectionMode: isSelectionMode,
                            isPerformingBulkAction: isPerformingBulkAction,
                            selectedFolder: selectedFolder,
                            onSetSelectionMode: { isEnabled in
                                isSelectionMode = isEnabled
                                if !isEnabled {
                                    selectedEmailIds.removeAll()
                                }
                            },
                            onSelectAll: {
                                selectedEmailIds = Set(emails.map(\.id))
                                isSelectionMode = true
                            },
                            onToggleSelection: { email in
                                toggleSelection(email)
                            },
                            onBulkAction: { action in
                                Task { await performBulkAction(action) }
                            },
                            onSelect: { email in
                                if selectedFolder == .drafts || email.draftId != nil {
                                    draftToEdit = email
                                } else {
                                    selectedEmail = email
                                }
                            },
                            onLoadMore: {
                                Task { await loadMoreEmails() }
                            }
                        )
                        .padding(.horizontal, 20)

                        Color.clear.frame(height: 110)
                    }
                    .padding(.top, 4)
                }
                .scrollIndicators(.hidden)

                BottomActionBar(
                    onMail: { /* already in mail */ },
                    onCompose: { isShowingComposer = true }
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                if isShowingComposer {
                    ComposerView(
                        mode: .compose,
                        accountId: selectedAccountId,
                        accounts: accounts,
                        onSent: {
                            Task { await loadEmails() }
                        },
                        onClose: {
                            isShowingComposer = false
                        }
                    )
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }

                if let draftToEdit {
                    ComposerView(
                        mode: .draft(draftToEdit),
                        accountId: selectedAccountId ?? draftToEdit.accountId,
                        accounts: accounts,
                        onSent: {
                            Task { await loadEmails() }
                        },
                        onClose: {
                            self.draftToEdit = nil
                        }
                    )
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .overlay(alignment: .bottom) {
                UndoSendToast()
                    .padding(.bottom, 88)
                    .zIndex(30)
            }
            .animation(.snappy(duration: 0.2), value: isShowingComposer)
            .animation(.snappy(duration: 0.2), value: draftToEdit)
            .modifier(HideNavigationBarModifier())
            .navigationDestination(item: $selectedEmail) { email in
                EmailDetailView(email: email, accountId: selectedAccountId ?? email.accountId, accounts: accounts) { blockedSender in
                    emails.removeAll {
                        $0.senderEmailAddress.caseInsensitiveCompare(blockedSender) == .orderedSame
                    }
                }
            }
            .task {
                await NotificationManager.shared.requestAuthorization()
                await loadAccounts()
                await loadEmails()
                await startRealtimeSync()
                startAutoRefresh()
                startMorningBriefPolling()
                openPendingMorningBriefIfNeeded()
            }
            .onChange(of: selectedAccountId) {
                selectedEmail = nil
                knownEmailIds.removeAll()
                hasLoadedInitialEmails = false
                nextPageToken = nil
                Task {
                    await loadEmails()
                    await startRealtimeSync()
                }
            }
            .onChange(of: selectedFolder) {
                selectedEmail = nil
                knownEmailIds.removeAll()
                hasLoadedInitialEmails = false
                nextPageToken = nil
                Task {
                    await loadEmails()
                }
            }
            .onChange(of: searchText) {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if Task.isCancelled { return }
                    nextPageToken = nil
                    await loadEmails()
                }
            }
            .onChange(of: session.pendingAuthURL) {
                guard let url = session.pendingAuthURL else { return }
                openURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMorningBrief)) { _ in
                isShowingMorningBrief = true
                UserDefaults.standard.removeObject(forKey: "pendingMorningBriefId")
            }
            .onDisappear {
                autoRefreshTask?.cancel()
                morningBriefTask?.cancel()
                searchTask?.cancel()
            }
            .sheet(isPresented: $isShowingBlockedSenders) {
                BlockedSendersView(accountId: selectedAccountId)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(accounts: accounts) {
                    Task {
                        await loadAccounts()
                        await loadEmails()
                    }
                }
            }
            .sheet(isPresented: $isShowingMorningBrief) {
                MorningBriefDetailView()
            }
            .refreshable {
                nextPageToken = nil
                await loadEmails(notifyForNewEmails: false)
            }
        }
        .tint(Theme.Palette.accent)
    }

    private var unreadCount: Int { emails.filter { !$0.isRead }.count }

    private func loadAccounts() async {
        do {
            accounts = try await apiClient.accounts()
            if let selectedAccountId, !accounts.contains(where: { $0.id == selectedAccountId }) {
                self.selectedAccountId = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not load accounts."
        }
    }

    private func loadEmails(notifyForNewEmails: Bool = true) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await apiClient.emails(accountId: selectedAccountId, searchQuery: searchText, folder: selectedFolder)
            let fetchedEmails = page.emails
            let fetchedIds = Set(fetchedEmails.map(\.id))

            if shouldNotifyForNewEmails(notifyForNewEmails: notifyForNewEmails) {
                let newEmails = fetchedEmails
                    .filter { !knownEmailIds.contains($0.id) }
                    .prefix(3)

                for email in newEmails {
                    await NotificationManager.shared.notifyNewEmail(email)
                }
            }

            emails = fetchedEmails
            nextPageToken = page.nextPageToken
            knownEmailIds = fetchedIds
            selectedEmailIds.removeAll()
            isSelectionMode = false
            hasLoadedInitialEmails = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not load inbox."
        }
    }

    private func loadMoreEmails() async {
        guard let nextPageToken, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await apiClient.emails(
                accountId: selectedAccountId,
                searchQuery: searchText,
                folder: selectedFolder,
                pageToken: nextPageToken
            )
            emails.append(contentsOf: page.emails.filter { newEmail in
                !emails.contains(where: { $0.id == newEmail.id })
            })
            self.nextPageToken = page.nextPageToken
            knownEmailIds.formUnion(page.emails.map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = "Could not load more emails."
        }
    }

    private func shouldNotifyForNewEmails(notifyForNewEmails: Bool) -> Bool {
        notifyForNewEmails &&
        hasLoadedInitialEmails &&
        selectedFolder == .inbox &&
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedEmails: [Email] {
        emails.filter { selectedEmailIds.contains($0.id) }
    }

    private func toggleSelection(_ email: Email) {
        if selectedEmailIds.contains(email.id) {
            selectedEmailIds.remove(email.id)
        } else {
            selectedEmailIds.insert(email.id)
        }
        isSelectionMode = !selectedEmailIds.isEmpty
    }

    private func performBulkAction(_ action: BulkEmailAction) async {
        let targets = selectedEmails
        guard !targets.isEmpty, !isPerformingBulkAction else { return }

        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }

        do {
            for email in targets {
                try await perform(action, email: email)
            }

            applyBulkAction(action, to: Set(targets.map(\.id)))
            selectedEmailIds.removeAll()
            isSelectionMode = false
            errorMessage = nil
        } catch {
            errorMessage = "Could not update selected emails."
        }
    }

    private func perform(_ action: BulkEmailAction, email: Email) async throws {
        switch action {
        case .trash:
            if let draftId = email.draftId {
                try await apiClient.deleteDraft(draftId: draftId, accountId: email.accountId)
            } else {
                try await apiClient.trashEmail(id: email.id, accountId: email.accountId)
            }
        case .archive:
            try await apiClient.archiveEmail(id: email.id, accountId: email.accountId)
        case .markRead:
            try await apiClient.markEmailRead(id: email.id, accountId: email.accountId)
        case .markUnread:
            try await apiClient.markEmailUnread(id: email.id, accountId: email.accountId)
        case .star:
            try await apiClient.starEmail(id: email.id, accountId: email.accountId)
        case .unstar:
            try await apiClient.unstarEmail(id: email.id, accountId: email.accountId)
        }
    }

    private func applyBulkAction(_ action: BulkEmailAction, to ids: Set<Email.ID>) {
        switch action {
        case .trash, .archive:
            emails.removeAll { ids.contains($0.id) }
        case .markRead:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isRead = true
            }
        case .markUnread:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isRead = false
            }
        case .star:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isStarred = true
            }
        case .unstar:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isStarred = false
            }
        }
    }

    private func startRealtimeSync() async {
        do {
            try await apiClient.startRealtimeSync(accountId: selectedAccountId)
        } catch {
            errorMessage = "Could not start realtime sync."
        }
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { return }
                await loadEmails()
            }
        }
    }

    private func startMorningBriefPolling() {
        morningBriefTask?.cancel()
        morningBriefTask = Task {
            while !Task.isCancelled {
                await runMorningBriefIfDue()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func runMorningBriefIfDue() async {
        do {
            let settings = try await apiClient.morningBriefSettings()
            guard settings.enabled else { return }

            let now = Date()
            let currentTime = Self.timeString(from: now)
            guard currentTime == settings.briefTime else { return }

            let runKey = "\(Self.dayString(from: now))-\(settings.briefTime)"
            guard UserDefaults.standard.string(forKey: "morningBriefLastRunKey") != runKey else { return }

            let result = try await apiClient.runMorningBrief()
            UserDefaults.standard.set(runKey, forKey: "morningBriefLastRunKey")

            if result.shouldNotify {
                await NotificationManager.shared.notifyMorningBrief(result.brief)
            }
        } catch {
            // Morning Brief should not block normal inbox usage.
        }
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static func dayString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func openPendingMorningBriefIfNeeded() {
        if UserDefaults.standard.string(forKey: "pendingMorningBriefId") != nil {
            isShowingMorningBrief = true
            UserDefaults.standard.removeObject(forKey: "pendingMorningBriefId")
        }
    }
}

private struct MorningBriefDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var brief: MorningBrief?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            content
        }
        .frame(minWidth: 640, minHeight: 620)
        .background(Theme.Palette.background)
        .task {
            await loadBrief()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Morning Brief")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let brief {
                    Text(brief.windowText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Unread emails from your overnight window")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.Palette.surfaceElevated.opacity(0.7)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(Theme.Palette.surface.opacity(0.72))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.warm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let brief {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MorningBriefStats(brief: brief)

                    MorningBriefDetailGroup(
                        title: "Needs Attention",
                        subtitle: "Real things worth dealing with first.",
                        systemImage: "target",
                        accent: Theme.Palette.warm,
                        items: brief.summary.important + brief.summary.needsAction + brief.summary.deadlines
                    )
                    MorningBriefDetailGroup(
                        title: "FYI",
                        subtitle: "Useful, but not urgent.",
                        systemImage: "info.circle",
                        accent: Theme.Palette.accentSoft,
                        items: brief.summary.fyi
                    )

                    if brief.summary.important.isEmpty,
                       brief.summary.needsAction.isEmpty,
                       brief.summary.deadlines.isEmpty,
                       brief.summary.fyi.isEmpty {
                        EmptyMorningBriefState(ignoredCount: brief.ignoredCount)
                    }
                }
                .padding(28)
            }
        } else {
            Text("No Morning Brief yet.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadBrief() async {
        isLoading = true
        defer { isLoading = false }

        do {
            brief = try await apiClient.latestMorningBrief()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load Morning Brief."
        }
    }
}

private struct MorningBriefStats: View {
    let brief: MorningBrief

    var body: some View {
        HStack(spacing: 10) {
            MorningBriefStatPill(title: "Scanned", value: "\(brief.totalUnread)", color: Theme.Palette.textSecondary)
            MorningBriefStatPill(title: "Needs attention", value: "\(brief.actionableCount)", color: Theme.Palette.warm)
            MorningBriefStatPill(title: "FYI", value: "\(brief.summary.fyi.count)", color: Theme.Palette.accentSoft)
            MorningBriefStatPill(title: "Ignored", value: "\(brief.ignoredCount)", color: Theme.Palette.textTertiary)
        }
    }
}

private struct MorningBriefStatPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

private struct MorningBriefDetailGroup: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let items: [MorningBriefItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(accent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }

                    Spacer()

                    Text("\(items.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }

                VStack(spacing: 8) {
                    ForEach(items) { item in
                        MorningBriefItemRow(item: item, accent: accent)
                    }
                }
            }
        }
    }
}

private struct MorningBriefItemRow: View {
    let item: MorningBriefItem
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.subject.cleanedBriefSubject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)

                Text(item.summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(3)

                if let action = item.action, !action.isEmpty, action.lowercased() != "none" {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(action)
                            .lineLimit(2)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.12)))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

private struct EmptyMorningBriefState: View {
    let ignoredCount: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Palette.accentSoft)

            Text("Nothing needs attention")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("\(ignoredCount) low-priority emails were skipped.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

// MARK: - Account + Search

private struct AccountSearchBar: View {
    let accounts: [GmailAccount]
    @Binding var selectedAccountId: String?
    @Binding var selectedFolder: MailboxFolder
    @Binding var searchText: String
    let onAddAccount: () -> Void
    let onRefreshAccounts: () -> Void
    let onManageBlockedSenders: () -> Void
    let onOpenSettings: () -> Void

    private var selectedAccount: GmailAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MailboxFolder.allCases) { folder in
                        Button {
                            selectedFolder = folder
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: folder.systemImage)
                                Text(folder.title)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedFolder == folder ? .white : Theme.Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedFolder == folder ? Theme.Palette.accent : Theme.Palette.surface.opacity(0.65))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selectedFolder == folder ? Color.clear : Theme.Palette.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                Menu {
                    Button {
                        selectedAccountId = nil
                    } label: {
                        Label("All Inboxes", systemImage: selectedAccountId == nil ? "checkmark.circle.fill" : "tray.full")
                    }

                    Divider()

                    ForEach(accounts) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            Label(account.email, systemImage: selectedAccountId == account.id ? "checkmark.circle.fill" : "circle")
                        }
                    }

                    Divider()

                    Button(action: onAddAccount) {
                        Label("Add Account", systemImage: "plus")
                    }

                    Button(action: onRefreshAccounts) {
                        Label("Refresh Accounts", systemImage: "arrow.clockwise")
                    }

                    Button(action: onManageBlockedSenders) {
                        Label("Blocked Senders", systemImage: "hand.raised")
                    }

                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                        Text(selectedAccount?.email ?? "All Inboxes")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.Palette.surface.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.Palette.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Palette.textTertiary)

                TextField("Search \(selectedFolder.title.lowercased())", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.Palette.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Palette.surface.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Platform helpers

private struct HideNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar(.hidden, for: .navigationBar)
        #else
        content
        #endif
    }
}

// MARK: - Header

private struct FluxHeader: View {
    var body: some View {
        HStack {
            Text("ClarityMail")
                .font(.system(size: 28, weight: .light, design: .default))
                .kerning(-0.5)
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Greeting

private struct GreetingBlock: View {
    let name: String
    let unreadCount: Int

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Hello"
        }
    }

    private var subtitle: String {
        switch unreadCount {
        case 0: return "You're all caught up."
        case 1: return "1 unread message"
        default: return "\(unreadCount) unread messages"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greeting), \(name)")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

// MARK: - Email List

private enum BulkEmailAction: String, CaseIterable {
    case archive
    case trash
    case markRead
    case markUnread
    case star
    case unstar

    var title: String {
        switch self {
        case .archive: return "Archive"
        case .trash: return "Trash"
        case .markRead: return "Read"
        case .markUnread: return "Unread"
        case .star: return "Star"
        case .unstar: return "Unstar"
        }
    }

    var systemImage: String {
        switch self {
        case .archive: return "archivebox"
        case .trash: return "trash"
        case .markRead: return "envelope.open"
        case .markUnread: return "envelope.badge"
        case .star: return "star"
        case .unstar: return "star.slash"
        }
    }
}

private struct EmailListSection: View {
    let emails: [Email]
    let isLoading: Bool
    let isSearchLoading: Bool
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let errorMessage: String?
    let selectedEmailIds: Set<Email.ID>
    let isSelectionMode: Bool
    let isPerformingBulkAction: Bool
    let selectedFolder: MailboxFolder
    let onSetSelectionMode: (Bool) -> Void
    let onSelectAll: () -> Void
    let onToggleSelection: (Email) -> Void
    let onBulkAction: (BulkEmailAction) -> Void
    let onSelect: (Email) -> Void
    let onLoadMore: () -> Void

    private var selectedCount: Int { selectedEmailIds.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.warm)
                    .padding(.horizontal, 4)
            }

            if !emails.isEmpty {
                selectionToolbar
            }

            if isSearchLoading {
                SearchLoadingView()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 260)
            } else if isLoading && emails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(emails) { email in
                        Button {
                            if isSelectionMode {
                                onToggleSelection(email)
                            } else {
                                onSelect(email)
                            }
                        } label: {
                            EmailRowView(
                                email: email,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedEmailIds.contains(email.id),
                                onToggleSelection: {
                                    onToggleSelection(email)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onToggleSelection(email)
                            } label: {
                                Label(selectedEmailIds.contains(email.id) ? "Deselect" : "Select", systemImage: "checkmark.circle")
                            }
                        }
                    }

                    if canLoadMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .onAppear(perform: onLoadMore)
                    } else if isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                Button {
                    onSetSelectionMode(!isSelectionMode)
                } label: {
                    Label(isSelectionMode ? "Cancel" : "Select", systemImage: isSelectionMode ? "xmark" : "checkmark.circle")
                }
                .buttonStyle(BulkActionButtonStyle())

                if isSelectionMode {
                    Button {
                        onSelectAll()
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BulkActionButtonStyle())

                    Text("\(selectedCount) selected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(minWidth: 70, alignment: .leading)

                    bulkActionButton(.archive)
                        .disabled(selectedFolder == .drafts || selectedFolder == .sent || selectedCount == 0)
                    bulkActionButton(.trash)
                        .disabled(selectedCount == 0)
                    bulkActionButton(.markRead)
                        .disabled(selectedFolder == .drafts || selectedCount == 0)
                    bulkActionButton(.markUnread)
                        .disabled(selectedFolder == .drafts || selectedCount == 0)

                    Menu {
                        Button {
                            onBulkAction(.star)
                        } label: {
                            Label("Star", systemImage: "star")
                        }
                        Button {
                            onBulkAction(.unstar)
                        } label: {
                            Label("Unstar", systemImage: "star.slash")
                        }
                    } label: {
                        Image(systemName: isPerformingBulkAction ? "hourglass" : "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 32)
                    }
                    .buttonStyle(BulkActionButtonStyle())
                    .disabled(selectedFolder == .drafts || selectedCount == 0 || isPerformingBulkAction)
                }
            }
        }
        .padding(.horizontal, 4)
        .scrollIndicators(.hidden)
        .animation(.snappy(duration: 0.18), value: isSelectionMode)
        .animation(.snappy(duration: 0.18), value: selectedCount)
    }

    private func bulkActionButton(_ action: BulkEmailAction) -> some View {
        Button {
            onBulkAction(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(BulkActionButtonStyle())
        .disabled(selectedCount == 0 || isPerformingBulkAction)
    }
}

private struct BulkActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(Theme.Palette.surface.opacity(configuration.isPressed ? 0.95 : 0.64))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
    }
}

private struct SearchLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.95)

            Text("Searching")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

private struct EmailRowView: View {
    let email: Email
    var isSelectionMode = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textTertiary)
                        .frame(width: 28, height: 38)
                }
                .buttonStyle(.plain)
            }

            SenderLogoView(email: email, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(email.displayName)
                        .font(.system(size: 15, weight: email.isRead ? .regular : .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Spacer()

                    Text(email.receivedAt.emailRowDateText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }

                Text(email.subject)
                    .font(.system(size: 14, weight: email.isRead ? .regular : .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                if let accountEmail = email.accountEmail, !accountEmail.isEmpty {
                    Text(accountEmail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(email.snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 4)

                    if !email.isRead {
                        Circle()
                            .fill(Theme.Palette.warm)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.accent.opacity(0.75) : Theme.Palette.border, lineWidth: isSelected ? 1.5 : 1)
        )
        .onLongPressGesture {
            onToggleSelection()
        }
    }
}

struct SenderLogoView: View {
    let email: Email
    let size: CGFloat
    @State private var logoImage: PlatformImage?
    @State private var isLoadingLogo = false

    private var initials: String {
        let parts = email.displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var seedColor: Color {
        let hash = abs(email.displayName.hashValue)
        let palette: [Color] = [
            Color(red: 0.078, green: 0.580, blue: 0.541), // teal
            Color(red: 0.180, green: 0.420, blue: 0.580), // ocean
            Color(red: 0.290, green: 0.341, blue: 0.541), // indigo
            Color(red: 0.400, green: 0.620, blue: 0.580), // sage
            Color(red: 0.180, green: 0.224, blue: 0.443)  // deep blue
        ]
        return palette[hash % palette.count]
    }

    var body: some View {
        Group {
            if let logoImage {
                Image(platformImage: logoImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .task(id: email.senderEmailAddress) {
            await loadLogoIfNeeded()
        }
    }

    private var fallback: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [seedColor.opacity(0.95), seedColor.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.system(size: max(11, size * 0.34), weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    private func loadLogoIfNeeded() async {
        guard logoImage == nil, !isLoadingLogo else { return }
        isLoadingLogo = true
        defer { isLoadingLogo = false }

        for url in email.senderLogoURLs {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 4
                request.cachePolicy = .returnCacheDataElseLoad

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      data.count > 100,
                      let image = PlatformImage(data: data) else {
                    continue
                }

                logoImage = image
                return
            } catch {
                continue
            }
        }
    }
}

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#endif

// MARK: - Bottom Action Bar

private struct BottomActionBar: View {
    let onMail: () -> Void
    let onCompose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            BarIconButton(systemName: "envelope.fill", isActive: true, action: onMail)
            Spacer()
            ComposeButton(action: onCompose)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 10)
        )
    }
}

private struct BarIconButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isActive ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct ComposeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                Text("Compose")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.Gradients.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command])
    }
}

// MARK: - Helpers

private extension Email {
    var displayName: String {
        if let start = sender.firstIndex(of: "<") {
            return sender[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sender
    }
}

private extension SessionStore {
    /// First-name display for the greeting. Derived from the user email since we don't track a profile yet.
    var displayName: String {
        guard let email = userEmail, let local = email.split(separator: "@").first else {
            return "there"
        }
        let cleaned = local.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let first = cleaned.split(separator: " ").first.map(String.init) ?? cleaned
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
