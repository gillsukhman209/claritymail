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
    @State private var isShowingHiddenSenders = false
    @State private var isShowingSettings = false
    @State private var isShowingMorningBrief = false
    @State private var draftToEdit: Email?
    @State private var sendAgainEmail: Email?
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
    @State private var mailboxCache: [MailboxCacheKey: EmailPage] = [:]
    @State private var hasPrefetchedMailboxes = false
#if os(iOS)
    @State private var authBrowserItem: AuthBrowserItem?
#endif

    private let apiClient = APIClient()
    private let cacheLimit = 50

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.Palette.background.ignoresSafeArea()

                // Faint warm wash at the masthead corner — barely perceptible.
                Theme.Gradients.ambient
                    .ignoresSafeArea()
                    .opacity(0.85)

                List {
                    headerSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.warm)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 14, leading: Theme.Layout.gutter, bottom: 0, trailing: Theme.Layout.gutter))
                    }

                    if !emails.isEmpty {
                        selectionToolbar
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 10, leading: Theme.Layout.gutter, bottom: 6, trailing: Theme.Layout.gutter))
                    }

                    if isSearchLoading {
                        SearchLoadingView()
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 240)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 12, leading: Theme.Layout.gutter, bottom: 0, trailing: Theme.Layout.gutter))
                    } else if isLoading && emails.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(emails) { email in
                            emailRow(for: email)
                        }

                        if canLoadMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .onAppear { Task { await loadMoreEmails() } }
                        } else if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }

                    Color.clear
                        .frame(height: 96)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollIndicators(.hidden)

                BottomActionBar(
                    onCompose: { isShowingComposer = true }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                #if os(macOS)
                ZStack(alignment: .bottomTrailing) {
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

                    if let sendAgainEmail {
                        ComposerView(
                            mode: .sendAgain(sendAgainEmail),
                            accountId: selectedAccountId ?? sendAgainEmail.accountId,
                            accounts: accounts,
                            recipientSuggestions: recipientSuggestions,
                            onSent: {
                                Task { await loadEmails() }
                            },
                            onClose: {
                                self.sendAgainEmail = nil
                            }
                        )
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: isShowingComposer)
                .animation(.easeOut(duration: 0.18), value: draftToEdit)
                .animation(.easeOut(duration: 0.18), value: sendAgainEmail)
                #endif
            }
            .overlay(alignment: .bottom) {
                UndoSendToast()
                    .padding(.bottom, 88)
                    .zIndex(30)
            }
            .modifier(HideNavigationBarModifier())
            .navigationDestination(item: $selectedEmail) { email in
                EmailDetailView(
                    email: email,
                    accountId: selectedAccountId ?? email.accountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions
                ) { blockedSender in
                    updateBlockedSender(senderEmail: blockedSender, isBlocked: true)
                } onPrioritySenderChanged: { senderEmail, isImportant in
                    updatePrioritySender(senderEmail: senderEmail, isImportant: isImportant)
                } onMutedSenderChanged: { senderEmail, isMuted in
                    updateMutedSender(senderEmail: senderEmail, isMuted: isMuted)
                } onHiddenSenderChanged: { senderEmail, isHidden in
                    updateHiddenSender(senderEmail: senderEmail, isHidden: isHidden)
                } onReadStateChanged: { id, isRead in
                    updateEmailReadState(id: id, isRead: isRead)
                }
            }
            .task {
                await NotificationManager.shared.requestAuthorization()
                restoreCachedMailbox(for: currentCacheKey)
                openPendingMorningBriefIfNeeded()
                openPendingNotificationEmailIfNeeded()
                async let accountsTask: Void = loadAccounts()
                async let emailsTask: Void = loadEmails(notifyForNewEmails: false)
                _ = await (accountsTask, emailsTask)

                Task {
                    await processDueScheduledEmails()
                    await refreshSyncStatus()
                    await startRealtimeSync()
                    await prefetchCommonMailboxes()
                }
                startAutoRefresh()
                startMorningBriefPolling()
            }
            .onChange(of: selectedAccountId) {
                switchMailboxContext()
                let requestID = mailboxRequestID
                Task {
                    await loadEmails(requestID: requestID)
                    await startRealtimeSync()
                }
            }
            .onChange(of: selectedFolder) {
                switchMailboxContext()
                let requestID = mailboxRequestID
                Task {
                    await loadEmails(requestID: requestID)
                }
            }
            .onChange(of: isPriorityMode) {
                switchMailboxContext()
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
#if os(iOS)
                authBrowserItem = AuthBrowserItem(url: url)
                session.pendingAuthURL = nil
#else
                openURL(url)
#endif
            }
#if os(iOS)
            .sheet(item: $authBrowserItem, onDismiss: {
                Task {
                    await session.refreshAuthStatus()
                    await loadAccounts()
                    await loadEmails(notifyForNewEmails: false)
                }
            }) { item in
                AuthBrowserView(url: item.url)
                    .ignoresSafeArea()
            }
#endif
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    openPendingNotificationEmailIfNeeded()
                    await processDueScheduledEmails()
                    await refreshSyncStatus()
                    await loadEmails(notifyForNewEmails: false)
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
            .sheet(isPresented: $isShowingHiddenSenders) {
                HiddenSendersView(accountId: selectedAccountId) {
                    Task { await loadEmails() }
                }
                .iosSheetPresentation()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(accounts: accounts) {
                    isShowingSettings = false
                    Task { await session.signInWithGoogle() }
                } onAccountsChanged: {
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
            .sheet(item: $sendAgainEmail) { email in
                ComposerView(
                    mode: .sendAgain(email),
                    accountId: selectedAccountId ?? email.accountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions,
                    onSent: {
                        Task { await loadEmails() }
                    },
                    onClose: {
                        sendAgainEmail = nil
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

    private var canLoadMore: Bool { nextPageToken != nil }

    private var isSearchLoading: Bool {
        isLoading && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - List sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuroraHeader(
                unreadCount: unreadCount,
                onOpenSettings: { isShowingSettings = true }
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
                onManageHiddenSenders: {
                    isShowingHiddenSenders = true
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
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private func emailRow(for email: Email) -> some View {
        EmailRowView(
            email: email,
            showPriorityLabel: isPriorityMode || email.isManualPrioritySender,
            isSelectionMode: isSelectionMode,
            isSelected: selectedEmailIds.contains(email.id),
            onToggleSelection: { toggleSelection(email) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                toggleSelection(email)
            } else if selectedFolder == .drafts || email.draftId != nil {
                draftToEdit = email
            } else {
                selectedEmail = email
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Layout.gutter, bottom: 0, trailing: Theme.Layout.gutter))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if selectedFolder == .sent {
                Button {
                    Task { await prepareSendAgain(email) }
                } label: {
                    Label("Send Again", systemImage: "paperplane")
                }
                .tint(Theme.Palette.accent)
            }

            if selectedFolder != .drafts {
                Button {
                    Task { await performSingleAction(email.isPinned == true ? .unpin : .pin, email: email) }
                } label: {
                    Label(
                        email.isPinned == true ? "Unpin" : "Pin",
                        systemImage: email.isPinned == true ? "pin.slash" : "pin"
                    )
                }
                .tint(Theme.Palette.warm)

                Button {
                    Task { await performSingleAction(email.isRead ? .markUnread : .markRead, email: email) }
                } label: {
                    Label(
                        email.isRead ? "Unread" : "Read",
                        systemImage: email.isRead ? "envelope.badge" : "envelope.open"
                    )
                }
                .tint(Theme.Palette.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await performSingleAction(.trash, email: email) }
            } label: {
                Label(email.draftId == nil ? "Trash" : "Delete", systemImage: "trash")
            }

            if selectedFolder != .drafts && selectedFolder != .sent {
                Button {
                    Task { await performSingleAction(.archive, email: email) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(Theme.Palette.accentCyan)
            }
        }
        .contextMenu {
            Button {
                toggleSelection(email)
            } label: {
                Label(
                    selectedEmailIds.contains(email.id) ? "Deselect" : "Select",
                    systemImage: "checkmark.circle"
                )
            }
            if selectedFolder == .sent {
                Button {
                    Task { await prepareSendAgain(email) }
                } label: {
                    Label("Send Again", systemImage: "paperplane")
                }
            }
            Button {
                Task { await performSingleAction(email.isPinned == true ? .unpin : .pin, email: email) }
            } label: {
                Label(
                    email.isPinned == true ? "Unpin" : "Pin",
                    systemImage: email.isPinned == true ? "pin.slash" : "pin"
                )
            }
        }
    }

    private func prepareSendAgain(_ email: Email) async {
        do {
            let fullEmail = try await apiClient.email(id: email.id, accountId: email.accountId)
            sendAgainEmail = fullEmail
            errorMessage = nil
        } catch {
            errorMessage = "Could not prepare email."
        }
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    let next = !isSelectionMode
                    isSelectionMode = next
                    if !next { selectedEmailIds.removeAll() }
                } label: {
                    Label(isSelectionMode ? "Cancel" : "Select", systemImage: isSelectionMode ? "xmark" : "checkmark.circle")
                }
                .buttonStyle(BulkActionButtonStyle())

                if isSelectionMode {
                    Button {
                        selectedEmailIds = Set(emails.map(\.id))
                        isSelectionMode = true
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BulkActionButtonStyle())

                    if isPerformingBulkAction {
                        ProgressView()
                            .controlSize(.small)
                        Text("UPDATING")
                            .font(Theme.Typography.mono(10, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Menu {
                        if selectedFolder != .drafts && selectedFolder != .sent {
                            Button { Task { await performBulkAction(.archive) } } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }

                        Button(role: .destructive) { Task { await performBulkAction(.trash) } } label: {
                            Label(selectedFolder == .drafts ? "Delete Drafts" : "Move to Trash", systemImage: "trash")
                        }

                        if selectedFolder != .drafts {
                            Divider()
                            Button { Task { await performBulkAction(.markRead) } } label: {
                                Label("Mark as Read", systemImage: "envelope.open")
                            }
                            Button { Task { await performBulkAction(.markUnread) } } label: {
                                Label("Mark as Unread", systemImage: "envelope.badge")
                            }
                        }

                        Divider()
                        Button { Task { await performBulkAction(.star) } } label: {
                            Label("Star", systemImage: "star")
                        }
                        Button { Task { await performBulkAction(.unstar) } } label: {
                            Label("Unstar", systemImage: "star.slash")
                        }
                        Button { Task { await performBulkAction(.pin) } } label: {
                            Label("Pin", systemImage: "pin")
                        }
                        Button { Task { await performBulkAction(.unpin) } } label: {
                            Label("Unpin", systemImage: "pin.slash")
                        }

                        if selectedFolder != .drafts {
                            Divider()
                            Button(role: .destructive) { Task { await performBulkAction(.blockSender) } } label: {
                                Label("Block Senders", systemImage: "hand.raised")
                            }
                            Button { Task { await performBulkAction(.muteSender) } } label: {
                                Label("Mute Senders", systemImage: "bell.slash")
                            }
                            Button { Task { await performBulkAction(.hideSender) } } label: {
                                Label("Hide Senders", systemImage: "eye.slash")
                            }
                        }
                    } label: {
                        Label("Actions (\(selectedEmailIds.count))", systemImage: isPerformingBulkAction ? "hourglass" : "ellipsis.circle")
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 112, minHeight: 30)
                    }
                    .buttonStyle(BulkActionButtonStyle())
                    .disabled(selectedEmailIds.isEmpty || isPerformingBulkAction)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func bulkActionButton(_ action: BulkEmailAction) -> some View {
        Button {
            Task { await performBulkAction(action) }
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 30)
        }
        .buttonStyle(BulkActionButtonStyle())
        .disabled(selectedEmailIds.isEmpty || isPerformingBulkAction)
    }

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

    private func switchMailboxContext() {
        resetMailboxState()
        restoreCachedMailbox(for: currentCacheKey)
    }

    private var currentCacheKey: MailboxCacheKey {
        MailboxCacheKey(
            accountId: selectedAccountId,
            folder: selectedFolder,
            priorityOnly: isPriorityMode,
            searchQuery: searchText
        )
    }

    private func restoreCachedMailbox(for key: MailboxCacheKey) {
        guard let page = mailboxCache[key] ?? persistedMailboxPage(for: key) else { return }
        emails = sortMailboxEmails(page.emails)
        nextPageToken = page.nextPageToken
        knownEmailIds = Set(page.emails.map(\.id))
        hasLoadedInitialEmails = true
        mergeRecipientSuggestions(from: page.emails)
    }

    private func cacheMailboxPage(_ page: EmailPage, for key: MailboxCacheKey) {
        let limitedPage = EmailPage(
            emails: Array(sortMailboxEmails(page.emails).prefix(cacheLimit)),
            nextPageToken: page.nextPageToken
        )
        mailboxCache[key] = limitedPage

        guard key.isPersistable else { return }
        do {
            let data = try JSONEncoder().encode(limitedPage)
            UserDefaults.standard.set(data, forKey: key.persistedStorageKey)
        } catch {
            // Cache writes are best effort only.
        }
    }

    private func persistedMailboxPage(for key: MailboxCacheKey) -> EmailPage? {
        guard key.isPersistable,
              let data = UserDefaults.standard.data(forKey: key.persistedStorageKey)
        else { return nil }

        do {
            return try JSONDecoder().decode(EmailPage.self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: key.persistedStorageKey)
            return nil
        }
    }

    private func loadAccounts() async {
        do {
            accounts = try await apiClient.accounts()
            session.refreshFromAccounts(accounts)
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
        let cacheKey = currentCacheKey
        if emails.isEmpty {
            restoreCachedMailbox(for: cacheKey)
        }
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

            emails = fetchedEmails
            nextPageToken = page.nextPageToken
            cacheMailboxPage(page, for: cacheKey)
            knownEmailIds = fetchedIds
            updateNotificationWatermark(with: fetchedEmails)
            await updateBadgeCount()
            selectedEmailIds.removeAll()
            isSelectionMode = false
            hasLoadedInitialEmails = true
            errorMessage = nil
        } catch {
            if activeRequestID == mailboxRequestID {
                if emails.isEmpty {
                    errorMessage = "Could not load \(selectedFolder.title.lowercased())."
                }
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
            cacheMailboxPage(EmailPage(emails: emails, nextPageToken: page.nextPageToken), for: currentCacheKey)
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
                    let shouldPromote = isImportant && !email.isRead
                    updated.priorityStatus = shouldPromote ? .important : .normal
                    updated.prioritySource = shouldPromote ? .manualSender : nil
                    updated.priorityReason = shouldPromote ? "Important sender" : nil
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

    private func updateBlockedSender(senderEmail: String, isBlocked: Bool) {
        let normalizedSender = senderEmail.lowercased()
        emails = emails.map { email in
            var updated = email
            if email.senderEmailAddress.lowercased() == normalizedSender {
                updated.isBlockedSender = isBlocked
            }
            return updated
        }
    }

    private func updateHiddenSender(senderEmail: String, isHidden: Bool) {
        let normalizedSender = senderEmail.lowercased()

        if isHidden && selectedFolder != .hidden {
            emails.removeAll { $0.senderEmailAddress.lowercased() == normalizedSender }
            if selectedEmail?.senderEmailAddress.lowercased() == normalizedSender {
                selectedEmail = nil
            }
            return
        }

        emails = emails.map { email in
            var updated = email
            if email.senderEmailAddress.lowercased() == normalizedSender {
                updated.isHiddenSender = isHidden
            }
            return updated
        }
    }

    private func updateEmailReadState(id: Email.ID, isRead: Bool) {
        for index in emails.indices where emails[index].id == id {
            emails[index].isRead = isRead
            if isRead && emails[index].prioritySource == .manualSender {
                emails[index].priorityStatus = .normal
                emails[index].prioritySource = nil
                emails[index].priorityReason = nil
            }
        }

        if selectedEmail?.id == id {
            selectedEmail?.isRead = isRead
            if isRead && selectedEmail?.prioritySource == .manualSender {
                selectedEmail?.priorityStatus = .normal
                selectedEmail?.prioritySource = nil
                selectedEmail?.priorityReason = nil
            }
        }

        emails = sortMailboxEmails(emails)
    }

    private func prioritySortScore(_ email: Email) -> Int {
        guard email.isPriority else { return 0 }
        return email.isManualPrioritySender && !email.isRead ? 3 : 2
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
        let targetIds = Set(targets.map(\.id))
        let targetSenderEmails = Set(targets.map { $0.senderEmailAddress.lowercased() })

        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }

        do {
            if let requestAction = action.bulkRequestAction, !targets.contains(where: { $0.draftId != nil }) {
                let response = try await apiClient.bulkUpdateEmails(targets, action: requestAction)
                applyBulkAction(action, to: Set(response.updatedIds), senderEmails: targetSenderEmails)
                if !response.failed.isEmpty {
                    errorMessage = "\(response.updatedIds.count) updated, \(response.failed.count) failed."
                } else {
                    errorMessage = nil
                }
            } else if action.isSenderScopedAction {
                try await performSenderScopedBulkAction(action, targets: targets)
                applyBulkAction(action, to: targetIds, senderEmails: targetSenderEmails)
                errorMessage = nil
            } else {
                for email in targets {
                    try await perform(action, email: email)
                }
                applyBulkAction(action, to: targetIds, senderEmails: targetSenderEmails)
                errorMessage = nil
            }

            selectedEmailIds.removeAll()
            isSelectionMode = false
        } catch {
            errorMessage = "Could not update selected emails."
        }
    }

    private func performSenderScopedBulkAction(_ action: BulkEmailAction, targets: [Email]) async throws {
        var representativesBySender: [String: Email] = [:]
        for email in targets {
            let key = "\(email.accountId ?? ""):\(email.senderEmailAddress.lowercased())"
            if representativesBySender[key] == nil {
                representativesBySender[key] = email
            }
        }

        for email in representativesBySender.values {
            try await perform(action, email: email)
        }
    }

    private func performSingleAction(_ action: BulkEmailAction, email: Email) async {
        guard !isPerformingBulkAction else { return }
        isPerformingBulkAction = true
        defer { isPerformingBulkAction = false }
        let senderEmails = Set([email.senderEmailAddress.lowercased()])

        do {
            try await perform(action, email: email)
            applyBulkAction(action, to: [email.id], senderEmails: senderEmails)
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
        case .blockSender:
            guard let accountId = email.accountId else {
                _ = try await apiClient.blockSender(id: email.id, accountId: email.accountId)
                return
            }
            _ = try await apiClient.blockSender(
                senderEmail: email.senderEmailAddress,
                accountId: accountId,
                fallbackEmailId: email.id
            )
        case .muteSender:
            guard let accountId = email.accountId else {
                _ = try await apiClient.muteSender(id: email.id, accountId: email.accountId)
                return
            }
            _ = try await apiClient.muteSender(
                senderEmail: email.senderEmailAddress,
                accountId: accountId,
                fallbackEmailId: email.id
            )
        case .hideSender:
            guard let accountId = email.accountId else {
                _ = try await apiClient.hideSender(id: email.id, accountId: email.accountId)
                return
            }
            _ = try await apiClient.hideSender(
                senderEmail: email.senderEmailAddress,
                accountId: accountId,
                fallbackEmailId: email.id
            )
        }
    }

    private func applyBulkAction(_ action: BulkEmailAction, to ids: Set<Email.ID>, senderEmails: Set<String> = []) {
        switch action {
        case .trash, .archive:
            emails.removeAll { ids.contains($0.id) }
        case .markRead:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isRead = true
                if emails[index].prioritySource == .manualSender {
                    emails[index].priorityStatus = .normal
                    emails[index].prioritySource = nil
                    emails[index].priorityReason = nil
                }
            }
            emails = sortMailboxEmails(emails)
        case .markUnread:
            for index in emails.indices where ids.contains(emails[index].id) {
                emails[index].isRead = false
            }
            emails = sortMailboxEmails(emails)
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
        case .blockSender:
            for index in emails.indices where ids.contains(emails[index].id) || senderEmails.contains(emails[index].senderEmailAddress.lowercased()) {
                emails[index].isBlockedSender = true
            }
        case .muteSender:
            for index in emails.indices where ids.contains(emails[index].id) || senderEmails.contains(emails[index].senderEmailAddress.lowercased()) {
                emails[index].isMutedSender = true
            }
        case .hideSender:
            if selectedFolder == .hidden {
                for index in emails.indices where ids.contains(emails[index].id) || senderEmails.contains(emails[index].senderEmailAddress.lowercased()) {
                    emails[index].isHiddenSender = true
                }
            } else {
                emails.removeAll { ids.contains($0.id) || senderEmails.contains($0.senderEmailAddress.lowercased()) }
            }
        }
    }

    private func sortMailboxEmails(_ emails: [Email]) -> [Email] {
        emails.sorted {
            if ($0.isPinned == true) != ($1.isPinned == true) {
                return $0.isPinned == true
            }
            let leftUnreadManualSender = selectedFolder == .inbox && $0.isManualPrioritySender && !$0.isRead
            let rightUnreadManualSender = selectedFolder == .inbox && $1.isManualPrioritySender && !$1.isRead
            if leftUnreadManualSender != rightUnreadManualSender {
                return leftUnreadManualSender
            }
            return $0.receivedAt > $1.receivedAt
        }
    }

    private func prefetchCommonMailboxes() async {
        guard !hasPrefetchedMailboxes,
              selectedAccountId == nil,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        hasPrefetchedMailboxes = true
        let targets: [(MailboxFolder, Bool)] = [
            (.sent, false),
            (.drafts, false),
            (.archive, false),
            (.trash, false),
            (.inbox, true)
        ]

        for (folder, priorityOnly) in targets {
            if Task.isCancelled { return }
            let key = MailboxCacheKey(
                accountId: nil,
                folder: folder,
                priorityOnly: priorityOnly,
                searchQuery: ""
            )
            if mailboxCache[key] != nil || persistedMailboxPage(for: key) != nil { continue }

            do {
                let page = try await apiClient.emails(
                    accountId: nil,
                    searchQuery: nil,
                    folder: folder,
                    priorityOnly: priorityOnly
                )
                cacheMailboxPage(page, for: key)
                mergeRecipientSuggestions(from: page.emails)
            } catch {
                // Prefetch should never block foreground mailbox use.
            }
        }
    }

    private func startRealtimeSync() async {
        do {
            try await apiClient.startRealtimeSync(accountId: selectedAccountId)
        } catch {
            // Realtime sync is best-effort; foreground refresh still works.
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
    let onRefreshAccounts: () -> Void
    let onManageBlockedSenders: () -> Void
    let onManageMutedSenders: () -> Void
    let onManageHiddenSenders: () -> Void
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
                        isPriorityMode.toggle()
                    }

                    ForEach(MailboxFolder.allCases) { folder in
                        FolderRailItem(
                            title: folder.title,
                            isActive: !isPriorityMode && selectedFolder == folder
                        ) {
                            if isPriorityMode { isPriorityMode = false }
                            selectedFolder = folder
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
                            Label(
                                account.isDisconnected ? "\(account.email) · Reconnect needed" : account.email,
                                systemImage: selectedAccountId == account.id
                                    ? "checkmark"
                                    : account.isDisconnected ? "exclamationmark.triangle" : "envelope"
                            )
                        }
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
                    Button(action: onManageHiddenSenders) {
                        Label("Hidden Senders", systemImage: "eye.slash")
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

private struct MailboxCacheKey: Hashable {
    let accountId: String?
    let folder: MailboxFolder
    let priorityOnly: Bool
    let searchQuery: String

    init(accountId: String?, folder: MailboxFolder, priorityOnly: Bool, searchQuery: String) {
        self.accountId = accountId
        self.folder = folder
        self.priorityOnly = priorityOnly
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isPersistable: Bool {
        searchQuery.isEmpty
    }

    var persistedStorageKey: String {
        [
            "mailbox-cache-v1",
            accountId ?? "all",
            folder.rawValue,
            priorityOnly ? "priority" : "normal"
        ].joined(separator: "|")
    }
}

// MARK: - Masthead

private struct AuroraHeader: View {
    let unreadCount: Int
    let onOpenSettings: () -> Void

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d · yyyy"
        return formatter.string(from: .now).uppercased()
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

                Text("ClarityMail")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Spacer()

            Text(todayLabel)
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.textSecondary)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(AuroraIconButtonStyle(size: 30))
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
        case .hidden:  return "Hidden"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    case blockSender
    case muteSender
    case hideSender

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
        case .blockSender: return "Block"
        case .muteSender: return "Mute"
        case .hideSender: return "Hide"
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
        case .blockSender: return "hand.raised"
        case .muteSender: return "bell.slash"
        case .hideSender: return "eye.slash"
        }
    }

    var isSenderScopedAction: Bool {
        switch self {
        case .blockSender, .muteSender, .hideSender:
            return true
        default:
            return false
        }
    }

    var bulkRequestAction: BulkEmailRequestAction? {
        switch self {
        case .archive: return .archive
        case .trash: return .trash
        case .markRead: return .markRead
        case .markUnread: return .markUnread
        case .star: return .star
        case .unstar: return .unstar
        case .pin, .unpin, .blockSender, .muteSender, .hideSender:
            return nil
        }
    }
}


private struct BulkActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.mono(10, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Theme.Palette.background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
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
    @AppStorage("hideEmailSubjects") private var hideEmailSubjects = false

    private var isUnread: Bool { !email.isRead }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectionMode {
                selectionIndicator
                    .padding(.top, 14)
                    .onTapGesture {
                        onToggleSelection()
                    }
            }

            SenderLogoView(email: email, size: 38)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(email.displayName)
                        .font(Theme.Typography.body(14, weight: isUnread ? .bold : .regular))
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

                    HStack(alignment: .center, spacing: 6) {
                        Text(email.receivedAt.emailRowDateText.replacingOccurrences(of: "\n", with: " · ").uppercased())
                            .font(Theme.Typography.mono(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(isUnread ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                            .lineLimit(1)

                        if isUnread {
                            Circle()
                                .fill(Theme.Palette.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                }

                if !hideEmailSubjects {
                    Text(email.subject)
                        .font(Theme.Typography.title(14.5))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .lineLimit(1)
                }

                Text(email.snippet)
                    .font(Theme.Typography.body(12.5))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(hideEmailSubjects ? 2 : 1)

                if email.isPinned == true || email.isBlockedSender == true || email.isMutedSender == true || email.isHiddenSender == true || (email.isPriority && showPriorityLabel) {
                    HStack(spacing: 8) {
                        if email.isPinned == true {
                            EmailRowChip(
                                title: "Pinned",
                                systemImage: nil,
                                color: Theme.Palette.warm
                            )
                        }
                        if email.isBlockedSender == true {
                            EmailRowChip(
                                title: "Blocked Sender",
                                systemImage: nil,
                                color: Theme.Palette.danger
                            )
                        }
                        if email.isMutedSender == true {
                            EmailRowChip(
                                title: "Muted Sender",
                                systemImage: nil,
                                color: Theme.Palette.warm
                            )
                        }
                        if email.isHiddenSender == true {
                            EmailRowChip(
                                title: "Hidden Sender",
                                systemImage: nil,
                                color: Theme.Palette.textTertiary
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

    private var selectionIndicator: some View {
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
            .frame(width: 14, height: 16, alignment: .center)
    }

    private var rowFill: Color {
        if isSelected { return Theme.Palette.accent.opacity(0.06) }
        if email.isManualPrioritySender && !email.isRead { return Theme.Palette.accent.opacity(0.04) }
        return Color.clear
    }
}

struct EmailRowChip: View {
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
                    .interpolation(.high)
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
                      let image = PlatformImage(data: data),
                      image.isLargeEnoughForSenderLogo(minPixelSize: max(56, size * 1.8)) else {
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

private extension NSImage {
    func isLargeEnoughForSenderLogo(minPixelSize: CGFloat) -> Bool {
        let bestPixelSize = representations.reduce(CGSize.zero) { current, representation in
            let candidate = CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
            return min(candidate.width, candidate.height) > min(current.width, current.height) ? candidate : current
        }

        let width = bestPixelSize.width > 0 ? bestPixelSize.width : size.width
        let height = bestPixelSize.height > 0 ? bestPixelSize.height : size.height
        return width >= minPixelSize && height >= minPixelSize
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage

private extension UIImage {
    func isLargeEnoughForSenderLogo(minPixelSize: CGFloat) -> Bool {
        size.width * scale >= minPixelSize && size.height * scale >= minPixelSize
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#endif

// MARK: - Bottom Action Bar (editorial footer)

private struct BottomActionBar: View {
    let onCompose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.borderStrong)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                Spacer()
                ComposeButton(action: onCompose)
            }
            .padding(.horizontal, Theme.Layout.gutter)
            .padding(.vertical, 12)
            .background(Theme.Palette.background)
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
