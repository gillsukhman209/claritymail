import SwiftUI

struct HiddenSendersView: View {
    let accountId: String?
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hiddenSenders: [HiddenSender] = []
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
                    } else if hiddenSenders.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            EyebrowLabel(
                                text: "Hidden · \(hiddenSenders.count) sender\(hiddenSenders.count == 1 ? "" : "s")",
                                accent: Theme.Palette.textTertiary
                            )
                            .padding(.bottom, 12)

                            ForEach(hiddenSenders) { sender in
                                HiddenSenderRow(sender: sender) {
                                    Task { await unhide(sender) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }
        }
        .hiddenSendersSheetFrame()
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 36, x: 0, y: 18)
        .task { await loadHiddenSenders() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 14, height: 1.5)
                Text("Visibility".uppercased())
                    .font(Theme.Typography.eyebrow(11))
                    .tracking(2.4)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(AuroraPrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.cancelAction)
            }

            Text("Hidden Senders")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Hidden emails stay out of Inbox and notifications.".uppercased())
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
                Image(systemName: "eye")
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.Palette.background)
            }

            Text("No Hidden Senders")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("Hidden senders will appear here.".uppercased())
                .font(Theme.Typography.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadHiddenSenders() async {
        isLoading = true
        defer { isLoading = false }

        do {
            hiddenSenders = try await apiClient.hiddenSenders(accountId: accountId)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load hidden senders."
        }
    }

    private func unhide(_ sender: HiddenSender) async {
        do {
            try await apiClient.unhideSender(accountId: sender.accountId, senderEmail: sender.senderEmail)
            hiddenSenders.removeAll { $0.id == sender.id }
            onChanged()
            errorMessage = nil
        } catch {
            errorMessage = "Could not unhide sender."
        }
    }
}

private extension View {
    @ViewBuilder
    func hiddenSendersSheetFrame() -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self.frame(minWidth: 560, minHeight: 440)
        #endif
    }
}

private struct HiddenSenderRow: View {
    let sender: HiddenSender
    let onUnhide: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("HIDDEN")
                .font(Theme.Typography.mono(9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    Rectangle().strokeBorder(Theme.Palette.textTertiary, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sender.senderName.isEmpty ? sender.senderEmail : sender.senderName)
                    .font(Theme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(sender.senderEmail)
                    .font(Theme.Typography.mono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Unhide", action: onUnhide)
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
