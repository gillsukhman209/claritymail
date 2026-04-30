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
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var knownEmailIds = Set<String>()
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
                            }
                        )
                        .padding(.horizontal, 20)

                        EmailListSection(
                            emails: emails,
                            isLoading: isLoading,
                            errorMessage: errorMessage,
                            onSelect: { selectedEmail = $0 }
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
            .modifier(HideNavigationBarModifier())
            .navigationDestination(item: $selectedEmail) { email in
                EmailDetailView(email: email, accountId: selectedAccountId ?? email.accountId) { blockedSender in
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
            }
            .onChange(of: selectedAccountId) {
                selectedEmail = nil
                knownEmailIds.removeAll()
                hasLoadedInitialEmails = false
                Task {
                    await loadEmails()
                    await startRealtimeSync()
                }
            }
            .onChange(of: selectedFolder) {
                selectedEmail = nil
                knownEmailIds.removeAll()
                hasLoadedInitialEmails = false
                Task {
                    await loadEmails()
                }
            }
            .onChange(of: searchText) {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if Task.isCancelled { return }
                    await loadEmails()
                }
            }
            .onChange(of: session.pendingAuthURL) {
                guard let url = session.pendingAuthURL else { return }
                openURL(url)
            }
            .onDisappear {
                autoRefreshTask?.cancel()
                searchTask?.cancel()
            }
            .sheet(isPresented: $isShowingComposer) {
                NavigationStack {
                    ComposerView(mode: .compose, accountId: selectedAccountId) {
                        Task { await loadEmails() }
                    }
                }
            }
            .sheet(isPresented: $isShowingBlockedSenders) {
                BlockedSendersView(accountId: selectedAccountId)
            }
            .refreshable {
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
            let fetchedEmails = try await apiClient.emails(accountId: selectedAccountId, searchQuery: searchText, folder: selectedFolder)
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
            knownEmailIds = fetchedIds
            hasLoadedInitialEmails = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not load inbox."
        }
    }

    private func shouldNotifyForNewEmails(notifyForNewEmails: Bool) -> Bool {
        notifyForNewEmails &&
        hasLoadedInitialEmails &&
        selectedFolder == .inbox &&
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                TextField("Search inbox", text: $searchText)
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

private struct EmailListSection: View {
    let emails: [Email]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (Email) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.warm)
                    .padding(.horizontal, 4)
            }

            if isLoading && emails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(emails) { email in
                        Button {
                            onSelect(email)
                        } label: {
                            EmailRowView(email: email)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct EmailRowView: View {
    let email: Email

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SenderLogoView(email: email, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(email.displayName)
                        .font(.system(size: 15, weight: email.isRead ? .regular : .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Spacer()

                    Text(email.receivedAt, style: .time)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
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
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
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
