// SmallWidgetView.swift
// Small widget showing next departure for one direction

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: DepartureEntry

    private var departures: [SharedDeparture] {
        switch entry.configuration.direction {
        case .northbound:
            return entry.northDepartures
        case .southbound:
            return entry.southDepartures
        case .both:
            return entry.northDepartures // Default to northbound for small widget
        }
    }

    private var stationName: String {
        switch entry.configuration.direction {
        case .northbound, .both:
            return entry.northStationName
        case .southbound:
            return entry.southStationName
        }
    }

    private var directionIcon: String {
        switch entry.configuration.direction {
        case .northbound, .both:
            return "arrow.up"
        case .southbound:
            return "arrow.down"
        }
    }

    private var directionColor: Color {
        switch entry.configuration.direction {
        case .northbound, .both:
            return .blue
        case .southbound:
            return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: directionIcon)
                    .font(.caption.bold())
                    .foregroundStyle(directionColor)
                Text(stationName)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Main content
            if let next = departures.first {
                // Large minute display
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(next.currentMinutes)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                    Text("min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Train info
                HStack(spacing: 4) {
                    if let trainNum = next.trainNumber {
                        Text("#\(trainNum)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if entry.configuration.showDelays,
                       let delay = next.delayMinutes, delay > 0 {
                        Text("+\(delay)")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                // No trains
                VStack(spacing: 4) {
                    Image(systemName: "train.side.front.car")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No trains")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Stale indicator
            if entry.isStale {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("Tap to refresh")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview(as: .systemSmall) {
    CaltrainWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [
            SharedDeparture(journeyRef: "1", minutes: 12, depTime: Date().addingTimeInterval(720),
                          direction: "N", destination: "SF", trainNumber: "123", arrivalTime: nil, delayMinutes: nil)
        ],
        southDepartures: [],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: false,
        configuration: ConfigurationAppIntent()
    )
}
