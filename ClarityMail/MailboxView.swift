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
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingComposer = false
    @State private var isShowingVoice = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?

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

                        GreetingBlock(name: session.displayName)
                            .padding(.horizontal, 24)

                        AccountSearchBar(
                            accounts: accounts,
                            selectedAccountId: $selectedAccountId,
                            searchText: $searchText,
                            onAddAccount: {
                                Task { await session.signInWithGoogle() }
                            },
                            onRefreshAccounts: {
                                Task {
                                    await loadAccounts()
                                    await loadEmails()
                                }
                            }
                        )
                        .padding(.horizontal, 20)

                        AIPulseCard(
                            important: importantCount,
                            needsReply: needsReplyCount,
                            updates: updatesCount
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
                .background(
                    GradientOrbBackground()
                        .ignoresSafeArea()
                )

                BottomActionBar(
                    onMail: { /* already in mail */ },
                    onVoice: { isShowingVoice = true },
                    onCompose: { isShowingComposer = true }
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            .modifier(HideNavigationBarModifier())
            .navigationDestination(item: $selectedEmail) { email in
                EmailDetailView(email: email, accountId: selectedAccountId ?? email.accountId)
            }
            .task {
                await loadAccounts()
                await loadEmails()
                await startRealtimeSync()
                startAutoRefresh()
            }
            .onChange(of: selectedAccountId) {
                selectedEmail = nil
                Task {
                    await loadEmails()
                    await startRealtimeSync()
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
            .sheet(isPresented: $isShowingVoice) {
                VoiceAssistantSheet()
            }
            .refreshable {
                await loadEmails()
            }
        }
        .tint(Theme.Palette.accent)
    }

    private var unreadCount: Int { emails.filter { !$0.isRead }.count }
    private var importantCount: Int { emails.filter { $0.isStarred }.count }
    private var needsReplyCount: Int { max(unreadCount - importantCount, 0) }
    private var updatesCount: Int { emails.count }

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

    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }

        do {
            emails = try await apiClient.emails(accountId: selectedAccountId, searchQuery: searchText)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load inbox."
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
}

// MARK: - Account + Search

private struct AccountSearchBar: View {
    let accounts: [GmailAccount]
    @Binding var selectedAccountId: String?
    @Binding var searchText: String
    let onAddAccount: () -> Void
    let onRefreshAccounts: () -> Void

    private var selectedAccount: GmailAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    var body: some View {
        VStack(spacing: 10) {
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Hello"
        }
    }

    private var greetingIcon: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<17: return "sun.max.fill"
        case 17..<20: return "sun.haze.fill"
        default: return "moon.stars.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(greeting), \(name)")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Image(systemName: greetingIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Palette.warmSoft)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("You're all caught up.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("2 important · 5 updates")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

// MARK: - AI Pulse Card

private struct AIPulseCard: View {
    let important: Int
    let needsReply: Int
    let updates: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI PULSE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.warmSoft)
                Text("Here's what matters today")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            HStack(spacing: 0) {
                PulseStat(value: important, label: "Important")
                PulseDivider()
                PulseStat(value: needsReply, label: "Needs Reply")
                PulseDivider()
                PulseStat(value: updates, label: "Updates")
            }

            Button {
                // Pulse brief sheet — wire up later
            } label: {
                HStack {
                    Text("View Pulse Brief")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .foregroundStyle(Theme.Palette.textPrimary)
                .background(Theme.Palette.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Gradients.pulseCardBorder, lineWidth: 1)
        )
    }
}

private struct PulseStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PulseDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.border)
            .frame(width: 1, height: 36)
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
            AvatarView(name: email.displayName)

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

private struct AvatarView: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var seedColor: Color {
        let hash = abs(name.hashValue)
        let palette: [Color] = [
            Color(red: 0.49, green: 0.38, blue: 1.0),
            Color(red: 0.95, green: 0.55, blue: 0.35),
            Color(red: 0.30, green: 0.72, blue: 0.65),
            Color(red: 0.85, green: 0.40, blue: 0.65),
            Color(red: 0.40, green: 0.55, blue: 0.95)
        ]
        return palette[hash % palette.count]
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [seedColor.opacity(0.85), seedColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 38, height: 38)
            .overlay(
                Text(initials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Bottom Action Bar

private struct BottomActionBar: View {
    let onMail: () -> Void
    let onVoice: () -> Void
    let onCompose: () -> Void

    var body: some View {
        HStack {
            BarIconButton(systemName: "envelope.fill", action: onMail)
            Spacer()
            VoiceButton(action: onVoice)
            Spacer()
            BarIconButton(systemName: "square.and.pencil", action: onCompose)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.85))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 12)
        )
    }
}

private struct BarIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct VoiceButton: View {
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.Gradients.voiceButton)
                    .frame(width: 64, height: 64)
                    .shadow(color: Theme.Palette.accent.opacity(0.55), radius: 18, x: 0, y: 8)

                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: pulse)
            }
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
    }
}

// MARK: - Background Orb

private struct GradientOrbBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Theme.Gradients.orb)
                    .frame(width: proxy.size.width * 0.85, height: proxy.size.width * 0.85)
                    .blur(radius: 60)
                    .opacity(0.55)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.width * 0.10)

                Circle()
                    .fill(Theme.Palette.accent.opacity(0.35))
                    .frame(width: proxy.size.width * 0.50, height: proxy.size.width * 0.50)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.30, y: proxy.size.height * 0.55)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Voice Sheet (placeholder)

private struct VoiceAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Capsule()
                    .fill(Theme.Palette.borderStrong)
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                Spacer()

                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .strokeBorder(Theme.Palette.accent.opacity(0.3 - Double(index) * 0.08), lineWidth: 1)
                            .frame(width: CGFloat(140 + index * 60))
                    }

                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.Palette.accent)
                }

                Text("How can I help you today?")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text("Tap to speak, or type below.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textSecondary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.Gradients.voiceButton)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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
