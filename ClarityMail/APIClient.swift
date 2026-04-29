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
}

private struct GoogleAuthURLResponse: Decodable {
    let url: URL
}

private struct EmailsResponse: Decodable {
    let emails: [Email]
}

struct AuthStatus: Decodable {
    let isSignedIn: Bool
    let email: String?
}

enum APIError: Error {
    case badResponse
}
