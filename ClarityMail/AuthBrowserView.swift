//
//  AuthBrowserView.swift
//  ClarityMail
//
//  Created by Codex on 5/3/26.
//

#if os(iOS)
import SafariServices
import SwiftUI

struct AuthBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct AuthBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
