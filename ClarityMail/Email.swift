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
    var draftId: String?
    let threadId: String
    let subject: String
    let sender: String
    var to: String?
    var cc: String? = nil
    var bcc: String? = nil
    let snippet: String
    let receivedAt: Date
    var isRead: Bool
    var isStarred: Bool
    var isPinned: Bool? = false
    var body: String?
    var htmlBody: String?
    var attachments: [EmailAttachment]?
    var priorityStatus: EmailPriorityStatus? = nil
    var prioritySource: EmailPrioritySource? = nil
    var priorityReason: String? = nil
    var isMutedSender: Bool? = false
    var isBlockedSender: Bool? = false

    var isPriority: Bool {
        priorityStatus == .important
    }

    var isManualPrioritySender: Bool {
        prioritySource == .manualSender
    }

    var senderEmailAddress: String {
        if let start = sender.lastIndex(of: "<"),
           let end = sender.lastIndex(of: ">"),
           start < end {
            return String(sender[sender.index(after: start)..<end])
        }

        return sender
    }

    var senderDisplayName: String {
        if let start = sender.lastIndex(of: "<") {
            let name = sender[..<start]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty {
                return name
            }
        }

        return senderEmailAddress
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
            "https://www.google.com/s2/favicons?domain=\(brandDomain)&sz=256",
            "https://www.google.com/s2/favicons?domain=\(normalizedDomain)&sz=256"
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
        case draftId
        case accountId
        case accountEmail
        case threadId
        case subject
        case sender
        case to
        case cc
        case bcc
        case snippet
        case receivedAt
        case isRead
        case isStarred
        case isPinned
        case body
        case htmlBody
        case attachments
        case priorityStatus
        case prioritySource
        case priorityReason
        case isMutedSender
        case isBlockedSender
    }
}

enum EmailPriorityStatus: String, Codable, Hashable {
    case important
    case normal
    case ignored
}

enum EmailPrioritySource: String, Codable, Hashable {
    case manualSender = "manual_sender"
    case ai
    case rules
    case gmail
}

struct EmailContact: Identifiable, Hashable {
    let email: String
    let name: String?

    var id: String { email.lowercased() }

    var displayName: String {
        guard let name, !name.isEmpty, name.caseInsensitiveCompare(email) != .orderedSame else {
            return email
        }
        return name
    }

    var subtitle: String? {
        displayName == email ? nil : email
    }

    static func contacts(from emails: [Email], accounts: [GmailAccount]) -> [EmailContact] {
        var contacts: [EmailContact] = []

        for account in accounts {
            contacts.append(EmailContact(email: account.email, name: "Me"))
        }

        for email in emails {
            contacts.append(EmailContact(email: email.senderEmailAddress, name: email.senderDisplayName))
            contacts.append(contentsOf: parseContacts(email.to))
            contacts.append(contentsOf: parseContacts(email.cc))
            contacts.append(contentsOf: parseContacts(email.bcc))
            if let accountEmail = email.accountEmail {
                contacts.append(EmailContact(email: accountEmail, name: "Me"))
            }
        }

        return deduped(contacts)
    }

    static func parseContacts(_ value: String?) -> [EmailContact] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        return value
            .split(whereSeparator: { ",;".contains($0) })
            .compactMap { rawValue in
                let raw = String(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }

                if let start = raw.lastIndex(of: "<"),
                   let end = raw.lastIndex(of: ">"),
                   start < end {
                    let email = String(raw[raw.index(after: start)..<end])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = raw[..<start]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return EmailContact(email: email, name: name.isEmpty ? nil : String(name))
                }

                if raw.contains("@") {
                    return EmailContact(email: raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")), name: nil)
                }

                return nil
            }
    }

    static func deduped(_ contacts: [EmailContact]) -> [EmailContact] {
        var seen = Set<String>()
        var result: [EmailContact] = []

        for contact in contacts {
            let normalized = contact.email
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard normalized.contains("@"), !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            result.append(
                EmailContact(
                    email: contact.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: contact.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

struct EmailAttachment: Identifiable, Hashable, Codable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
