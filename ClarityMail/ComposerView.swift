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
        case forward(Email)
        case draft(Email)
    }

    private enum FocusField {
        case to
        case cc
        case bcc
        case subject
        case body
    }

    let mode: Mode
    let accounts: [GmailAccount]
    let recipientSuggestions: [EmailContact]
    let onSent: () -> Void
    let onClose: () -> Void

    @State private var selectedAccountId: String?
    @State private var currentDraftId: String?
    @State private var draftThreadId: String?
    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var isShowingCcBcc = false
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var forwardedHTMLBody: String?
    @State private var attachments: [ComposerAttachment] = []
    @State private var isShowingFileImporter = false
    @State private var isShowingSendLaterSheet = false
    @State private var scheduledSendDate = Date().addingTimeInterval(3600)
    @State private var isSending = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedDraftFingerprint = ""
    @State private var errorMessage: String?
    @AppStorage("undoSendDelaySeconds") private var undoSendDelaySeconds = 10
    @FocusState private var focusedField: FocusField?

    private let apiClient = APIClient()
    private let maxAttachmentBytes = 25 * 1024 * 1024

    init(
        mode: Mode,
        accountId: String?,
        accounts: [GmailAccount] = [],
        recipientSuggestions: [EmailContact] = [],
        onSent: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.mode = mode
        self.accounts = accounts
        self.recipientSuggestions = recipientSuggestions
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
        case .forward:
            return "Forward"
        case .draft:
            return "Draft"
        }
    }

    private var canSend: Bool {
        !isSending &&
        !cleanedRecipients(to).isEmpty &&
        (!messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || forwardedHTMLBody != nil) &&
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

    private var currentRecipientQuery: String {
        let separators = CharacterSet(charactersIn: ",;")
        return recipientText(for: focusedField)
            .components(separatedBy: separators)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var selectedRecipientEmails: Set<String> {
        let separators = CharacterSet(charactersIn: ",;")
        return Set(
            [to, cc, bcc].joined(separator: ",").components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.contains("@") && $0 != currentRecipientQuery.lowercased() }
        )
    }

    private var filteredRecipientSuggestions: [EmailContact] {
        let query = currentRecipientQuery.lowercased()
        guard !query.isEmpty else { return [] }

        return recipientSuggestions
            .filter { contact in
                !selectedRecipientEmails.contains(contact.email.lowercased()) &&
                (
                    contact.email.lowercased().contains(query) ||
                    contact.displayName.lowercased().contains(query)
                )
            }
            .sorted { first, second in
                let firstEmail = first.email.lowercased()
                let secondEmail = second.email.lowercased()
                let firstName = first.displayName.lowercased()
                let secondName = second.displayName.lowercased()

                let firstStarts = firstEmail.hasPrefix(query) || firstName.hasPrefix(query)
                let secondStarts = secondEmail.hasPrefix(query) || secondName.hasPrefix(query)

                if firstStarts != secondStarts {
                    return firstStarts
                }

                return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
            }
            .prefix(6)
            .map { $0 }
    }

    private var shouldShowRecipientSuggestions: Bool {
        (focusedField == .to || focusedField == .cc || focusedField == .bcc) && !filteredRecipientSuggestions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button {
                    autosaveTask?.cancel()
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
                recipientRow("To", text: $to, focus: .to, showCcBccButton: !isShowingCcBcc)

                if shouldShowRecipientSuggestions {
                    RecipientSuggestionList(
                        contacts: filteredRecipientSuggestions,
                        onSelect: selectRecipientSuggestion
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().overlay(Theme.Palette.border)

                if isShowingCcBcc {
                    recipientRow("Cc", text: $cc, focus: .cc)

                    Divider().overlay(Theme.Palette.border)

                    recipientRow("Bcc", text: $bcc, focus: .bcc)

                    Divider().overlay(Theme.Palette.border)
                }

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
                    .accessibilityLabel("Attachments")

                    Button {
                        scheduledSendDate = defaultScheduledDate()
                        isShowingSendLaterSheet = true
                    } label: {
                        Image(systemName: "clock")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .disabled(!canSend)

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
        .frame(minWidth: 320, maxWidth: 520)
        .frame(height: composerHeight)
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
        .sheet(isPresented: $isShowingSendLaterSheet) {
            SendLaterSheet(
                scheduledDate: $scheduledSendDate,
                canSchedule: canSend && scheduledSendDate > Date(),
                onSchedule: {
                    Task { await sendLater() }
                }
            )
            .presentationDetents([.height(260)])
        }
        .onAppear {
            configureInitialValues()
            focusInitialField()
        }
        .onChange(of: to) { scheduleAutosave() }
        .onChange(of: cc) { scheduleAutosave() }
        .onChange(of: bcc) { scheduleAutosave() }
        .onChange(of: subject) { scheduleAutosave() }
        .onChange(of: messageBody) { scheduleAutosave() }
        .onChange(of: selectedAccountId) { scheduleAutosave() }
        .onDisappear {
            autosaveTask?.cancel()
        }
    }

    private var composerHeight: CGFloat {
        var height: CGFloat = attachments.isEmpty ? 430 : 470
        if shouldShowRecipientSuggestions {
            height += 70
        }
        if isShowingCcBcc {
            height += 92
        }
        return min(height, 560)
    }

    private func recipientRow(
        _ label: String,
        text: Binding<String>,
        focus: FocusField,
        showCcBccButton: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 54, alignment: .leading)

            TextField("name@example.com", text: text)
                .textFieldStyle(.plain)
                .textContentType(.emailAddress)
                .focused($focusedField, equals: focus)

            if showCcBccButton {
                Button("Cc/Bcc") {
                    isShowingCcBcc = true
                    focusedField = .cc
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.accentSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    private func selectRecipientSuggestion(_ contact: EmailContact) {
        guard let focusedField else { return }
        let separators = CharacterSet(charactersIn: ",;")
        var currentText = recipientText(for: focusedField)
        var parts = currentText.components(separatedBy: separators)
        if parts.isEmpty {
            parts = [contact.email]
        } else {
            parts[parts.count - 1] = " \(contact.email)"
        }

        currentText = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if !currentText.hasSuffix(", ") {
            currentText += ", "
        }

        switch focusedField {
        case .to:
            to = currentText
        case .cc:
            cc = currentText
        case .bcc:
            bcc = currentText
        case .subject, .body:
            break
        }

        self.focusedField = focusedField
    }

    private func recipientText(for focus: FocusField?) -> String {
        switch focus {
        case .to:
            return to
        case .cc:
            return cc
        case .bcc:
            return bcc
        case .subject, .body, nil:
            return ""
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
            draftThreadId = email.threadId
        case .forward(let email):
            selectedAccountId = selectedAccountId ?? email.accountId
            subject = email.subject.lowercased().hasPrefix("fwd:") ? email.subject : "Fwd: \(email.subject)"
            forwardedHTMLBody = forwardedHTML(from: email)
            messageBody = ""
        case .draft(let email):
            currentDraftId = email.draftId
            selectedAccountId = selectedAccountId ?? email.accountId
            draftThreadId = email.threadId
            to = email.to ?? ""
            cc = email.cc ?? ""
            bcc = email.bcc ?? ""
            isShowingCcBcc = !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            subject = email.subject == "(No subject)" ? "" : email.subject
            messageBody = email.body ?? email.snippet
            lastSavedDraftFingerprint = draftFingerprint()
        }
    }

    private func focusInitialField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch mode {
            case .compose:
                focusedField = .to
            case .reply:
                focusedField = .body
            case .forward:
                focusedField = .to
            case .draft:
                focusedField = to.isEmpty ? .to : .body
            }
        }
    }

    private func send() async {
        guard canSend else { return }
        autosaveTask?.cancel()
        isSending = true

        let uploads = attachmentUploads()
        let htmlBody = composedHTMLBody()
        let selectedAccountId = selectedAccountId
        let currentDraftId = currentDraftId
        let draftThreadId = draftThreadId
        let to = cleanedRecipients(to)
        let cc = cleanedOptionalRecipient(cc)
        let bcc = cleanedOptionalRecipient(bcc)
        let subject = subject
        let body = messageBody
        let mode = mode
        let apiClient = apiClient
        let onSent = onSent

        UndoSendManager.shared.schedule(
            title: "Sending",
            delay: undoSendDelaySeconds,
            operation: {
                switch mode {
                case .compose, .forward:
                    try await apiClient.sendEmail(
                        to: to,
                        cc: cc,
                        bcc: bcc,
                        subject: subject,
                        body: body,
                        htmlBody: htmlBody,
                        accountId: selectedAccountId,
                        attachments: uploads
                    )
                    if let currentDraftId {
                        try? await apiClient.deleteDraft(draftId: currentDraftId, accountId: selectedAccountId)
                    }
                case .reply(let email):
                    if let currentDraftId {
                        try await apiClient.sendDraft(
                            draftId: currentDraftId,
                            to: to,
                            cc: cc,
                            bcc: bcc,
                            subject: subject,
                            body: body,
                            htmlBody: htmlBody,
                            accountId: selectedAccountId,
                            threadId: email.threadId,
                            attachments: uploads
                        )
                    } else {
                        try await apiClient.reply(
                            to: to,
                            cc: cc,
                            bcc: bcc,
                            subject: subject,
                            body: body,
                            htmlBody: htmlBody,
                            threadId: email.threadId,
                            accountId: selectedAccountId,
                            attachments: uploads
                        )
                    }
                case .draft(let email):
                    if let currentDraftId {
                        try await apiClient.sendDraft(
                            draftId: currentDraftId,
                            to: to,
                            cc: cc,
                            bcc: bcc,
                            subject: subject,
                            body: body,
                            htmlBody: htmlBody,
                            accountId: selectedAccountId,
                            threadId: draftThreadId ?? email.threadId,
                            attachments: uploads
                        )
                    } else {
                        try await apiClient.sendEmail(
                            to: to,
                            cc: cc,
                            bcc: bcc,
                            subject: subject,
                            body: body,
                            htmlBody: htmlBody,
                            accountId: selectedAccountId,
                            attachments: uploads
                        )
                    }
                }
            },
            onComplete: {
                onSent()
            },
            onError: {}
        )

        isSending = false
        onClose()
    }

    private func sendLater() async {
        guard canSend, scheduledSendDate > Date() else { return }
        autosaveTask?.cancel()
        isSending = true
        defer { isSending = false }

        do {
            let threadId: String?
            switch mode {
            case .reply(let email):
                threadId = email.threadId
            case .draft(let email):
                threadId = draftThreadId ?? email.threadId
            default:
                threadId = nil
            }

            _ = try await apiClient.scheduleEmail(
                to: cleanedRecipients(to),
                cc: cleanedOptionalRecipient(cc),
                bcc: cleanedOptionalRecipient(bcc),
                subject: subject,
                body: messageBody,
                htmlBody: composedHTMLBody(),
                sendAt: scheduledSendDate,
                accountId: selectedAccountId,
                threadId: threadId,
                attachments: attachmentUploads()
            )

            if let currentDraftId {
                try? await apiClient.deleteDraft(draftId: currentDraftId, accountId: selectedAccountId)
            }

            isShowingSendLaterSheet = false
            onSent()
            onClose()
        } catch {
            errorMessage = "Could not schedule email."
        }
    }

    private func defaultScheduledDate() -> Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
    }

    private func cleanedOptionalRecipient(_ value: String) -> String? {
        let trimmed = cleanedRecipients(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedRecipients(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func attachmentUploads() -> [EmailAttachmentUpload] {
        attachments.map {
            EmailAttachmentUpload(
                filename: $0.name,
                mimeType: $0.mimeType,
                data: $0.data.base64EncodedString()
            )
        }
    }

    private func composedHTMLBody() -> String? {
        guard let forwardedHTMLBody else { return nil }
        let note = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return forwardedHTMLBody }

        let noteHTML = escapeHTML(note).replacingOccurrences(of: "\n", with: "<br>")
        return "<div>\(noteHTML)</div><br>\(forwardedHTMLBody)"
    }

    private func scheduleAutosave() {
        guard shouldAutosaveDraft else { return }

        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            await saveDraftIfNeeded()
        }
    }

    private var shouldAutosaveDraft: Bool {
        !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func draftFingerprint() -> String {
        "\(selectedAccountId ?? "")|\(to)|\(cc)|\(bcc)|\(subject)|\(messageBody)|\(attachments.map(\.name).joined(separator: ","))"
    }

    private func saveDraftIfNeeded() async {
        let fingerprint = draftFingerprint()
        guard fingerprint != lastSavedDraftFingerprint else { return }

        do {
            let uploads = attachments.map {
                EmailAttachmentUpload(
                    filename: $0.name,
                    mimeType: $0.mimeType,
                    data: $0.data.base64EncodedString()
                )
            }

            let result: DraftSaveResult
            if let currentDraftId {
                result = try await apiClient.updateDraft(
                    draftId: currentDraftId,
                    to: cleanedRecipients(to),
                    cc: cleanedOptionalRecipient(cc),
                    bcc: cleanedOptionalRecipient(bcc),
                    subject: subject,
                    body: messageBody,
                    htmlBody: composedHTMLBody(),
                    accountId: selectedAccountId,
                    threadId: draftThreadId,
                    attachments: uploads
                )
            } else {
                result = try await apiClient.createDraft(
                    to: cleanedRecipients(to),
                    cc: cleanedOptionalRecipient(cc),
                    bcc: cleanedOptionalRecipient(bcc),
                    subject: subject,
                    body: messageBody,
                    htmlBody: composedHTMLBody(),
                    accountId: selectedAccountId,
                    threadId: draftThreadId,
                    attachments: uploads
                )
            }

            currentDraftId = result.id
            draftThreadId = result.threadId.isEmpty ? draftThreadId : result.threadId
            lastSavedDraftFingerprint = fingerprint
        } catch {
            errorMessage = "Could not save draft."
        }
    }

    private func forwardedHTML(from email: Email) -> String {
        let originalHTML = email.htmlBody ?? "<div>\(escapeHTML(email.body ?? email.snippet).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        return """
        <div><br></div>
        <div>---------- Forwarded message ----------</div>
        <div><b>From:</b> \(escapeHTML(email.sender))</div>
        <div><b>Date:</b> \(escapeHTML(email.receivedAt.formatted(date: .abbreviated, time: .shortened)))</div>
        <div><b>Subject:</b> \(escapeHTML(email.subject))</div>
        <br>
        \(originalHTML)
        """
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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

private struct RecipientSuggestionList: View {
    let contacts: [EmailContact]
    let onSelect: (EmailContact) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(contacts) { contact in
                Button {
                    onSelect(contact)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.Palette.accent.opacity(0.16))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(initials(for: contact))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.Palette.accentSoft)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(contact.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)

                            if let subtitle = contact.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.Palette.surfaceElevated.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }

    private func initials(for contact: EmailContact) -> String {
        let source: String
        if let name = contact.name, !name.isEmpty {
            source = name
        } else {
            source = contact.email
        }

        let parts = source.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined()
        if !initials.isEmpty {
            return initials.uppercased()
        }
        return String(contact.email.prefix(1)).uppercased()
    }
}

private struct SendLaterSheet: View {
    @Binding var scheduledDate: Date
    let canSchedule: Bool
    let onSchedule: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Send Later")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.textTertiary)
            }

            DatePicker(
                "Send at",
                selection: $scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(Theme.Palette.accent)

            HStack(spacing: 10) {
                quickDateButton("In 1 hour", date: Calendar.current.date(byAdding: .hour, value: 1, to: Date()))
                quickDateButton("Tomorrow 9 AM", date: tomorrowMorning())
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.textTertiary)

                Button {
                    onSchedule()
                    dismiss()
                } label: {
                    Label("Schedule", systemImage: "clock.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(canSchedule ? Theme.Palette.accent : Theme.Palette.textTertiary.opacity(0.35))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSchedule)
            }
        }
        .padding(18)
        .background(Theme.Palette.surface)
    }

    private func quickDateButton(_ title: String, date: Date?) -> some View {
        Button(title) {
            if let date {
                scheduledDate = date
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.Palette.accentSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Palette.accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private func tomorrowMorning() -> Date? {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
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
