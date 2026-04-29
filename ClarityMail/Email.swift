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

    enum CodingKeys: String, CodingKey {
        case id
        case threadId
        case subject
        case sender
        case snippet
        case receivedAt
        case isRead
        case isStarred
    }
}
