import SwiftUI

struct BlockedSendersView: View {
    let accountId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var blockedSenders: [BlockedSender] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocked Senders")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Text("Remove a sender to allow future emails back into your inbox.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.warm)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if blockedSenders.isEmpty {
                ContentUnavailableView(
                    "No Blocked Senders",
                    systemImage: "hand.raised",
                    description: Text("Blocked senders will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(blockedSenders) { sender in
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(Theme.Palette.accentSoft)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(sender.senderEmail)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.Palette.textPrimary)

                                Text(sender.accountEmail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }

                            Spacer()

                            Button("Unblock") {
                                Task { await unblock(sender) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 260)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .background(Theme.Palette.background)
        .task {
            await loadBlockedSenders()
        }
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
