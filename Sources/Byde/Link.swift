import AppKit
import SwiftUI

/// The optional meditation app link: URL, label and cached favicon.
/// The only network access in Byde: one page fetch and one icon fetch when the URL is saved (or on a debug refetch).
@MainActor
final class LinkStore: ObservableObject {
    static let shared = LinkStore()
    static let labelLimit = 20
    static var iconFile: URL { Log.dir.appendingPathComponent("favicon.png") }

    @Published private(set) var url: String
    @Published var label: String {
        didSet {
            if label.count > Self.labelLimit { label = String(label.prefix(Self.labelLimit)) }
            UserDefaults.standard.set(label, forKey: "linkLabel")
        }
    }
    @Published private(set) var favicon: NSImage?
    @Published var error = ""

    init() {
        let d = UserDefaults.standard
        url = d.string(forKey: "linkURL") ?? ""
        label = d.string(forKey: "linkLabel") ?? ""
        if d.string(forKey: "linkFaviconFor") == url, !url.isEmpty { favicon = NSImage(contentsOf: Self.iconFile) }
    }

    var isSet: Bool { !url.isEmpty }
    var openURL: URL? { URL(string: url) }
    /// Button text: the label, or the site name if the label is empty.
    var title: String { label.isEmpty ? (openURL?.host ?? "") : label }

    /// 16 pt image for menu items: the favicon, or the globe symbol.
    var menuImage: NSImage {
        let img = favicon.map { $0.copy() as! NSImage } ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    // MARK: saving

    /// Called when the Website field is committed.
    func commit(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { remove(); return }
        guard let u = Self.normalize(t) else { error = "Enter a valid web address."; return }
        error = ""
        guard u.absoluteString != url else { return }
        url = u.absoluteString
        label = ""
        favicon = nil
        let d = UserDefaults.standard
        d.set(url, forKey: "linkURL")
        d.removeObject(forKey: "linkFaviconFor")
        Task { await fetch(u, fillLabel: true) }
    }

    func remove() {
        url = ""; label = ""; favicon = nil; error = ""
        let d = UserDefaults.standard
        for k in ["linkURL", "linkLabel", "linkFaviconFor"] { d.removeObject(forKey: k) }
        try? FileManager.default.removeItem(at: Self.iconFile)      // the cached icon, which Byde owns
    }

    #if DEBUG
    /// Debug: fetch the favicon again for the current URL.
    func refetchFavicon() {
        guard let u = openURL else { return }
        Task { await fetch(u, fillLabel: false) }
    }
    #endif

    /// Adds https:// when the scheme is missing; nil unless it is a plausible web address.
    static func normalize(_ s: String) -> URL? {
        let t = s.contains("://") ? s : "https://" + s
        guard let c = URLComponents(string: t), let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host, host.contains(".") || host == "localhost" else { return nil }
        return c.url
    }

    // MARK: fetching

    private func fetch(_ u: URL, fillLabel: Bool) async {
        let (html, base) = await Self.page(u)
        guard url == u.absoluteString else { return }                // URL changed while fetching
        if fillLabel, label.isEmpty {                                // never over a label you've typed meanwhile
            label = String((html.flatMap(Self.siteName) ?? u.host ?? "").prefix(Self.labelLimit))
        }
        let png = await Self.icon(base: base, html: html)
        guard url == u.absoluteString else { return }
        try? FileManager.default.createDirectory(at: Log.dir, withIntermediateDirectories: true)
        if let png, (try? png.write(to: Self.iconFile, options: .atomic)) != nil {
            favicon = NSImage(data: png)
        } else {
            favicon = nil
            try? FileManager.default.removeItem(at: Self.iconFile)    // never leave a stale icon from another site
        }
        UserDefaults.standard.set(u.absoluteString, forKey: "linkFaviconFor")   // fetched once; not retried
    }

    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static func get(_ u: URL) async -> (Data, URL)? {
        var r = URLRequest(url: u, timeoutInterval: 10)
        r.setValue(agent, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        return (data, resp.url ?? u)
    }

    /// The page's HTML (first 512 KB) and its final URL after redirects.
    private static func page(_ u: URL) async -> (String?, URL) {
        guard let (data, final) = await get(u) else { return (nil, u) }
        return (String(decoding: data.prefix(512_000), as: UTF8.self), final)
    }

    // MARK: parsing (regex, no dependencies)

    private static func tags(_ name: String, in html: String) -> [[String: String]] {
        let tag = try! NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: .caseInsensitive)
        let attr = try! NSRegularExpression(pattern: "([a-zA-Z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
        let ns = html as NSString
        return tag.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { m in
            let t = ns.substring(with: m.range) as NSString
            var out: [String: String] = [:]
            for a in attr.matches(in: t as String, range: NSRange(location: 0, length: t.length)) {
                let v = a.range(at: 2).location != NSNotFound ? a.range(at: 2) : a.range(at: 3)
                out[t.substring(with: a.range(at: 1)).lowercased()] = t.substring(with: v)
            }
            return out
        }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// og:site_name, else the page title up to its first separator ( | – — - : ).
    /// A site name that is just a hostname (some sites set og:site_name to their own domain) is skipped, and the
    /// app-name meta tags (apple-mobile-web-app-title, application-name) are tried before the title.
    static func siteName(from html: String) -> String? {
        let metas = tags("meta", in: html)
        func meta(_ key: String, hostOK: Bool) -> String? {
            for m in metas where (m["property"] ?? m["name"])?.lowercased() == key {
                if let c = m["content"].map(unescape), !c.isEmpty, hostOK || c.contains(" ") || !c.contains(".") { return c }
            }
            return nil
        }
        if let n = meta("og:site_name", hostOK: false) ?? meta("apple-mobile-web-app-title", hostOK: true)
            ?? meta("application-name", hostOK: true) { return n }
        let re = try! NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let title = unescape(ns.substring(with: m.range(at: 1)))
        var cut = title.endIndex
        for sep in [" | ", " – ", " — ", " - ", ": "] {
            if let r = title.range(of: sep), r.lowerBound < cut { cut = r.lowerBound }
        }
        let name = String(title[..<cut]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Declared icons, best first (apple-touch-icon, then largest), then /favicon.ico. Returns a 64 px PNG.
    private static func icon(base: URL, html: String?) async -> Data? {
        var found: [(url: URL, apple: Bool, size: Int)] = []
        for l in html.map({ tags("link", in: $0) }) ?? [] {
            guard let rel = l["rel"]?.lowercased(), rel.contains("icon"), let href = l["href"],
                  let u = URL(string: unescape(href), relativeTo: base)?.absoluteURL, !u.path.lowercased().hasSuffix(".svg") else { continue }
            let size = l["sizes"].flatMap { Int($0.split(whereSeparator: { $0 == "x" || $0 == "X" }).first ?? "") } ?? 0
            found.append((u, rel.contains("apple-touch-icon"), size))
        }
        var urls = found.sorted { ($0.apple ? 1 : 0, $0.size) > ($1.apple ? 1 : 0, $1.size) }.map(\.url)
        if let root = URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL { urls.append(root) }
        for u in urls {
            if let (data, _) = await get(u), let png = png64(data) { return png }
        }
        return nil
    }

    private static func png64(_ data: Data) -> Data? {
        guard let img = NSImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
        let px = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let s = min(CGFloat(px) / img.size.width, CGFloat(px) / img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        img.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// 16 pt favicon, or the globe when there is none.
struct LinkIcon: View {
    @ObservedObject var link = LinkStore.shared
    var body: some View {
        Group {
            if let f = link.favicon { Image(nsImage: f).resizable().interpolation(.high) } else { Image(systemName: "globe") }
        }
        .frame(width: 16, height: 16)
    }
}
