import SwiftUI

struct BlockedSendersView: View {
    let accountId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var blockedSenders: [BlockedSender] = []
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
                        .foregroundStyle(Theme.Palette.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle().strokeBorder(Theme.Palette.danger.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.bottom, 14)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if blockedSenders.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            EyebrowLabel(
                                text: "Banned · \(blockedSenders.count) sender\(blockedSenders.count == 1 ? "" : "s")",
                                accent: Theme.Palette.danger
                            )
                            .padding(.bottom, 12)

                            ForEach(blockedSenders) { sender in
                                BlockedSenderRow(sender: sender) {
                                    Task { await unblock(sender) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }
        }
        .blockedSendersSheetFrame()
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 36, x: 0, y: 18)
        .task { await loadBlockedSenders() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 14, height: 1.5)
                Text("Editorial".uppercased())
                    .font(Theme.Typography.eyebrow(11))
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(AuroraPrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.cancelAction)
            }

            Text("Blocked Senders")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Unblock anyone to let their dispatches through.".uppercased())
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
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.Palette.background)
            }

            Text("No Blocked Senders")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Anyone you block will appear here.".uppercased())
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadBlockedSenders() async {
        isLoading = true
        defer { isLoading = false }

        do {
            blockedSenders = try await apiClient.blockedSenders(accountId: accountId)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load blocked senders."
        }
    }

    private func unblock(_ sender: BlockedSender) async {
        do {
            try await apiClient.unblockSender(accountId: sender.accountId, senderEmail: sender.senderEmail)
            blockedSenders.removeAll { $0.id == sender.id }
            errorMessage = nil
        } catch {
            errorMessage = "Could not unblock sender."
        }
    }
}

private extension View {
    @ViewBuilder
    func blockedSendersSheetFrame() -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self.frame(minWidth: 560, minHeight: 440)
        #endif
    }
}

private struct BlockedSenderRow: View {
    let sender: BlockedSender
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("BLOCKED")
                .font(Theme.Typography.mono(9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.danger)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    Rectangle().strokeBorder(Theme.Palette.danger, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sender.senderEmail)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(sender.accountEmail.uppercased())
                    .font(Theme.Typography.mono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Unblock", action: onUnblock)
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
