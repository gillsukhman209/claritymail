//
//  LoginView.swift
//  ClarityMail
//
//  Editorial sign-in cover.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var session: SessionStore
    @Environment(\.openURL) private var openURL

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMMM d · yyyy"
        return formatter.string(from: .now).uppercased()
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            // Whispered warm wash anchored to the top corner.
            Theme.Gradients.ambient
                .ignoresSafeArea()
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                    .padding(.bottom, 18)

                Rectangle()
                    .fill(Theme.Palette.borderStrong)
                    .frame(height: 1)

                Spacer(minLength: 0)

                hero
                    .padding(.horizontal, 32)

                Spacer(minLength: 0)

                actions
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                if let errorMessage = session.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text(errorMessage.uppercased())
                            .font(Theme.Typography.mono(11, weight: .semibold))
                            .tracking(1.2)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)
                    .transition(.opacity)
                }

                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(height: 0.5)

                footer
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
            }
            .frame(maxWidth: 720, maxHeight: .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: session.pendingAuthURL) {
            guard let url = session.pendingAuthURL else { return }
            openURL(url)
        }
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.textPrimary)
                    .frame(width: 32, height: 32)
                Text("CM")
                    .font(.system(size: 11, weight: .black, design: .serif))
                    .tracking(0.6)
                    .foregroundStyle(Theme.Palette.background)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ClarityMail")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Edition · The Daily Inbox".uppercased())
                    .font(Theme.Typography.mono(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer()

            Text(todayLabel)
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            EyebrowLabel(text: "Volume 1 — Issue 01", accent: Theme.Palette.accent)

            Text("An inbox\nthat reads itself.")
                .font(.system(size: 64, weight: .bold, design: .serif).italic())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(-4)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Connect a Gmail account and ClarityMail begins composing daily briefs, surfacing what matters, and dispatching the rest. No effort, no noise.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
                .padding(.bottom, 14)

            HStack(alignment: .center, spacing: 14) {
                Button {
                    Task { await session.signInWithGoogle() }
                } label: {
                    HStack(spacing: 9) {
                        Text("Continue with Google")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .heavy))
                    }
                }
                .buttonStyle(AuroraPrimaryButtonStyle())

                Button {
                    Task { await session.refreshAuthStatus() }
                } label: {
                    Text("I've finished signing in")
                }
                .buttonStyle(AuroraSecondaryButtonStyle())

                Spacer()

                Spacer(minLength: 0)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10, weight: .heavy))
                Text("ENCRYPTED IN TRANSIT")
                    .tracking(1.6)
            }

            Rectangle()
                .fill(Theme.Palette.border)
                .frame(width: 0.5, height: 12)

            Text("PRIVATE BY DEFAULT")
                .tracking(1.6)

            Spacer()

            Text("© CLARITYMAIL")
                .tracking(1.6)
        }
        .font(Theme.Typography.mono(9, weight: .semibold))
        .foregroundStyle(Theme.Palette.textTertiary)
    }
}
