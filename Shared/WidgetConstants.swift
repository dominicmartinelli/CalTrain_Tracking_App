// WidgetConstants.swift
// Shared constants for main app and widget extension

import Foundation

enum WidgetConstants {
    static let appGroupID = "group.com.caltraintracker.app"

    // UserDefaults keys for shared data
    static let northboundDeparturesKey = "widget_northbound_departures"
    static let southboundDeparturesKey = "widget_southbound_departures"
    static let lastUpdateKey = "widget_last_update"
    static let northboundStopCodeKey = "widget_northbound_stop_code"
    static let southboundStopCodeKey = "widget_southbound_stop_code"
    static let northboundStopNameKey = "widget_northbound_stop_name"
    static let southboundStopNameKey = "widget_southbound_stop_name"

    // Cache settings
    static let cacheExpirationMinutes: Double = 15
}
