// ConfigurationAppIntent.swift
// Widget configuration intent for iOS 17+

import AppIntents
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Widget"
    static var description = IntentDescription("Choose which trains to display.")

    @Parameter(title: "Direction", default: .both)
    var direction: TrainDirection

    @Parameter(title: "Show Delays", default: true)
    var showDelays: Bool
}

enum TrainDirection: String, AppEnum {
    case northbound = "northbound"
    case southbound = "southbound"
    case both = "both"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"

    static var caseDisplayRepresentations: [TrainDirection: DisplayRepresentation] = [
        .northbound: DisplayRepresentation(title: "Northbound", subtitle: "Toward San Francisco"),
        .southbound: DisplayRepresentation(title: "Southbound", subtitle: "Toward San Jose"),
        .both: DisplayRepresentation(title: "Both Directions", subtitle: "Show all trains")
    ]
}
