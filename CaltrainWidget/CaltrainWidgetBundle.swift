// CaltrainWidgetBundle.swift
// Widget extension entry point

import WidgetKit
import SwiftUI

@main
struct CaltrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaltrainWidget()
        CaltrainLockScreenWidget()
    }
}
