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

    func emails() async throws -> [Email] {
        let response: EmailsResponse = try await get("/emails")
        return response.emails
    }

    func email(id: Email.ID) async throws -> Email {
        let response: EmailResponse = try await get("/emails/\(id)")
        return response.email
    }

    func archiveEmail(id: Email.ID) async throws {
        try await post("/emails/\(id)/archive")
    }

    func trashEmail(id: Email.ID) async throws {
        try await post("/emails/\(id)/trash")
    }

    func markEmailRead(id: Email.ID) async throws {
        try await post("/emails/\(id)/read")
    }

    func markEmailUnread(id: Email.ID) async throws {
        try await post("/emails/\(id)/unread")
    }

    func starEmail(id: Email.ID) async throws {
        try await post("/emails/\(id)/star")
    }

    func unstarEmail(id: Email.ID) async throws {
        try await post("/emails/\(id)/unstar")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appending(path: path)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badResponse
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

struct AuthStatus: Decodable {
    let isSignedIn: Bool
    let email: String?
}

enum APIError: Error {
    case badResponse
}
