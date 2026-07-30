import Foundation

struct BeerDiscoveryCandidate: Identifiable, Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case catalogBeer
        case webSearch
    }

    let id: String
    let name: String
    let brewery: String?
    let styleName: String?
    let coarseStyleName: String?
    let abv: Double?
    let source: Source
    let sourceURL: URL

    var beerStyle: BeerStyle? {
        coarseStyleName.flatMap(BeerStyle.init(rawValue:))
    }

    var resolvedBeer: ResolvedBeer {
        ResolvedBeer(
            name: name,
            brewery: brewery,
            style: beerStyle,
            abv: abv,
            source: .online,
            factSource: BeerFactSource(
                kind: source == .catalogBeer ? .catalogBeer : .webSearch,
                url: sourceURL
            )
        )
    }

    var attributionLabel: String {
        switch source {
        case .catalogBeer:
            return "Catalog.beer"
        case .webSearch:
            return sourceURL.host?.replacingOccurrences(of: "www.", with: "") ?? "Source"
        }
    }

    var licenseURL: URL? {
        source == .catalogBeer
            ? URL(string: "https://creativecommons.org/licenses/by/4.0/")
            : nil
    }
}

enum BeerDiscoveryError: Error {
    case invalidResponse
    case unavailable
}

enum BeerDiscoveryText {
    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US")
        )
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func coarseStyle(from value: String?) -> BeerStyle? {
        guard let value else { return nil }
        let tokens = Set(normalize(value).split(separator: " ").map(String.init))
        if tokens.contains("pivo") { return .lager }
        return TasteScorer.inferStyle(from: value)
    }

    static func parseABV(from value: String) -> Double? {
        let patterns = [
            #"(?i)\ba\.?b\.?v\.?\s*[:=-]?\s*(\d{1,2}(?:[.,]\d{1,2})?)\s*%?"#,
            #"(?i)(\d{1,2}(?:[.,]\d{1,2})?)\s*%\s*a\.?b\.?v\.?\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                  ),
                  let range = Range(match.range(at: 1), in: value),
                  let parsed = Double(value[range].replacingOccurrences(of: ",", with: ".")),
                  (0...25).contains(parsed) else { continue }
            return parsed
        }
        return nil
    }

    static func validatedABV(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber { parsed = number.doubleValue }
        else if let string = value as? String { parsed = Double(string.replacingOccurrences(of: ",", with: ".")) }
        else { parsed = nil }
        guard let parsed, (0...25).contains(parsed) else { return nil }
        return parsed
    }
}

enum BeerDiscoveryRelevance {
    private static let ignoredTokens = Set(["beer", "brew", "brewing", "brewery", "company", "co"])

    static func score(_ candidate: BeerDiscoveryCandidate, query: String) -> Int {
        let queryValue = BeerDiscoveryText.normalize(query)
        let name = BeerDiscoveryText.normalize(candidate.name)
        let brewery = BeerDiscoveryText.normalize(candidate.brewery ?? "")
        let combined = "\(brewery) \(name)".trimmingCharacters(in: .whitespaces)
        guard !queryValue.isEmpty else { return 0 }
        if name == queryValue { return 100 }
        if brewery == queryValue { return 98 }
        let compactQuery = queryValue.replacingOccurrences(of: " ", with: "")
        if name.replacingOccurrences(of: " ", with: "") == compactQuery { return 100 }
        if brewery.replacingOccurrences(of: " ", with: "") == compactQuery { return 98 }
        if name.hasPrefix(queryValue) { return 95 }
        if combined.contains(queryValue) { return 92 }

        let queryTokens = queryValue.split(separator: " ").map(String.init)
            .filter { !ignoredTokens.contains($0) }
        let candidateTokens = combined.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return 0 }
        let allTokensMatch = queryTokens.allSatisfy { queryToken in
            candidateTokens.contains { candidateToken in
                candidateToken.hasPrefix(queryToken)
                    || queryToken.hasPrefix(candidateToken)
                    || (min(candidateToken.count, queryToken.count) >= 4
                        && BeerMatcher.calculateSimilarity(candidateToken, queryToken) >= 0.8)
            }
        }
        return allTokensMatch ? 85 : 0
    }
}

struct CatalogBeerSearchClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = BeerDiscoverySession.make()) {
        self.session = session
    }

    func search(query: String, limit: Int) async throws -> [BeerDiscoveryCandidate] {
        var components = URLComponents(string: "https://catalog.beer/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "beer")
        ]
        guard let url = components?.url else { throw BeerDiscoveryError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(BeerDiscoverySession.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count <= 1_500_000,
              let html = String(data: data, encoding: .utf8) else {
            throw BeerDiscoveryError.invalidResponse
        }
        return CatalogBeerHTMLParser.parse(html, query: query, limit: limit)
    }
}

enum CatalogBeerHTMLParser {
    static func parse(_ html: String, query: String, limit: Int) -> [BeerDiscoveryCandidate] {
        guard limit > 0 else { return [] }
        if reportedResultCount(in: html) == 0 { return [] }

        var indexed: [(BeerDiscoveryCandidate, Int, Int)] = []
        for (index, row) in HTMLFragment.elements(tag: "a", classToken: "sr-hit", in: html).enumerated() {
            guard let href = HTMLFragment.attribute("href", in: row.attributes),
                  let sourceURL = URL(string: href, relativeTo: URL(string: "https://catalog.beer"))?.absoluteURL,
                  sourceURL.scheme == "https",
                  sourceURL.host == "catalog.beer",
                  sourceURL.path.hasPrefix("/beer/"),
                  let rawName = HTMLFragment.innerHTML(classToken: "sr-hit__name", in: row.innerHTML) else {
                continue
            }

            let name = HTMLFragment.plainText(rawName)
            guard isPlausibleBeerName(name) else { continue }
            let context = HTMLFragment.innerHTML(classToken: "sr-hit__ctx", in: row.innerHTML)
                .map(HTMLFragment.plainText) ?? ""
            let contextParts = context
                .components(separatedBy: "·")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let brewery = contextParts.first
            let styleName = contextParts.dropFirst().first
            let value = HTMLFragment.innerHTML(classToken: "sr-hit__value", in: row.innerHTML)
                .map(HTMLFragment.plainText) ?? ""
            let candidate = BeerDiscoveryCandidate(
                id: "catalog:\(sourceURL.lastPathComponent)",
                name: name,
                brewery: brewery,
                styleName: styleName,
                coarseStyleName: BeerDiscoveryText.coarseStyle(
                    from: [styleName, name].compactMap { $0 }.joined(separator: " ")
                )?.rawValue,
                abv: BeerDiscoveryText.parseABV(from: value),
                source: .catalogBeer,
                sourceURL: sourceURL
            )
            let relevance = BeerDiscoveryRelevance.score(candidate, query: query)
            if relevance > 0 { indexed.append((candidate, relevance, index)) }
        }

        return indexed.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }
        .prefix(limit)
        .map(\.0)
    }

    static func isPlausibleBeerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...100).contains(trimmed.count) && trimmed.contains(where: \.isLetter)
    }

    private static func reportedResultCount(in html: String) -> Int? {
        guard let countHTML = HTMLFragment.innerHTML(classToken: "sr-count", in: html) else {
            return nil
        }
        let countText = HTMLFragment.plainText(countHTML)
        let pattern = #"(?i)^\s*([0-9][0-9,]*)\s+results?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: countText,
                range: NSRange(countText.startIndex..., in: countText)
              ),
              let countRange = Range(match.range(at: 1), in: countText) else {
            return nil
        }
        return Int(countText[countRange].replacingOccurrences(of: ",", with: ""))
    }
}

enum HTMLFragment {
    struct Element {
        let attributes: String
        let innerHTML: String
    }

    static func elements(tag: String, classToken: String, in html: String) -> [Element] {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        let pattern = "(?is)<\(escapedTag)\\b([^>]*)>(.*?)</\(escapedTag)\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let contentRange = Range(match.range(at: 2), in: html) else { return nil }
            let attributes = String(html[attributesRange])
            guard attribute("class", in: attributes)?
                .split(whereSeparator: \.isWhitespace)
                .contains(Substring(classToken)) == true else { return nil }
            return Element(attributes: attributes, innerHTML: String(html[contentRange]))
        }
    }

    static func attribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?is)\\b\(escapedName)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: attributes,
                range: NSRange(attributes.startIndex..., in: attributes)
              ) else { return nil }
        for index in 1...3 where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: attributes) {
                return decodeEntities(String(attributes[range]))
            }
        }
        return nil
    }

    static func innerHTML(classToken: String, in html: String) -> String? {
        let pattern = #"(?is)<\s*(/?)\s*([a-z][a-z0-9:-]*)\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var targetTag: String?
        var depth = 0
        var contentStart: String.Index?

        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: html),
                  let slashRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range(at: 2), in: html),
                  let attributesRange = Range(match.range(at: 3), in: html) else { continue }
            let isClosing = !html[slashRange].isEmpty
            let tag = html[tagRange].lowercased()
            let attributes = String(html[attributesRange])

            if targetTag == nil {
                guard !isClosing,
                      attribute("class", in: attributes)?
                        .split(whereSeparator: \.isWhitespace)
                        .contains(Substring(classToken)) == true else { continue }
                targetTag = tag
                depth = 1
                contentStart = fullRange.upperBound
                continue
            }

            guard tag == targetTag else { continue }
            if isClosing {
                depth -= 1
                if depth == 0, let contentStart {
                    return String(html[contentStart..<fullRange.lowerBound])
                }
            } else if !attributes.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") {
                depth += 1
            }
        }
        return nil
    }

    static func plainText(_ html: String) -> String {
        let spaced = html.replacingOccurrences(
            of: #"(?is)</?(?:br|p|div|li)\b[^>]*>"#,
            with: " ",
            options: .regularExpression
        )
        let withoutTags = spaced.replacingOccurrences(
            of: #"(?is)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeEntities(withoutTags)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func decodeEntities(_ input: String) -> String {
        var value = input
        let numericPattern = #"&#(?:[xX]([0-9A-Fa-f]+)|([0-9]+));"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let fullRange = Range(match.range(at: 0), in: value) else { continue }
                let code: UInt32?
                if match.range(at: 1).location != NSNotFound,
                   let range = Range(match.range(at: 1), in: value) {
                    code = UInt32(value[range], radix: 16)
                } else if let range = Range(match.range(at: 2), in: value) {
                    code = UInt32(value[range], radix: 10)
                } else {
                    code = nil
                }
                if let code, let scalar = UnicodeScalar(code) {
                    value.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        let named = [
            "&nbsp;": " ", "&quot;": "\"", "&apos;": "'", "&#39;": "'",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&lsquo;": "\u{2018}",
            "&rsquo;": "\u{2019}", "&ndash;": "\u{2013}", "&mdash;": "\u{2014}",
            "&hellip;": "\u{2026}", "&middot;": "\u{00B7}", "&lt;": "<", "&gt;": ">", "&amp;": "&"
        ]
        for (entity, replacement) in named {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }
}

struct BeerSearchProxyClient: @unchecked Sendable {
    private static let reservedHostSuffixes: Set<String> = [
        "example", "invalid", "localhost", "local", "test", "internal", "home", "lan", "onion"
    ]
    private static let trackingQueryNames: Set<String> = [
        "fbclid", "gclid", "mc_cid", "mc_eid", "msclkid"
    ]
    private static let responseByteLimit = 256_000
    private static let allowedResultKeys: Set<String> = [
        "name", "brewery", "style", "abv", "source_url"
    ]
    private static let requiredResultKeys: Set<String> = [
        "name", "brewery", "style", "source_url"
    ]

    private let session: URLSession
    private let endpoint: URL?

    init(
        session: URLSession = BeerDiscoverySession.make(),
        endpoint: URL? = URL(string: Config.beerSearchEndpoint)
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    var isConfigured: Bool {
        endpoint.map(Self.isAllowedProxyEndpoint) == true
    }

    func search(query: String, limit: Int) async throws -> [BeerDiscoveryCandidate] {
        guard let endpoint, Self.isAllowedProxyEndpoint(endpoint) else {
            throw BeerDiscoveryError.unavailable
        }
        guard (1...8).contains(limit),
              (2...160).contains(query.count),
              BeerDiscoveryText.normalize(query).count >= 2 else {
            throw BeerDiscoveryError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(BeerDiscoverySession.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "limit": limit
        ])
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let mimeType = http.mimeType?.lowercased(),
              mimeType == "application/json" || mimeType.hasSuffix("+json"),
              data.count <= Self.responseByteLimit else {
            throw BeerDiscoveryError.invalidResponse
        }
        return try Self.parseResponse(data, query: query, limit: limit)
    }

    static func parseResponse(_ data: Data, query: String, limit: Int) throws -> [BeerDiscoveryCandidate] {
        guard data.count <= responseByteLimit,
              (1...8).contains(limit),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["results"],
              let results = root["results"] as? [[String: Any]],
              results.count <= limit else {
            throw BeerDiscoveryError.invalidResponse
        }
        if results.isEmpty { return [] }

        var candidates: [BeerDiscoveryCandidate] = []
        candidates.reserveCapacity(results.count)
        for result in results {
            let keys = Set(result.keys)
            guard requiredResultKeys.isSubset(of: keys),
                  keys.isSubset(of: allowedResultKeys),
                  let rawName = result["name"] as? String,
                  let rawBrewery = result["brewery"] as? String,
                  let rawStyle = result["style"],
                  let rawURL = result["source_url"] as? String else {
                throw BeerDiscoveryError.invalidResponse
            }

            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let brewery = rawBrewery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidText(name, length: 2...100),
                  isValidText(brewery, length: 2...120),
                  let sourceURL = allowedSourceURL(rawURL) else {
                throw BeerDiscoveryError.invalidResponse
            }

            let styleName: String?
            if rawStyle is NSNull {
                styleName = nil
            } else if let style = rawStyle as? String {
                let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isValidText(trimmed, length: 2...120) else {
                    throw BeerDiscoveryError.invalidResponse
                }
                styleName = trimmed
            } else {
                throw BeerDiscoveryError.invalidResponse
            }

            let abv: Double?
            if result["abv"] == nil || result["abv"] is NSNull {
                abv = nil
            } else if !(result["abv"] is Bool),
                      let number = result["abv"] as? NSNumber,
                      let validated = BeerDiscoveryText.validatedABV(number) {
                abv = validated
            } else {
                abv = nil
            }

            let candidate = BeerDiscoveryCandidate(
                id: "web:\(BeerDiscoveryText.normalize(brewery)):\(BeerDiscoveryText.normalize(name))",
                name: name,
                brewery: brewery,
                styleName: styleName,
                coarseStyleName: BeerDiscoveryText.coarseStyle(
                    from: [styleName, name].compactMap { $0 }.joined(separator: " ")
                )?.rawValue,
                abv: abv,
                source: .webSearch,
                sourceURL: sourceURL
            )
            guard BeerDiscoveryRelevance.score(candidate, query: query) > 0 else {
                throw BeerDiscoveryError.invalidResponse
            }
            candidates.append(candidate)
        }
        return BeerDiscoveryMerger.merge(candidates, query: query, limit: limit)
    }

    private static func isAllowedProxyEndpoint(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.user == nil
            && url.password == nil
            && (url.port == nil || url.port == 443)
            && url.host?.contains(".") == true
    }

    private static func isValidText(_ value: String, length: ClosedRange<Int>) -> Bool {
        length.contains(value.count)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func allowedSourceURL(_ raw: String) -> URL? {
        guard raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.utf8.count <= 2_048,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              (4...253).contains(host.count),
              host.contains("."),
              !host.contains(":"),
              !isIPv4Address(host),
              let suffix = host.split(separator: ".").last.map(String.init),
              !reservedHostSuffixes.contains(suffix),
              host.split(separator: ".").allSatisfy({ label in
                  (1...63).contains(label.count)
                      && label.first != "-"
                      && label.last != "-"
                      && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
              }) else {
            return nil
        }
        return canonicalSourceURL(url)
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func canonicalSourceURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.host = components.host?.lowercased()

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path

        if let queryItems = components.queryItems {
            let retained = queryItems.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingQueryNames.contains(name)
            }
            components.queryItems = retained.isEmpty ? nil : retained
        }
        return components.url
    }
}

enum BeerDiscoveryMerger {
    static func merge(
        _ candidates: [BeerDiscoveryCandidate],
        query: String,
        limit: Int
    ) -> [BeerDiscoveryCandidate] {
        var indexed: [String: (BeerDiscoveryCandidate, Int)] = [:]
        for (index, candidate) in candidates.enumerated() {
            let key = "\(BeerDiscoveryText.normalize(candidate.name))|\(BeerDiscoveryText.normalize(candidate.brewery ?? ""))"
            if indexed[key] == nil { indexed[key] = (candidate, index) }
        }
        return indexed.values.sorted { lhs, rhs in
            let leftScore = BeerDiscoveryRelevance.score(lhs.0, query: query)
            let rightScore = BeerDiscoveryRelevance.score(rhs.0, query: query)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.1 < rhs.1
        }
        .prefix(max(0, limit))
        .map(\.0)
    }

    static func mergeWebFirst(
        web: [BeerDiscoveryCandidate],
        catalog: [BeerDiscoveryCandidate],
        limit: Int
    ) -> [BeerDiscoveryCandidate] {
        var seen: Set<String> = []
        return (web + catalog).filter { candidate in
            let key = "\(BeerDiscoveryText.normalize(candidate.name))|\(BeerDiscoveryText.normalize(candidate.brewery ?? ""))"
            return seen.insert(key).inserted
        }
        .prefix(max(0, limit))
        .map { $0 }
    }
}

private final class BeerDiscoveryCache {
    private struct Record: Codable {
        let candidates: [BeerDiscoveryCandidate]
        let expiresAt: Date
        let updatedAt: Date
    }

    private struct Snapshot: Codable {
        var records: [String: Record]
    }

    struct Lookup {
        let fresh: [BeerDiscoveryCandidate]?
        let stale: [BeerDiscoveryCandidate]?
    }

    private var snapshot: Snapshot
    private let writer: JSONSnapshotWriter<Snapshot>?
    private let now: () -> Date

    init(fileURL: URL?, now: @escaping () -> Date) {
        self.now = now
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot(records: [:])
        }
        writer = fileURL.map(JSONSnapshotWriter.init(fileURL:))
    }

    func lookup(query: String) -> Lookup {
        guard let record = snapshot.records[query] else {
            return Lookup(fresh: nil, stale: nil)
        }
        let current = now()
        if record.expiresAt > current {
            return Lookup(fresh: record.candidates, stale: nil)
        }
        let stale = !record.candidates.isEmpty
            && record.updatedAt.addingTimeInterval(7 * 24 * 60 * 60) > current
            ? record.candidates
            : nil
        return Lookup(fresh: nil, stale: stale)
    }

    func store(
        _ candidates: [BeerDiscoveryCandidate],
        for query: String,
        ttlOverride: TimeInterval? = nil
    ) {
        let current = now()
        let ttl: TimeInterval
        if let ttlOverride { ttl = ttlOverride }
        else if candidates.isEmpty { ttl = 10 * 60 }
        else if candidates.contains(where: { $0.source == .webSearch }) { ttl = 2 * 60 * 60 }
        else { ttl = 12 * 60 * 60 }

        snapshot.records[query] = Record(
            candidates: candidates,
            expiresAt: current.addingTimeInterval(ttl),
            updatedAt: current
        )
        if snapshot.records.count > 100 {
            let keysToRemove = snapshot.records
                .sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(snapshot.records.count - 100)
                .map(\.key)
            keysToRemove.forEach { snapshot.records.removeValue(forKey: $0) }
        }
        writer?.schedule(snapshot)
    }

    func flush() {
        writer?.flush()
    }
}

actor BeerDiscoveryService {
    static let shared = BeerDiscoveryService()

    private let catalogClient: CatalogBeerSearchClient
    private let webSearchClient: BeerSearchProxyClient
    private let cache: BeerDiscoveryCache
    private let mockSearch: Bool
    private let networkAvailable: @Sendable () -> Bool

    init(
        session: URLSession = BeerDiscoverySession.make(),
        cacheURL: URL? = BeerDiscoveryService.defaultCacheURL,
        now: @escaping () -> Date = Date.init,
        mockSearch: Bool = ProcessInfo.processInfo.arguments.contains("--mock-beer-search"),
        webSearchEndpoint: URL? = URL(string: Config.beerSearchEndpoint),
        networkAvailable: @escaping @Sendable () -> Bool = { NetworkMonitor.shared.isSatisfied }
    ) {
        catalogClient = CatalogBeerSearchClient(session: session)
        webSearchClient = BeerSearchProxyClient(session: session, endpoint: webSearchEndpoint)
        cache = BeerDiscoveryCache(fileURL: cacheURL, now: now)
        self.mockSearch = mockSearch
        self.networkAvailable = networkAvailable
    }

    func search(
        query: String,
        limit: Int = 8,
        onCatalogResults: (([BeerDiscoveryCandidate]) async -> Void)? = nil
    ) async throws -> [BeerDiscoveryCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = BeerDiscoveryText.normalize(trimmed)
        // Beer and brewery names are short. A hard input cap prevents pasted
        // prose or prompt-like payloads from becoming large URL/model requests;
        // the exact typed action in the UI remains available regardless.
        guard (2...160).contains(trimmed.count), normalized.count >= 2, limit > 0 else {
            return []
        }
        let fetchLimit = 8
        if mockSearch { return Array(mockCandidates(for: normalized).prefix(limit)) }

        let cached = cache.lookup(query: normalized)
        if let fresh = cached.fresh { return Array(fresh.prefix(limit)) }
        guard networkAvailable() else {
            if let stale = cached.stale { return Array(stale.prefix(limit)) }
            throw BeerDiscoveryError.unavailable
        }

        var catalogSucceeded = false
        var webSearchSucceeded = false
        var webSearchAttempted = false
        var usedStaleWebTopUp = false
        var results: [BeerDiscoveryCandidate] = []
        do {
            results = try await catalogClient.search(query: trimmed, limit: fetchLimit)
            catalogSucceeded = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            results = []
        }
        try Task.checkCancellation()

        // Catalog is the fast connected tier. Let the UI publish it now while
        // a weak/brewery match continues to a fresher web top-up; a slow model
        // must not hide a useful result we already have.
        if !results.isEmpty {
            await onCatalogResults?(Array(results.prefix(limit)))
            try Task.checkCancellation()
        }

        let catalogResults = results
        let shouldSearchWeb = Self.needsWebTopUp(
            catalogResults: catalogResults,
            query: trimmed
        )
        if shouldSearchWeb, webSearchClient.isConfigured {
            webSearchAttempted = true
            do {
                let webResults = try await webSearchClient.search(query: trimmed, limit: fetchLimit)
                results = BeerDiscoveryMerger.mergeWebFirst(
                    web: webResults,
                    catalog: catalogResults,
                    limit: fetchLimit
                )
                webSearchSucceeded = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let staleWeb = cached.stale?.filter { $0.source == .webSearch } ?? []
                if staleWeb.isEmpty {
                    results = catalogResults
                } else {
                    results = BeerDiscoveryMerger.mergeWebFirst(
                        web: staleWeb,
                        catalog: catalogResults,
                        limit: fetchLimit
                    )
                    usedStaleWebTopUp = true
                }
            }
        }
        try Task.checkCancellation()

        if results.isEmpty, !catalogSucceeded, !webSearchSucceeded {
            if let stale = cached.stale { return Array(stale.prefix(limit)) }
            throw BeerDiscoveryError.unavailable
        }
        if !usedStaleWebTopUp,
           !results.isEmpty || webSearchSucceeded || !webSearchClient.isConfigured {
            let degradedTopUp = webSearchAttempted
                && !results.contains(where: { $0.source == .webSearch })
            cache.store(
                results,
                for: normalized,
                ttlOverride: degradedTopUp ? 10 * 60 : nil
            )
        }
        return Array(results.prefix(limit))
    }

    func flushCacheForTesting() {
        cache.flush()
    }

    private static func needsWebTopUp(
        catalogResults: [BeerDiscoveryCandidate],
        query: String
    ) -> Bool {
        guard !catalogResults.isEmpty else { return true }
        guard let best = catalogResults.max(by: {
            BeerDiscoveryRelevance.score($0, query: query)
                < BeerDiscoveryRelevance.score($1, query: query)
        }) else { return true }
        let bestRelevance = BeerDiscoveryRelevance.score(best, query: query)
        if bestRelevance < 92 { return true }
        if best.beerStyle == nil { return true }

        let queryBrewery = breweryIdentity(query)
        return catalogResults.contains { candidate in
            guard let brewery = candidate.brewery else { return false }
            return breweryIdentity(brewery) == queryBrewery
        }
    }

    private static func breweryIdentity(_ value: String) -> String {
        let suffixes = Set(["brewery", "brewing", "company", "co"])
        return BeerDiscoveryText.normalize(value)
            .split(separator: " ")
            .map(String.init)
            .filter { !suffixes.contains($0) }
            .joined(separator: " ")
    }

    private func mockCandidates(for query: String) -> [BeerDiscoveryCandidate] {
        guard query.contains("neighborhood fermentary") || query.contains("harbor fog") else { return [] }
        return [
            BeerDiscoveryCandidate(
                id: "mock:harbor-fog",
                name: "Harbor Fog IPA",
                brewery: "Neighborhood Fermentary",
                styleName: "West Coast IPA",
                coarseStyleName: BeerStyle.ipa.rawValue,
                abv: 6.8,
                source: .webSearch,
                sourceURL: URL(string: "https://neighborhood-fermentary.example/beers/harbor-fog")!
            )
        ]
    }

    private static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("beer-discovery-cache.json")
    }
}

enum BeerDiscoverySession {
    static let userAgent = "SipCheck/1.0 (+https://github.com/rishi09/sipcheck; user-triggered beer search)"

    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: configuration)
    }
}
