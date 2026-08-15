import Foundation

/// Pulls identifying details out of a host's HTTP service.
///
/// Used on demand from the detail screen, never during a sweep: a scan should
/// not wait on someone's slow router web UI.
enum HTTPFingerprinter {

    struct Fingerprint: Sendable, Hashable {
        var statusCode: Int
        var server: String?
        var title: String?
        var poweredBy: String?
        var realm: String?
        var redirectsTo: String?

        var summary: String {
            [title, server, poweredBy]
                .compactMap { $0 }
                .first ?? "HTTP \(statusCode)"
        }
    }

    /// Fetches the root document and extracts server headers plus `<title>`.
    static func fingerprint(
        address: IPv4,
        port: UInt16,
        useTLS: Bool,
        timeout: TimeInterval = 3
    ) async -> Fingerprint? {
        let scheme = useTLS ? "https" : "http"
        var components = URLComponents()
        components.scheme = scheme
        components.host = address.description
        components.port = Int(port)
        components.path = "/"

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        request.setValue("NetScope/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            let headers = http.allHeaderFields
            func header(_ name: String) -> String? {
                headers.first { ($0.key as? String)?.lowercased() == name }?.value as? String
            }

            // Only the first few KB are needed to find a <title>.
            let body = String(decoding: data.prefix(16 * 1024), as: UTF8.self)

            return Fingerprint(
                statusCode: http.statusCode,
                server: header("server"),
                title: extractTitle(from: body),
                poweredBy: header("x-powered-by"),
                realm: header("www-authenticate"),
                redirectsTo: header("location")
            )
        } catch {
            // Self-signed TLS, plain-text-only servers and refused connections
            // all land here; the caller simply shows nothing.
            return nil
        }
    }

    private static func extractTitle(from html: String) -> String? {
        guard let openRange = html.range(of: "<title", options: .caseInsensitive),
              let contentStart = html.range(of: ">", range: openRange.upperBound..<html.endIndex),
              let closeRange = html.range(of: "</title>", options: .caseInsensitive, range: contentStart.upperBound..<html.endIndex)
        else { return nil }

        let title = html[contentStart.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        return title.isEmpty ? nil : String(title.prefix(120))
    }
}
