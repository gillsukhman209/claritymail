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
                VStack(alignment: .leading, spacing: 28) {
                    sendingSection
                    morningBriefSection
                    accountsSection

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .heavy))
                            Text(errorMessage.uppercased())
                                .font(Theme.Typography.mono(11, weight: .semibold))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Theme.Palette.danger)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }
        }
        .frame(width: 600, height: 520)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 36, x: 0, y: 18)
        .task {
            await loadMorningBrief()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 14, height: 1.5)
                Text("Configuration".uppercased())
                    .font(Theme.Typography.eyebrow(11))
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(AuroraPrimaryButtonStyle(compact: true))
            }

            Text("Settings")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Sending behavior · Morning brief · Connected accounts".uppercased())
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().fill(Theme.Palette.borderStrong).frame(height: 1),
            alignment: .bottom
        )
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

                HStack(spacing: 0) {
                    ForEach(Array([0, 5, 10, 15, 30].enumerated()), id: \.element) { index, seconds in
                        Button {
                            withAnimation(Theme.Motion.snappy) { undoSendDelaySeconds = seconds }
                        } label: {
                            Text(seconds == 0 ? "OFF" : "\(seconds)S")
                                .font(Theme.Typography.mono(11, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(undoSendDelaySeconds == seconds ? Theme.Palette.background : Theme.Palette.textSecondary)
                                .frame(width: 56, height: 32)
                                .background(undoSendDelaySeconds == seconds ? Theme.Palette.textPrimary : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            if index < 4 {
                                Rectangle()
                                    .fill(Theme.Palette.border)
                                    .frame(width: 0.5)
                            }
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                )
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

                    HStack(spacing: 0) {
                        ForEach(Array([10, 12, 14, 16, 20].enumerated()), id: \.element) { index, hours in
                            Button {
                                withAnimation(Theme.Motion.snappy) { briefSettings.lookbackHours = hours }
                            } label: {
                                Text("\(hours)H")
                                    .font(Theme.Typography.mono(11, weight: .heavy))
                                    .tracking(1.4)
                                    .foregroundStyle(briefSettings.lookbackHours == hours ? Theme.Palette.background : Theme.Palette.textSecondary)
                                    .frame(width: 52, height: 32)
                                    .background(briefSettings.lookbackHours == hours ? Theme.Palette.textPrimary : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .trailing) {
                                if index < 4 {
                                    Rectangle()
                                        .fill(Theme.Palette.border)
                                        .frame(width: 0.5)
                                }
                            }
                        }
                    }
                    .overlay(
                        Rectangle()
                            .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                    )
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
        .background(Theme.Palette.surfaceMuted)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(width: 2)
        }
    }

    private func briefGroup(_ title: String, items: [MorningBriefItem]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(Theme.Typography.mono(10, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Palette.accent)

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
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .tracking(0.4)
            .foregroundStyle(isPrimary ? Theme.Palette.background : Theme.Palette.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(isPrimary ? Theme.Palette.textPrimary : Theme.Palette.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : Theme.Palette.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
            EyebrowLabel(text: title, accent: Theme.Palette.accent)
            content
        }
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
    }
}

private struct AccountSettingsRow: View {
    let account: GmailAccount
    let isWorking: Bool
    let onLogout: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.background)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Palette.textPrimary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("GMAIL · CONNECTED")
                    .font(Theme.Typography.mono(9, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            Spacer()

            Button(role: .destructive, action: onLogout) {
                Text("LOG OUT")
                    .font(Theme.Typography.mono(10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(
                        Rectangle().strokeBorder(Theme.Palette.danger, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
    }

    private var initials: String {
        let name = account.email.split(separator: "@").first.map(String.init) ?? "G"
        return String(name.prefix(1)).uppercased()
    }
}
