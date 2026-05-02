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
    let onMutedSenderChanged: ((String, Bool) -> Void)?
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
                VStack(alignment: .leading, spacing: 0) {
                    actionBar
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                        .padding(.bottom, 14)

                    Rectangle()
                        .fill(Theme.Palette.borderStrong)
                        .frame(height: 1)

                    headerSection
                        .padding(.horizontal, 22)
                        .padding(.top, 26)
                        .padding(.bottom, 22)

                    deliveryDetailsCard
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)

                    summaryCard
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .heavy))
                            Text(errorMessage.uppercased())
                                .font(Theme.Typography.mono(11, weight: .semibold))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Theme.Palette.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle()
                                .strokeBorder(Theme.Palette.danger.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, 22)
                        .padding(.bottom, 18)
                    }

                    threadSection
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)

                    if isLoading && loadedEmail == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }

                    Color.clear.frame(height: 40)
                }
                .frame(maxWidth: 760, alignment: .leading)
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
        .task(id: email.id) {
            await loadEmail()
            await loadSummary()
        }
        .tint(Theme.Palette.accent)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                #if os(iOS)
                dismiss()
                #endif
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Inbox".uppercased())
                        .font(Theme.Typography.mono(10, weight: .semibold))
                        .tracking(1.6)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .opacity(0)
            .frame(width: 0, height: 0)
            #endif

            Spacer()

            Button { isShowingReply = true } label: {
                Text("Reply")
            }
            .buttonStyle(AuroraPrimaryButtonStyle(compact: true))
            .disabled(isPerformingAction)
            .keyboardShortcut("r", modifiers: [.command])

            Button { isShowingForward = true } label: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .buttonStyle(AuroraIconButtonStyle(size: 30))
            .disabled(isPerformingAction)
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Menu {
                Button { Task { await toggleStar() } } label: {
                    Label(visibleEmail.isStarred ? "Unstar" : "Star",
                          systemImage: visibleEmail.isStarred ? "star.fill" : "star")
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button { Task { await togglePin() } } label: {
                    Label(visibleEmail.isPinned == true ? "Unpin" : "Pin",
                          systemImage: visibleEmail.isPinned == true ? "pin.slash" : "pin")
                }

                Button { Task { await toggleRead() } } label: {
                    Label(visibleEmail.isRead ? "Mark Unread" : "Mark Read",
                          systemImage: visibleEmail.isRead ? "envelope.badge" : "envelope.open")
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button { Task { await archive() } } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button(role: .destructive) { Task { await trash() } } label: {
                    Label("Trash", systemImage: "trash")
                }

                Button(role: .destructive) { Task { await blockSender() } } label: {
                    Label("Block Sender", systemImage: "hand.raised")
                }
                .keyboardShortcut("b", modifiers: [.command])

                if visibleEmail.isMutedSender == true {
                    Button { Task { await unmuteSender() } } label: {
                        Label("Unmute Sender", systemImage: "bell")
                    }
                } else {
                    Button { Task { await muteSender() } } label: {
                        Label("Mute Sender", systemImage: "bell.slash")
                    }
                }

                Divider()

                if visibleEmail.isManualPrioritySender {
                    Button { Task { await removeImportantSender() } } label: {
                        Label("Remove Important Sender", systemImage: "bolt.slash")
                    }
                } else {
                    Button { Task { await markImportantSender() } } label: {
                        Label("Mark Sender Important", systemImage: "bolt.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .disabled(isPerformingAction)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowLabel(
                text: "Dispatch",
                trailing: visibleEmail.receivedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()),
                accent: Theme.Palette.accent
            )

            Text(visibleEmail.subject)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(2)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                SenderLogoView(email: visibleEmail, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(visibleEmail.senderDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(visibleEmail.senderEmailAddress)
                        .font(Theme.Typography.mono(11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private var deliveryDetailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeliveryDetailRow(
                title: "From",
                primary: visibleEmail.senderEmailAddress,
                secondary: visibleEmail.senderDisplayName
            )
            .dossierDivider()

            DeliveryDetailRow(
                title: "To",
                primary: toDisplayText,
                secondary: receivedAccountText
            )
            .dossierDivider()

            if let cc = visibleEmail.cc?.trimmingCharacters(in: .whitespacesAndNewlines), !cc.isEmpty {
                DeliveryDetailRow(title: "Cc", primary: cc, secondary: nil)
                    .dossierDivider()
            }

            if let bcc = visibleEmail.bcc?.trimmingCharacters(in: .whitespacesAndNewlines), !bcc.isEmpty {
                DeliveryDetailRow(title: "Bcc", primary: bcc, secondary: nil)
                    .dossierDivider()
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 18, height: 1.5)
                Text("Editor's Summary".uppercased())
                    .font(Theme.Typography.eyebrow())
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.accent)

                Spacer()

                if isLoadingSummary {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text("AI · GPT")
                        .font(Theme.Typography.mono(9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            SummaryContentView(summary: summary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Theme.Palette.surfaceMuted)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 2)
        }
    }

    @ViewBuilder
    private var threadSection: some View {
        let messages = threadEmails.isEmpty ? [visibleEmail] : threadEmails
        VStack(alignment: .leading, spacing: 22) {
            EyebrowLabel(
                text: messages.count > 1 ? "Conversation — \(messages.count) entries" : "Body",
                accent: Theme.Palette.accent
            )

            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Palette.border)
                        .frame(height: 0.5)
                        .padding(.vertical, 4)
                }
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

    private func togglePin() async {
        await performAction {
            if visibleEmail.isPinned == true {
                try await apiClient.unpinEmail(id: visibleEmail.id, accountId: accountId)
            } else {
                try await apiClient.pinEmail(id: visibleEmail.id, accountId: accountId)
            }
        }

        if loadedEmail != nil {
            loadedEmail?.isPinned = !(visibleEmail.isPinned == true)
        } else {
            loadedEmail = email
            loadedEmail?.isPinned = !(email.isPinned == true)
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

    private func muteSender() async {
        var mutedSenderEmail: String?

        await performAction {
            mutedSenderEmail = try await apiClient.muteSender(id: visibleEmail.id, accountId: accountId)
        }

        if errorMessage == nil, let mutedSenderEmail {
            applyMutedSenderChange(senderEmail: mutedSenderEmail, isMuted: true)
        }
    }

    private func unmuteSender() async {
        guard let resolvedAccountId = visibleEmail.accountId ?? accountId else {
            errorMessage = "Could not unmute sender."
            return
        }

        let senderEmail = visibleEmail.senderEmailAddress
        await performAction {
            try await apiClient.unmuteSender(accountId: resolvedAccountId, senderEmail: senderEmail)
        }

        if errorMessage == nil {
            applyMutedSenderChange(senderEmail: senderEmail, isMuted: false)
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

    private func applyMutedSenderChange(senderEmail: String, isMuted: Bool) {
        if loadedEmail == nil {
            loadedEmail = email
        }

        loadedEmail?.isMutedSender = isMuted
        onMutedSenderChanged?(senderEmail.lowercased(), isMuted)
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
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title.uppercased())
                .font(Theme.Typography.mono(10, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(primary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                if let secondary, !secondary.isEmpty, secondary.caseInsensitiveCompare(primary) != .orderedSame {
                    Text(secondary)
                        .font(Theme.Typography.mono(10, weight: .medium))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
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
                HStack(spacing: 12) {
                    Image(systemName: attachmentIcon(for: attachment.mimeType))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.background)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.Palette.accent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(detailText.uppercased())
                            .font(Theme.Typography.mono(9, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .overlay(
                    Rectangle()
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SenderLogoView(email: email, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(email.sender)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(email.receivedAt, style: .date)
                        .font(Theme.Typography.mono(10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer()
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(height: 0.5)
            }

            let attachments = email.attachments ?? []
            if !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel(
                        text: "\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")",
                        accent: Theme.Palette.accent
                    )

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
                .padding(.bottom, 4)
            }

            EmailHTMLView(
                html: email.htmlBody,
                plainText: email.body ?? email.snippet
            )
        }
        .padding(.vertical, 4)
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
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineSpacing(4)
                    .textSelection(.enabled)

                if let action = cleanedSummary.action {
                    HStack(alignment: .top, spacing: 10) {
                        Text("ACTION")
                            .font(Theme.Typography.mono(9, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(Theme.Palette.accent)
                            .padding(.top, 3)

                        Text(action)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineSpacing(2)
                    }
                    .padding(.top, 4)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.Palette.border)
                            .frame(height: 0.5)
                    }
                }
            }
        } else {
            Text("Composing summary…".uppercased())
                .font(Theme.Typography.mono(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
