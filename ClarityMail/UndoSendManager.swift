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
            HStack(spacing: 12) {
                Text("\(pendingSend.title) in \(pendingSend.secondsRemaining)s")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Button("Undo") {
                    manager.undo()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.accentSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.Palette.surfaceElevated.opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
