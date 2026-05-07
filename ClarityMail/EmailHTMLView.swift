//
//  EmailHTMLView.swift
//  ClarityMail
//

import SwiftUI
import WebKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct EmailHTMLView: View {
    let html: String?
    let plainText: String
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        if let html, !html.isEmpty {
            EmailWebView(html: wrappedHTML(html), contentHeight: $contentHeight)
                .frame(height: max(contentHeight, 80))
                .frame(maxWidth: .infinity)
                #if os(macOS)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                #endif
        } else {
            Text(plainText)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Wraps the email's HTML in a fixed-light render context so any color CSS
    /// the sender shipped (white-on-dark dark-mode tweaks, transparent text,
    /// etc.) lands on a predictable canvas.
    private func wrappedHTML(_ body: String) -> String {
        #if os(iOS)
        let bodyPadding = "0"
        #else
        let bodyPadding = "18px 18px 22px 18px"
        #endif

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta name="color-scheme" content="light only">
          <meta name="supported-color-schemes" content="light">
          <style>
            :root {
              color-scheme: light only;
              -webkit-color-scheme: light;
            }
            html, body {
              margin: 0;
              padding: \(bodyPadding);
              width: 100% !important;
              max-width: 100% !important;
              box-sizing: border-box;
              background: #FFFFFF;
              color: #1A1A1A;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
              font-size: 15px;
              line-height: 1.55;
              word-wrap: break-word;
              overflow-wrap: anywhere;
              overflow-x: hidden;
              -webkit-text-size-adjust: 100%;
            }
            *, *::before, *::after {
              box-sizing: border-box;
              max-width: 100% !important;
            }
            *:not([style*="color"]):not(font[color]) {
              color: inherit;
            }
            p, div, span, td, th, li, h1, h2, h3, h4, h5, h6 {
              color: inherit;
            }
            img {
              max-width: 100% !important;
              height: auto !important;
              border: 0;
            }
            table {
              width: 100% !important;
              max-width: 100% !important;
              border-collapse: collapse;
              table-layout: auto !important;
            }
            td, th {
              max-width: 100% !important;
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            a {
              color: #C2410C;
              text-decoration: underline;
            }
            blockquote {
              margin: 12px 0;
              padding: 0 0 0 14px;
              border-left: 2px solid #E5E2DA;
              color: #555049;
            }
            pre, code {
              font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
              background: #F4F1EA;
              border-radius: 4px;
            }
            pre {
              padding: 10px 12px;
              overflow-x: auto;
            }
            code {
              padding: 1px 4px;
            }
            hr {
              border: none;
              border-top: 1px solid #E5E2DA;
              margin: 16px 0;
            }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

// MARK: - URL handling

/// Sends a URL through the system's default opener. Handles http(s), mailto,
/// tel, and any custom scheme the OS knows about.
private func openExternal(_ url: URL) {
    #if canImport(AppKit)
    NSWorkspace.shared.open(url)
    #elseif canImport(UIKit)
    UIApplication.shared.open(url)
    #endif
}

#if os(macOS)
private struct EmailWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = PassthroughScrollWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // Opaque white canvas — the email body owns its own background.
        view.setValue(true, forKey: "drawsBackground")
        view.allowsLinkPreview = true
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var contentHeight: CGFloat
        var html = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        // Intercept link clicks → open in the user's default browser / mail
        // client / phone. Allow only the initial inline HTML load.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // First load of the inline HTML: allow.
            if navigationAction.navigationType == .other,
               navigationAction.request.url == nil ||
               navigationAction.request.url?.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            if let url = navigationAction.request.url {
                // Treat any user-initiated click (including from JS-redirects
                // wrapped as `linkActivated`) as an external open.
                switch navigationAction.navigationType {
                case .linkActivated, .formSubmitted, .formResubmitted, .reload, .backForward:
                    openExternal(url)
                    decisionHandler(.cancel)
                    return
                case .other:
                    // Some emails issue meta-refresh / JS redirects that arrive
                    // as .other — bounce anything that isn't the initial load.
                    if url.scheme == "http" || url.scheme == "https" ||
                       url.scheme == "mailto" || url.scheme == "tel" {
                        openExternal(url)
                        decisionHandler(.cancel)
                        return
                    }
                @unknown default:
                    break
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else { return }
                let height = CGFloat((result as? NSNumber)?.doubleValue ?? 120)
                DispatchQueue.main.async {
                    self.contentHeight = height + 24
                }
            }
        }
    }

    final class PassthroughScrollWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }
    }
}
#else
private struct EmailWebView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.backgroundColor = .white
        view.isOpaque = true
        view.scrollView.backgroundColor = .white
        view.scrollView.isScrollEnabled = false
        view.overrideUserInterfaceStyle = .light
        // Long-press preview gives the native context menu (Open, Open in
        // Background, Copy Link, Share) on iOS.
        view.allowsLinkPreview = true
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var contentHeight: CGFloat
        var html = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow the initial loadHTMLString through.
            if navigationAction.navigationType == .other,
               navigationAction.request.url == nil ||
               navigationAction.request.url?.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            if let url = navigationAction.request.url {
                switch navigationAction.navigationType {
                case .linkActivated, .formSubmitted, .formResubmitted, .reload, .backForward:
                    openExternal(url)
                    decisionHandler(.cancel)
                    return
                case .other:
                    if url.scheme == "http" || url.scheme == "https" ||
                       url.scheme == "mailto" || url.scheme == "tel" {
                        openExternal(url)
                        decisionHandler(.cancel)
                        return
                    }
                @unknown default:
                    break
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
                guard let self else { return }
                let height = CGFloat((result as? NSNumber)?.doubleValue ?? 120)
                DispatchQueue.main.async {
                    self.contentHeight = height + 24
                }
            }
        }
    }
}
#endif
