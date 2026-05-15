import SwiftUI
import WebKit
import AppKit

struct MermaidBlockView: View {
    let code: String
    let textColumnWidth: CGFloat
    @State private var height: CGFloat = 120
    @State private var errorMessage: String?
    @State private var copyRequest: UUID?
    @State private var copyState: CopyState = .idle
    @State private var isFullWidth: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ThemePalette.storageKey) private var palette: String = ThemePalette.rose.rawValue

    enum CopyState {
        case idle, copied, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            MermaidWebView(
                code: code,
                colorScheme: colorScheme,
                palette: palette,
                copyRequest: copyRequest,
                height: $height,
                errorMessage: $errorMessage,
                onCopyResult: handleCopyResult(_:)
            )
            .frame(height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: isFullWidth ? .infinity : textColumnWidth, alignment: .leading)
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .imageScale(.small)
                Text("mermaid")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.4)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.accentSoft)
            .clipShape(Capsule())
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                FullWidthToggle(isOn: isFullWidth) {
                    isFullWidth.toggle()
                }
                CopyButton(state: copyState) {
                    copyState = .idle
                    copyRequest = UUID()
                }
            }
            .padding(8)
        }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.elevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
        }
    }

    private func handleCopyResult(_ success: Bool) {
        copyState = success ? .copied : .failed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copyState != .idle { copyState = .idle }
        }
    }
}

private struct CopyButton: View {
    let state: MermaidBlockView.CopyState
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy diagram as PNG to clipboard")
    }

    private var icon: String {
        switch state {
        case .idle: return "doc.on.doc"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var label: String {
        switch state {
        case .idle: return "Copy PNG"
        case .copied: return "Copied"
        case .failed: return "Failed"
        }
    }

    private var foreground: Color {
        switch state {
        case .copied: return .green
        case .failed: return .red
        case .idle: return Theme.accent
        }
    }

    private var background: Color {
        if hovering { return Theme.accentSoft.opacity(1.4) }
        return Theme.accentSoft
    }
}

private struct FullWidthToggle: View {
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn
                      ? "arrow.right.and.line.vertical.and.arrow.left"
                      : "arrow.left.and.line.vertical.and.arrow.right")
                    .imageScale(.small)
                Text(isOn ? "Fit Column" : "Full Width")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(hovering ? Theme.accentSoft.opacity(1.4) : Theme.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOn ? "Shrink diagram to text column width" : "Expand diagram to full pane width")
    }
}

struct MermaidWebView: NSViewRepresentable {
    let code: String
    let colorScheme: ColorScheme
    let palette: String
    let copyRequest: UUID?
    @Binding var height: CGFloat
    @Binding var errorMessage: String?
    let onCopyResult: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "supermd")
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.loadHTMLString(html(), baseURL: URL(string: "https://supermd.local/"))
        context.coordinator.lastRendered = (code, colorScheme, palette)
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView

        let last = context.coordinator.lastRendered
        if last?.code != code || last?.scheme != colorScheme || last?.palette != palette {
            context.coordinator.lastRendered = (code, colorScheme, palette)
            webView.loadHTMLString(html(), baseURL: URL(string: "https://supermd.local/"))
        }

        if let req = copyRequest, context.coordinator.lastCopyRequest != req {
            context.coordinator.lastCopyRequest = req
            context.coordinator.triggerCopy()
        }
    }

    private func html() -> String {
        // Match the SwiftUI Theme.codeBackground that surrounds the WebView so it blends seamlessly.
        let bg = Theme.codeBackgroundHex
        let fg = Theme.textHex
        let themeVars = Theme.mermaidThemeVarsJSON
        let escaped = Data(code.utf8).base64EncodedString()
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: \(bg); color: \(fg); }
          body { padding: 36px 16px 16px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
          #out { display: block; width: 100%; min-height: 40px; }
          #out svg { display: block; width: 100% !important; height: auto !important; max-width: 100%; }
          .error { color: #d33; font: 12px ui-monospace, Menlo, monospace; white-space: pre-wrap; text-align: left; }
          .loading { color: #888; font: 12px -apple-system, sans-serif; }
        </style>
        </head><body>
          <div id="out"><span class="loading">Loading diagram…</span></div>
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"
                  onerror="window.__mermaidLoadFailed = true"></script>
          <script>
            (function () {
              const post = (payload) => {
                try { window.webkit.messageHandlers.supermd.postMessage(payload); } catch (e) {}
              };
              const measure = () => Math.max(
                document.body.scrollHeight,
                document.documentElement.scrollHeight,
                document.getElementById('out').offsetHeight + 60
              );
              const reportHeight = () => {
                requestAnimationFrame(() => {
                  post({ type: 'height', value: Math.ceil(measure()) });
                });
              };
              const showError = (msg) => {
                document.getElementById('out').innerHTML =
                  '<pre class="error">' + msg + '</pre>';
                post({ type: 'error', value: msg });
                reportHeight();
              };

              const fixSvgSizing = (svg) => {
                if (!svg) return;
                // Replace fixed width/height with a viewBox so it flexes to 100%.
                const wAttr = svg.getAttribute('width');
                const hAttr = svg.getAttribute('height');
                if (!svg.getAttribute('viewBox') && wAttr && hAttr) {
                  svg.setAttribute('viewBox', '0 0 ' + parseFloat(wAttr) + ' ' + parseFloat(hAttr));
                }
                svg.removeAttribute('width');
                svg.removeAttribute('height');
                svg.style.width = '100%';
                svg.style.height = 'auto';
                svg.style.maxWidth = '100%';
                svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
              };

              const source = atob('\(escaped)');

              if (window.__mermaidLoadFailed || typeof mermaid === 'undefined') {
                showError('Could not load mermaid.min.js. Check internet connection.');
                return;
              }

              try {
                mermaid.initialize({
                  startOnLoad: false,
                  theme: 'base',
                  themeVariables: \(themeVars),
                  flowchart: { curve: 'basis', useMaxWidth: true },
                  sequence: { useMaxWidth: true },
                  gantt: { useMaxWidth: true },
                  securityLevel: 'loose',
                  fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'
                });
                mermaid.render('supermd-diagram-' + Math.random().toString(36).slice(2), source)
                  .then(({ svg }) => {
                    document.getElementById('out').innerHTML = svg;
                    fixSvgSizing(document.querySelector('#out svg'));
                    post({ type: 'error', value: '' });
                    reportHeight();
                    setTimeout(reportHeight, 50);
                    setTimeout(reportHeight, 250);
                    setTimeout(reportHeight, 800);
                  })
                  .catch((err) => {
                    showError(err && err.message ? err.message : String(err));
                  });
              } catch (err) {
                showError(err && err.message ? err.message : String(err));
              }

              if (typeof ResizeObserver !== 'undefined') {
                new ResizeObserver(reportHeight).observe(document.body);
              }

              window.__supermdCopyPNG = function (scale) {
                try {
                  const svg = document.querySelector('#out svg');
                  if (!svg) { post({ type: 'png', value: '', error: 'No diagram' }); return; }

                  const rect = svg.getBoundingClientRect();
                  let vb = svg.viewBox && svg.viewBox.baseVal ? svg.viewBox.baseVal : null;
                  const baseW = vb && vb.width  ? vb.width  : rect.width;
                  const baseH = vb && vb.height ? vb.height : rect.height;

                  // Build a standalone SVG string with explicit dimensions for rasterization.
                  const clone = svg.cloneNode(true);
                  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
                  clone.setAttribute('width',  baseW);
                  clone.setAttribute('height', baseH);
                  const xml = new XMLSerializer().serializeToString(clone);

                  const w = Math.ceil(baseW * scale);
                  const h = Math.ceil(baseH * scale);
                  const canvas = document.createElement('canvas');
                  canvas.width = w; canvas.height = h;
                  const ctx = canvas.getContext('2d');
                  ctx.fillStyle = '#ffffff';
                  ctx.fillRect(0, 0, w, h);

                  const img = new Image();
                  img.onload = function () {
                    ctx.drawImage(img, 0, 0, w, h);
                    try {
                      const data = canvas.toDataURL('image/png');
                      post({ type: 'png', value: data });
                    } catch (e) {
                      post({ type: 'png', value: '', error: String(e) });
                    }
                  };
                  img.onerror = function (e) {
                    post({ type: 'png', value: '', error: 'Image load failed' });
                  };
                  img.src = 'data:image/svg+xml;base64,' +
                            btoa(unescape(encodeURIComponent(xml)));
                } catch (e) {
                  post({ type: 'png', value: '', error: String(e) });
                }
              };
            })();
          </script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        weak var webView: WKWebView?
        var lastRendered: (code: String, scheme: ColorScheme, palette: String)?
        var lastCopyRequest: UUID?

        init(_ parent: MermaidWebView) { self.parent = parent }

        func triggerCopy() {
            let scale = (NSScreen.main?.backingScaleFactor ?? 2.0)
            webView?.evaluateJavaScript("window.__supermdCopyPNG(\(scale))", completionHandler: nil)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "supermd",
                  let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch type {
                case "height":
                    if let value = dict["value"] as? NSNumber {
                        let newHeight = CGFloat(value.doubleValue)
                        let clamped = max(80, newHeight)
                        if abs(clamped - self.parent.height) > 1 {
                            self.parent.height = clamped
                        }
                    }
                case "error":
                    let msg = (dict["value"] as? String) ?? ""
                    self.parent.errorMessage = msg.isEmpty ? nil : msg
                case "png":
                    let dataUrl = (dict["value"] as? String) ?? ""
                    let ok = self.writePNGToPasteboard(dataUrl)
                    self.parent.onCopyResult(ok)
                default:
                    break
                }
            }
        }

        private func writePNGToPasteboard(_ dataUrl: String) -> Bool {
            guard let comma = dataUrl.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...])),
                  let image = NSImage(data: data) else {
                return false
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            let withTIFF = pb.writeObjects([image])
            let pngOk = pb.setData(data, forType: .png)
            return withTIFF || pngOk
        }
    }
}
