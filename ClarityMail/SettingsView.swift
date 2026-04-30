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
    @State private var isSavingBrief = false
    @State private var isGeneratingBrief = false
    @State private var errorMessage: String?
    @State private var briefSettings = MorningBriefSettings.default
    @State private var briefTime = SettingsView.date(from: MorningBriefSettings.default.briefTime)
    @State private var latestBrief: MorningBrief?

    private let apiClient = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sendingSection
                    morningBriefSection
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
        .task {
            await loadMorningBrief()
        }
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

    private var morningBriefSection: some View {
        SettingsCard(title: "Morning Brief", systemImage: "sunrise.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enabled", isOn: $briefSettings.enabled)
                    .toggleStyle(.switch)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Brief time")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("For testing, set this near the current time and keep the app open.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }

                    Spacer()

                    DatePicker("", selection: $briefTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: briefTime) {
                            briefSettings.briefTime = Self.timeString(from: briefTime)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lookback window")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    HStack(spacing: 8) {
                        ForEach([10, 12, 14, 16, 20], id: \.self) { hours in
                            Button {
                                briefSettings.lookbackHours = hours
                            } label: {
                                Text("\(hours)h")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(briefSettings.lookbackHours == hours ? .white : Theme.Palette.textSecondary)
                                    .frame(width: 48, height: 30)
                                    .background(
                                        Capsule()
                                            .fill(briefSettings.lookbackHours == hours ? Theme.Palette.accent : Theme.Palette.surfaceElevated.opacity(0.72))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Toggle("Unread emails only", isOn: $briefSettings.unreadOnly)
                    .toggleStyle(.switch)
                Toggle("Only notify if important emails exist", isOn: $briefSettings.onlyNotifyIfImportant)
                    .toggleStyle(.switch)

                HStack(spacing: 10) {
                    Button {
                        Task { await saveMorningBriefSettings() }
                    } label: {
                        Label(isSavingBrief ? "Saving" : "Save", systemImage: "checkmark")
                    }
                    .buttonStyle(SettingsActionButtonStyle(isPrimary: false))
                    .disabled(isSavingBrief || isGeneratingBrief)

                    Button {
                        Task { await generateTestBrief() }
                    } label: {
                        Label(isGeneratingBrief ? "Generating" : "Generate Test Brief", systemImage: "sparkles")
                    }
                    .buttonStyle(SettingsActionButtonStyle(isPrimary: true))
                    .disabled(isSavingBrief || isGeneratingBrief)
                }

                if let latestBrief {
                    MorningBriefPreview(brief: latestBrief)
                        .padding(.top, 4)
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

    private func loadMorningBrief() async {
        do {
            briefSettings = try await apiClient.morningBriefSettings()
            briefTime = Self.date(from: briefSettings.briefTime)
            latestBrief = try await apiClient.latestMorningBrief()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load Morning Brief settings."
        }
    }

    private func saveMorningBriefSettings() async {
        isSavingBrief = true
        defer { isSavingBrief = false }

        do {
            briefSettings.briefTime = Self.timeString(from: briefTime)
            briefSettings.includeNewsletters = false
            briefSettings = try await apiClient.saveMorningBriefSettings(briefSettings)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save Morning Brief settings."
        }
    }

    private func generateTestBrief() async {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        do {
            await saveMorningBriefSettings()
            let result = try await apiClient.runMorningBrief()
            latestBrief = result.brief
            if result.shouldNotify {
                await NotificationManager.shared.notifyMorningBrief(result.brief)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not generate Morning Brief."
        }
    }

    private static func date(from value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 9
        components.minute = parts.dropFirst().first ?? 0
        return Calendar.current.date(from: components) ?? .now
    }

    private static func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
    }
}

private struct MorningBriefPreview: View {
    let brief: MorningBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest brief")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(brief.totalUnread) unread scanned • \(brief.ignoredCount) ignored")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer()

                Text("\(brief.actionableCount) important")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accentSoft)
            }

            briefGroup("Important", items: brief.summary.important)
            briefGroup("Needs Action", items: brief.summary.needsAction)
            briefGroup("Deadlines", items: brief.summary.deadlines)
            briefGroup("FYI", items: brief.summary.fyi)

            if brief.summary.important.isEmpty,
               brief.summary.needsAction.isEmpty,
               brief.summary.deadlines.isEmpty,
               brief.summary.fyi.isEmpty {
                Text("Nothing important found in the selected window.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Palette.background.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
    }

    private func briefGroup(_ title: String, items: [MorningBriefItem]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    ForEach(items.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.subject)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)
                            Text(item.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isPrimary ? .white : Theme.Palette.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isPrimary ? Theme.Palette.accent : Theme.Palette.surfaceElevated.opacity(0.72))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
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
