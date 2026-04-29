//
//  Email+Preview.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation

extension Email {
    static let previewEmails: [Email] = [
        Email(
            accountId: nil,
            accountEmail: nil,
            id: "preview-1",
            threadId: "thread-1",
            subject: "Welcome to ClarityMail",
            sender: "ClarityMail",
            snippet: "Your Gmail inbox and AI tools will appear here once Google auth is connected.",
            receivedAt: .now,
            isRead: false,
            isStarred: false,
            body: "Your Gmail inbox and AI tools will appear here once Google auth is connected."
        ),
        Email(
            accountId: nil,
            accountEmail: nil,
            id: "preview-2",
            threadId: "thread-2",
            subject: "Daily digest preview",
            sender: "AI Summary",
            snippet: "Important emails, action items, and reply suggestions will be summarized here.",
            receivedAt: .now.addingTimeInterval(-3600),
            isRead: true,
            isStarred: true,
            body: "Important emails, action items, and reply suggestions will be summarized here."
        )
    ]
}
