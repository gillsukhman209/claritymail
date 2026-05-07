//
//  SessionStore.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var errorMessage: String?
    @Published var pendingAuthURL: URL?
    @Published var isCheckingAuth = false

    private let apiClient = APIClient()
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let hasConnectedAccount = "ClarityMail.hasConnectedAccount"
        static let lastSignedInEmail = "ClarityMail.lastSignedInEmail"
    }

    init() {
        restoreCachedSignIn()
    }

    func signInWithGoogle() async {
        do {
            pendingAuthURL = try await apiClient.googleAuthURL()
            errorMessage = nil
        } catch {
            errorMessage = "Could not start Google sign-in."
        }
    }

    func refreshAuthStatus() async {
        isCheckingAuth = true
        defer { isCheckingAuth = false }

        do {
            let status = try await apiClient.authStatus()
            if status.isSignedIn {
                confirmSignedIn(email: status.email)
            } else {
                clearSignedInState()
            }
            errorMessage = nil
        } catch {
            if hasCachedSignIn || hasPersistedMailboxCache {
                restoreCachedSignIn()
                isSignedIn = true
                errorMessage = nil
            } else {
                errorMessage = "Could not check sign-in status."
            }
        }
    }

    func usePreviewSession() {
        confirmSignedIn(email: "you@example.com")
    }

    func confirmSignedIn(email: String?) {
        userEmail = email ?? userEmail
        isSignedIn = true
        defaults.set(true, forKey: DefaultsKey.hasConnectedAccount)
        if let email {
            defaults.set(email, forKey: DefaultsKey.lastSignedInEmail)
        }
    }

    func refreshFromAccounts(_ accounts: [GmailAccount]) {
        if let firstAccount = accounts.first {
            confirmSignedIn(email: firstAccount.email)
        }
    }

    func signOut() {
        clearSignedInState()
    }

    private var hasCachedSignIn: Bool {
        defaults.bool(forKey: DefaultsKey.hasConnectedAccount)
    }

    private var hasPersistedMailboxCache: Bool {
        defaults
            .dictionaryRepresentation()
            .keys
            .contains { $0.hasPrefix("mailbox-cache-v1|") }
    }

    private func restoreCachedSignIn() {
        guard hasCachedSignIn || hasPersistedMailboxCache else { return }
        userEmail = defaults.string(forKey: DefaultsKey.lastSignedInEmail)
        isSignedIn = true
    }

    private func clearSignedInState() {
        userEmail = nil
        isSignedIn = false
        defaults.removeObject(forKey: DefaultsKey.hasConnectedAccount)
        defaults.removeObject(forKey: DefaultsKey.lastSignedInEmail)
    }
}
