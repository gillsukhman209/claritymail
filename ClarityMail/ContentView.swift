//
//  ContentView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        Group {
            if session.isSignedIn {
                MailboxView(session: session)
            } else {
                LoginView(session: session)
            }
        }
        .task {
            await session.refreshAuthStatus()
        }
    }
}
