// DepartureTimelineProvider.swift
// Timeline provider for widget updates

import WidgetKit
import SwiftUI

struct DepartureEntry: TimelineEntry {
    let date: Date
    let northDepartures: [SharedDeparture]
    let southDepartures: [SharedDeparture]
    let northStationName: String
    let southStationName: String
    let isStale: Bool
    let configuration: ConfigurationAppIntent

    /// Check if we have any departure data
    var hasData: Bool {
        !northDepartures.isEmpty || !southDepartures.isEmpty
    }
}

struct DepartureTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = DepartureEntry
    typealias Intent = ConfigurationAppIntent

    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(
            date: Date(),
            northDepartures: [Self.sampleDeparture(direction: "N", minutes: 12)],
            southDepartures: [Self.sampleDeparture(direction: "S", minutes: 8)],
            northStationName: "Mountain View",
            southStationName: "22nd Street",
            isStale: false,
            configuration: ConfigurationAppIntent()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> DepartureEntry {
        loadEntry(for: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<DepartureEntry> {
        let entry = loadEntry(for: configuration)

        // Calculate optimal refresh time
        let refreshDate: Date
        if let nextDeparture = entry.northDepartures.first?.depTime ?? entry.southDepartures.first?.depTime {
            // Refresh 1 minute after next train departs
            refreshDate = nextDeparture.addingTimeInterval(60)
        } else {
            // No trains - check again in 5 minutes
            refreshDate = Date().addingTimeInterval(300)
        }

        // Cap at 15 minutes max between refreshes
        let maxRefresh = Date().addingTimeInterval(900)
        let finalRefresh = min(refreshDate, maxRefresh)

        return Timeline(entries: [entry], policy: .after(finalRefresh))
    }

    private func loadEntry(for configuration: ConfigurationAppIntent) -> DepartureEntry {
        let manager = SharedDataManager.shared

        let northDepartures = manager.loadNorthboundDepartures()
        let southDepartures = manager.loadSouthboundDepartures()
        let northName = manager.northboundStopName()
        let southName = manager.southboundStopName()
        let isStale = !manager.isCacheValid()

        return DepartureEntry(
            date: Date(),
            northDepartures: northDepartures,
            southDepartures: southDepartures,
            northStationName: northName,
            southStationName: southName,
            isStale: isStale,
            configuration: configuration
        )
    }

    // MARK: - Sample Data

    private static func sampleDeparture(direction: String, minutes: Int) -> SharedDeparture {
        SharedDeparture(
            journeyRef: "sample-\(direction)",
            minutes: minutes,
            depTime: Date().addingTimeInterval(Double(minutes) * 60),
            direction: direction,
            destination: direction == "N" ? "San Francisco" : "San Jose",
            trainNumber: "123",
            arrivalTime: nil,
            delayMinutes: nil
        )
    }
}
