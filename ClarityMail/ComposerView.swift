//
//  ComposerView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct ComposerView: View {
    enum Mode {
        case compose
        case reply(Email)
    }

    let mode: Mode
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var title: String {
        switch mode {
        case .compose:
            return "New Message"
        case .reply:
            return "Reply"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("To", text: $to)
                    .textContentType(.emailAddress)

                TextField("Subject", text: $subject)

                TextEditor(text: $messageBody)
                    .font(.body)
                    .frame(minHeight: 220)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    Task {
                        await send()
                    }
                }
                .disabled(isSending || to.isEmpty || subject.isEmpty || messageBody.isEmpty)
            }
        }
        .onAppear {
            configureInitialValues()
        }
    }

    private func configureInitialValues() {
        switch mode {
        case .compose:
            break
        case .reply(let email):
            to = email.senderEmailAddress
            subject = email.subject.lowercased().hasPrefix("re:") ? email.subject : "Re: \(email.subject)"
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        do {
            switch mode {
            case .compose:
                try await apiClient.sendEmail(to: to, subject: subject, body: messageBody)
            case .reply(let email):
                try await apiClient.reply(to: to, subject: subject, body: messageBody, threadId: email.threadId)
            }

            errorMessage = nil
            onSent()
            dismiss()
        } catch {
            errorMessage = "Could not send email."
        }
    }
}
