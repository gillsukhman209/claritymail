//
//  EmailDetailView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct EmailDetailView: View {
    let email: Email
    let accountId: String?
    let accounts: [GmailAccount]
    let recipientSuggestions: [EmailContact]
    let onBlockedSender: ((String) -> Void)?
    let onPrioritySenderChanged: ((String, Bool) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var loadedEmail: Email?
    @State private var threadEmails: [Email] = []
    @State private var isLoading = false
    @State private var isPerformingAction = false
    @State private var isShowingReply = false
    @State private var isShowingForward = false
    @State private var summary: String?
    @State private var isLoadingSummary = false
    @State private var errorMessage: String?
    @State private var attachmentData: [String: Data] = [:]
    @State private var loadingAttachmentIds = Set<String>()

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

                    deliveryDetailsCard

                    summaryCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.warm)
                    }

                    threadSection

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

            if isShowingReply {
                composerOverlay(mode: .reply(visibleEmail), isPresented: $isShowingReply)
            }

            if isShowingForward {
                composerOverlay(mode: .forward(visibleEmail), isPresented: $isShowingForward)
            }

            VStack {
                Spacer()
                UndoSendToast()
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy(duration: 0.2), value: isShowingReply)
        .navigationTitle("")
        .background {
            Button("") {
                Task { await trash() }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(isPerformingAction || isShowingReply)
            .opacity(0)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingReply = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(isPerformingAction)
                .keyboardShortcut("r", modifiers: [.command])
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingForward = true
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                .disabled(isPerformingAction)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await toggleStar() }
                    } label: {
                        Label(visibleEmail.isStarred ? "Unstar" : "Star",
                              systemImage: visibleEmail.isStarred ? "star.fill" : "star")
                    }
                    .keyboardShortcut("l", modifiers: [.command])

                    Button {
                        Task { await toggleRead() }
                    } label: {
                        Label(visibleEmail.isRead ? "Mark Unread" : "Mark Read",
                              systemImage: visibleEmail.isRead ? "envelope.badge" : "envelope.open")
                    }
                    .keyboardShortcut("u", modifiers: [.command])

                    Button {
                        Task { await archive() }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .keyboardShortcut("e", modifiers: [.command])

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
                    .keyboardShortcut("b", modifiers: [.command])

                    Divider()

                    if visibleEmail.isManualPrioritySender {
                        Button {
                            Task { await removeImportantSender() }
                        } label: {
                            Label("Remove Important Sender", systemImage: "bolt.slash")
                        }
                    } else {
                        Button {
                            Task { await markImportantSender() }
                        } label: {
                            Label("Mark Sender Important", systemImage: "bolt.circle")
                        }
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

    private var deliveryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeliveryDetailRow(
                title: "From",
                primary: visibleEmail.senderEmailAddress,
                secondary: visibleEmail.senderDisplayName
            )

            Divider().overlay(Theme.Palette.border)

            DeliveryDetailRow(
                title: "To",
                primary: toDisplayText,
                secondary: receivedAccountText
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }

    private var toDisplayText: String {
        if let to = visibleEmail.to?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty {
            return to
        }

        if let accountEmail = visibleEmail.accountEmail, !accountEmail.isEmpty {
            return accountEmail
        }

        return "Unknown recipient"
    }

    private var receivedAccountText: String? {
        guard let accountEmail = visibleEmail.accountEmail, !accountEmail.isEmpty else { return nil }
        guard toDisplayText.caseInsensitiveCompare(accountEmail) != .orderedSame else { return nil }
        return "Received in \(accountEmail)"
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

    @ViewBuilder
    private var threadSection: some View {
        let messages = threadEmails.isEmpty ? [visibleEmail] : threadEmails
        VStack(alignment: .leading, spacing: 14) {
            if messages.count > 1 {
                Text("\(messages.count) messages in this conversation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            ForEach(messages) { message in
                ThreadMessageView(
                    email: message,
                    attachmentData: attachmentData,
                    loadingAttachmentIds: loadingAttachmentIds,
                    onOpenAttachment: openAttachment
                )
            }
        }
    }

    private func composerOverlay(mode: ComposerView.Mode, isPresented: Binding<Bool>) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ComposerView(
                    mode: mode,
                    accountId: accountId ?? visibleEmail.accountId,
                    accounts: accounts,
                    recipientSuggestions: recipientSuggestions,
                    onSent: {},
                    onClose: {
                        isPresented.wrappedValue = false
                    }
                )
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(20)
    }

    private func attachmentIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        return "paperclip"
    }

    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedEmail = try await apiClient.email(id: email.id, accountId: accountId)
            loadedEmail = fetchedEmail
            errorMessage = nil
            await loadThread(for: fetchedEmail)
        } catch {
            errorMessage = "Could not load email body."
        }
    }

    private func loadThread(for email: Email) async {
        do {
            threadEmails = try await apiClient.thread(id: email.threadId, accountId: accountId)
            for message in threadEmails {
                await loadAttachments(for: message)
            }
        } catch {
            threadEmails = [email]
            await loadAttachments(for: email)
        }
    }

    private func loadAttachments(for email: Email) async {
        for attachment in email.attachments ?? [] where attachmentData[attachment.id] == nil {
            loadingAttachmentIds.insert(attachment.id)
            defer { loadingAttachmentIds.remove(attachment.id) }

            do {
                attachmentData[attachment.id] = try await apiClient.emailAttachment(
                    messageId: email.id,
                    attachmentId: attachment.id,
                    accountId: accountId
                )
            } catch {
                errorMessage = "Could not load attachment."
            }
        }
    }

    private func openAttachment(_ attachment: EmailAttachment) {
        guard let data = attachmentData[attachment.id] else { return }

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClarityMailAttachments", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileURL = directory.appendingPathComponent(safeFilename(attachment.filename))
            try data.write(to: fileURL, options: [.atomic])

            #if canImport(AppKit)
            NSWorkspace.shared.open(fileURL)
            #endif
        } catch {
            errorMessage = "Could not open attachment."
        }
    }

    private func safeFilename(_ filename: String) -> String {
        let blocked = CharacterSet(charactersIn: "/\\:")
        return filename
            .components(separatedBy: blocked)
            .joined(separator: "-")
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

        if errorMessage == nil {
            dismiss()
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

    private func markImportantSender() async {
        var importantSenderEmail: String?

        await performAction {
            importantSenderEmail = try await apiClient.markSenderImportant(id: visibleEmail.id, accountId: accountId)
        }

        if errorMessage == nil, let importantSenderEmail {
            applyPrioritySenderChange(senderEmail: importantSenderEmail, isImportant: true)
        }
    }

    private func removeImportantSender() async {
        guard let resolvedAccountId = visibleEmail.accountId ?? accountId else {
            errorMessage = "Could not remove important sender."
            return
        }

        let senderEmail = visibleEmail.senderEmailAddress
        await performAction {
            try await apiClient.removeImportantSender(accountId: resolvedAccountId, senderEmail: senderEmail)
        }

        if errorMessage == nil {
            applyPrioritySenderChange(senderEmail: senderEmail, isImportant: false)
        }
    }

    private func applyPrioritySenderChange(senderEmail: String, isImportant: Bool) {
        if loadedEmail == nil {
            loadedEmail = email
        }

        loadedEmail?.priorityStatus = isImportant ? .important : .normal
        loadedEmail?.prioritySource = isImportant ? .manualSender : nil
        loadedEmail?.priorityReason = isImportant ? "Important sender" : nil
        onPrioritySenderChanged?(senderEmail.lowercased(), isImportant)
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

private struct DeliveryDetailRow: View {
    let title: String
    let primary: String
    let secondary: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(primary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                if let secondary, !secondary.isEmpty, secondary.caseInsensitiveCompare(primary) != .orderedSame {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: EmailAttachment
    let data: Data?
    let isLoading: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachment.mimeType.hasPrefix("image/"),
               let data,
               let image = platformImage(from: data) {
                imageView(image)
            }

            Button {
                onOpen()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: attachmentIcon(for: attachment.mimeType))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accentSoft)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Theme.Palette.accent.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(detailText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Palette.surface.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(data == nil)
        }
    }

    private var detailText: String {
        if isLoading {
            return "Loading attachment..."
        }

        return "\(attachment.mimeType) • \(attachment.sizeText)"
    }

    private func attachmentIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        return "paperclip"
    }

    @ViewBuilder
    private func imageView(_ image: PlatformImage) -> some View {
        #if canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .onTapGesture {
                onOpen()
            }
        #elseif canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        #endif
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        #if canImport(AppKit)
        return NSImage(data: data)
        #elseif canImport(UIKit)
        return UIImage(data: data)
        #else
        return nil
        #endif
    }
}

private struct ThreadMessageView: View {
    let email: Email
    let attachmentData: [String: Data]
    let loadingAttachmentIds: Set<String>
    let onOpenAttachment: (EmailAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SenderLogoView(email: email, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(email.sender)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(email.receivedAt, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer()
            }

            let attachments = email.attachments ?? []
            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)

                    ForEach(attachments) { attachment in
                        AttachmentPreview(
                            attachment: attachment,
                            data: attachmentData[attachment.id],
                            isLoading: loadingAttachmentIds.contains(attachment.id),
                            onOpen: {
                                onOpenAttachment(attachment)
                            }
                        )
                    }
                }
            }

            EmailHTMLView(
                html: email.htmlBody,
                plainText: email.body ?? email.snippet
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
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
