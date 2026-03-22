// LockScreenWidgetView.swift
// Lock screen accessory widgets

import SwiftUI
import WidgetKit

struct LockScreenWidgetView: View {
    let entry: DepartureEntry
    @Environment(\.widgetFamily) var family

    private var nextDeparture: SharedDeparture? {
        // For lock screen, show whichever direction has the sooner train
        let north = entry.northDepartures.first
        let south = entry.southDepartures.first

        guard let n = north, let s = south else {
            return north ?? south
        }

        return n.currentMinutes <= s.currentMinutes ? n : s
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        default:
            accessoryRectangular
        }
    }

    // MARK: - Circular

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12))
                    .widgetAccentable()

                if let next = nextDeparture {
                    Text("\(next.currentMinutes)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("min")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Rectangular

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                Text("Next Caltrain")
                    .font(.caption2.bold())
            }
            .widgetAccentable()

            if let next = nextDeparture {
                // Main info
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(next.currentMinutes)")
                        .font(.system(.title2, design: .rounded, weight: .bold))

                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if entry.configuration.showDelays,
                       let delay = next.delayMinutes, delay > 0 {
                        Text("(+\(delay))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Train details
                HStack(spacing: 4) {
                    if let trainNum = next.trainNumber {
                        Text("Train #\(trainNum)")
                    }
                    if let dest = next.destination {
                        Text("to \(dest)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("No scheduled trains")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline

    private var accessoryInline: some View {
        if let next = nextDeparture {
            let delayText = (entry.configuration.showDelays && (next.delayMinutes ?? 0) > 0)
                ? " (+\(next.delayMinutes!))"
                : ""
            return Label("Next: \(next.currentMinutes)m\(delayText)", systemImage: "tram.fill")
        } else {
            return Label("No trains", systemImage: "tram.fill")
        }
    }
}

#Preview(as: .accessoryRectangular) {
    CaltrainLockScreenWidget()
} timeline: {
    DepartureEntry(
        date: Date(),
        northDepartures: [
            SharedDeparture(journeyRef: "1", minutes: 8, depTime: Date().addingTimeInterval(480),
                          direction: "N", destination: "San Francisco", trainNumber: "123",
                          arrivalTime: nil, delayMinutes: 2)
        ],
        southDepartures: [],
        northStationName: "Mountain View",
        southStationName: "22nd Street",
        isStale: false,
        configuration: ConfigurationAppIntent()
    )
}
