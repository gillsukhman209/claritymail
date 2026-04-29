//
//  Email.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation

struct Email: Identifiable, Hashable, Codable {
    let id: String
    let threadId: String
    let subject: String
    let sender: String
    let snippet: String
    let receivedAt: Date
    var isRead: Bool
    var isStarred: Bool
    var body: String?

    var senderEmailAddress: String {
        if let start = sender.lastIndex(of: "<"),
           let end = sender.lastIndex(of: ">"),
           start < end {
            return String(sender[sender.index(after: start)..<end])
        }

        return sender
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadId
        case subject
        case sender
        case snippet
        case receivedAt
        case isRead
        case isStarred
        case body
    }
}
