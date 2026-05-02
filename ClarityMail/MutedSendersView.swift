import SwiftUI

struct MutedSendersView: View {
    let accountId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var mutedSenders: [MutedSender] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .heavy))
                            Text(errorMessage.uppercased())
                                .font(Theme.Typography.mono(11, weight: .semibold))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Theme.Palette.warm)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle().strokeBorder(Theme.Palette.warm.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.bottom, 14)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if mutedSenders.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            EyebrowLabel(
                                text: "Muted · \(mutedSenders.count) sender\(mutedSenders.count == 1 ? "" : "s")",
                                accent: Theme.Palette.warm
                            )
                            .padding(.bottom, 12)

                            ForEach(mutedSenders) { sender in
                                MutedSenderRow(sender: sender) {
                                    Task { await unmute(sender) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }
        }
        .mutedSendersSheetFrame()
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 36, x: 0, y: 18)
        .task { await loadMutedSenders() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 14, height: 1.5)
                Text("Notifications".uppercased())
                    .font(Theme.Typography.eyebrow(11))
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(AuroraPrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.cancelAction)
            }

            Text("Muted Senders")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Emails still arrive. Notifications stay quiet.".uppercased())
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.Palette.textPrimary)
                    .frame(width: 44, height: 44)
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.Palette.background)
            }

            Text("No Muted Senders")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Muted senders will appear here.".uppercased())
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadMutedSenders() async {
        isLoading = true
        defer { isLoading = false }

        do {
            mutedSenders = try await apiClient.mutedSenders(accountId: accountId)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load muted senders."
        }
    }

    private func unmute(_ sender: MutedSender) async {
        do {
            try await apiClient.unmuteSender(accountId: sender.accountId, senderEmail: sender.senderEmail)
            mutedSenders.removeAll { $0.id == sender.id }
            errorMessage = nil
        } catch {
            errorMessage = "Could not unmute sender."
        }
    }
}

private extension View {
    @ViewBuilder
    func mutedSendersSheetFrame() -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self.frame(minWidth: 560, minHeight: 440)
        #endif
    }
}

private struct MutedSenderRow: View {
    let sender: MutedSender
    let onUnmute: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("MUTED")
                .font(Theme.Typography.mono(9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.warm)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    Rectangle().strokeBorder(Theme.Palette.warm, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sender.senderName.isEmpty ? sender.senderEmail : sender.senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(sender.senderEmail)
                    .font(Theme.Typography.mono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Unmute", action: onUnmute)
                .buttonStyle(AuroraSecondaryButtonStyle(compact: true))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
    }
}
