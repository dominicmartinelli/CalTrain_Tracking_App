// SharedDeparture.swift
// Codable departure model for sharing between main app and widget

import Foundation

struct SharedDeparture: Codable, Identifiable, Hashable {
    var id: String { journeyRef + (depTime?.ISO8601Format() ?? "") }
    let journeyRef: String
    let minutes: Int
    let depTime: Date?
    let direction: String?
    let destination: String?
    let trainNumber: String?
    let arrivalTime: Date?
    let delayMinutes: Int?

    /// Recalculate minutes based on current time (for widget display)
    var currentMinutes: Int {
        guard let depTime = depTime else { return max(0, minutes) }
        return max(0, Int(ceil(depTime.timeIntervalSinceNow / 60)))
    }

    /// Check if this departure is still in the future
    var isUpcoming: Bool {
        currentMinutes > 0
    }

    /// Formatted departure time string
    var formattedTime: String {
        guard let depTime = depTime else { return "--:--" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: depTime)
    }
}
