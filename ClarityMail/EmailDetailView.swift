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
    let onBlockedSender: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
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

                    EmailHTMLView(
                        html: visibleEmail.htmlBody,
                        plainText: visibleEmail.body ?? visibleEmail.snippet
                    )

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

                    Button(role: .destructive) {
                        Task { await blockSender() }
                    } label: {
                        Label("Block Sender", systemImage: "hand.raised")
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
                SenderLogoView(email: visibleEmail, size: 36)

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

            SummaryContentView(summary: summary)
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

    private func blockSender() async {
        var blockedSenderEmail: String?

        await performAction {
            blockedSenderEmail = try await apiClient.blockSender(id: visibleEmail.id, accountId: accountId)
        }

        if errorMessage == nil, let blockedSenderEmail {
            onBlockedSender?(blockedSenderEmail)
            dismiss()
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

private struct SummaryContentView: View {
    let summary: String?

    private var cleanedSummary: (summary: String, action: String?)? {
        guard let summary, !summary.isEmpty else { return nil }

        let lines = summary
            .replacingOccurrences(of: "*", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var summaryText = ""
        var actionText: String?

        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("summary:") {
                summaryText = String(line.dropFirst("summary:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lowercased.hasPrefix("action:") {
                let value = String(line.dropFirst("action:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && value.lowercased() != "none" {
                    actionText = value
                }
            } else if summaryText.isEmpty {
                summaryText = line
            }
        }

        return (summaryText.isEmpty ? summary : summaryText, actionText)
    }

    var body: some View {
        if let cleanedSummary {
            VStack(alignment: .leading, spacing: 12) {
                Text(cleanedSummary.summary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.92))
                    .lineSpacing(3)
                    .textSelection(.enabled)

                if let action = cleanedSummary.action {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.accentSoft)
                            .padding(.top, 2)

                        Text(action)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.Palette.surfaceElevated.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
            }
        } else {
            Text("Summarizing this email...")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
