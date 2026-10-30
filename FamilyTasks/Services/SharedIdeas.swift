import Foundation

/// What a link's page says about itself: its title, a picture and the site's name, and for
/// map links, the place.
struct LinkPreview: Equatable, Sendable {
    struct Place: Equatable, Sendable {
        var name: String
        var latitude: Double?
        var longitude: Double?
    }

    var title = ""
    var summary = ""
    var imageURL = ""
    var siteName = ""
    var place: Place?

    var isEmpty: Bool {
        title.isEmpty && imageURL.isEmpty && place == nil
    }

    /// Looks the page up. Never throws: a page that can't be read gives what the link
    /// itself says (a YouTube picture, a map place) or nothing.
    static func fetch(_ url: URL, session: URLSession = .shared) async -> LinkPreview {
        var preview = LinkPreview()
        preview.place = mapPlace(in: url)

        if let videoID = youTubeID(in: url) {
            preview.imageURL = "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
            preview.siteName = "YouTube"
            if let title = await youTubeTitle(for: url, session: session) { preview.title = title }
            return preview
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        // Sites give link-preview bots the page's title and picture without needing JavaScript.
        request.setValue("facebookexternalhit/1.1 Twitterbot/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request) else { return preview }
        let html = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        let finalURL = response.url ?? url
        let page = parse(html: html, baseURL: finalURL)
        preview.title = page.title
        preview.summary = page.summary
        preview.imageURL = page.imageURL
        preview.siteName = page.siteName
        // Short map links ("maps.app.goo.gl/…") only show the place once followed.
        if preview.place == nil { preview.place = mapPlace(in: finalURL) }
        if preview.place != nil, preview.title.isEmpty { preview.title = preview.place?.name ?? "" }
        return preview
    }

    static func parse(html: String, baseURL: URL) -> LinkPreview {
        var values: [String: String] = [:]
        for tag in matches(of: #"<meta\b[^>]*>"#, in: html) {
            var attributes: [String: String] = [:]
            for attribute in groups(of: #"([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: tag) {
                attributes[attribute[0].lowercased()] = attribute[1].isEmpty ? attribute[2] : attribute[1]
            }
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"].map(decodeEntities),
                  !content.isEmpty, values[key] == nil else { continue }
            values[key] = content
        }
        let titleTag = groups(of: #"<title[^>]*>([\s\S]*?)</title>"#, in: html).first?.first.map(decodeEntities)

        var preview = LinkPreview()
        preview.title = tidy(values["og:title"] ?? values["twitter:title"] ?? titleTag ?? "", limit: 200)
        preview.summary = tidy(values["og:description"] ?? values["twitter:description"] ?? values["description"] ?? "", limit: 400)
        preview.siteName = tidy(values["og:site_name"] ?? values["application-name"] ?? "", limit: 60)
        if let image = values["og:image"] ?? values["og:image:url"] ?? values["og:image:secure_url"] ?? values["twitter:image"] ?? values["twitter:image:src"],
           let imageURL = URL(string: image, relativeTo: baseURL)?.absoluteURL,
           imageURL.scheme?.hasPrefix("http") == true {
            preview.imageURL = imageURL.absoluteString
        }
        return preview
    }

    static func youTubeID(in url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("youtu.be") { return parts.first }
        guard host.contains("youtube.") else { return nil }
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return id
        }
        if parts.count >= 2, ["shorts", "embed", "live"].contains(parts[0]) { return parts[1] }
        return nil
    }

    /// The place in an Apple Maps or Google Maps link.
    static func mapPlace(in url: URL) -> Place? {
        guard let host = url.host()?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        func coordinates(_ text: String?) -> (Double, Double)? {
            guard let parts = text?.split(separator: ","), parts.count >= 2,
                  let latitude = Double(parts[0]), let longitude = Double(parts[1]) else { return nil }
            return (latitude, longitude)
        }

        if host.contains("maps.apple.com") {
            guard let name = value("name") ?? value("q") ?? value("address") ?? value("daddr") else { return nil }
            let point = coordinates(value("coordinate") ?? value("ll") ?? value("sll"))
            return Place(name: name, latitude: point?.0, longitude: point?.1)
        }

        if host.contains("google."), url.path.hasPrefix("/maps") {
            let parts = url.pathComponents
            var name: String?
            if let index = parts.firstIndex(of: "place"), parts.indices.contains(index + 1) {
                name = parts[index + 1].replacingOccurrences(of: "+", with: " ")
            }
            name = name ?? value("q") ?? value("query") ?? value("destination")
            guard let name else { return nil }
            let at = parts.first { $0.hasPrefix("@") }.map { String($0.dropFirst()) }
            let point = coordinates(at)
            return Place(name: name, latitude: point?.0, longitude: point?.1)
        }
        return nil
    }

    private static func youTubeTitle(for url: URL, session: URLSession) async -> String? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let oembed = components.url,
              let (data, _) = try? await session.data(for: URLRequest(url: oembed, timeoutInterval: 8)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else { return nil }
        return tidy(title, limit: 200)
    }

    private static func tidy(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "#39": "'"]
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            guard let semicolon = rest[afterAmpersand...].prefix(10).firstIndex(of: ";") else {
                result += "&"
                rest = rest[afterAmpersand...]
                continue
            }
            let entity = String(rest[afterAmpersand..<semicolon])
            var decoded = named[entity.lowercased()]
            if decoded == nil, entity.hasPrefix("#") {
                let number = entity.dropFirst()
                let code = number.lowercased().hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                decoded = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            }
            if let decoded {
                result += decoded
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result += "&"
                rest = rest[afterAmpersand...]
            }
        }
        return result + rest
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// Each match's capture groups, with "" for a group that didn't take part.
    private static func groups(of pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}

/// What another app shared as text: Google Maps sends "Balboa Park\nhttps://maps.app.goo.gl/…",
/// X sends the post with its link.
enum SharedLinkText {
    static func split(_ text: String) -> (url: URL?, rest: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return (nil, text)
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), let url = match.url,
              let linkRange = Range(match.range, in: text) else {
            return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var rest = text
        rest.removeSubrange(linkRange)
        let lines = rest
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (url, lines.joined(separator: "\n"))
    }
}

/// Ideas saved from the share sheet wait here, in the App Group, until the app opens and
/// takes them in. One file per idea, so saving never clashes with the app reading.
struct IdeaInbox: Sendable {
    /// The same App Group the widgets use.
    static let appGroupID = "group.com.naveenkeerthy.FamilyTasks"

    /// Nil when the App Group is unavailable (for example in unsigned test builds).
    static var shared: IdeaInbox? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            .map(IdeaInbox.init(directory:))
    }

    let directory: URL

    private var inboxDirectory: URL { directory.appendingPathComponent("shared-ideas", isDirectory: true) }

    func add(_ idea: IdeaNote) throws {
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        let url = inboxDirectory.appendingPathComponent("\(idea.id.uuidString).json")
        try JSONEncoder().encode(idea).write(to: url, options: [.atomic])
    }

    /// Saved ideas not yet taken in, oldest first.
    func pending() -> [(url: URL, idea: IdeaNote)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let idea = try? JSONDecoder().decode(IdeaNote.self, from: data) else { return nil }
                return (url, idea)
            }
            .sorted { $0.idea.createdAt < $1.idea.createdAt }
    }

    func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
