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

    private enum FocusField {
        case to
        case subject
        case body
    }

    let mode: Mode
    let accountId: String?
    let onSent: () -> Void
    let onClose: () -> Void

    @State private var to = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusField?

    private let apiClient = APIClient()

    private var title: String {
        switch mode {
        case .compose:
            return "New Message"
        case .reply:
            return "Reply"
        }
    }

    private var canSend: Bool {
        !isSending &&
        !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.textTertiary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.Palette.surfaceElevated.opacity(0.8))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("To")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(width: 54, alignment: .leading)

                    TextField("name@example.com", text: $to)
                        .textFieldStyle(.plain)
                        .textContentType(.emailAddress)
                        .focused($focusedField, equals: .to)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Theme.Palette.border)

                HStack(spacing: 8) {
                    Text("Subject")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(width: 54, alignment: .leading)

                    TextField("Subject", text: $subject)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .subject)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().overlay(Theme.Palette.border)

                TextEditor(text: $messageBody)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .focused($focusedField, equals: .body)
                    .padding(12)
                    .frame(height: 190)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Palette.warm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                Divider().overlay(Theme.Palette.border)

                HStack(spacing: 12) {
                    Button {
                        focusedField = .body
                    } label: {
                        Image(systemName: "textformat")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)

                    Button {
                        focusedField = .body
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)

                    Spacer()

                    Text(accountId == nil ? "Default account" : "Selected account")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)

                    Button {
                        Task { await send() }
                    } label: {
                        HStack(spacing: 7) {
                            if isSending {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Image(systemName: "paperplane.fill")
                            Text("Send")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(canSend ? Theme.Palette.accent : Theme.Palette.textTertiary.opacity(0.35))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 520, height: 430)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 34, x: 0, y: 18)
        .onAppear {
            configureInitialValues()
            focusInitialField()
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

    private func focusInitialField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch mode {
            case .compose:
                focusedField = .to
            case .reply:
                focusedField = .body
            }
        }
    }

    private func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }

        do {
            switch mode {
            case .compose:
                try await apiClient.sendEmail(to: to, subject: subject, body: messageBody, accountId: accountId)
            case .reply(let email):
                try await apiClient.reply(to: to, subject: subject, body: messageBody, threadId: email.threadId, accountId: accountId)
            }

            errorMessage = nil
            onSent()
            onClose()
        } catch {
            errorMessage = "Could not send email."
        }
    }
}
