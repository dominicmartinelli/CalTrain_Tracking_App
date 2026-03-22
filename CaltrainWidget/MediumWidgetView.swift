// MediumWidgetView.swift
// Medium widget showing departures for both directions

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: DepartureEntry

    var body: some View {
        HStack(spacing: 0) {
            // Northbound column
            DirectionColumn(
                title: "Northbound",
                stationName: entry.northStationName,
                icon: "arrow.up",
                color: .blue,
                departures: Array(entry.northDepartures.prefix(3)),
                showDelays: entry.configuration.showDelays
            )

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
                .padding(.vertical, 8)

            // Southbound column
            DirectionColumn(
                title: "Southbound",
                stationName: entry.southStationName,
                icon: "arrow.down",
                color: .orange,
                departures: Array(entry.southDepartures.prefix(3)),
                showDelays: entry.configuration.showDelays
            )
        }
        .overlay(alignment: .bottom) {
            if entry.isStale {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                    Text("Open app to refresh")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.bottom, 4)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DirectionColumn: View {
    let title: String
    let stationName: String
    let icon: String
    let color: Color
    let departures: [SharedDeparture]
    let showDelays: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text(stationName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            // Departures list
            if departures.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No trains")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(departures) { dep in
                    DepartureRowView(departure: dep, showDelays: showDelays, color: color)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DepartureRowView: View {
    let departure: SharedDeparture
    let showDelays: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            // Time in minutes
            Text("\(departure.currentMinutes)")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text("min")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            // Train number
            if let trainNum = departure.trainNumber {
                Text("#\(trainNum)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Delay indicator
            if showDelays, let delay = departure.delayMinutes, delay > 0 {
                Text("+\(delay)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

#Preview(as: .systemMedium) {
    CaltrainWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [
            SharedDeparture(journeyRef: "1", minutes: 5, depTime: Date().addingTimeInterval(300),
                          direction: "N", destination: "SF", trainNumber: "101", arrivalTime: nil, delayMinutes: 2),
            SharedDeparture(journeyRef: "2", minutes: 18, depTime: Date().addingTimeInterval(1080),
                          direction: "N", destination: "SF", trainNumber: "103", arrivalTime: nil, delayMinutes: nil),
            SharedDeparture(journeyRef: "3", minutes: 32, depTime: Date().addingTimeInterval(1920),
                          direction: "N", destination: "SF", trainNumber: "105", arrivalTime: nil, delayMinutes: nil)
        ],
        southDepartures: [
            SharedDeparture(journeyRef: "4", minutes: 8, depTime: Date().addingTimeInterval(480),
                          direction: "S", destination: "SJ", trainNumber: "102", arrivalTime: nil, delayMinutes: nil),
            SharedDeparture(journeyRef: "5", minutes: 24, depTime: Date().addingTimeInterval(1440),
                          direction: "S", destination: "SJ", trainNumber: "104", arrivalTime: nil, delayMinutes: 5)
        ],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: false,
        configuration: ConfigurationAppIntent()
    )
}
