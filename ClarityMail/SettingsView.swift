//
//  SettingsView.swift
//  ClarityMail
//

import SwiftUI

struct SettingsView: View {
    let accounts: [GmailAccount]
    let onAddAccount: () -> Void
    let onAccountsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("undoSendDelaySeconds") private var undoSendDelaySeconds = 10
    @AppStorage(AppearanceStorage.key) private var appearanceRaw: String = AppearancePreference.system.rawValue
    @AppStorage(AppNotificationSound.storageKey) private var selectedNotificationSoundRaw = AppNotificationSound.chime.rawValue
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
                    appearanceSection
                    sendingSection
                    notificationsSection
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
        .settingsSheetFrame()
        .background(Theme.Palette.background)
        .settingsSheetChrome()
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

            Text("Sending behavior · Notifications · Connected accounts".uppercased())
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

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var appearanceSection: some View {
        SettingsCard(title: "Appearance", systemImage: "circle.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Theme")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Match the system, or pick a fixed canvas. Light mode is hand-tuned bone paper; dark is deep ink.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    ForEach(AppearancePreference.allCases) { option in
                        AppearanceOptionTile(
                            option: option,
                            isSelected: appearance == option
                        ) {
                            withAnimation(Theme.Motion.snappy) {
                                appearanceRaw = option.rawValue
                            }
                        }
                    }
                }
            }
        }
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

                Button(action: onAddAccount) {
                    Label("ADD GMAIL ACCOUNT", systemImage: "plus")
                        .font(Theme.Typography.mono(10, weight: .heavy))
                        .tracking(1.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().strokeBorder(Theme.Palette.borderStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    private var selectedNotificationSound: AppNotificationSound {
        AppNotificationSound(rawValue: selectedNotificationSoundRaw) ?? .chime
    }

    private var notificationsSection: some View {
        SettingsCard(title: "Notifications", systemImage: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New email sound")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Pick a sound for new mail notifications. Sent mail uses its own confirmation sound.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(AppNotificationSound.allCases.enumerated()), id: \.element.id) { index, sound in
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(Theme.Motion.snappy) {
                                    selectedNotificationSoundRaw = sound.rawValue
                                }
                                Task { await NotificationManager.shared.syncRegisteredDeviceSound() }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedNotificationSound == sound ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(selectedNotificationSound == sound ? Theme.Palette.accent : Theme.Palette.textTertiary)

                                    Text(sound.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.textPrimary)

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                AppSoundPlayer.shared.playNewEmailPreview(sound)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(Theme.Palette.accent)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play \(sound.title)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if index < AppNotificationSound.allCases.count - 1 {
                                Rectangle()
                                    .fill(Theme.Palette.border)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                )

                Button {
                    AppSoundPlayer.shared.playSentMail()
                } label: {
                    Label("Preview Sent Sound", systemImage: "paperplane.fill")
                }
                .buttonStyle(SettingsActionButtonStyle(isPrimary: false))
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

                ViewThatFits {
                    HStack(spacing: 10) {
                        morningBriefActions
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        morningBriefActions
                    }
                }

                if let latestBrief {
                    MorningBriefPreview(brief: latestBrief)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var morningBriefActions: some View {
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

private extension View {
    @ViewBuilder
    func settingsSheetFrame() -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self.frame(width: 600, height: 520)
        #endif
    }

    @ViewBuilder
    func settingsSheetChrome() -> some View {
        #if os(iOS)
        self.overlay(
            Rectangle()
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        #else
        self
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
        #endif
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
                Text(account.isDisconnected ? "GMAIL · RECONNECT NEEDED" : "GMAIL · CONNECTED")
                    .font(Theme.Typography.mono(9, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(account.isDisconnected ? Theme.Palette.danger : Theme.Palette.textTertiary)
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

private struct AppearanceOptionTile: View {
    let option: AppearancePreference
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                preview

                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 11, weight: .heavy))
                    Text(option.label.uppercased())
                        .font(Theme.Typography.mono(10, weight: .heavy))
                        .tracking(1.6)
                }
                .foregroundStyle(isSelected ? Theme.Palette.background : Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Rectangle().fill(isSelected ? Theme.Palette.textPrimary : Color.clear)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.Palette.border)
                        .frame(height: 0.5)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Palette.textPrimary : Theme.Palette.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack(alignment: .topLeading) {
            // Mini "page" preview — adapts to its own forced color scheme so users
            // see what each mode actually looks like without leaving Settings.
            switch option {
            case .system:
                HStack(spacing: 0) {
                    miniPage(for: .light)
                    miniPage(for: .dark)
                }
            case .light:
                miniPage(for: .light)
            case .dark:
                miniPage(for: .dark)
            }
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func miniPage(for scheme: ColorScheme) -> some View {
        let bg: Color = scheme == .light
            ? Color(red: 0.961, green: 0.949, blue: 0.922)
            : Color(red: 0.055, green: 0.051, blue: 0.043)
        let surface: Color = scheme == .light
            ? Color(red: 0.996, green: 0.992, blue: 0.980)
            : Color(red: 0.094, green: 0.090, blue: 0.082)
        let ink: Color = scheme == .light
            ? Color(red: 0.063, green: 0.055, blue: 0.047)
            : Color(red: 0.937, green: 0.925, blue: 0.890)
        let muted: Color = scheme == .light
            ? Color(red: 0.541, green: 0.514, blue: 0.467)
            : Color(red: 0.604, green: 0.580, blue: 0.541)
        let saffron = Color(red: 0.761, green: 0.255, blue: 0.047)

        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Rectangle().fill(saffron).frame(width: 8, height: 1.5)
                    Rectangle().fill(ink.opacity(0.8)).frame(width: 18, height: 2)
                }
                Rectangle().fill(ink).frame(width: 38, height: 4)
                Rectangle().fill(muted).frame(width: 28, height: 2)

                Rectangle()
                    .fill(surface)
                    .frame(height: 14)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 3) {
                            Circle().fill(saffron).frame(width: 5, height: 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Rectangle().fill(ink).frame(width: 22, height: 1.5)
                                Rectangle().fill(muted).frame(width: 32, height: 1)
                            }
                        }
                        .padding(.leading, 4)
                    }
                    .overlay(
                        Rectangle().strokeBorder(ink.opacity(0.10), lineWidth: 0.5)
                    )
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
