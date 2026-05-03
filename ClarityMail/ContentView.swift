//
//  ContentView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()
    @State private var hasCheckedAuth = false

    var body: some View {
        Group {
            if session.isSignedIn {
                MailboxView(session: session)
            } else if hasCheckedAuth {
                LoginView(session: session)
            } else {
                Theme.Palette.background
                    .ignoresSafeArea()
            }
        }
        .task {
            await session.refreshAuthStatus()
            hasCheckedAuth = true
        }
    }
}
