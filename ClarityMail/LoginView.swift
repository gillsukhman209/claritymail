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
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.Gradients.primary)
                            .frame(width: 84, height: 84)

                        Image(systemName: "envelope.fill")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(.white)
                    }

                    Text("ClarityMail")
                        .font(.system(size: 36, weight: .light))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text("Your inbox, focused.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await session.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Sign in with Google")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.Gradients.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await session.refreshAuthStatus() }
                    } label: {
                        Text("I finished signing in")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        session.usePreviewSession()
                    } label: {
                        Text("Use Preview Inbox")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.warm)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
        .onChange(of: session.pendingAuthURL) {
            guard let url = session.pendingAuthURL else { return }
            openURL(url)
        }
    }
}
