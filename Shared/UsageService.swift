import Foundation

enum UsageServiceError: LocalizedError {
    case noSessionKey
    case noOrganization
    case unauthorized
    case cloudflareBlocked
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noSessionKey: return "No session key configured"
        case .noOrganization: return "Could not find organization"
        case .unauthorized: return "Session key expired or invalid"
        case .cloudflareBlocked: return "Blocked by Cloudflare — retrying with browser cookies"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

enum UsageService {
    private static let baseURL = "https://claude.ai/api"
    private static let appGroupID = "group.com.juicebox.claudeusage"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Cached Cloudflare cookies from WKWebView solve
    private static var cfCookies: [String: String] = [:]

    static func fetchUsage() async throws -> UsageData {
        guard let sessionKey = KeychainHelper.loadSessionKey() else {
            throw UsageServiceError.noSessionKey
        }

        do {
            return try await fetchUsageDirectly(sessionKey: sessionKey)
        } catch UsageServiceError.cloudflareBlocked {
            // Cloudflare blocked us — use WKWebView to solve the challenge
            print("[DEBUG] Cloudflare blocked, solving challenge via WKWebView...")
            let solver = await CloudflareSolver()
            let cookies = try await solver.solveChallengeAndGetCookies(sessionKey: sessionKey)

            // Store the CF cookies for subsequent requests
            cfCookies = [:]
            for cookie in cookies {
                cfCookies[cookie.name] = cookie.value
            }

            // Retry with the CF cookies
            return try await fetchUsageDirectly(sessionKey: sessionKey)
        }
    }

    private static func fetchUsageDirectly(sessionKey: String) async throws -> UsageData {
        let orgID = try await fetchOrganizationID(sessionKey: sessionKey)
        let usage = try await fetchUsageData(sessionKey: sessionKey, orgID: orgID)

        if let encoded = try? JSONEncoder().encode(usage) {
            sharedDefaults?.set(encoded, forKey: "cachedUsage")
        }

        return usage
    }

    static func cachedUsage() -> UsageData? {
        guard let data = sharedDefaults?.data(forKey: "cachedUsage") else { return nil }
        return try? JSONDecoder().decode(UsageData.self, from: data)
    }

    // MARK: - Private

    private static func fetchOrganizationID(sessionKey: String) async throws -> String {
        if let cached = sharedDefaults?.string(forKey: "orgID") {
            return cached
        }

        let url = URL(string: "\(baseURL)/organizations")!
        let request = makeRequest(url: url, sessionKey: sessionKey)

        let (data, response) = try await performRequest(request)
        try checkResponse(response)

        do {
            let orgs = try JSONDecoder().decode([OrganizationResponse].self, from: data)
            guard let org = orgs.first else {
                throw UsageServiceError.noOrganization
            }
            sharedDefaults?.set(org.uuid, forKey: "orgID")
            return org.uuid
        } catch let error as UsageServiceError {
            throw error
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }

    private static func fetchUsageData(sessionKey: String, orgID: String) async throws -> UsageData {
        let url = URL(string: "\(baseURL)/organizations/\(orgID)/usage")!
        let request = makeRequest(url: url, sessionKey: sessionKey)

        let (data, response) = try await performRequest(request)
        try checkResponse(response)

        do {
            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            return mapResponse(usage)
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }

    private static func makeRequest(url: URL, sessionKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false

        // Build full cookie header with session key + any Cloudflare cookies
        var cookieParts = ["sessionKey=\(sessionKey)"]
        for (name, value) in cfCookies where name != "sessionKey" {
            cookieParts.append("\(name)=\(value)")
        }
        request.setValue(cookieParts.joined(separator: "; "), forHTTPHeaderField: "Cookie")

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Use a realistic browser User-Agent to reduce Cloudflare challenges
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30
        return request
    }

    private static func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw UsageServiceError.networkError(error)
        }
    }

    private static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        print("[UsageService] HTTP \(http.statusCode) from \(http.url?.absoluteString ?? "?")")

        if http.statusCode == 403 {
            // Check if it's a Cloudflare challenge vs actual auth failure
            let cfMitigated = http.value(forHTTPHeaderField: "cf-mitigated")
            if cfMitigated != nil || http.value(forHTTPHeaderField: "cf-ray") != nil {
                // Check response size — Cloudflare challenge pages are large HTML
                // while actual 403s from the API are small JSON
                if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
                   contentType.contains("text/html") {
                    sharedDefaults?.removeObject(forKey: "orgID")
                    throw UsageServiceError.cloudflareBlocked
                }
            }
            sharedDefaults?.removeObject(forKey: "orgID")
            throw UsageServiceError.unauthorized
        }

        if http.statusCode == 401 {
            sharedDefaults?.removeObject(forKey: "orgID")
            throw UsageServiceError.unauthorized
        }
    }

    private static func mapResponse(_ response: UsageResponse) -> UsageData {
        let iso = ISO8601DateFormatter()

        return UsageData(
            sessionWindow: UsageWindow(
                utilizationPercent: response.fiveHour?.utilizationPercent ?? 0,
                resetsAt: response.fiveHour?.resetsAt.flatMap { iso.date(from: $0) }
            ),
            weeklyUsage: UsageWindow(
                utilizationPercent: response.sevenDay?.utilizationPercent ?? 0,
                resetsAt: response.sevenDay?.resetsAt.flatMap { iso.date(from: $0) }
            ),
            opusWeekly: response.sevenDayOpus.map { opus in
                UsageWindow(
                    utilizationPercent: opus.utilizationPercent ?? 0,
                    resetsAt: opus.resetsAt.flatMap { iso.date(from: $0) }
                )
            },
            fetchedAt: Date()
        )
    }

    static func clearCache() {
        sharedDefaults?.removeObject(forKey: "orgID")
        sharedDefaults?.removeObject(forKey: "cachedUsage")
        cfCookies = [:]
    }
}
