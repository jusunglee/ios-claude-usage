import Foundation

struct UsageData: Codable {
    let sessionWindow: UsageWindow
    let weeklyUsage: UsageWindow
    let opusWeekly: UsageWindow?
    let sonnetWeekly: UsageWindow?
    let fetchedAt: Date

    static let placeholder = UsageData(
        sessionWindow: UsageWindow(utilizationPercent: 35, resetsAt: Date().addingTimeInterval(3600)),
        weeklyUsage: UsageWindow(utilizationPercent: 60, resetsAt: Date().addingTimeInterval(86400 * 3)),
        opusWeekly: nil,
        sonnetWeekly: UsageWindow(utilizationPercent: 45, resetsAt: Date().addingTimeInterval(86400 * 3)),
        fetchedAt: Date()
    )
}

struct UsageWindow: Codable {
    let utilizationPercent: Double
    let resetsAt: Date?

    var timeUntilReset: String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "Now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - API Response Types

struct OrganizationResponse: Codable {
    let uuid: String
    let name: String?
}

struct UsageResponse: Codable {
    let fiveHour: UsageWindowResponse?
    let sevenDay: UsageWindowResponse?
    let sevenDayOpus: UsageWindowResponse?
    let sevenDaySonnet: UsageWindowResponse?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindowResponse: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
