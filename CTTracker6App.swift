// Caltrain Tracking App (iOS 17+, single file)
// - Single @main app file
// - Uses .task { } + iOS17 .onChange(of:initial:) (no .task(id:) ambiguity)
// - Robust 511 SIRI decode (wrapped/bare root, array/single deliveries, String/[String] destination)
// - Keychain-backed API key gate with full-screen cover
// - Bay Area events via Ticketmaster Discovery API

import SwiftUI
import Combine
import Foundation
import Security

// MARK: - Global App State
final class AppState: ObservableObject {
    @Published var hasKey: Bool = (Keychain.shared["api_511"]?.isEmpty == false)
    func refreshFromKeychain() { hasKey = (Keychain.shared["api_511"]?.isEmpty == false) }
    func clearKey() { Keychain.shared["api_511"] = nil; hasKey = false }
    func saveKey(_ key: String) { Keychain.shared["api_511"] = key; hasKey = true }
}

// MARK: - Optional embedded key (simulator only)
private let EmbeddedAPIKey_SIMULATOR_ONLY: String? = {
#if targetEnvironment(simulator)
    return nil // e.g. "2d8f9a3e-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#else
    return nil
#endif
}()

// MARK: - Helpers
@inline(__always)
func isLikelyAPIKey(_ key: String) -> Bool {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 256 else { return false }
    // Allow letters, numbers, hyphens, underscores, and dots (common in API keys)
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
    return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
}

// MARK: - App Entry (single @main)
@main
struct CaltrainCheckerApp: App {
    @StateObject private var app = AppState()
    @State private var showSplash = true

    init() {
        // Seed Keychain from embedded key if none present
        if (Keychain.shared["api_511"] ?? "").isEmpty,
           let embedded = EmbeddedAPIKey_SIMULATOR_ONLY, !embedded.isEmpty {
            Keychain.shared["api_511"] = embedded
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(app)

                if showSplash {
                    SplashScreen()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}

// MARK: - Splash Screen
struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color(red: 0.85, green: 0.75, blue: 0.65)
                .ignoresSafeArea()

            Image("LaunchImage")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 400)
                .padding(40)
        }
    }
}

// MARK: - API Key Gate (full-screen cover)
struct APIKeySetupScreen: View {
    @EnvironmentObject private var app: AppState
    @State private var apiKey: String = ""
    @State private var message: String?
    @State private var messageColor: Color = .secondary

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Enter your 511.org API Key")
                    .font(.title2).bold().multilineTextAlignment(.center)

                Text("Create one at 511.org → Open Data → Token. You only need to do this once on this device.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                if let msg = message { Text(msg).foregroundStyle(messageColor) }

                HStack {
                    Button(action: save) {
                        Label("Save & Continue", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: verify) {
                        Label("Verify", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let stored = Keychain.shared["api_511"], !stored.isEmpty {
                    LabeledContent("Stored", value: Keychain.masked(stored))
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Caltrain Checker")
            .onAppear {
                apiKey = Keychain.shared["api_511"] ?? ""
                verify()
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyAPIKey(trimmed) else {
            message = "Please paste a valid 511 key (letters/numbers/dashes, ≤128 chars)."
            messageColor = .red
            return
        }
        app.saveKey(trimmed)
        verify()
    }

    private func verify() {
        let current = Keychain.shared["api_511"] ?? ""
        if !current.isEmpty {
            message = "Saved ✓  (\(Keychain.masked(current)))"
            messageColor = .green
        } else {
            message = "No key in Keychain."
            messageColor = .red
        }
    }
}

// MARK: - Root Tabs
struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab = 0
    @State private var alerts: [ServiceAlert] = []
    @State private var alertsLoading = false

    // Bind cover visibility (true when key is missing)
    private var needsKeyBinding: Binding<Bool> {
        Binding(get: { !app.hasKey }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $tab) {
            TrainsScreen(sharedAlerts: $alerts)
                .tabItem { Label("Trains", systemImage: "train.side.front.car") }.tag(0)
            EventsScreen()
                .tabItem { Label("Events", systemImage: "calendar") }.tag(1)
            AlertsScreen(alerts: $alerts, isLoading: $alertsLoading)
                .tabItem {
                    Label("Alerts", systemImage: alerts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .badge(alerts.count)
                .tag(2)
            StationsScreen()
                .tabItem { Label("Stations", systemImage: "mappin.and.ellipse") }.tag(3)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(alerts.isEmpty ? .green : .red)
        .fullScreenCover(isPresented: needsKeyBinding) {
            APIKeySetupScreen().environmentObject(app)
        }
        .onAppear {
            app.refreshFromKeychain()
            Task { await loadAlerts() }
        }
        .onChange(of: tab, initial: false) { _, newTab in
            if newTab == 2 { // Alerts tab
                Task { await loadAlerts() }
            }
        }
    }

    func loadAlerts() async {
        guard let key = Keychain.shared["api_511"], !key.isEmpty else { return }
        alertsLoading = true
        defer { alertsLoading = false }
        do {
            alerts = try await SIRIService.serviceAlerts(apiKey: key)
        } catch {
            print("Failed to load alerts: \(error)")
        }
    }
}

// MARK: - Stations Screen
struct StationsScreen: View {
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode

    private var selectedNorthbound: CaltrainStop {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode } ?? CaltrainStops.defaultNorthbound
    }

    private var selectedSouthbound: CaltrainStop {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode } ?? CaltrainStops.defaultSouthbound
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select your two Caltrain stations:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("• Southern Station: Your station closer to San Jose")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("• Northern Station: Your station closer to San Francisco")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Southern Station (e.g., Mountain View)") {
                    Picker("Southern Station", selection: $northboundStopCode) {
                        ForEach(CaltrainStops.northbound) { stop in
                            Text(stop.name).tag(stop.stopCode)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }

                Section("Northern Station (e.g., 22nd Street)") {
                    Picker("Northern Station", selection: $southboundStopCode) {
                        ForEach(CaltrainStops.southbound) { stop in
                            Text(stop.name).tag(stop.stopCode)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Northbound", systemImage: "arrow.up")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            Text("\(selectedNorthbound.name) → \(selectedSouthbound.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Southbound", systemImage: "arrow.down")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            Text("\(selectedSouthbound.name) → \(selectedNorthbound.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } header: {
                    Text("Your Routes")
                }
            }
            .navigationTitle("Stations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image("LogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
        }
    }
}

// MARK: - Settings
struct SettingsScreen: View {
    @EnvironmentObject private var app: AppState
    @State private var apiKey511: String = ""
    @State private var apiKeyTicketmaster: String = ""
    @State private var status511: String = ""
    @State private var statusTicketmaster: String = ""
    @State private var status511Color: Color = .secondary
    @State private var statusTicketmasterColor: Color = .secondary

    var body: some View {
        NavigationStack {
            Form {

                Section("511.org API") {
                    SecureField("API Key", text: $apiKey511)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !status511.isEmpty { Text(status511).foregroundStyle(status511Color) }

                    Button(action: save511) {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 12) {
                        Button("Verify") { verify511() }
                            .buttonStyle(.bordered)
                        Button("Clear") {
                            app.clearKey()
                            apiKey511 = ""
                            status511 = "Cleared from Keychain."
                            status511Color = .orange
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    if let stored = Keychain.shared["api_511"], !stored.isEmpty {
                        LabeledContent("Stored", value: Keychain.masked(stored))
                    }
                }

                Section("Ticketmaster API") {
                    SecureField("API Key", text: $apiKeyTicketmaster)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !statusTicketmaster.isEmpty { Text(statusTicketmaster).foregroundStyle(statusTicketmasterColor) }

                    Button(action: saveTicketmaster) {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 12) {
                        Button("Verify") { verifyTicketmaster() }
                            .buttonStyle(.bordered)
                        Button("Clear") {
                            print("🔴 CLEAR BUTTON TAPPED")
                            Keychain.shared["api_ticketmaster"] = nil
                            apiKeyTicketmaster = ""
                            statusTicketmaster = "Cleared from Keychain."
                            statusTicketmasterColor = .orange
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    if let stored = Keychain.shared["api_ticketmaster"], !stored.isEmpty {
                        LabeledContent("Stored", value: Keychain.masked(stored))
                    }
                    Text("Get your free API key from developer.ticketmaster.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        HStack {
                            Label("About", systemImage: "info.circle")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image("LogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
            .onAppear {
                apiKey511 = Keychain.shared["api_511"] ?? ""
                apiKeyTicketmaster = Keychain.shared["api_ticketmaster"] ?? ""
                verify511()
                verifyTicketmaster()
            }
        }
    }

    private func save511() {
        let trimmed = apiKey511.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyAPIKey(trimmed) else {
            status511 = "Please enter a valid key."
            status511Color = .red
            return
        }
        app.saveKey(trimmed)
        verify511()
    }

    private func verify511() {
        let current = Keychain.shared["api_511"] ?? ""
        if !current.isEmpty { status511 = "Saved ✓  (\(Keychain.masked(current)))"; status511Color = .green }
        else { status511 = "No key in Keychain."; status511Color = .red }
    }

    private func saveTicketmaster() {
        let trimmed = apiKeyTicketmaster.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔑 Ticketmaster save - Input length: \(trimmed.count)")
        print("🔑 Ticketmaster save - isLikelyAPIKey: \(isLikelyAPIKey(trimmed))")
        guard isLikelyAPIKey(trimmed) else {
            statusTicketmaster = "Please enter a valid key."
            statusTicketmasterColor = .red
            print("🔑 Ticketmaster save - FAILED validation")
            return
        }
        print("🔑 Ticketmaster save - Saving to keychain...")
        Keychain.shared["api_ticketmaster"] = trimmed
        apiKeyTicketmaster = trimmed  // Update state variable
        print("🔑 Ticketmaster save - Verifying...")
        verifyTicketmaster()
    }

    private func verifyTicketmaster() {
        let current = Keychain.shared["api_ticketmaster"] ?? ""
        print("🔑 Ticketmaster verify - Read from keychain length: \(current.count)")
        if !current.isEmpty {
            statusTicketmaster = "Saved ✓  (\(Keychain.masked(current)))"
            statusTicketmasterColor = .green
            print("🔑 Ticketmaster verify - SUCCESS")
        } else {
            statusTicketmaster = "No key in Keychain."
            statusTicketmasterColor = .red
            print("🔑 Ticketmaster verify - EMPTY")
        }
    }
}

// MARK: - About Screen
struct AboutScreen: View {
    var body: some View {
        List {
            Section("Version") {
                LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }

            Section("Data Sources") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transit Data")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Provided by 511.org")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Events Data")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Provided by Ticketmaster Discovery API")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Disclaimer") {
                Text("Transit times are estimates only. Data is provided 'as is' without warranty of any kind. Always verify departure times before traveling and exercise reasonable judgment when planning your trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Terms of Use") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This app uses data from 511.org under their authorized API access terms.")
                        .font(.footnote)

                    Text("This app is for personal use only. Commercial distribution requires written authorization from MTC (Metropolitan Transportation Commission).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link("View 511.org Terms", destination: URL(string: "https://511.org/about/terms")!)
                        .font(.footnote)
                }
            }

            Section("Credits") {
                Text("🤖 Generated with Claude Code")
                    .font(.footnote)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image("LogoIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
        }
    }
}

// MARK: - Trains UI
struct TrainsScreen: View {
    @Binding var sharedAlerts: [ServiceAlert]
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode
    @State private var refDate = Date()
    @State private var north: [Departure] = []
    @State private var south: [Departure] = []
    @State private var loading = false
    @State private var error: String?

    private var northboundStop: CaltrainStop {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode } ?? CaltrainStops.defaultNorthbound
    }

    private var southboundStop: CaltrainStop {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode } ?? CaltrainStops.defaultSouthbound
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Time", selection: $refDate, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.compact)

                HStack {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Now") { refDate = Date() }
                        .buttonStyle(.bordered)
                }

                if loading { ProgressView("Loading…") }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }

                List {
                    if !sharedAlerts.isEmpty {
                        Section {
                            ForEach(sharedAlerts) { alert in
                                ServiceAlertRow(alert: alert)
                            }
                        } header: {
                            Label("Service Alerts", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("Northbound from \(northboundStop.name)") {
                        ForEach(north) { DepartureRow(dep: $0, destinationLabel: southboundStop.name) }
                    }
                    Section("Southbound from \(southboundStop.name)") {
                        ForEach(south) { DepartureRow(dep: $0, destinationLabel: northboundStop.name) }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal)
            .navigationTitle("Caltrain")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image("LogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
            .task { await load() } // initial fetch
            .onChange(of: refDate, initial: false) { _, _ in // iOS 17 two-arg
                Task { await load() }
            }
            .onChange(of: northboundStopCode, initial: false) { _, _ in
                Task { await load() }
            }
            .onChange(of: southboundStopCode, initial: false) { _, _ in
                Task { await load() }
            }
        }
    }

    func load() async {
        loading = true; defer { loading = false }
        error = nil
        guard let key = Keychain.shared["api_511"], !key.isEmpty else {
            error = "Add your 511 API key in Settings."
            return
        }
        print("🔍 Loading trains - Northbound code: \(northboundStopCode), Southbound code: \(southboundStopCode)")
        print("🔍 Northbound station: \(northboundStop.name), Southbound station: \(southboundStop.name)")
        do {
            async let nb = SIRIService.nextDepartures(from: northboundStopCode, at: refDate, apiKey: key, expectedDirection: "N")
            async let sb = SIRIService.nextDepartures(from: southboundStopCode, at: refDate, apiKey: key, expectedDirection: "S")
            async let al = SIRIService.serviceAlerts(apiKey: key)
            let (n, s, a) = try await (nb, sb, al)
            north = n; south = s; sharedAlerts = a
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

struct ServiceAlertRow: View {
    let alert: ServiceAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(alert.summary)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let severity = alert.severity {
                    Text(severity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let description = alert.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let creationTime = alert.creationTime {
                Text(creationTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DepartureRow: View {
    let dep: Departure
    let destinationLabel: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "—").font(.headline)
                Text(destinationLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(dep.minutes)m").font(.title3).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Departure in \(dep.minutes) minutes to \(destinationLabel)")
    }
}

// MARK: - Alerts UI
struct AlertsScreen: View {
    @Binding var alerts: [ServiceAlert]
    @Binding var isLoading: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Checking for alerts…")
                        .padding()
                }

                if alerts.isEmpty && !isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.green)

                        Text("Alright Alright Alright")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("No active Caltrain service alerts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if !alerts.isEmpty {
                    List {
                        ForEach(alerts) { alert in
                            ServiceAlertRow(alert: alert)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Service Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image("LogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
        }
    }
}

// MARK: - Events UI
struct EventsScreen: View {
    @State private var events: [BayAreaEvent] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selectedStation: String = "All Stations"
    @State private var maxDistance: Double = 50.0

    private var allStationNames: [String] {
        var stations = ["All Stations"]
        stations.append(contentsOf: CaltrainStops.northbound.map { $0.name })
        return stations
    }

    private var filteredEvents: [BayAreaEvent] {
        if selectedStation == "All Stations" {
            return events
        }

        return events.filter { event in
            guard let nearest = event.nearestStation else { return false }
            return nearest.station.name == selectedStation && nearest.distance <= maxDistance
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading events…")
                } else if let error {
                    VStack {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                            .textSelection(.enabled)
                    }
                } else if events.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No upcoming events found")
                            .foregroundStyle(.secondary)
                        Text("Add your Ticketmaster API key in Settings")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                } else if !events.isEmpty && filteredEvents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No events near \(selectedStation)")
                            .foregroundStyle(.secondary)
                        Text("Try increasing the distance or selecting a different station")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // Filter controls as first section
                        Section {
                            Picker("Filter by Station", selection: $selectedStation) {
                                ForEach(allStationNames, id: \.self) { station in
                                    Text(station).tag(station)
                                }
                            }

                            if selectedStation != "All Stations" {
                                HStack {
                                    Text("Max Distance")
                                    Spacer()
                                    Text("\(String(format: "%.1f", maxDistance)) mi")
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: $maxDistance, in: 0.5...10.0, step: 0.5)
                            }
                        }

                        // Events section
                        Section {
                            ForEach(filteredEvents) { event in
                                EventRow(event: event)
                            }
                        } header: {
                            if selectedStation == "All Stations" {
                                Text("All Events Today")
                            } else {
                                Text("Events near \(selectedStation)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Bay Area Events")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("LogoIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task { await load() }
        }
    }

    func load() async {
        loading = true
        defer { loading = false }
        error = nil

        guard let key = Keychain.shared["api_ticketmaster"], !key.isEmpty else {
            error = "Add your Ticketmaster API key in Settings."
            return
        }

        do {
            events = try await TicketmasterService.searchEvents(apiKey: key)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

struct EventRow: View {
    let event: BayAreaEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.name)
                .font(.headline)

            if let venue = event.venueName {
                Label(venue, systemImage: "mappin.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let nearest = event.nearestStation {
                Label {
                    Text("Nearest: \(nearest.station.name) (\(String(format: "%.1f", nearest.distance)) mi)")
                } icon: {
                    Image(systemName: "tram.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }

            if let date = event.date {
                Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let url = event.url {
                Link("Get Tickets", destination: url)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Domain & Networking

// Station model
struct CaltrainStop: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let stopCode: String
    let latitude: Double
    let longitude: Double

    init(name: String, stopCode: String, latitude: Double, longitude: Double) {
        self.id = stopCode
        self.name = name
        self.stopCode = stopCode
        self.latitude = latitude
        self.longitude = longitude
    }

    // Calculate distance in miles to a given lat/lon using Haversine formula
    func distanceTo(latitude: Double, longitude: Double) -> Double {
        let earthRadiusMiles = 3959.0
        let lat1Rad = self.latitude * .pi / 180
        let lat2Rad = latitude * .pi / 180
        let dLat = (latitude - self.latitude) * .pi / 180
        let dLon = (longitude - self.longitude) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return earthRadiusMiles * c
    }
}

// All available Caltrain stops
struct CaltrainStops {
    // Northbound stops (toward San Francisco) - odd numbered stop codes
    static let northbound: [CaltrainStop] = [
        CaltrainStop(name: "Gilroy", stopCode: "777403", latitude: 37.0035, longitude: -121.5682),
        CaltrainStop(name: "San Martin", stopCode: "777402", latitude: 37.0855, longitude: -121.6106),
        CaltrainStop(name: "Morgan Hill", stopCode: "777401", latitude: 37.1295, longitude: -121.6503),
        CaltrainStop(name: "Blossom Hill", stopCode: "70007", latitude: 37.2524, longitude: -121.7983),
        CaltrainStop(name: "Capitol", stopCode: "70005", latitude: 37.2894, longitude: -121.8421),
        CaltrainStop(name: "Tamien", stopCode: "70003", latitude: 37.3119, longitude: -121.8841),
        CaltrainStop(name: "San Jose Diridon", stopCode: "70261", latitude: 37.3297, longitude: -121.9026),
        CaltrainStop(name: "Santa Clara", stopCode: "70271", latitude: 37.3530, longitude: -121.9364),
        CaltrainStop(name: "Lawrence", stopCode: "70281", latitude: 37.3705, longitude: -121.9972),
        CaltrainStop(name: "Sunnyvale", stopCode: "70291", latitude: 37.3784, longitude: -122.0309),
        CaltrainStop(name: "Mountain View", stopCode: "70211", latitude: 37.3942, longitude: -122.0764),
        CaltrainStop(name: "San Antonio", stopCode: "70221", latitude: 37.4074, longitude: -122.1070),
        CaltrainStop(name: "California Ave", stopCode: "70231", latitude: 37.4294, longitude: -122.1426),
        CaltrainStop(name: "Palo Alto", stopCode: "70241", latitude: 37.4429, longitude: -122.1649),
        CaltrainStop(name: "Menlo Park", stopCode: "70251", latitude: 37.4546, longitude: -122.1824),
        CaltrainStop(name: "Redwood City", stopCode: "70311", latitude: 37.4854, longitude: -122.2317),
        CaltrainStop(name: "San Carlos", stopCode: "70321", latitude: 37.5071, longitude: -122.2604),
        CaltrainStop(name: "Belmont", stopCode: "70331", latitude: 37.5206, longitude: -122.2756),
        CaltrainStop(name: "Hillsdale", stopCode: "70341", latitude: 37.5378, longitude: -122.2977),
        CaltrainStop(name: "San Mateo", stopCode: "70351", latitude: 37.5683, longitude: -122.3238),
        CaltrainStop(name: "Burlingame", stopCode: "70361", latitude: 37.5797, longitude: -122.3449),
        CaltrainStop(name: "Millbrae", stopCode: "70371", latitude: 37.5996, longitude: -122.3868),
        CaltrainStop(name: "San Bruno", stopCode: "70381", latitude: 37.6308, longitude: -122.4112),
        CaltrainStop(name: "South San Francisco", stopCode: "70011", latitude: 37.6566, longitude: -122.4056),
        CaltrainStop(name: "Bayshore", stopCode: "70031", latitude: 37.7097, longitude: -122.4016),
        CaltrainStop(name: "22nd Street", stopCode: "70021", latitude: 37.7571, longitude: -122.3924),
        CaltrainStop(name: "San Francisco", stopCode: "70041", latitude: 37.7765, longitude: -122.3947)
    ]

    // Southbound stops (toward San Jose) - even numbered stop codes
    static let southbound: [CaltrainStop] = [
        CaltrainStop(name: "San Francisco", stopCode: "70042", latitude: 37.7765, longitude: -122.3947),
        CaltrainStop(name: "22nd Street", stopCode: "70022", latitude: 37.7571, longitude: -122.3924),
        CaltrainStop(name: "Bayshore", stopCode: "70032", latitude: 37.7097, longitude: -122.4016),
        CaltrainStop(name: "South San Francisco", stopCode: "70012", latitude: 37.6566, longitude: -122.4056),
        CaltrainStop(name: "San Bruno", stopCode: "70382", latitude: 37.6308, longitude: -122.4112),
        CaltrainStop(name: "Millbrae", stopCode: "70372", latitude: 37.5996, longitude: -122.3868),
        CaltrainStop(name: "Burlingame", stopCode: "70362", latitude: 37.5797, longitude: -122.3449),
        CaltrainStop(name: "San Mateo", stopCode: "70352", latitude: 37.5683, longitude: -122.3238),
        CaltrainStop(name: "Hillsdale", stopCode: "70342", latitude: 37.5378, longitude: -122.2977),
        CaltrainStop(name: "Belmont", stopCode: "70332", latitude: 37.5206, longitude: -122.2756),
        CaltrainStop(name: "San Carlos", stopCode: "70322", latitude: 37.5071, longitude: -122.2604),
        CaltrainStop(name: "Redwood City", stopCode: "70312", latitude: 37.4854, longitude: -122.2317),
        CaltrainStop(name: "Menlo Park", stopCode: "70252", latitude: 37.4546, longitude: -122.1824),
        CaltrainStop(name: "Palo Alto", stopCode: "70242", latitude: 37.4429, longitude: -122.1649),
        CaltrainStop(name: "California Ave", stopCode: "70232", latitude: 37.4294, longitude: -122.1426),
        CaltrainStop(name: "San Antonio", stopCode: "70222", latitude: 37.4074, longitude: -122.1070),
        CaltrainStop(name: "Mountain View", stopCode: "70212", latitude: 37.3942, longitude: -122.0764),
        CaltrainStop(name: "Sunnyvale", stopCode: "70292", latitude: 37.3784, longitude: -122.0309),
        CaltrainStop(name: "Lawrence", stopCode: "70282", latitude: 37.3705, longitude: -121.9972),
        CaltrainStop(name: "Santa Clara", stopCode: "70272", latitude: 37.3530, longitude: -121.9364),
        CaltrainStop(name: "San Jose Diridon", stopCode: "70262", latitude: 37.3297, longitude: -121.9026),
        CaltrainStop(name: "Tamien", stopCode: "70004", latitude: 37.3119, longitude: -121.8841),
        CaltrainStop(name: "Capitol", stopCode: "70006", latitude: 37.2894, longitude: -121.8421),
        CaltrainStop(name: "Blossom Hill", stopCode: "70008", latitude: 37.2524, longitude: -121.7983),
        CaltrainStop(name: "Morgan Hill", stopCode: "777402", latitude: 37.1295, longitude: -121.6503),
        CaltrainStop(name: "San Martin", stopCode: "777403", latitude: 37.0855, longitude: -121.6106),
        CaltrainStop(name: "Gilroy", stopCode: "777404", latitude: 37.0035, longitude: -121.5682)
    ]

    // Default stops (Mountain View northbound and 22nd Street southbound)
    static let defaultNorthbound = northbound.first { $0.name == "Mountain View" }!
    static let defaultSouthbound = southbound.first { $0.name == "22nd Street" }!
}

struct Departure: Identifiable, Hashable {
    var id: String { journeyRef + (depTime?.ISO8601Format() ?? "") }
    let journeyRef: String
    let minutes: Int
    let depTime: Date?
    let direction: String?
    let destination: String?
}

struct ServiceAlert: Identifiable, Hashable {
    let id: String
    let summary: String
    let description: String?
    let severity: String?
    let creationTime: Date?
}

struct BayAreaEvent: Identifiable, Hashable {
    let id: String
    let name: String
    let date: Date?
    let venueName: String?
    let url: URL?
    let venueLatitude: Double?
    let venueLongitude: Double?

    var nearestStation: (station: CaltrainStop, distance: Double)? {
        guard let lat = venueLatitude, let lon = venueLongitude else { return nil }

        // Get all unique stations (combine northbound and southbound, avoiding duplicates)
        var allStations: [CaltrainStop] = []
        var seenNames = Set<String>()

        for station in CaltrainStops.northbound {
            if !seenNames.contains(station.name) {
                allStations.append(station)
                seenNames.insert(station.name)
            }
        }

        // Find the closest station
        return allStations.map { station in
            (station: station, distance: station.distanceTo(latitude: lat, longitude: lon))
        }.min { $0.distance < $1.distance }
    }
}

actor HTTPClient {
    static let shared = HTTPClient()
    func get(url: URL, headers: [String:String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        var all = headers
        if all["Accept"] == nil { all["Accept"] = "application/json" }
        all["User-Agent"] = all["User-Agent"] ?? "CaltrainChecker/1.0"
        all.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.timeoutInterval = 25
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Robust SIRI models (unique names to avoid collisions)

// Accept either wrapped {"Siri":{...}} or bare {"ServiceDelivery":{...}} roots.
struct SiriEnvelopeNode: Decodable {
    let Siri: SiriBodyNode?
    let ServiceDelivery: ServiceDeliveryNode?
}
struct SiriBodyNode: Decodable {
    let ServiceDelivery: ServiceDeliveryNode
}

// Accept array OR single object for StopMonitoringDelivery
struct ServiceDeliveryNode: Decodable {
    let StopMonitoringDelivery: [StopMonitoringDeliveryNode]?

    enum CodingKeys: String, CodingKey { case StopMonitoringDelivery }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode(Array<StopMonitoringDeliveryNode>.self, forKey: .StopMonitoringDelivery) {
            self.StopMonitoringDelivery = many
        } else if let one = try? c.decode(StopMonitoringDeliveryNode.self, forKey: .StopMonitoringDelivery) {
            self.StopMonitoringDelivery = [one]
        } else {
            self.StopMonitoringDelivery = nil
        }
    }
}

struct StopMonitoringDeliveryNode: Decodable {
    let MonitoredStopVisit: [MonitoredStopVisitNode]?
}

struct MonitoredStopVisitNode: Decodable {
    let MonitoredVehicleJourney: MonitoredVehicleJourneyNode
}

// DestinationName can be String OR [String] depending on feed
struct MonitoredVehicleJourneyNode: Decodable {
    let LineRef: String?
    let DirectionRef: String?
    let DestinationName: String?
    let MonitoredCall: MonitoredCallNode?
    let FramedVehicleJourneyRef: FramedVehicleJourneyRefNode?

    enum CodingKeys: String, CodingKey {
        case LineRef, DirectionRef, DestinationName, MonitoredCall, FramedVehicleJourneyRef
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.LineRef = try? c.decodeIfPresent(String.self, forKey: .LineRef)
        self.DirectionRef = try? c.decodeIfPresent(String.self, forKey: .DirectionRef)
        self.MonitoredCall = try? c.decodeIfPresent(MonitoredCallNode.self, forKey: .MonitoredCall)
        self.FramedVehicleJourneyRef = try? c.decodeIfPresent(FramedVehicleJourneyRefNode.self, forKey: .FramedVehicleJourneyRef)

        if let s = try? c.decodeIfPresent(String.self, forKey: .DestinationName) {
            self.DestinationName = s
        } else if let arr = try? c.decodeIfPresent(Array<String>.self, forKey: .DestinationName) {
            self.DestinationName = arr.first
        } else {
            self.DestinationName = nil
        }
    }
}

struct FramedVehicleJourneyRefNode: Decodable { let DatedVehicleJourneyRef: String? }
struct MonitoredCallNode: Decodable { let AimedDepartureTime: String? }

// MARK: - SIRI-SX Service Alerts models
struct AlertsEnvelope: Decodable {
    let Siri: AlertsSiriBody?
    let ServiceDelivery: AlertsServiceDelivery?
}

struct AlertsSiriBody: Decodable {
    let ServiceDelivery: AlertsServiceDelivery
}

struct AlertsServiceDelivery: Decodable {
    let SituationExchangeDelivery: [AlertsSituationExchangeDelivery]?

    enum CodingKeys: String, CodingKey { case SituationExchangeDelivery }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode(Array<AlertsSituationExchangeDelivery>.self, forKey: .SituationExchangeDelivery) {
            self.SituationExchangeDelivery = many
        } else if let one = try? c.decode(AlertsSituationExchangeDelivery.self, forKey: .SituationExchangeDelivery) {
            self.SituationExchangeDelivery = [one]
        } else {
            self.SituationExchangeDelivery = nil
        }
    }
}

struct AlertsSituationExchangeDelivery: Decodable {
    let Situations: AlertsSituationsWrapper?
}

struct AlertsSituationsWrapper: Decodable {
    let PtSituationElement: [AlertsPtSituationElement]?

    enum CodingKeys: String, CodingKey { case PtSituationElement }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode(Array<AlertsPtSituationElement>.self, forKey: .PtSituationElement) {
            self.PtSituationElement = many
        } else if let one = try? c.decode(AlertsPtSituationElement.self, forKey: .PtSituationElement) {
            self.PtSituationElement = [one]
        } else {
            self.PtSituationElement = nil
        }
    }
}

struct AlertsPtSituationElement: Decodable {
    let SituationNumber: String?
    let CreationTime: String?
    let Summary: String?
    let Description: String?
    let Severity: String?
}

// MARK: - SIRI service
struct SIRIService {
    static func serviceAlerts(apiKey: String) async throws -> [ServiceAlert] {
        var comps = URLComponents(string: "http://api.511.org/transit/servicealerts")!
        comps.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "agency", value: "CT"),
            .init(name: "format", value: "json")
        ]
        print("🚨 Fetching service alerts from: \(comps.url!)")
        let (raw, http) = try await HTTPClient.shared.get(url: comps.url!)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: raw, encoding: .utf8)?.prefix(200) ?? ""
            print("🚨 Service alerts HTTP error: \(http.statusCode)")
            throw NSError(domain: "SIRI-SX", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(snippet)"])
        }

        let cleaned = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) ?? raw

        do {
            let env = try JSONDecoder().decode(AlertsEnvelope.self, from: cleaned)
            let sd = env.Siri?.ServiceDelivery ?? env.ServiceDelivery
            let situations = sd?.SituationExchangeDelivery?.first?.Situations?.PtSituationElement ?? []
            print("🚨 Found \(situations.count) service alert situations")

            let dfFrac = ISO8601DateFormatter(); dfFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let df = ISO8601DateFormatter()

            var alerts: [ServiceAlert] = []
            for sit in situations {
                let creationTime = sit.CreationTime.flatMap { dfFrac.date(from: $0) ?? df.date(from: $0) }
                let summary = sit.Summary ?? "Service Alert"
                print("🚨 Alert: \(summary)")
                let alert = ServiceAlert(
                    id: sit.SituationNumber ?? UUID().uuidString,
                    summary: summary,
                    description: sit.Description,
                    severity: sit.Severity,
                    creationTime: creationTime
                )
                alerts.append(alert)
            }
            print("🚨 Returning \(alerts.count) service alerts")
            return alerts
        } catch {
            let snippet = String(data: cleaned, encoding: .utf8)?.prefix(280) ?? ""
            print("🚨 Failed to decode alerts: \(error)")
            throw NSError(domain: "SIRI-SX.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "Couldn't parse 511 alerts response. \(error.localizedDescription)\n\(snippet)"])
        }
    }

    static func stopMonitoring(stopCode: String, max: Int = 6, apiKey: String) async throws -> [MonitoredStopVisitNode] {
        var comps = URLComponents(string: "http://api.511.org/transit/StopMonitoring")!
        comps.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "agency", value: "CT"),
            .init(name: "stopcode", value: stopCode),
            .init(name: "format", value: "json")
        ]
        let (raw, http) = try await HTTPClient.shared.get(url: comps.url!)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: raw, encoding: .utf8)?.prefix(200) ?? ""
            throw NSError(domain: "SIRI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(snippet)"])
        }
        let cleaned = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) ?? raw
        do {
            let env = try JSONDecoder().decode(SiriEnvelopeNode.self, from: cleaned)
            let sd = env.Siri?.ServiceDelivery ?? env.ServiceDelivery
            let visits = sd?.StopMonitoringDelivery?.first?.MonitoredStopVisit ?? []
            return visits
        } catch {
            let snippet = String(data: cleaned, encoding: .utf8)?.prefix(280) ?? ""
            throw NSError(domain: "SIRI.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "Couldn’t parse 511 response. \(error.localizedDescription)\n\(snippet)"])
        }
    }

    static func nextDepartures(from stop: String, at refDate: Date, apiKey: String, expectedDirection: String? = nil) async throws -> [Departure] {
        let visits = try await stopMonitoring(stopCode: stop, apiKey: apiKey)
        let dfFrac = ISO8601DateFormatter(); dfFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df = ISO8601DateFormatter()
        let now = Date() // Use actual current time, not the picker time

        var out: [Departure] = []
        print("📍 Stop: \(stop), Expected Dir: \(expectedDirection ?? "any"), Now: \(now), Visits: \(visits.count)")
        for v in visits {
            let mvj = v.MonitoredVehicleJourney
            let aimed = mvj.MonitoredCall?.AimedDepartureTime
            let date = aimed.flatMap { dfFrac.date(from: $0) ?? df.date(from: $0) }
            // Calculate minutes, rounding up (ceiling) so a train in 30 seconds shows as 1m
            let minutes = date.map { Int(ceil($0.timeIntervalSince(now) / 60)) } ?? 0
            let direction = mvj.DirectionRef
            print("  🚂 Dir: \(direction ?? "?"), Aimed: \(aimed ?? "nil"), Minutes: \(minutes), Dest: \(mvj.DestinationName ?? "nil")")

            // Filter by direction if we have an expected direction
            if let expected = expectedDirection, direction != expected {
                print("    ⏭️  Skipping - wrong direction")
                continue
            }

            let dep = Departure(
                journeyRef: mvj.FramedVehicleJourneyRef?.DatedVehicleJourneyRef ?? UUID().uuidString,
                minutes: minutes, depTime: date,
                direction: mvj.DirectionRef, destination: mvj.DestinationName
            )
            // Only include future departures (at least 1 minute away)
            if minutes > 0 { out.append(dep) }
        }
        // Sort by time and take first 3
        let result = Array(out.sorted { ($0.depTime ?? .distantFuture) < ($1.depTime ?? .distantFuture) }.prefix(3))
        print("  ✅ Returning \(result.count) departures")
        return result
    }
}

// MARK: - Ticketmaster API
struct TicketmasterService {
    static func searchEvents(apiKey: String, city: String = "San Francisco", radius: String = "50") async throws -> [BayAreaEvent] {
        // Get today's date in ISO format (YYYY-MM-DD)
        let today = Date.now
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let startDateTime = dateFormatter.string(from: startOfToday) + "T00:00:00Z"
        let endDateTime = dateFormatter.string(from: endOfToday) + "T00:00:00Z"

        var comps = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        comps.queryItems = [
            .init(name: "apikey", value: apiKey),
            .init(name: "city", value: city),
            .init(name: "radius", value: radius),
            .init(name: "unit", value: "miles"),
            .init(name: "startDateTime", value: startDateTime),
            .init(name: "endDateTime", value: endDateTime),
            .init(name: "size", value: "100"),
            .init(name: "sort", value: "date,asc")
        ]

        print("🎟️ Fetching Ticketmaster events for today (\(startDateTime) to \(endDateTime))")
        print("🎟️ URL: \(comps.url!)")
        let (data, http) = try await HTTPClient.shared.get(url: comps.url!)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            print("🎟️ Ticketmaster HTTP error: \(http.statusCode)")
            throw NSError(domain: "Ticketmaster", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(snippet)"])
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            guard let embedded = json["_embedded"] as? [String: Any],
                  let eventsArray = embedded["events"] as? [[String: Any]] else {
                print("🎟️ No events found in response")
                return []
            }

            var events: [BayAreaEvent] = []
            let df = ISO8601DateFormatter()

            for eventData in eventsArray {
                guard let id = eventData["id"] as? String,
                      let name = eventData["name"] as? String else { continue }

                // Parse date
                var date: Date?
                if let dates = eventData["dates"] as? [String: Any],
                   let start = dates["start"] as? [String: Any],
                   let dateTimeStr = start["dateTime"] as? String {
                    date = df.date(from: dateTimeStr)
                }

                // Parse venue
                var venueName: String?
                var venueLat: Double?
                var venueLon: Double?
                if let embedded = eventData["_embedded"] as? [String: Any],
                   let venues = embedded["venues"] as? [[String: Any]],
                   let firstVenue = venues.first {
                    venueName = firstVenue["name"] as? String

                    // Parse location
                    if let location = firstVenue["location"] as? [String: Any] {
                        if let latStr = location["latitude"] as? String, let lat = Double(latStr) {
                            venueLat = lat
                        }
                        if let lonStr = location["longitude"] as? String, let lon = Double(lonStr) {
                            venueLon = lon
                        }
                    }
                }

                // Parse URL
                var eventURL: URL?
                if let urlString = eventData["url"] as? String {
                    eventURL = URL(string: urlString)
                }

                let event = BayAreaEvent(
                    id: id,
                    name: name,
                    date: date,
                    venueName: venueName,
                    url: eventURL,
                    venueLatitude: venueLat,
                    venueLongitude: venueLon
                )
                events.append(event)
            }

            print("🎟️ Found \(events.count) events")
            return events
        } catch {
            print("🎟️ Failed to decode: \(error)")
            throw NSError(domain: "Ticketmaster.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse events: \(error.localizedDescription)"])
        }
    }
}

// MARK: - Keychain Wrapper
final class Keychain {
    static let shared = Keychain(service: Bundle.main.bundleIdentifier ?? "CaltrainChecker")
    private let service: String
    init(service: String) { self.service = service }
    subscript(key: String) -> String? { get { read(key) } set { if let v = newValue { save(key, v) } else { delete(key) } } }

    static func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return String(repeating: "•", count: max(0, trimmed.count - 2)) + trimmed.suffix(2) }
        return "•••• " + trimmed.suffix(4)
    }

    private func save(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        print("🔐 Keychain saving key=\(key) value_length=\(value.count)")
        SecItemDelete(q as CFDictionary)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            print("🔐 Keychain save FAILED: \(status)")
        } else {
            print("🔐 Keychain save SUCCESS")
        }
    }
    private func read(_ key: String) -> String? {
        let q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecSuccess, let d = out as? Data { return String(data: d, encoding: .utf8) }
        return nil
    }
    private func delete(_ key: String) {
        let q: [String:Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}
