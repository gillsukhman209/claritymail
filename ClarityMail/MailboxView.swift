//
//  MailboxView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct MailboxView: View {
    @ObservedObject var session: SessionStore
    @State private var selectedEmail: Email.ID?
    @State private var emails = Email.previewEmails
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var selectedMessage: Email? {
        emails.first { $0.id == selectedEmail }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedEmail) {
                Section("Inbox") {
                    ForEach(emails) { email in
                        EmailRowView(email: email)
                            .tag(email.id)
                    }
                }
            }
            .navigationTitle("ClarityMail")
            .toolbar {
                Button {
                    Task {
                        await loadEmails()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    session.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .task {
                await loadEmails()
            }
        } detail: {
            if let selectedMessage {
                EmailDetailView(email: selectedMessage)
            } else {
                ContentUnavailableView("Select an Email", systemImage: "envelope.open")
            }
        }
    }

    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }

        do {
            emails = try await apiClient.emails()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load inbox."
        }
    }
}

private struct EmailRowView: View {
    let email: Email

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(email.sender)
                    .fontWeight(email.isRead ? .regular : .semibold)

                Spacer()

                Text(email.receivedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(email.subject)
                .lineLimit(1)
                .fontWeight(email.isRead ? .regular : .medium)

            Text(email.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
