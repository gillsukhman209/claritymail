//
//  EmailDetailView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct EmailDetailView: View {
    let email: Email
    let accountId: String?
    @State private var loadedEmail: Email?
    @State private var isLoading = false
    @State private var isPerformingAction = false
    @State private var isShowingReply = false
    @State private var summary: String?
    @State private var isLoadingSummary = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    private var visibleEmail: Email {
        loadedEmail ?? email
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection

                    summaryCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.warm)
                    }

                    Text(visibleEmail.body ?? visibleEmail.snippet)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    if isLoading && loadedEmail == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingReply = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(isPerformingAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await toggleStar() }
                    } label: {
                        Label(visibleEmail.isStarred ? "Unstar" : "Star",
                              systemImage: visibleEmail.isStarred ? "star.fill" : "star")
                    }

                    Button {
                        Task { await toggleRead() }
                    } label: {
                        Label(visibleEmail.isRead ? "Mark Unread" : "Mark Read",
                              systemImage: visibleEmail.isRead ? "envelope.badge" : "envelope.open")
                    }

                    Button {
                        Task { await archive() }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        Task { await trash() }
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isPerformingAction)
            }
        }
        .task(id: email.id) {
            await loadEmail()
            await loadSummary()
        }
        .sheet(isPresented: $isShowingReply) {
            NavigationStack {
                ComposerView(mode: .reply(visibleEmail), accountId: accountId) {}
            }
        }
        .tint(Theme.Palette.accent)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(visibleEmail.subject)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Palette.accent.opacity(0.85), Theme.Palette.accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(visibleEmail.sender)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(visibleEmail.receivedAt, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentSoft)
                Text("AI SUMMARY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.accentSoft)
                Spacer()
                if isLoadingSummary {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            Text(summary ?? "Summarizing this email...")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }

    private var initials: String {
        let name = visibleEmail.sender
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadedEmail = try await apiClient.email(id: email.id, accountId: accountId)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load email body."
        }
    }

    private func loadSummary() async {
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        do {
            summary = try await apiClient.summarizeEmail(id: email.id, accountId: accountId)
        } catch {
            summary = "Summary unavailable. Check that OPENAI_API_KEY is set in the backend."
        }
    }

    private func toggleStar() async {
        await performAction {
            if visibleEmail.isStarred {
                try await apiClient.unstarEmail(id: visibleEmail.id, accountId: accountId)
            } else {
                try await apiClient.starEmail(id: visibleEmail.id, accountId: accountId)
            }
        }

        if loadedEmail != nil {
            loadedEmail?.isStarred.toggle()
        } else {
            loadedEmail = email
            loadedEmail?.isStarred.toggle()
        }
    }

    private func toggleRead() async {
        await performAction {
            if visibleEmail.isRead {
                try await apiClient.markEmailUnread(id: visibleEmail.id, accountId: accountId)
            } else {
                try await apiClient.markEmailRead(id: visibleEmail.id, accountId: accountId)
            }
        }

        if loadedEmail != nil {
            loadedEmail?.isRead.toggle()
        } else {
            loadedEmail = email
            loadedEmail?.isRead.toggle()
        }
    }

    private func archive() async {
        await performAction {
            try await apiClient.archiveEmail(id: visibleEmail.id, accountId: accountId)
        }
    }

    private func trash() async {
        await performAction {
            try await apiClient.trashEmail(id: visibleEmail.id, accountId: accountId)
        }
    }

    private func performAction(_ action: () async throws -> Void) async {
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await action()
            errorMessage = nil
        } catch {
            errorMessage = "Could not update email."
        }
    }
}
