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

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Theme.Gradients.orb)
                        .frame(width: proxy.size.width * 0.9, height: proxy.size.width * 0.9)
                        .blur(radius: 70)
                        .opacity(0.55)
                        .offset(x: proxy.size.width * 0.25, y: -proxy.size.width * 0.20)

                    Circle()
                        .fill(Theme.Palette.accent.opacity(0.40))
                        .frame(width: proxy.size.width * 0.55, height: proxy.size.width * 0.55)
                        .blur(radius: 90)
                        .offset(x: -proxy.size.width * 0.30, y: proxy.size.height * 0.30)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.Gradients.voiceButton)
                            .frame(width: 84, height: 84)
                            .shadow(color: Theme.Palette.accent.opacity(0.55), radius: 24, x: 0, y: 10)

                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white)
                    }

                    Text("ClarityMail")
                        .font(.system(size: 36, weight: .light))
                        .kerning(-0.5)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text("Your inbox, with intent.")
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
                        .background(Theme.Gradients.voiceButton)
                        .clipShape(Capsule())
                        .shadow(color: Theme.Palette.accent.opacity(0.4), radius: 16, x: 0, y: 8)
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
