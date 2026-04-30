//
//  ComposerView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI
import UniformTypeIdentifiers

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
    let accounts: [GmailAccount]
    let onSent: () -> Void
    let onClose: () -> Void

    @State private var selectedAccountId: String?
    @State private var to = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var attachments: [ComposerAttachment] = []
    @State private var isShowingFileImporter = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusField?

    private let apiClient = APIClient()
    private let maxAttachmentBytes = 25 * 1024 * 1024

    init(
        mode: Mode,
        accountId: String?,
        accounts: [GmailAccount] = [],
        onSent: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.mode = mode
        self.accounts = accounts
        self.onSent = onSent
        self.onClose = onClose
        _selectedAccountId = State(initialValue: accountId)
    }

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
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        attachmentBytes <= maxAttachmentBytes
    }

    private var selectedAccount: GmailAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    private var attachmentBytes: Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    private var attachmentSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(attachmentBytes), countStyle: .file)
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
                    .frame(height: attachments.isEmpty ? 165 : 105)

                if !attachments.isEmpty {
                    attachmentList
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

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
                        isShowingFileImporter = true
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)

                    Spacer()

                    accountPicker

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
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onAppear {
            configureInitialValues()
            focusInitialField()
        }
    }

    private var attachmentList: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                Text(attachmentSizeText)
                Spacer()
                Text("25 MB max")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(attachmentBytes > maxAttachmentBytes ? Theme.Palette.warm : Theme.Palette.textTertiary)

            ForEach(attachments) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Theme.Palette.textTertiary)

                    Text(attachment.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text(attachment.sizeText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)

                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.surfaceElevated.opacity(0.7))
                )
            }
        }
    }

    @ViewBuilder
    private var accountPicker: some View {
        if accounts.isEmpty {
            Text(selectedAccountId == nil ? "Default account" : "Original account")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
        } else {
            Menu {
                ForEach(accounts) { account in
                    Button {
                        selectedAccountId = account.id
                    } label: {
                        Label(
                            account.email,
                            systemImage: selectedAccountId == account.id ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selectedAccount?.email ?? accounts.first?.email ?? "Select account")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: 190, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func configureInitialValues() {
        switch mode {
        case .compose:
            if selectedAccountId == nil {
                selectedAccountId = accounts.first?.id
            }
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
            let uploads = attachments.map {
                EmailAttachmentUpload(
                    filename: $0.name,
                    mimeType: $0.mimeType,
                    data: $0.data.base64EncodedString()
                )
            }

            switch mode {
            case .compose:
                try await apiClient.sendEmail(
                    to: to,
                    subject: subject,
                    body: messageBody,
                    accountId: selectedAccountId,
                    attachments: uploads
                )
            case .reply(let email):
                try await apiClient.reply(
                    to: to,
                    subject: subject,
                    body: messageBody,
                    threadId: email.threadId,
                    accountId: selectedAccountId,
                    attachments: uploads
                )
            }

            errorMessage = nil
            onSent()
            onClose()
        } catch {
            errorMessage = "Could not send email."
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls {
                addAttachment(from: url)
            }
        } catch {
            errorMessage = "Could not attach file."
        }
    }

    private func addAttachment(from url: URL) {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard attachmentBytes + data.count <= maxAttachmentBytes else {
                errorMessage = "Gmail allows up to 25 MB total attachments."
                return
            }

            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
            attachments.append(
                ComposerAttachment(
                    name: url.lastPathComponent,
                    mimeType: resourceValues?.contentType?.preferredMIMEType ?? "application/octet-stream",
                    data: data
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = "Could not attach file."
        }
    }
}

private struct ComposerAttachment: Identifiable {
    let id = UUID()
    let name: String
    let mimeType: String
    let data: Data

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}
