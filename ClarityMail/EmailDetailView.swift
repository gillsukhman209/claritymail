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
}
