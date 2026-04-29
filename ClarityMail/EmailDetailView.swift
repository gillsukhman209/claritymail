//
//  EmailDetailView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @State private var loadedEmail: Email?
    @State private var isLoading = false
    @State private var isPerformingAction = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    private var visibleEmail: Email {
        loadedEmail ?? email
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(visibleEmail.subject)
                        .font(.title2.bold())

                    Text(visibleEmail.sender)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.headline)

                    Text("AI summary will appear here after the OpenAI backend route is connected.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }

                Text(visibleEmail.body ?? visibleEmail.snippet)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(visibleEmail.subject)
        .toolbar {
            Button {
                Task {
                    await toggleStar()
                }
            } label: {
                Label(visibleEmail.isStarred ? "Unstar" : "Star", systemImage: visibleEmail.isStarred ? "star.fill" : "star")
            }
            .disabled(isPerformingAction)

            Button {
                Task {
                    await toggleRead()
                }
            } label: {
                Label(visibleEmail.isRead ? "Mark Unread" : "Mark Read", systemImage: visibleEmail.isRead ? "envelope.badge" : "envelope.open")
            }
            .disabled(isPerformingAction)

            Button {
                Task {
                    await archive()
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .disabled(isPerformingAction)

            Button(role: .destructive) {
                Task {
                    await trash()
                }
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .disabled(isPerformingAction)
        }
        .task(id: email.id) {
            await loadEmail()
        }
    }

    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadedEmail = try await apiClient.email(id: email.id)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load email body."
        }
    }

    private func toggleStar() async {
        await performAction {
            if visibleEmail.isStarred {
                try await apiClient.unstarEmail(id: visibleEmail.id)
            } else {
                try await apiClient.starEmail(id: visibleEmail.id)
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
                try await apiClient.markEmailUnread(id: visibleEmail.id)
            } else {
                try await apiClient.markEmailRead(id: visibleEmail.id)
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
            try await apiClient.archiveEmail(id: visibleEmail.id)
        }
    }

    private func trash() async {
        await performAction {
            try await apiClient.trashEmail(id: visibleEmail.id)
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
