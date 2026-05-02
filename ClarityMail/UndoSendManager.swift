//
//  UndoSendManager.swift
//  ClarityMail
//

import Combine
import SwiftUI

@MainActor
final class UndoSendManager: ObservableObject {
    static let shared = UndoSendManager()

    struct PendingSend: Identifiable {
        let id = UUID()
        let title: String
        var secondsRemaining: Int
    }

    @Published var pendingSend: PendingSend?

    private var task: Task<Void, Never>?

    private init() {}

    func schedule(
        title: String,
        delay: Int,
        operation: @escaping () async throws -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor () -> Void
    ) {
        task?.cancel()

        let delay = max(0, delay)
        guard delay > 0 else {
            task = Task {
                do {
                    try await operation()
                    await MainActor.run {
                        onComplete()
                    }
                } catch {
                    await MainActor.run {
                        onError()
                    }
                }
            }
            return
        }

        pendingSend = PendingSend(title: title, secondsRemaining: delay)
        task = Task {
            var remaining = delay

            while !Task.isCancelled && remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                await MainActor.run {
                    self.pendingSend?.secondsRemaining = remaining
                }
            }

            if Task.isCancelled { return }

            await MainActor.run {
                self.pendingSend = nil
            }

            do {
                try await operation()
                await MainActor.run {
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    onError()
                }
            }
        }
    }

    func undo() {
        task?.cancel()
        task = nil
        pendingSend = nil
    }
}

struct UndoSendToast: View {
    @ObservedObject private var manager = UndoSendManager.shared

    var body: some View {
        if let pendingSend = manager.pendingSend {
            HStack(spacing: 14) {
                Text("\(pendingSend.secondsRemaining)")
                    .font(Theme.Typography.mono(13, weight: .heavy))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Rectangle().strokeBorder(Theme.Palette.accent, lineWidth: 1)
                    )

                Text("\(pendingSend.title.uppercased())")
                    .font(Theme.Typography.mono(11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Button("Undo".uppercased()) {
                    manager.undo()
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.mono(11, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.background)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.Palette.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.Palette.surfaceElevated)
            .overlay(
                Rectangle()
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
