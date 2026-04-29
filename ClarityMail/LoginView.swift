//
//  LoginView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("ClarityMail")
                    .font(.largeTitle.bold())

                Text("Sign in with Google to connect Gmail.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        await session.signInWithGoogle()
                    }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Use Preview Inbox") {
                    session.usePreviewSession()
                }
                .buttonStyle(.borderless)

                Button("I Finished Google Sign-In") {
                    Task {
                        await session.refreshAuthStatus()
                    }
                }
                .buttonStyle(.borderless)
            }
            .onChange(of: session.pendingAuthURL) {
                guard let url = session.pendingAuthURL else { return }
                openURL(url)
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Spacer()
        }
        .padding()
    }
}
