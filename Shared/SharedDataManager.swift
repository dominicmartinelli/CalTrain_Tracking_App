// SharedDataManager.swift
// Manages shared data between main app and widget via App Group

import Foundation
import WidgetKit

class SharedDataManager {
    static let shared = SharedDataManager()

    private let userDefaults: UserDefaults?

    private init() {
        userDefaults = UserDefaults(suiteName: WidgetConstants.appGroupID)
    }

    // MARK: - Write Methods (Called from Main App)

    /// Save departures and station names, then trigger widget refresh
    func saveDepartures(northbound: [SharedDeparture], southbound: [SharedDeparture],
                        northStationName: String, southStationName: String) {
        // Save departures
        if let northData = try? JSONEncoder().encode(northbound) {
            userDefaults?.set(northData, forKey: WidgetConstants.northboundDeparturesKey)
        }
        if let southData = try? JSONEncoder().encode(southbound) {
            userDefaults?.set(southData, forKey: WidgetConstants.southboundDeparturesKey)
        }
        // Save station names
        userDefaults?.set(northStationName, forKey: WidgetConstants.northboundStopNameKey)
        userDefaults?.set(southStationName, forKey: WidgetConstants.southboundStopNameKey)
        // Update timestamp
        userDefaults?.set(Date(), forKey: WidgetConstants.lastUpdateKey)
    }

    // MARK: - Read Methods (Called from Widget)

    /// Load cached northbound departures
    func loadNorthboundDepartures() -> [SharedDeparture] {
        guard let data = userDefaults?.data(forKey: WidgetConstants.northboundDeparturesKey),
              let departures = try? JSONDecoder().decode([SharedDeparture].self, from: data) else {
            return []
        }
        return departures.filter { $0.isUpcoming }
    }

    /// Load cached southbound departures
    func loadSouthboundDepartures() -> [SharedDeparture] {
        guard let data = userDefaults?.data(forKey: WidgetConstants.southboundDeparturesKey),
              let departures = try? JSONDecoder().decode([SharedDeparture].self, from: data) else {
            return []
        }
        return departures.filter { $0.isUpcoming }
    }

    /// Get saved northbound stop name
    func northboundStopName() -> String {
        userDefaults?.string(forKey: WidgetConstants.northboundStopNameKey) ?? "Mountain View"
    }

    /// Get saved southbound stop name
    func southboundStopName() -> String {
        userDefaults?.string(forKey: WidgetConstants.southboundStopNameKey) ?? "22nd Street"
    }

    /// Check if cached data is still valid
    func isCacheValid() -> Bool {
        guard let lastUpdate = userDefaults?.object(forKey: WidgetConstants.lastUpdateKey) as? Date else {
            return false
        }
        let elapsedMinutes = Date().timeIntervalSince(lastUpdate) / 60
        return elapsedMinutes < WidgetConstants.cacheExpirationMinutes
    }
}
