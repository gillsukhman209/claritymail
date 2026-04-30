//
//  Email.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation

struct Email: Identifiable, Hashable, Codable {
    let accountId: String?
    let accountEmail: String?
    let id: String
    let threadId: String
    let subject: String
    let sender: String
    let snippet: String
    let receivedAt: Date
    var isRead: Bool
    var isStarred: Bool
    var body: String?
    var htmlBody: String?

    var senderEmailAddress: String {
        if let start = sender.lastIndex(of: "<"),
           let end = sender.lastIndex(of: ">"),
           start < end {
            return String(sender[sender.index(after: start)..<end])
        }

        return sender
    }

    var senderLogoURLs: [URL] {
        let email = senderEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let domain = email.split(separator: "@").last else { return [] }

        let normalizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        let brandDomain = Self.brandDomain(from: normalizedDomain)

        let candidates = [
            "https://logo.clearbit.com/\(brandDomain)",
            "https://logo.clearbit.com/\(normalizedDomain)",
            "https://www.google.com/s2/favicons?domain=\(brandDomain)&sz=128",
            "https://www.google.com/s2/favicons?domain=\(normalizedDomain)&sz=128"
        ]

        return candidates.compactMap(URL.init(string:))
    }

    private static func brandDomain(from domain: String) -> String {
        let knownBrands = [
            "tiktok": "tiktok.com",
            "cargurus": "cargurus.com",
            "amazon": "amazon.com",
            "linkedin": "linkedin.com",
            "capitalone": "capitalone.com",
            "fedex": "fedex.com",
            "coinbase": "coinbase.com",
            "meta": "meta.com",
            "facebook": "facebook.com",
            "apple": "apple.com",
            "google": "google.com",
            "youtube": "youtube.com",
            "netflix": "netflix.com",
            "spotify": "spotify.com",
            "doordash": "doordash.com",
            "uber": "uber.com"
        ]

        for (needle, brandDomain) in knownBrands where domain.contains(needle) {
            return brandDomain
        }

        let ignoredPrefixes: Set<String> = [
            "mail",
            "email",
            "emails",
            "notification",
            "notifications",
            "notify",
            "noreply",
            "no-reply",
            "news",
            "newsletter",
            "message",
            "messages",
            "account",
            "accounts",
            "support",
            "info"
        ]

        let parts = domain.split(separator: ".").map(String.init)
        let usefulParts = parts.drop { ignoredPrefixes.contains($0) }

        if usefulParts.count >= 2 {
            return usefulParts.suffix(2).joined(separator: ".")
        }

        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }

        return domain
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case accountEmail
        case threadId
        case subject
        case sender
        case snippet
        case receivedAt
        case isRead
        case isStarred
        case body
        case htmlBody
    }
}
