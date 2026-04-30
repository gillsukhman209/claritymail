//
//  SettingsView.swift
//  ClarityMail
//

import SwiftUI

struct SettingsView: View {
    let accounts: [GmailAccount]
    let onAccountsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("undoSendDelaySeconds") private var undoSendDelaySeconds = 10
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sendingSection
                    accountsSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Palette.warm)
                            .padding(.top, 2)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 560, height: 460)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 16)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text("Sending and connected Gmail accounts")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Theme.Palette.accent)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Theme.Palette.surface.opacity(0.7))
    }

    private var sendingSection: some View {
        SettingsCard(title: "Sending", systemImage: "paperplane.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Undo Send")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(undoSendDelaySeconds == 0 ? "Send immediately" : "Wait \(undoSendDelaySeconds) seconds before sending")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach([0, 5, 10, 15, 30], id: \.self) { seconds in
                        Button {
                            undoSendDelaySeconds = seconds
                        } label: {
                            Text(seconds == 0 ? "Off" : "\(seconds)s")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(undoSendDelaySeconds == seconds ? .white : Theme.Palette.textSecondary)
                                .frame(width: 54, height: 30)
                                .background(
                                    Capsule()
                                        .fill(undoSendDelaySeconds == seconds ? Theme.Palette.accent : Theme.Palette.surfaceElevated.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var accountsSection: some View {
        SettingsCard(title: "Accounts", systemImage: "person.crop.circle.badge.checkmark") {
            VStack(spacing: 10) {
                if accounts.isEmpty {
                    Text("No Gmail accounts connected.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(accounts) { account in
                        AccountSettingsRow(account: account, isWorking: isWorking) {
                            Task { await logout(account) }
                        }
                    }
                }
            }
        }
    }

    private func logout(_ account: GmailAccount) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await apiClient.logoutAccount(id: account.id)
            errorMessage = nil
            onAccountsChanged()
        } catch {
            errorMessage = "Could not log out \(account.email)."
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentSoft)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.Palette.accent.opacity(0.14)))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }
}

private struct AccountSettingsRow: View {
    let account: GmailAccount
    let isWorking: Bool
    let onLogout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.Palette.accentDeep))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("Gmail")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer()

            Button(role: .destructive, action: onLogout) {
                Text("Log Out")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.Palette.warm.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.warm)
            .disabled(isWorking)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Palette.surfaceElevated.opacity(0.58))
        )
    }

    private var initials: String {
        let name = account.email.split(separator: "@").first.map(String.init) ?? "G"
        return String(name.prefix(1)).uppercased()
    }
}
