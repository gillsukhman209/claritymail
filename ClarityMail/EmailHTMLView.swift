//
//  EmailHTMLView.swift
//  ClarityMail
//

import SwiftUI
import WebKit

struct EmailHTMLView: View {
    let html: String?
    let plainText: String
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        if let html, !html.isEmpty {
            EmailWebView(html: wrappedHTML(html), contentHeight: $contentHeight)
                .frame(height: max(contentHeight, 80))
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
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
    /// etc.) lands on a predictable canvas. This is the same pattern Apple Mail
    /// and Gmail use: the email body is always rendered against white, with a
    /// dark default text color, regardless of system appearance.
    private func wrappedHTML(_ body: String) -> String {
        """
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
              padding: 18px 18px 22px 18px;
              background: #FFFFFF;
              color: #1A1A1A;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
              font-size: 15px;
              line-height: 1.55;
              word-wrap: break-word;
              overflow-wrap: anywhere;
              -webkit-text-size-adjust: 100%;
            }
            /* Defeat dark-mode email tweaks. Many marketing templates ship a
               @media (prefers-color-scheme: dark) block that flips text white;
               since we forced color-scheme: light, those rules won't activate.
               We still guard against bare `color: #fff` etc. by giving any
               element with no color a sensible default. */
            *:not([style*="color"]):not(font[color]) {
              color: inherit;
            }
            /* Some senders set body color: #fff inline. Force readable defaults
               on bare paragraphs / spans / divs that inherit nothing useful. */
            p, div, span, td, th, li, h1, h2, h3, h4, h5, h6 {
              color: inherit;
            }
            img {
              max-width: 100% !important;
              height: auto !important;
              border: 0;
            }
            table {
              max-width: 100% !important;
              border-collapse: collapse;
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
        // Opaque white canvas — the email body owns its own background. This is
        // what real mail clients do; the surrounding chrome can be any theme.
        view.setValue(true, forKey: "drawsBackground")
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
        // Opaque white canvas. The body's CSS owns the background, so we don't
        // want to bleed the cream/ink theme onto the email's content.
        view.backgroundColor = .white
        view.isOpaque = true
        view.scrollView.backgroundColor = .white
        view.scrollView.isScrollEnabled = false
        // Force light appearance inside the WebView regardless of system trait.
        view.overrideUserInterfaceStyle = .light
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
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
