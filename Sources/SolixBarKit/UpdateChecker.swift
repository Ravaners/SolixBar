import Foundation

struct ReleaseInfo: Equatable, Sendable {
    let version: String
    let url: URL
}

/// Fragt das neueste GitHub-Release ab und vergleicht Versionen.
/// Netzwerkfehler sind hier nie fatal — der Aufrufer schluckt sie still,
/// damit ein Offline-Rechner keine Fehlermeldungen produziert.
enum UpdateChecker {
    static let releasesPageURL = URL(string: "https://github.com/itsab1989/SolixBar/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/itsab1989/SolixBar/releases/latest")!

    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }

    static func fetchLatestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SolixProviderError.httpError(http.statusCode)
        }
        let release = try JSONDecoder().decode(LatestRelease.self, from: data)
        return ReleaseInfo(
            version: release.tagName,
            url: URL(string: release.htmlUrl) ?? releasesPageURL
        )
    }

    /// Numerischer Segment-Vergleich ("v0.10.1" > "0.9"), tolerant gegenüber
    /// v-Präfix und unterschiedlich vielen Segmenten. Unparsbares gilt nie
    /// als neuer; ein Dev-Build (unbundled) ist nie veraltet.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        guard current != "dev" else { return false }
        guard let remote = versionComponents(tag), let local = versionComponents(current) else {
            return false
        }
        let count = max(remote.count, local.count)
        for index in 0..<count {
            let r = index < remote.count ? remote[index] : 0
            let l = index < local.count ? local[index] : 0
            if r != l { return r > l }
        }
        return false
    }

    private static func versionComponents(_ raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text = String(text.dropFirst())
        }
        guard !text.isEmpty else { return nil }
        var components: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        return components.isEmpty ? nil : components
    }
}
