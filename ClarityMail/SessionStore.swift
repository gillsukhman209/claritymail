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

    private let apiClient = APIClient()

    func signInWithGoogle() async {
        do {
            pendingAuthURL = try await apiClient.googleAuthURL()
            errorMessage = nil
        } catch {
            errorMessage = "Could not start Google sign-in."
        }
    }

    func refreshAuthStatus() async {
        do {
            let status = try await apiClient.authStatus()
            isSignedIn = status.isSignedIn
            userEmail = status.email
            errorMessage = nil
        } catch {
            errorMessage = "Could not check sign-in status."
        }
    }

    func usePreviewSession() {
        userEmail = "you@example.com"
        isSignedIn = true
    }

    func signOut() {
        userEmail = nil
        isSignedIn = false
    }
}
