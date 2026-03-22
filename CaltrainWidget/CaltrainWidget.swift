// CaltrainWidget.swift
// Main widget definitions

import WidgetKit
import SwiftUI

// MARK: - Home Screen Widget

struct CaltrainWidget: Widget {
    let kind: String = "CaltrainWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: DepartureTimelineProvider()
        ) { entry in
            CaltrainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Caltrain Departures")
        .description("See upcoming train departures from your stations.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CaltrainWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DepartureEntry

    var body: some View {
        Group {
            if !entry.hasData {
                noDataView
            } else {
                switch family {
                case .systemSmall:
                    SmallWidgetView(entry: entry)
                case .systemMedium:
                    MediumWidgetView(entry: entry)
                default:
                    SmallWidgetView(entry: entry)
                }
            }
        }
    }

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "train.side.front.car")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Open app to load trains")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Lock Screen Widget

struct CaltrainLockScreenWidget: Widget {
    let kind: String = "CaltrainLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: DepartureTimelineProvider()
        ) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Train")
        .description("Quick view of next departure time.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CaltrainWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [
            SharedDeparture(journeyRef: "1", minutes: 12, depTime: Date().addingTimeInterval(720),
                          direction: "N", destination: "San Francisco", trainNumber: "123",
                          arrivalTime: nil, delayMinutes: nil)
        ],
        southDepartures: [],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: false,
        configuration: ConfigurationAppIntent()
    )
}

#Preview("Medium", as: .systemMedium) {
    CaltrainWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [
            SharedDeparture(journeyRef: "1", minutes: 5, depTime: Date().addingTimeInterval(300),
                          direction: "N", destination: "SF", trainNumber: "101",
                          arrivalTime: nil, delayMinutes: 2),
            SharedDeparture(journeyRef: "2", minutes: 18, depTime: Date().addingTimeInterval(1080),
                          direction: "N", destination: "SF", trainNumber: "103",
                          arrivalTime: nil, delayMinutes: nil)
        ],
        southDepartures: [
            SharedDeparture(journeyRef: "3", minutes: 8, depTime: Date().addingTimeInterval(480),
                          direction: "S", destination: "SJ", trainNumber: "102",
                          arrivalTime: nil, delayMinutes: nil)
        ],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: false,
        configuration: ConfigurationAppIntent()
    )
}

#Preview("No Data", as: .systemSmall) {
    CaltrainWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [],
        southDepartures: [],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: true,
        configuration: ConfigurationAppIntent()
    )
}
