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
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedEmail: Email?
    @State private var emails: [Email] = []
    @State private var accounts: [GmailAccount] = []
    @State private var selectedAccountId: String?
    @State private var selectedFolder: MailboxFolder = .inbox
    @State private var isPriorityMode = false
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingComposer = false
    @State private var isShowingBlockedSenders = false
    @State private var isShowingMutedSenders = false
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
    @State private var recipientSuggestions: [EmailContact] = []
    @State private var mailboxRequestID = UUID()

    private let apiClient = APIClient()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.Palette.background.ignoresSafeArea()

                // Faint warm wash at the masthead corner — barely perceptible.
                Theme.Gradients.ambient
                    .ignoresSafeArea()
                    .opacity(0.85)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AuroraHeader(
                            unreadCount: unreadCount,
                            onOpenSettings: { isShowingSettings = true },
                            onAddAccount: { Task { await session.signInWithGoogle() } }
                        )
                            .pageGutter()
                            .padding(.top, 14)
                            .padding(.bottom, 14)

                        Rectangle()
                            .fill(Theme.Palette.borderStrong)
                            .frame(height: 1)

                        GreetingBlock(
                            name: session.displayName,
                            unreadCount: unreadCount,
                            messageCount: emails.count,
                            selectedFolder: selectedFolder,
                            isPriorityMode: isPriorityMode
                        )
                            .pageGutter()
                            .padding(.top, 26)
                            .padding(.bottom, 22)

                        AccountSearchBar(
                            accounts: accounts,
                            selectedAccountId: $selectedAccountId,
                            selectedFolder: $selectedFolder,
                            isPriorityMode: $isPriorityMode,
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
                            onManageMutedSenders: {
                                isShowingMutedSenders = true
                            },
                            onOpenSettings: {
                                isShowingSettings = true
                            }
                        )
                        .pageGutter()
                        .padding(.bottom, 14)

                        Rectangle()
                            .fill(Theme.Palette.border)
                            .frame(height: 0.5)
                            .padding(.bottom, 4)

                        EmailListSection(
                            emails: emails,
                            isPriorityMode: isPriorityMode,
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
                            onEmailAction: { action, email in
                                Task { await performSingleAction(action, email: email) }
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
                        .pageGutter()

                        Color.clear.frame(height: 96)
                    }
                }
                .scrollIndicators(.hidden)

                BottomActionBar(
                    folderTitle: selectedFolder.title,
                    unreadCount: unreadCount,
                    onMail: { /* already in mail */ },
                    onCompose: { isShowingComposer = true }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                #if os(macOS)
                if isShowingComposer {
                    ComposerView(
                        mode: .compose,
                        accountId: selectedAccountId,
                        accounts: accounts,
                        recipientSuggestions: recipientSuggestions,
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
                        recipientSuggestions: recipientSuggestions,
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
                #endif
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
                EmailDetailView(
                    email: email,
                    accountId: selectedAccountId ?? email.accountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions
                ) { blockedSender in
                    emails.removeAll {
                        $0.senderEmailAddress.caseInsensitiveCompare(blockedSender) == .orderedSame
                    }
                } onPrioritySenderChanged: { senderEmail, isImportant in
                    updatePrioritySender(senderEmail: senderEmail, isImportant: isImportant)
                } onMutedSenderChanged: { senderEmail, isMuted in
                    updateMutedSender(senderEmail: senderEmail, isMuted: isMuted)
                }
            }
            .task {
                await NotificationManager.shared.requestAuthorization()
                await loadAccounts()
                await processDueScheduledEmails()
                await loadEmails()
                await refreshSyncStatus()
                await startRealtimeSync()
                startAutoRefresh()
                startMorningBriefPolling()
                openPendingMorningBriefIfNeeded()
                openPendingNotificationEmailIfNeeded()
            }
            .onChange(of: selectedAccountId) {
                resetMailboxState()
                let requestID = mailboxRequestID
                Task {
                    await loadEmails(requestID: requestID)
                    await startRealtimeSync()
                }
            }
            .onChange(of: selectedFolder) {
                resetMailboxState()
                let requestID = mailboxRequestID
                Task {
                    await loadEmails(requestID: requestID)
                }
            }
            .onChange(of: isPriorityMode) {
                resetMailboxState()
                let requestID = mailboxRequestID
                Task {
                    await loadEmails(requestID: requestID)
                }
            }
            .onChange(of: searchText) {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if Task.isCancelled { return }
                    resetMailboxState(clearEmails: false)
                    let requestID = mailboxRequestID
                    await loadEmails(requestID: requestID)
                }
            }
            .onChange(of: session.pendingAuthURL) {
                guard let url = session.pendingAuthURL else { return }
                openURL(url)
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await processDueScheduledEmails()
                    await refreshSyncStatus()
                    await loadEmails(notifyForNewEmails: false)
                    openPendingNotificationEmailIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMorningBrief)) { _ in
                isShowingMorningBrief = true
                UserDefaults.standard.removeObject(forKey: "pendingMorningBriefId")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openEmailFromNotification)) { _ in
                openPendingNotificationEmailIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .emailSyncNeeded)) { _ in
                Task {
                    await refreshSyncStatus()
                    await loadEmails(notifyForNewEmails: false)
                }
            }
            .onDisappear {
                autoRefreshTask?.cancel()
                morningBriefTask?.cancel()
                searchTask?.cancel()
            }
            .sheet(isPresented: $isShowingBlockedSenders) {
                BlockedSendersView(accountId: selectedAccountId)
                    .iosSheetPresentation()
            }
            .sheet(isPresented: $isShowingMutedSenders) {
                MutedSendersView(accountId: selectedAccountId)
                    .iosSheetPresentation()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(accounts: accounts) {
                    Task {
                        await loadAccounts()
                        await loadEmails()
                    }
                }
                .iosSheetPresentation()
            }
            .sheet(isPresented: $isShowingMorningBrief) {
                MorningBriefDetailView()
                    .iosSheetPresentation()
            }
            #if os(iOS)
            .sheet(isPresented: $isShowingComposer) {
                ComposerView(
                    mode: .compose,
                    accountId: selectedAccountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions,
                    onSent: {
                        Task { await loadEmails() }
                    },
                    onClose: {
                        isShowingComposer = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $draftToEdit) { draft in
                ComposerView(
                    mode: .draft(draft),
                    accountId: selectedAccountId ?? draft.accountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions,
                    onSent: {
                        Task { await loadEmails() }
                    },
                    onClose: {
                        draftToEdit = nil
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            #endif
            .refreshable {
                nextPageToken = nil
                await loadEmails(notifyForNewEmails: false)
            }
        }
        .tint(Theme.Palette.accent)
    }

    private var unreadCount: Int { emails.filter { !$0.isRead }.count }

    private func resetMailboxState(clearEmails: Bool = true) {
        mailboxRequestID = UUID()
        selectedEmail = nil
        knownEmailIds.removeAll()
        selectedEmailIds.removeAll()
        isSelectionMode = false
        hasLoadedInitialEmails = false
        nextPageToken = nil
        if clearEmails {
            emails = []
        }
    }

    private func loadAccounts() async {
        do {
            accounts = try await apiClient.accounts()
            if let selectedAccountId, !accounts.contains(where: { $0.id == selectedAccountId }) {
                self.selectedAccountId = nil
            }
            mergeRecipientSuggestions(from: [])
            errorMessage = nil
        } catch {
            errorMessage = "Could not load accounts."
        }
    }

    private func loadEmails(notifyForNewEmails: Bool = true, requestID: UUID? = nil) async {
        let activeRequestID = requestID ?? mailboxRequestID
        isLoading = true
        defer {
            if activeRequestID == mailboxRequestID {
                isLoading = false
            }
        }

        do {
            let page = try await apiClient.emails(
                accountId: selectedAccountId,
                searchQuery: searchText,
                folder: selectedFolder,
                priorityOnly: isPriorityMode
            )
            let fetchedEmails = page.emails
            guard activeRequestID == mailboxRequestID else { return }
            let fetchedIds = Set(fetchedEmails.map(\.id))
            mergeRecipientSuggestions(from: fetchedEmails)

            if shouldNotifyForNewEmails(notifyForNewEmails: notifyForNewEmails) {
                let watermark = notificationWatermark()
                let newEmails = fetchedEmails
                    .filter { !knownEmailIds.contains($0.id) }
                    .filter { $0.isMutedSender != true }
                    .filter { email in
                        guard let watermark else { return false }
                        return email.receivedAt > watermark
                    }
                    .prefix(3)

                for email in newEmails {
                    await NotificationManager.shared.notifyNewEmail(email)
                }
            }

            emails = fetchedEmails
            nextPageToken = page.nextPageToken
            knownEmailIds = fetchedIds
            updateNotificationWatermark(with: fetchedEmails)
            await updateBadgeCount()
            selectedEmailIds.removeAll()
            isSelectionMode = false
            hasLoadedInitialEmails = true
            errorMessage = nil
        } catch {
            if activeRequestID == mailboxRequestID {
                errorMessage = "Could not load inbox."
            }
        }
    }

    private func loadMoreEmails() async {
        guard let nextPageToken, !isLoadingMore, !isLoading else { return }
        let activeRequestID = mailboxRequestID
        isLoadingMore = true
        defer {
            if activeRequestID == mailboxRequestID {
                isLoadingMore = false
            }
        }

        do {
            let page = try await apiClient.emails(
                accountId: selectedAccountId,
                searchQuery: searchText,
                folder: selectedFolder,
                pageToken: nextPageToken,
                priorityOnly: isPriorityMode
            )
            guard activeRequestID == mailboxRequestID else { return }
            mergeRecipientSuggestions(from: page.emails)
            emails.append(contentsOf: page.emails.filter { newEmail in
                !emails.contains(where: { $0.id == newEmail.id })
            })
            emails = sortMailboxEmails(emails)
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

    private var notificationWatermarkKey: String {
        "lastInboxNotificationWatermark-\(selectedAccountId ?? "all")"
    }

    private func notificationWatermark() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: notificationWatermarkKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private func updateNotificationWatermark(with loadedEmails: [Email]) {
        guard selectedFolder == .inbox,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let newest = loadedEmails.map(\.receivedAt).max()
        else { return }

        let current = notificationWatermark()
        if current == nil || newest > current! {
            UserDefaults.standard.set(newest.timeIntervalSince1970, forKey: notificationWatermarkKey)
        }
    }

    private func mergeRecipientSuggestions(from emails: [Email]) {
        recipientSuggestions = EmailContact.contacts(
            from: emails,
            accounts: accounts
        ) + recipientSuggestions

        recipientSuggestions = EmailContact.deduped(recipientSuggestions)
    }

    private func updatePrioritySender(senderEmail: String, isImportant: Bool) {
        let normalizedSender = senderEmail.lowercased()
        emails = emails
            .map { email in
                var updated = email
                if email.senderEmailAddress.lowercased() == normalizedSender {
                    updated.priorityStatus = isImportant ? .important : .normal
                    updated.prioritySource = isImportant ? .manualSender : nil
                    updated.priorityReason = isImportant ? "Important sender" : nil
                }
                return updated
            }

        if isPriorityMode && !isImportant {
            emails.removeAll { $0.senderEmailAddress.lowercased() == normalizedSender }
        } else if !isPriorityMode {
            emails = sortMailboxEmails(emails)
        } else {
            emails.sort { left, right in
                let leftScore = prioritySortScore(left)
                let rightScore = prioritySortScore(right)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return left.receivedAt > right.receivedAt
            }
        }
    }

    private func updateMutedSender(senderEmail: String, isMuted: Bool) {
        let normalizedSender = senderEmail.lowercased()
        emails = emails.map { email in
            var updated = email
            if email.senderEmailAddress.lowercased() == normalizedSender {
                updated.isMutedSender = isMuted
            }
            return updated
        }
    }

    private func prioritySortScore(_ email: Email) -> Int {
        guard email.isPriority else { return 0 }
        return email.isManualPrioritySender ? 3 : 2
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

    private func performSingleAction(_ action: BulkEmailAction, email: Email) async {
        guard !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }

        do {
            try await perform(action, email: email)
            applyBulkAction(action, to: [email.id])
            errorMessage = nil
        } catch {
            errorMessage = "Could not update email."
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
        case .pin:
            try await apiClient.pinEmail(id: email.id, accountId: email.accountId)
        case .unpin:
            try await apiClient.unpinEmail(id: email.id, accountId: email.accountId)
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
        case .pin:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isPinned = true
            }
            emails = sortMailboxEmails(emails)
        case .unpin:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isPinned = false
            }
            emails = sortMailboxEmails(emails)
        }
    }

    private func sortMailboxEmails(_ emails: [Email]) -> [Email] {
        emails.sorted {
            if ($0.isPinned == true) != ($1.isPinned == true) {
                return $0.isPinned == true
            }
            if selectedFolder == .inbox && $0.isManualPrioritySender != $1.isManualPrioritySender {
                return $0.isManualPrioritySender
            }
            return $0.receivedAt > $1.receivedAt
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
                await processDueScheduledEmails()
            guard selectedFolder == .inbox,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !isLoading,
                  !isLoadingMore,
                  !isSelectionMode
                else { continue }
                await refreshSyncStatus()
                await loadEmails(notifyForNewEmails: false)
            }
        }
    }

    private func processDueScheduledEmails() async {
        do {
            try await apiClient.processDueScheduledEmails()
        } catch {
            // Scheduled send processing should not block inbox refresh.
        }
    }

    private func refreshSyncStatus() async {
        do {
            let status = try await apiClient.syncStatus()
            await NotificationManager.shared.setBadgeCount(status.unreadInboxCount)
        } catch {
            // Badge refresh should not block inbox usage.
        }
    }

    private func updateBadgeCount() async {
        guard selectedAccountId == nil,
              selectedFolder == .inbox,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            await refreshSyncStatus()
            return
        }

        await NotificationManager.shared.setBadgeCount(emails.filter { !$0.isRead }.count)
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

    private func openPendingNotificationEmailIfNeeded() {
        guard let emailId = UserDefaults.standard.string(forKey: "pendingNotificationEmailId") else { return }
        let accountId = UserDefaults.standard.string(forKey: "pendingNotificationAccountId")

        UserDefaults.standard.removeObject(forKey: "pendingNotificationEmailId")
        UserDefaults.standard.removeObject(forKey: "pendingNotificationAccountId")

        Task {
            await openEmailFromNotification(emailId: emailId, accountId: accountId)
        }
    }

    private func openEmailFromNotification(emailId: String, accountId: String?) async {
        do {
            if let accountId, !accountId.isEmpty {
                selectedAccountId = accountId
            }
            if selectedFolder != .inbox {
                selectedFolder = .inbox
            }

            let email = try await apiClient.email(id: emailId, accountId: accountId)
            selectedEmail = email

            if !emails.contains(where: { $0.id == email.id }) {
                emails.insert(email, at: 0)
                emails.sort { $0.receivedAt > $1.receivedAt }
            }
        } catch {
            errorMessage = "Could not open that email."
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
        .adaptiveSheetFrame(minWidth: 640, minHeight: 620)
        .background(Theme.Palette.background)
        .task {
            await loadBrief()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.Gradients.aurora)
                    .frame(width: 44, height: 44)
                    .blur(radius: 14)
                    .opacity(0.55)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Gradients.aurora)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Morning Brief")
                    .font(.system(size: 26, weight: .semibold))
                    .kerning(-0.4)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(brief?.windowText ?? "Unread emails from your overnight window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(AuroraIconButtonStyle(size: 34))
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Theme.Palette.background)
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
    @Binding var isPriorityMode: Bool
    @Binding var searchText: String
    let onAddAccount: () -> Void
    let onRefreshAccounts: () -> Void
    let onManageBlockedSenders: () -> Void
    let onManageMutedSenders: () -> Void
    let onOpenSettings: () -> Void

    private var selectedAccount: GmailAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Underline-style folder rail. Text only, hairline divider beneath.
            ScrollView(.horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    PriorityRailItem(isOn: isPriorityMode) {
                        withAnimation(Theme.Motion.snappy) { isPriorityMode.toggle() }
                    }

                    ForEach(MailboxFolder.allCases) { folder in
                        FolderRailItem(
                            title: folder.title,
                            isActive: !isPriorityMode && selectedFolder == folder
                        ) {
                            withAnimation(Theme.Motion.snappy) {
                                if isPriorityMode { isPriorityMode = false }
                                selectedFolder = folder
                            }
                        }
                    }

                    Spacer(minLength: 12)
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(height: 0.5)
            }

            // Search line + account picker — flat bordered field, no rounded pill.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)

                TextField("Filter \(selectedFolder.title.lowercased())", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(width: 0.5, height: 18)
                    .padding(.horizontal, 4)

                Menu {
                    Button {
                        selectedAccountId = nil
                    } label: {
                        Label("All Inboxes", systemImage: selectedAccountId == nil ? "checkmark" : "tray")
                    }

                    if !accounts.isEmpty { Divider() }

                    ForEach(accounts) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            Label(account.email, systemImage: selectedAccountId == account.id ? "checkmark" : "envelope")
                        }
                    }

                    Divider()

                    Button(action: onAddAccount) {
                        Label("Add Account", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(accountLabel.uppercased())
                            .font(Theme.Typography.mono(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Menu {
                    Button(action: onRefreshAccounts) {
                        Label("Refresh Mail", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button(action: onManageBlockedSenders) {
                        Label("Blocked Senders", systemImage: "hand.raised")
                    }
                    Button(action: onManageMutedSenders) {
                        Label("Muted Senders", systemImage: "bell.slash")
                    }
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
        }
    }

    private var accountLabel: String {
        if let selectedAccount {
            return selectedAccount.email.split(separator: "@").first.map(String.init) ?? selectedAccount.email
        }
        return "All inboxes"
    }
}

private struct FolderRailItem: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: isActive ? .black : .semibold))
                    .tracking(1.8)
                    .foregroundStyle(isActive ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)

                Rectangle()
                    .fill(isActive ? Theme.Palette.accent : Color.clear)
                    .frame(height: 1.5)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

private struct PriorityRailItem: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "asterisk")
                        .font(.system(size: 9, weight: .black))
                    Text("Priority".uppercased())
                        .font(.system(size: 11, weight: isOn ? .black : .semibold))
                        .tracking(1.8)
                }
                .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textTertiary)

                Rectangle()
                    .fill(isOn ? Theme.Palette.accent : Color.clear)
                    .frame(height: 1.5)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
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

private extension View {
    @ViewBuilder
    func iosSheetPresentation() -> some View {
        #if os(iOS)
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    @ViewBuilder
    func adaptiveSheetFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self.frame(minWidth: minWidth, minHeight: minHeight)
        #endif
    }
}

// MARK: - Masthead

private struct AuroraHeader: View {
    let unreadCount: Int
    let onOpenSettings: () -> Void
    let onAddAccount: () -> Void

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d · yyyy"
        return formatter.string(from: .now).uppercased()
    }

    private var volumeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "VOL. \(formatter.string(from: .now))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Editorial wordmark — small ink square + serif name in two lines.
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.Palette.textPrimary)
                        .frame(width: 28, height: 28)
                    Text("CM")
                        .font(.system(size: 10, weight: .black, design: .serif))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.background)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("ClarityMail")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(volumeLabel)
                        .font(Theme.Typography.mono(9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            Spacer()

            Text(todayLabel)
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.textSecondary)

            HStack(spacing: 8) {
                Button(action: onAddAccount) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AuroraIconButtonStyle(size: 30))

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(AuroraIconButtonStyle(size: 30))
            }
        }
    }
}

// MARK: - Editorial hero

private struct GreetingBlock: View {
    let name: String
    let unreadCount: Int
    let messageCount: Int
    let selectedFolder: MailboxFolder
    let isPriorityMode: Bool

    private var headline: String {
        if isPriorityMode { return "Priority" }
        switch selectedFolder {
        case .inbox:   return "Inbox"
        case .sent:    return "Sent"
        case .drafts:  return "Drafts"
        case .archive: return "Archive"
        case .trash:   return "Trash"
        }
    }

    private var byline: String {
        let metric: String
        if isPriorityMode {
            metric = "\(messageCount) priority \(messageCount == 1 ? "thread" : "threads")"
        } else if selectedFolder == .inbox {
            metric = unreadCount == 0
                ? "All caught up"
                : "\(unreadCount) unread of \(messageCount)"
        } else {
            metric = "\(messageCount) \(messageCount == 1 ? "item" : "items")"
        }
        return "\(metric) · @\(name.lowercased())"
    }

    private var sectionLabel: String {
        if isPriorityMode { return "Section A — flagged" }
        switch selectedFolder {
        case .inbox:   return "Section A — incoming"
        case .sent:    return "Section B — outgoing"
        case .drafts:  return "Section C — pending"
        case .archive: return "Section D — filed"
        case .trash:   return "Section E — discarded"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowLabel(text: sectionLabel, trailing: nil, accent: Theme.Palette.accent)

            Text(headline)
                .font(Theme.Typography.display(58))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(byline.uppercased())
                .font(Theme.Typography.mono(11, weight: .semibold))
                .tracking(1.6)
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
    case pin
    case unpin

    var title: String {
        switch self {
        case .archive: return "Archive"
        case .trash: return "Trash"
        case .markRead: return "Read"
        case .markUnread: return "Unread"
        case .star: return "Star"
        case .unstar: return "Unstar"
        case .pin: return "Pin"
        case .unpin: return "Unpin"
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
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        }
    }
}

private struct EmailListSection: View {
    let emails: [Email]
    let isPriorityMode: Bool
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
    let onEmailAction: (BulkEmailAction, Email) -> Void
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
                LazyVStack(spacing: 0) {
                    ForEach(emails) { email in
                        SwipeableEmailRow(
                            isEnabled: !isSelectionMode,
                            leadingActions: leadingSwipeActions(for: email),
                            trailingActions: trailingSwipeActions(for: email),
                            onTap: {
                                if isSelectionMode {
                                    onToggleSelection(email)
                                } else {
                                    onSelect(email)
                                }
                            }
                        ) {
                            EmailRowView(
                                email: email,
                                showPriorityLabel: isPriorityMode || email.isManualPrioritySender,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedEmailIds.contains(email.id),
                                onToggleSelection: {
                                    onToggleSelection(email)
                                }
                            )
                        }
                        .contextMenu {
                            Button {
                                onToggleSelection(email)
                            } label: {
                                Label(selectedEmailIds.contains(email.id) ? "Deselect" : "Select", systemImage: "checkmark.circle")
                            }
                            Button {
                                onEmailAction(email.isPinned == true ? .unpin : .pin, email)
                            } label: {
                                Label(email.isPinned == true ? "Unpin" : "Pin", systemImage: email.isPinned == true ? "pin.slash" : "pin")
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
                        Button {
                            onBulkAction(.pin)
                        } label: {
                            Label("Pin", systemImage: "pin")
                        }
                        Button {
                            onBulkAction(.unpin)
                        } label: {
                            Label("Unpin", systemImage: "pin.slash")
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

    private func leadingSwipeActions(for email: Email) -> [RowSwipeAction] {
        guard selectedFolder != .drafts else { return [] }

        return [
            RowSwipeAction(
                id: email.isPinned == true ? "unpin" : "pin",
                title: email.isPinned == true ? "Unpin" : "Pin",
                systemImage: email.isPinned == true ? "pin.slash" : "pin",
                tint: Theme.Palette.warm,
                action: { onEmailAction(email.isPinned == true ? .unpin : .pin, email) }
            ),
            RowSwipeAction(
                id: email.isRead ? "unread" : "read",
                title: email.isRead ? "Unread" : "Read",
                systemImage: email.isRead ? "envelope.badge" : "envelope.open",
                tint: Theme.Palette.accent,
                action: { onEmailAction(email.isRead ? .markUnread : .markRead, email) }
            )
        ]
    }

    private func trailingSwipeActions(for email: Email) -> [RowSwipeAction] {
        var actions: [RowSwipeAction] = []

        if selectedFolder != .drafts && selectedFolder != .sent {
            actions.append(
                RowSwipeAction(
                    id: "archive",
                    title: "Archive",
                    systemImage: "archivebox",
                    tint: .blue,
                    action: { onEmailAction(.archive, email) }
                )
            )
        }

        actions.append(
            RowSwipeAction(
                id: "trash",
                title: email.draftId == nil ? "Trash" : "Delete",
                systemImage: "trash",
                tint: .red,
                action: { onEmailAction(.trash, email) }
            )
        )

        return actions
    }
}

private struct BulkActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(
                Capsule().fill(Theme.Palette.surface)
            )
            .overlay(
                Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

private struct RowSwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
}

private struct SwipeableEmailRow<Content: View>: View {
    let isEnabled: Bool
    let leadingActions: [RowSwipeAction]
    let trailingActions: [RowSwipeAction]
    let onTap: () -> Void
    private let content: () -> Content

    @State private var settledOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 78
    private let revealThreshold: CGFloat = 54
    private let fullSwipeThreshold: CGFloat = 132

    init(
        isEnabled: Bool,
        leadingActions: [RowSwipeAction],
        trailingActions: [RowSwipeAction],
        onTap: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isEnabled = isEnabled
        self.leadingActions = leadingActions
        self.trailingActions = trailingActions
        self.onTap = onTap
        self.content = content
    }

    private var maxLeadingOffset: CGFloat {
        CGFloat(leadingActions.count) * actionWidth
    }

    private var maxTrailingOffset: CGFloat {
        CGFloat(trailingActions.count) * actionWidth
    }

    private var currentOffset: CGFloat {
        clamped(settledOffset + dragOffset)
    }

    var body: some View {
        ZStack {
            swipeBackground
                .opacity(abs(currentOffset) > 1 ? 1 : 0)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: isEnabled ? currentOffset : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    if abs(settledOffset) > 1 {
                        close()
                    } else {
                        onTap()
                    }
                }
                .simultaneousGesture(rowDragGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .animation(.snappy(duration: 0.18), value: settledOffset)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                close()
            }
        }
    }

    private var swipeBackground: some View {
        HStack(spacing: 0) {
            if currentOffset > 1 {
                ForEach(leadingActions) { actionButton($0) }
                Spacer(minLength: 0)
            } else if currentOffset < -1 {
                Spacer(minLength: 0)
                ForEach(trailingActions.reversed()) { actionButton($0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.surfaceMuted)
    }

    private func actionButton(_ swipeAction: RowSwipeAction) -> some View {
        Button {
            swipeAction.action()
            close()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: swipeAction.systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(swipeAction.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(swipeAction.tint.opacity(0.92))
        }
        .buttonStyle(.plain)
    }

    private var rowDragGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard isEnabled, isHorizontalDrag(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isEnabled, isHorizontalDrag(value) else { return }

                let proposedOffset = clamped(settledOffset + value.translation.width)

                if proposedOffset > fullSwipeThreshold, let action = leadingActions.first {
                    action.action()
                    close()
                } else if proposedOffset < -fullSwipeThreshold, let action = trailingActions.first {
                    action.action()
                    close()
                } else if proposedOffset > revealThreshold, !leadingActions.isEmpty {
                    settledOffset = maxLeadingOffset
                } else if proposedOffset < -revealThreshold, !trailingActions.isEmpty {
                    settledOffset = -maxTrailingOffset
                } else {
                    close()
                }
            }
    }

    private func isHorizontalDrag(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > max(24, abs(value.translation.height) * 1.35)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, -maxTrailingOffset), maxLeadingOffset)
    }

    private func close() {
        withAnimation(.snappy(duration: 0.18)) {
            settledOffset = 0
        }
    }
}

private struct SearchLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.Palette.border, lineWidth: 1)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(
                        Theme.Gradients.aurora,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .modifier(SpinForeverModifier())
            }

            Text("Searching")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

private struct SpinForeverModifier: ViewModifier {
    @State private var spin = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

private struct EmailRowView: View {
    let email: Email
    var showPriorityLabel = false
    var isSelectionMode = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    private var isUnread: Bool { !email.isRead }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread/selection indicator — single saffron dot or bullet.
            ZStack {
                if isSelectionMode {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            isSelected ? Theme.Palette.accent : Theme.Palette.borderStrong,
                            lineWidth: 1
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isSelected ? Theme.Palette.accent : Color.clear)
                        )
                        .frame(width: 11, height: 11)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                } else if isUnread {
                    Circle()
                        .fill(Theme.Palette.accent)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
            }
            .frame(width: 14, height: 16, alignment: .center)
            .padding(.top, 14)
            .onTapGesture {
                if isSelectionMode { onToggleSelection() }
            }

            SenderLogoView(email: email, size: 38)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(email.displayName)
                        .font(.system(size: 14, weight: isUnread ? .bold : .regular))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)

                    if email.isManualPrioritySender {
                        Text("STAR")
                            .font(Theme.Typography.mono(8, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                Rectangle().strokeBorder(Theme.Palette.accent, lineWidth: 0.75)
                            )
                    }

                    Spacer(minLength: 4)

                    Text(email.receivedAt.emailRowDateText.replacingOccurrences(of: "\n", with: " · ").uppercased())
                        .font(Theme.Typography.mono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(isUnread ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                        .lineLimit(1)
                }

                Text(email.subject)
                    .font(.system(size: 14.5, weight: isUnread ? .semibold : .regular, design: .serif))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Text(email.snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)

                if email.isPinned == true || (email.isPriority && showPriorityLabel) {
                    HStack(spacing: 8) {
                        if email.isPinned == true {
                            EmailRowChip(
                                title: "Pinned",
                                systemImage: nil,
                                color: Theme.Palette.warm
                            )
                        }
                        if email.isPriority && showPriorityLabel {
                            EmailRowChip(
                                title: email.priorityReason?.isEmpty == false ? email.priorityReason! : "Priority",
                                systemImage: nil,
                                color: Theme.Palette.accent
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            onToggleSelection()
        }
    }

    private var rowFill: Color {
        if isSelected { return Theme.Palette.accent.opacity(0.06) }
        if email.isManualPrioritySender { return Theme.Palette.accent.opacity(0.04) }
        return Color.clear
    }
}

private struct EmailRowChip: View {
    let title: String
    let systemImage: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .black))
            }
            Text(title.uppercased())
                .lineLimit(1)
        }
        .font(Theme.Typography.mono(9, weight: .heavy))
        .tracking(1.2)
        .foregroundStyle(color)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .overlay(
            Rectangle().strokeBorder(color.opacity(0.65), lineWidth: 0.75)
        )
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
            Color(red: 0.180, green: 0.369, blue: 0.310),  // pine
            Color(red: 0.545, green: 0.122, blue: 0.059),  // oxblood
            Color(red: 0.078, green: 0.067, blue: 0.059),  // ink
            Color(red: 0.420, green: 0.349, blue: 0.227),  // umber
            Color(red: 0.292, green: 0.220, blue: 0.180)   // walnut
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
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 0.75)
        )
        .task(id: email.senderEmailAddress) {
            await loadLogoIfNeeded()
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(seedColor)
            .overlay(
                Text(initials)
                    .font(.system(size: max(11, size * 0.36), weight: .bold, design: .serif))
                    .foregroundStyle(Theme.Palette.background)
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

// MARK: - Bottom Action Bar (editorial footer)

private struct BottomActionBar: View {
    let folderTitle: String
    let unreadCount: Int
    let onMail: () -> Void
    let onCompose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.borderStrong)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                Button(action: onMail) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Theme.Palette.accent)
                            .frame(width: 14, height: 1.5)
                        Text(folderTitle.uppercased())
                            .font(Theme.Typography.mono(11, weight: .heavy))
                            .tracking(2.0)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .buttonStyle(.plain)

                if unreadCount > 0 {
                    Text("·")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text("\(unreadCount) UNREAD")
                        .font(Theme.Typography.mono(10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer()

                ComposeButton(action: onCompose)
            }
            .padding(.horizontal, Theme.Layout.gutter)
            .padding(.vertical, 12)
            .background(Theme.Palette.background.opacity(0.97))
        }
    }
}

private struct ComposeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Compose")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(0.5)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(Theme.Palette.background)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.textPrimary)
            )
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
