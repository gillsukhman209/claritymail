//
//  EmailHTMLView.swift
//  ClarityMail
//

import SwiftUI
import WebKit

struct EmailHTMLView: View {
    let html: String?
    let plainText: String
    @State private var contentHeight: CGFloat = 700

    var body: some View {
        if let html, !html.isEmpty {
            EmailWebView(html: wrappedHTML(html), contentHeight: $contentHeight)
                .frame(minHeight: max(contentHeight, 700))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        } else {
            Text(plainText)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wrappedHTML(_ body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }
            body {
              color: #f7f7f8;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
              overflow-wrap: anywhere;
            }
            img {
              max-width: 100% !important;
              height: auto !important;
            }
            table {
              max-width: 100% !important;
            }
            a {
              color: #26B8AB;
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
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
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
                let height = CGFloat((result as? NSNumber)?.doubleValue ?? 700)
                DispatchQueue.main.async {
                    self.contentHeight = height + 24
                }
            }
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
        view.backgroundColor = .clear
        view.isOpaque = false
        view.scrollView.backgroundColor = .clear
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
                let height = CGFloat((result as? NSNumber)?.doubleValue ?? 700)
                DispatchQueue.main.async {
                    self.contentHeight = height + 24
                }
            }
        }
    }
}
#endif
