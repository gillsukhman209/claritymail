//
//  APIClient.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation

struct APIClient {
    var baseURL = URL(string: "https://backend-five-henna-54.vercel.app")!

    func googleAuthURL() async throws -> URL {
        let response: GoogleAuthURLResponse = try await get("/auth/google/url")
        return response.url
    }

    func authStatus() async throws -> AuthStatus {
        try await get("/auth/status")
    }

    func accounts() async throws -> [GmailAccount] {
        let response: AccountsResponse = try await get("/auth/accounts")
        return response.accounts
    }

    func blockedSenders(accountId: String? = nil) async throws -> [BlockedSender] {
        let response: BlockedSendersResponse = try await get(
            "/blocked-senders",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return response.blockedSenders
    }

    func unblockSender(accountId: String, senderEmail: String) async throws {
        try await delete(
            "/blocked-senders",
            queryItems: [
                URLQueryItem(name: "accountId", value: accountId),
                URLQueryItem(name: "senderEmail", value: senderEmail)
            ]
        )
    }

    func logoutAccount(id: String) async throws {
        try await delete("/auth/accounts/\(id)")
    }

    func emails(
        accountId: String? = nil,
        searchQuery: String? = nil,
        folder: MailboxFolder = .inbox,
        pageToken: String? = nil
    ) async throws -> EmailPage {
        let response: EmailsResponse = try await get(
            "/emails",
            queryItems: accountQueryItems(accountId: accountId, searchQuery: searchQuery, folder: folder, pageToken: pageToken)
        )
        return EmailPage(emails: response.emails, nextPageToken: response.nextPageToken)
    }

    func email(id: Email.ID, accountId: String? = nil) async throws -> Email {
        let response: EmailResponse = try await get(
            "/emails/\(id)",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return response.email
    }

    func thread(id: String, accountId: String? = nil) async throws -> [Email] {
        let response: EmailsResponse = try await get(
            "/threads/\(id)",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return response.emails
    }

    func emailAttachment(messageId: Email.ID, attachmentId: String, accountId: String? = nil) async throws -> Data {
        let response: EmailAttachmentResponse = try await get(
            "/emails/\(messageId)/attachments/\(attachmentId)",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return try response.attachment.decodedData()
    }

    func archiveEmail(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/archive", queryItems: accountQueryItems(accountId: accountId))
    }

    func trashEmail(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/trash", queryItems: accountQueryItems(accountId: accountId))
    }

    func blockSender(id: Email.ID, accountId: String? = nil) async throws -> String {
        let response: BlockSenderResponse = try await postForResponse(
            "/emails/\(id)/block-sender",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return response.senderEmail
    }

    func markEmailRead(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/read", queryItems: accountQueryItems(accountId: accountId))
    }

    func markEmailUnread(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/unread", queryItems: accountQueryItems(accountId: accountId))
    }

    func starEmail(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/star", queryItems: accountQueryItems(accountId: accountId))
    }

    func unstarEmail(id: Email.ID, accountId: String? = nil) async throws {
        try await post("/emails/\(id)/unstar", queryItems: accountQueryItems(accountId: accountId))
    }

    func sendEmail(
        to: String,
        subject: String,
        body: String,
        htmlBody: String? = nil,
        accountId: String? = nil,
        attachments: [EmailAttachmentUpload] = []
    ) async throws {
        try await postJSON(
            "/send",
            body: SendEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                htmlBody: htmlBody,
                attachments: attachments
            )
        )
    }

    func createDraft(
        to: String,
        subject: String,
        body: String,
        htmlBody: String? = nil,
        accountId: String? = nil,
        threadId: String? = nil,
        attachments: [EmailAttachmentUpload] = []
    ) async throws -> DraftSaveResult {
        let response: DraftResponse = try await postJSONForResponse(
            "/drafts",
            body: DraftEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                htmlBody: htmlBody,
                threadId: threadId,
                attachments: attachments
            )
        )
        return response.draft
    }

    func updateDraft(
        draftId: String,
        to: String,
        subject: String,
        body: String,
        htmlBody: String? = nil,
        accountId: String? = nil,
        threadId: String? = nil,
        attachments: [EmailAttachmentUpload] = []
    ) async throws -> DraftSaveResult {
        let response: DraftResponse = try await putJSONForResponse(
            "/drafts/\(draftId)",
            body: DraftEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                htmlBody: htmlBody,
                threadId: threadId,
                attachments: attachments
            )
        )
        return response.draft
    }

    func sendDraft(
        draftId: String,
        to: String,
        subject: String,
        body: String,
        htmlBody: String? = nil,
        accountId: String? = nil,
        threadId: String? = nil,
        attachments: [EmailAttachmentUpload] = []
    ) async throws {
        try await postJSON(
            "/drafts/\(draftId)/send",
            body: DraftEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                htmlBody: htmlBody,
                threadId: threadId,
                attachments: attachments
            )
        )
    }

    func deleteDraft(draftId: String, accountId: String? = nil) async throws {
        try await delete("/drafts/\(draftId)", queryItems: accountQueryItems(accountId: accountId))
    }

    func reply(to email: Email, body: String, accountId: String? = nil, attachments: [EmailAttachmentUpload] = []) async throws {
        try await postJSON(
            "/reply",
            body: ReplyEmailRequest(
                accountId: accountId,
                to: email.senderEmailAddress,
                subject: email.subject,
                body: body,
                htmlBody: nil,
                threadId: email.threadId,
                attachments: attachments
            )
        )
    }

    func reply(
        to: String,
        subject: String,
        body: String,
        htmlBody: String? = nil,
        threadId: String,
        accountId: String? = nil,
        attachments: [EmailAttachmentUpload] = []
    ) async throws {
        try await postJSON(
            "/reply",
            body: ReplyEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                htmlBody: htmlBody,
                threadId: threadId,
                attachments: attachments
            )
        )
    }

    func startRealtimeSync(accountId: String? = nil) async throws {
        try await post("/gmail/watch", queryItems: accountQueryItems(accountId: accountId))
    }

    func summarizeEmail(id: Email.ID, accountId: String? = nil) async throws -> String {
        let response: EmailSummaryResponse = try await postJSONForResponse(
            "/emails/\(id)/summary",
            body: AccountRequest(accountId: accountId)
        )
        return response.summary
    }

    func morningBriefSettings() async throws -> MorningBriefSettings {
        let response: MorningBriefSettingsResponse = try await get("/morning-brief/settings")
        return response.settings
    }

    func saveMorningBriefSettings(_ settings: MorningBriefSettings) async throws -> MorningBriefSettings {
        let response: MorningBriefSettingsResponse = try await putJSONForResponse(
            "/morning-brief/settings",
            body: settings
        )
        return response.settings
    }

    func latestMorningBrief() async throws -> MorningBrief? {
        let response: MorningBriefLatestResponse = try await get("/morning-brief/latest")
        return response.brief
    }

    func runMorningBrief(accountId: String? = nil) async throws -> MorningBriefRunResponse {
        try await postJSONForResponse(
            "/morning-brief/run",
            body: AccountRequest(accountId: accountId)
        )
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = makeURL(path, queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ path: String, queryItems: [URLQueryItem] = []) async throws {
        let url = makeURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }
    }

    private func postForResponse<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = makeURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(_ path: String, queryItems: [URLQueryItem] = []) async throws {
        let url = makeURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }
    }

    private func putJSONForResponse<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        let url = makeURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func postJSON<T: Encodable>(_ path: String, body: T) async throws {
        let url = makeURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }
    }

    private func postJSONForResponse<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        let url = makeURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private func makeURL(_ path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func accountQueryItems(
        accountId: String?,
        searchQuery: String? = nil,
        folder: MailboxFolder? = nil,
        pageToken: String? = nil
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let accountId, !accountId.isEmpty {
            items.append(URLQueryItem(name: "accountId", value: accountId))
        }
        if let searchQuery, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "q", value: searchQuery))
        }
        if let folder {
            items.append(URLQueryItem(name: "folder", value: folder.rawValue))
        }
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return items
    }
}

enum MailboxFolder: String, CaseIterable, Identifiable {
    case inbox
    case sent
    case drafts
    case archive
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .archive: return "Archive"
        case .trash: return "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .sent: return "paperplane.fill"
        case .drafts: return "doc.text.fill"
        case .archive: return "archivebox.fill"
        case .trash: return "trash.fill"
        }
    }
}

private struct GoogleAuthURLResponse: Decodable {
    let url: URL
}

private struct EmailsResponse: Decodable {
    let emails: [Email]
    let nextPageToken: String?
}

private struct EmailResponse: Decodable {
    let email: Email
}

private struct EmailAttachmentResponse: Decodable {
    let attachment: EmailAttachmentPayload
}

private struct EmailAttachmentPayload: Decodable {
    let data: String
    let size: Int

    func decodedData() throws -> Data {
        var normalized = data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }

        guard let decoded = Data(base64Encoded: normalized) else {
            throw APIError.badResponse
        }

        return decoded
    }
}

private struct EmailSummaryResponse: Decodable {
    let summary: String
}

private struct MorningBriefSettingsResponse: Decodable {
    let settings: MorningBriefSettings
}

private struct MorningBriefLatestResponse: Decodable {
    let brief: MorningBrief?
}

struct MorningBriefRunResponse: Decodable {
    let brief: MorningBrief
    let shouldNotify: Bool
}

private struct BlockSenderResponse: Decodable {
    let senderEmail: String
}

private struct BlockedSendersResponse: Decodable {
    let blockedSenders: [BlockedSender]
}

private struct AccountsResponse: Decodable {
    let accounts: [GmailAccount]
}

struct EmailPage {
    let emails: [Email]
    let nextPageToken: String?
}

struct GmailAccount: Identifiable, Hashable, Decodable {
    let id: String
    let email: String
    let provider: String
}

struct AuthStatus: Decodable {
    let isSignedIn: Bool
    let email: String?
}

struct BlockedSender: Identifiable, Hashable, Decodable {
    let id: String
    let accountId: String
    let accountEmail: String
    let senderEmail: String
}

struct EmailAttachmentUpload: Encodable {
    let filename: String
    let mimeType: String
    let data: String
}

struct DraftSaveResult: Decodable {
    let id: String
    let messageId: String
    let threadId: String
}

struct MorningBriefSettings: Codable, Hashable {
    var enabled: Bool
    var briefTime: String
    var timeZone: String
    var lookbackHours: Int
    var unreadOnly: Bool
    var includeNewsletters: Bool
    var onlyNotifyIfImportant: Bool

    static let `default` = MorningBriefSettings(
        enabled: true,
        briefTime: "09:00",
        timeZone: "America/Los_Angeles",
        lookbackHours: 14,
        unreadOnly: true,
        includeNewsletters: false,
        onlyNotifyIfImportant: true
    )
}

struct MorningBrief: Identifiable, Hashable, Decodable {
    let id: String
    let windowStart: String
    let windowEnd: String
    let generatedAt: String
    let totalUnread: Int
    let ignoredCount: Int
    let settings: MorningBriefSettings
    let summary: MorningBriefSummary

    var actionableCount: Int {
        summary.important.count + summary.needsAction.count + summary.deadlines.count
    }

    var windowText: String {
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: windowStart),
              let end = formatter.date(from: windowEnd) else {
            return "Overnight unread emails"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        return "\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))"
    }
}

struct MorningBriefSummary: Hashable, Decodable {
    let important: [MorningBriefItem]
    let needsAction: [MorningBriefItem]
    let deadlines: [MorningBriefItem]
    let fyi: [MorningBriefItem]
    let ignored: [MorningBriefItem]
}

struct MorningBriefItem: Identifiable, Hashable, Decodable {
    let id: String
    let sender: String
    let subject: String
    let summary: String
    let action: String?
}

extension String {
    var cleanedBriefSubject: String {
        var value = self
        while value.localizedCaseInsensitiveContains("Fwd: ") || value.localizedCaseInsensitiveContains("Re: ") {
            if value.lowercased().hasPrefix("fwd: ") {
                value = String(value.dropFirst(5))
            } else if value.lowercased().hasPrefix("re: ") {
                value = String(value.dropFirst(4))
            } else {
                break
            }
        }
        return value
    }
}

extension Date {
    var emailRowDateText: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            formatter.dateFormat = "h:mm a"
            return "Today\n\(formatter.string(from: self))"
        }

        if calendar.isDateInYesterday(self) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday\n\(formatter.string(from: self))"
        }

        if calendar.component(.year, from: self) == calendar.component(.year, from: .now) {
            formatter.dateFormat = "MMM d\nh:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy\nh:mm a"
        }
        return formatter.string(from: self)
    }
}

private struct DraftResponse: Decodable {
    let draft: DraftSaveResult
}

private struct SendEmailRequest: Encodable {
    let accountId: String?
    let to: String
    let subject: String
    let body: String
    let htmlBody: String?
    let attachments: [EmailAttachmentUpload]
}

private struct ReplyEmailRequest: Encodable {
    let accountId: String?
    let to: String
    let subject: String
    let body: String
    let htmlBody: String?
    let threadId: String
    let attachments: [EmailAttachmentUpload]
}

private struct DraftEmailRequest: Encodable {
    let accountId: String?
    let to: String
    let subject: String
    let body: String
    let htmlBody: String?
    let threadId: String?
    let attachments: [EmailAttachmentUpload]
}

private struct AccountRequest: Encodable {
    let accountId: String?
}

enum APIError: Error {
    case badResponse
}
