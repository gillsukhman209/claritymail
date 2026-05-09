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
    private func wrappedHTML(_ html: String) -> String {
        #if os(iOS)
        let bodyPadding = "0"
        #else
        let bodyPadding = "18px 18px 22px 18px"
        #endif
        let documentParts = emailDocumentParts(from: html)
        let isTableEmail = documentParts.body.range(of: "<table", options: .caseInsensitive) != nil
        let rootClass = isTableEmail ? "clarity-table-email" : "clarity-fluid-email"
        let viewport = isTableEmail ? "width=640, initial-scale=1.0" : "width=device-width, initial-scale=1.0"

        let layoutCSS = """
            html, body {
              margin: 0;
              padding: \(bodyPadding);
              width: 100%;
              box-sizing: border-box;
              background: #FFFFFF;
              color: #1A1A1A;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
              font-size: 15px;
              line-height: 1.55;
              overflow-x: hidden;
              -webkit-text-size-adjust: 100%;
            }
            #clarity-email-root {
              display: block;
              max-width: none;
              transform-origin: top left;
            }
            #clarity-email-root.clarity-table-email {
              width: 640px;
              min-width: 640px;
            }
            #clarity-email-root.clarity-fluid-email {
              width: 100%;
              min-width: 100%;
            }
            img {
              height: auto;
              border: 0;
            }
            a {
              color: #C2410C;
              text-decoration: underline;
            }
        """

        return """
        <!doctype html>
        <html>
        <head>
          \(documentParts.head)
          <meta name="viewport" content="\(viewport)">
          <meta name="color-scheme" content="light only">
          <meta name="supported-color-schemes" content="light">
          <style>
            :root {
              color-scheme: light only;
              -webkit-color-scheme: light;
            }
            \(layoutCSS)
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
        <body><div id="clarity-email-root" class="\(rootClass)">\(documentParts.body)</div></body>
        </html>
        """
    }

    private func emailDocumentParts(from html: String) -> (head: String, body: String) {
        let head = firstCapture(in: html, pattern: "<head[^>]*>([\\s\\S]*?)</head>") ?? ""
        let body = firstCapture(in: html, pattern: "<body[^>]*>([\\s\\S]*?)</body>") ?? html
        return (head, body)
    }

    private func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: fullRange),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[captureRange])
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
            updateContentSize(for: webView)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateContentSize(for: webView)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateContentSize(for: webView)
            }
        }

        private func updateContentSize(for webView: WKWebView) {
            let viewportWidth = max(webView.bounds.width, 1)
            webView.evaluateJavaScript(emailSizingScript(viewportWidth: viewportWidth)) { [weak self] result, _ in
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
            updateContentSize(for: webView)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateContentSize(for: webView)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.updateContentSize(for: webView)
            }
        }

        private func updateContentSize(for webView: WKWebView) {
            let viewportWidth = max(webView.bounds.width, 1)
            webView.evaluateJavaScript(emailSizingScript(viewportWidth: viewportWidth)) { [weak self] result, _ in
                guard let self else { return }
                let height = CGFloat((result as? NSNumber)?.doubleValue ?? 120)
                DispatchQueue.main.async {
                    self.contentHeight = height + 8
                }
            }
        }
    }
}
#endif

private func emailSizingScript(viewportWidth: CGFloat) -> String {
    """
    (function() {
      const root = document.getElementById('clarity-email-root') || document.body;
      const viewportWidth = \(viewportWidth);
      const isTableEmail = root.classList.contains('clarity-table-email');
      const baseWidth = isTableEmail ? 640 : viewportWidth;

      root.style.transform = 'none';
      root.style.width = baseWidth + 'px';
      root.style.minWidth = baseWidth + 'px';
      root.style.maxWidth = 'none';

      const naturalWidth = Math.max(
        baseWidth,
        root.scrollWidth,
        root.offsetWidth,
        document.body.scrollWidth,
        document.documentElement.scrollWidth,
        viewportWidth
      );
      const scale = Math.min(1, viewportWidth / naturalWidth);

      root.style.width = naturalWidth + 'px';
      root.style.minWidth = naturalWidth + 'px';
      root.style.transformOrigin = 'top left';
      root.style.transform = 'scale(' + scale + ')';

      document.body.style.width = viewportWidth + 'px';
      document.documentElement.style.width = viewportWidth + 'px';

      const rect = root.getBoundingClientRect();
      return Math.max(rect.height, document.body.scrollHeight * scale, 80);
    })();
    """
}
