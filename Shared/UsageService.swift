import Foundation

enum UsageServiceError: LocalizedError {
    case noSessionKey
    case noOrganization
    case unauthorized
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noSessionKey: return "No session key configured"
        case .noOrganization: return "Could not find organization"
        case .unauthorized: return "Session key expired or invalid"
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

    static func fetchUsage() async throws -> UsageData {
        guard let sessionKey = KeychainHelper.loadSessionKey() else {
            throw UsageServiceError.noSessionKey
        }

        let orgID = try await fetchOrganizationID(sessionKey: sessionKey)
        let usage = try await fetchUsageData(sessionKey: sessionKey, orgID: orgID)

        // Cache the result for widget access
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
        // Check cached org ID first
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
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
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
        if http.statusCode == 401 || http.statusCode == 403 {
            // Clear cached org ID on auth failure
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

    /// Clear cached org ID (useful when switching accounts)
    static func clearCache() {
        sharedDefaults?.removeObject(forKey: "orgID")
        sharedDefaults?.removeObject(forKey: "cachedUsage")
    }
}
