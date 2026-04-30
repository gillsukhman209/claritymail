//
//  APIClient.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation

struct APIClient {
    var baseURL = URL(string: "http://localhost:3000")!

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

    func emails(accountId: String? = nil, searchQuery: String? = nil, folder: MailboxFolder = .inbox) async throws -> [Email] {
        let response: EmailsResponse = try await get(
            "/emails",
            queryItems: accountQueryItems(accountId: accountId, searchQuery: searchQuery, folder: folder)
        )
        return response.emails
    }

    func email(id: Email.ID, accountId: String? = nil) async throws -> Email {
        let response: EmailResponse = try await get(
            "/emails/\(id)",
            queryItems: accountQueryItems(accountId: accountId)
        )
        return response.email
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

    func sendEmail(to: String, subject: String, body: String, accountId: String? = nil) async throws {
        try await postJSON("/send", body: SendEmailRequest(accountId: accountId, to: to, subject: subject, body: body))
    }

    func reply(to email: Email, body: String, accountId: String? = nil) async throws {
        try await postJSON(
            "/reply",
            body: ReplyEmailRequest(
                accountId: accountId,
                to: email.senderEmailAddress,
                subject: email.subject,
                body: body,
                threadId: email.threadId
            )
        )
    }

    func reply(to: String, subject: String, body: String, threadId: String, accountId: String? = nil) async throws {
        try await postJSON(
            "/reply",
            body: ReplyEmailRequest(
                accountId: accountId,
                to: to,
                subject: subject,
                body: body,
                threadId: threadId
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

    private func accountQueryItems(accountId: String?, searchQuery: String? = nil, folder: MailboxFolder? = nil) -> [URLQueryItem] {
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
        return items
    }
}

enum MailboxFolder: String, CaseIterable, Identifiable {
    case inbox
    case sent
    case archive
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .archive: return "Archive"
        case .trash: return "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .sent: return "paperplane.fill"
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
}

private struct EmailResponse: Decodable {
    let email: Email
}

private struct EmailSummaryResponse: Decodable {
    let summary: String
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

private struct SendEmailRequest: Encodable {
    let accountId: String?
    let to: String
    let subject: String
    let body: String
}

private struct ReplyEmailRequest: Encodable {
    let accountId: String?
    let to: String
    let subject: String
    let body: String
    let threadId: String
}

private struct AccountRequest: Encodable {
    let accountId: String?
}

enum APIError: Error {
    case badResponse
}
