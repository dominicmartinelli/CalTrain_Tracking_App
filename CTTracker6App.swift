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
import Compression
import UserNotifications
import CoreLocation

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
                .tabItem { Label("Trains", systemImage: "train.side.front.car") }
                .tag(0)
            EventsScreen()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(1)
            AlertsScreen(alerts: $alerts, isLoading: $alertsLoading)
                .tabItem {
                    Label("Alerts", systemImage: alerts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .badge(alerts.isEmpty ? 0 : alerts.count)
                .tag(2)
            StationsScreen()
                .tabItem { Label("Stations", systemImage: "mappin.and.ellipse") }
                .tag(3)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .accentColor(alerts.isEmpty ? .green : .red)
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
    @State private var savedCommutes: [SavedCommute] = []
    @State private var showingAddCommute = false
    @State private var editingCommute: SavedCommute?
    @State private var newCommuteName = ""
    @State private var renamingCommuteName = ""

    private var selectedNorthbound: CaltrainStop {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode } ?? CaltrainStops.defaultNorthbound
    }

    private var selectedSouthbound: CaltrainStop {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode } ?? CaltrainStops.defaultSouthbound
    }

    var body: some View {
        NavigationStack {
            Form {
                // Saved Commutes Section
                Section {
                    ForEach(savedCommutes) { commute in
                        Button {
                            loadCommute(commute)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(commute.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let south = commute.southboundStation, let north = commute.northboundStation {
                                        Text("\(south.name) ↔ \(north.name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if commute.southboundStopCode == southboundStopCode &&
                                   commute.northboundStopCode == northboundStopCode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteCommute(commute)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingCommute = commute
                                renamingCommuteName = commute.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }

                    Button {
                        showingAddCommute = true
                    } label: {
                        Label("Save Current as Commute", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("My Commutes")
                } footer: {
                    Text("Save your frequent routes for quick access")
                }

                // Current Route Section
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
                    Text("Current Route")
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
            .onAppear {
                savedCommutes = CommuteStorage.shared.load()
            }
            .alert("Save Commute", isPresented: $showingAddCommute) {
                TextField("Commute Name", text: $newCommuteName)
                Button("Cancel", role: .cancel) {
                    newCommuteName = ""
                }
                Button("Save") {
                    addCommute(name: newCommuteName)
                    newCommuteName = ""
                }
            } message: {
                Text("Enter a name for this commute route")
            }
            .alert("Rename Commute", isPresented: Binding(
                get: { editingCommute != nil },
                set: { if !$0 { editingCommute = nil; renamingCommuteName = "" } }
            )) {
                TextField("Commute Name", text: $renamingCommuteName)
                Button("Cancel", role: .cancel) {
                    editingCommute = nil
                    renamingCommuteName = ""
                }
                Button("Save") {
                    if let commute = editingCommute {
                        renameCommute(commute, to: renamingCommuteName)
                    }
                    editingCommute = nil
                    renamingCommuteName = ""
                }
            } message: {
                Text("Enter a new name for this commute")
            }
        }
    }

    private func addCommute(name: String) {
        let newCommute = SavedCommute(
            name: name.isEmpty ? "My Commute" : name,
            southboundStopCode: southboundStopCode,
            northboundStopCode: northboundStopCode
        )
        savedCommutes.append(newCommute)
        CommuteStorage.shared.save(savedCommutes)
    }

    private func loadCommute(_ commute: SavedCommute) {
        southboundStopCode = commute.southboundStopCode
        northboundStopCode = commute.northboundStopCode
    }

    private func deleteCommute(_ commute: SavedCommute) {
        savedCommutes.removeAll { $0.id == commute.id }
        CommuteStorage.shared.save(savedCommutes)
    }

    private func renameCommute(_ commute: SavedCommute, to newName: String) {
        if let index = savedCommutes.firstIndex(where: { $0.id == commute.id }) {
            var updated = commute
            updated.name = newName
            savedCommutes[index] = updated
            CommuteStorage.shared.save(savedCommutes)
        }
    }
}

// MARK: - Insights View
struct InsightsView: View {
    @State private var stats: (checksThisWeek: Int, mostCommonRoute: String?) = (0, nil)
    @State private var co2Savings: (trips: Int, co2SavedLbs: Double) = (0, 0.0)
    @State private var patterns: [CommutePattern] = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(stats.checksThisWeek)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.green)
                            Text("Checks this week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 40))
                            .foregroundStyle(.green.opacity(0.5))
                    }

                    if let route = stats.mostCommonRoute {
                        Text("Most common: **\(route)**")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("This Week")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(co2Savings.trips)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.blue)
                            Text("Trips this month")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green.opacity(0.6))
                    }

                    HStack(spacing: 4) {
                        Text("~**\(Int(co2Savings.co2SavedLbs)) lbs**")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("CO₂ saved vs. driving")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Environmental Impact")
            } footer: {
                Text("Manually track trips you've taken for accurate CO₂ savings. Based on average car emissions of 0.89 lbs CO₂ per mile.")
                    .font(.caption2)
            }

            if !patterns.isEmpty {
                Section {
                    ForEach(patterns.prefix(3), id: \.fromStopCode) { pattern in
                        VStack(alignment: .leading, spacing: 6) {
                            let fromName = CaltrainStops.northbound.first { $0.stopCode == pattern.fromStopCode }?.name ?? "Unknown"
                            let toName = CaltrainStops.northbound.first { $0.stopCode == pattern.toStopCode }?.name ?? "Unknown"

                            HStack {
                                Text("\(fromName) → \(toName)")
                                    .font(.headline)
                                Spacer()
                                Text("\(pattern.frequency)x")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !pattern.commonHours.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Usually around " + pattern.commonHours.sorted().map { String(format: "%d:00", $0) }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Your Commute Patterns")
                } footer: {
                    Text("Based on your usage history (stored locally)")
                        .font(.caption2)
                }
            }

            Section {
                Button(role: .destructive) {
                    CommuteHistoryStorage.shared.clearHistory()
                    loadStats()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            } footer: {
                Text("All data is stored locally on your device. Clearing history will reset insights and patterns.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Commute Insights")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadStats()
        }
    }

    private func loadStats() {
        stats = CommuteHistoryStorage.shared.getWeeklyStats()
        co2Savings = CommuteHistoryStorage.shared.calculateCO2Savings()
        patterns = CommuteHistoryStorage.shared.analyzePatterns()
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
    @StateObject private var notificationManager = SmartNotificationManager.shared

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
                Section("Smart Features") {
                    Toggle(isOn: Binding(
                        get: { notificationManager.notificationsEnabled },
                        set: { enabled in
                            if enabled && !notificationManager.notificationsEnabled {
                                notificationManager.requestPermission()
                            } else if !enabled {
                                // Open Settings to disable
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    )) {
                        Label("Smart Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        InsightsView()
                    } label: {
                        Label("Commute Insights", systemImage: "chart.bar")
                    }
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
    @State private var showNotificationPrompt = false
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var notificationManager = SmartNotificationManager.shared

    private var northboundStop: CaltrainStop {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode } ?? CaltrainStops.defaultNorthbound
    }

    private var southboundStop: CaltrainStop {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode } ?? CaltrainStops.defaultSouthbound
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)

                    DatePicker("", selection: $refDate, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .fixedSize()

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

                    Section {
                        ForEach(north) { DepartureRow(dep: $0, destinationLabel: southboundStop.name) }
                    } header: {
                        HStack {
                            Text("Northbound from \(northboundStop.name)")
                            Spacer()
                            if let weather = weatherService.currentWeather[southboundStopCode] {
                                HStack(spacing: 4) {
                                    Text(weather.symbol)
                                    Text("\(Int(weather.temp))°F at \(southboundStop.name)")
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(south) { DepartureRow(dep: $0, destinationLabel: northboundStop.name) }
                    } header: {
                        HStack {
                            Text("Southbound from \(southboundStop.name)")
                            Spacer()
                            if let weather = weatherService.currentWeather[northboundStopCode] {
                                HStack(spacing: 4) {
                                    Text(weather.symbol)
                                    Text("\(Int(weather.temp))°F at \(northboundStop.name)")
                                        .font(.caption)
                                }
                            }
                        }
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
            .task {
                await load()

                // Request notification permission on first launch
                if !notificationManager.hasRequestedPermission {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showNotificationPrompt = true
                    }
                }
            }
            .onChange(of: refDate, initial: false) { _, _ in
                Task { await load() }
            }
            .onChange(of: northboundStopCode, initial: false) { _, _ in
                Task { await load() }
            }
            .onChange(of: southboundStopCode, initial: false) { _, _ in
                Task { await load() }
            }
            .alert("Enable Smart Notifications?", isPresented: $showNotificationPrompt) {
                Button("Enable") {
                    notificationManager.requestPermission()
                }
                Button("Not Now", role: .cancel) {
                    UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
                }
            } message: {
                Text("Get notified about your usual trains, delays, and Giants game crowding.")
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
            // Load GTFS scheduled departures
            async let nbScheduled = GTFSService.shared.getScheduledDepartures(stopCode: northboundStopCode, direction: 0, refDate: refDate, count: 3)
            async let sbScheduled = GTFSService.shared.getScheduledDepartures(stopCode: southboundStopCode, direction: 1, refDate: refDate, count: 3)

            // Load SIRI real-time data for service types and delays
            async let nbRealtime = SIRIService.nextDepartures(from: northboundStopCode, at: refDate, apiKey: key, expectedDirection: "N")
            async let sbRealtime = SIRIService.nextDepartures(from: southboundStopCode, at: refDate, apiKey: key, expectedDirection: "S")
            async let al = SIRIService.serviceAlerts(apiKey: key)

            let (nScheduled, sScheduled, nRealtime, sRealtime, a) = try await (nbScheduled, sbScheduled, nbRealtime, sbRealtime, al)

            // Merge GTFS scheduled times with SIRI real-time service types
            north = mergeScheduledWithRealtime(scheduled: nScheduled, realtime: nRealtime)
            south = mergeScheduledWithRealtime(scheduled: sScheduled, realtime: sRealtime)
            sharedAlerts = a

            // Record usage history for pattern learning
            CommuteHistoryStorage.shared.recordCheck(
                fromStopCode: northboundStopCode,
                toStopCode: southboundStopCode,
                direction: "North"
            )
            CommuteHistoryStorage.shared.recordCheck(
                fromStopCode: southboundStopCode,
                toStopCode: northboundStopCode,
                direction: "South"
            )

            // Fetch weather for destination stations
            await weatherService.fetchWeather(for: northboundStop)
            await weatherService.fetchWeather(for: southboundStop)

        } catch {
            self.error = (error as NSError).localizedDescription
            print("❌ Error loading trains: \(error)")
        }
    }

    // Merge GTFS scheduled times with SIRI real-time service types
    private func mergeScheduledWithRealtime(scheduled: [Departure], realtime: [Departure]) -> [Departure] {
        var result = scheduled

        // Match scheduled trains with real-time data by approximate departure time
        for (index, scheduledDep) in result.enumerated() {
            guard let scheduledTime = scheduledDep.depTime else { continue }

            // Find matching real-time departure (within 2 minutes)
            if let matchingRealtime = realtime.first(where: { realtimeDep in
                guard let realtimeTime = realtimeDep.depTime else { return false }
                let diff = abs(scheduledTime.timeIntervalSince(realtimeTime))
                return diff < 120 // 2 minutes tolerance
            }) {
                // Update with real-time service type if available
                if let serviceType = matchingRealtime.trainNumber, !serviceType.isEmpty {
                    result[index] = Departure(
                        journeyRef: scheduledDep.journeyRef,
                        minutes: scheduledDep.minutes,
                        depTime: scheduledDep.depTime,
                        direction: scheduledDep.direction,
                        destination: scheduledDep.destination,
                        trainNumber: serviceType
                    )
                }
            }
        }

        return result
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
            VStack(alignment: .leading, spacing: 4) {
                Text(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "—").font(.headline)
                HStack(spacing: 4) {
                    Text(destinationLabel).font(.subheadline).foregroundStyle(.secondary)
                    if let serviceType = dep.trainNumber, !serviceType.isEmpty {
                        Text("(\(serviceType))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
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
        stations.append(contentsOf: CaltrainStops.northbound.reversed().map { $0.name })
        return stations
    }

    private var filteredEvents: [BayAreaEvent] {
        // First filter by capacity (20,000+)
        let largeEvents = events.filter { event in
            guard let capacity = event.venueCapacity else { return false }
            return capacity >= 20000
        }

        // Then filter by station if selected
        if selectedStation == "All Stations" {
            return largeEvents
        }

        return largeEvents.filter { event in
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
                } else {
                    ZStack(alignment: .top) {
                        // Events list or empty state
                        if filteredEvents.isEmpty {
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
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
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
                            .safeAreaInset(edge: .top, spacing: 0) {
                                VStack(spacing: 12) {
                                    Menu {
                                        Picker("Station", selection: $selectedStation) {
                                            ForEach(allStationNames, id: \.self) { station in
                                                Text(station).tag(station)
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text("Station:")
                                                .foregroundStyle(.secondary)
                                            Text(selectedStation)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                    }

                                    if selectedStation != "All Stations" {
                                        VStack(spacing: 4) {
                                            HStack {
                                                Text("Max Distance")
                                                Spacer()
                                                Text("\(String(format: "%.1f", maxDistance)) mi")
                                                    .foregroundStyle(.secondary)
                                            }
                                            Slider(value: $maxDistance, in: 0.5...10.0, step: 0.5)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(.systemGroupedBackground))
                            }
                        }
                    }
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
    let trainNumber: String?
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
    let venueCapacity: Int?

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

// MARK: - Saved Commutes
struct SavedCommute: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var southboundStopCode: String
    var northboundStopCode: String

    init(id: UUID = UUID(), name: String, southboundStopCode: String, northboundStopCode: String) {
        self.id = id
        self.name = name
        self.southboundStopCode = southboundStopCode
        self.northboundStopCode = northboundStopCode
    }

    var southboundStation: CaltrainStop? {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode }
    }

    var northboundStation: CaltrainStop? {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode }
    }
}

class CommuteStorage {
    static let shared = CommuteStorage()
    private let key = "savedCommutes"

    func load() -> [SavedCommute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let commutes = try? JSONDecoder().decode([SavedCommute].self, from: data) else {
            return []
        }
        return commutes
    }

    func save(_ commutes: [SavedCommute]) {
        if let data = try? JSONEncoder().encode(commutes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Commute History & Pattern Learning
struct CommuteHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let fromStopCode: String
    let toStopCode: String
    let direction: String // "North" or "South"
    let timeOfDay: Int // Hour of day (0-23)
    let dayOfWeek: Int // 1=Sunday, 7=Saturday
    var wasTripTaken: Bool = false // true = user confirmed they took this trip

    init(fromStopCode: String, toStopCode: String, direction: String, wasTripTaken: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.fromStopCode = fromStopCode
        self.toStopCode = toStopCode
        self.direction = direction
        self.wasTripTaken = wasTripTaken

        let calendar = Calendar.current
        self.timeOfDay = calendar.component(.hour, from: timestamp)
        self.dayOfWeek = calendar.component(.weekday, from: timestamp)
    }
}

struct CommutePattern: Codable {
    let fromStopCode: String
    let toStopCode: String
    let direction: String
    let commonHours: [Int] // Hours user typically checks this route
    let frequency: Int // Number of times checked
    let lastUsed: Date
}

class CommuteHistoryStorage {
    static let shared = CommuteHistoryStorage()
    private let historyKey = "commuteHistory"
    private let maxHistoryEntries = 500 // Keep last 500 checks

    func recordCheck(fromStopCode: String, toStopCode: String, direction: String) {
        var history = loadHistory()
        let entry = CommuteHistoryEntry(fromStopCode: fromStopCode, toStopCode: toStopCode, direction: direction)
        history.append(entry)

        // Keep only recent entries
        if history.count > maxHistoryEntries {
            history = Array(history.suffix(maxHistoryEntries))
        }

        saveHistory(history)
    }

    func loadHistory() -> [CommuteHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([CommuteHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    private func saveHistory(_ history: [CommuteHistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    // Analyze patterns to find user's regular commutes
    func analyzePatterns() -> [CommutePattern] {
        let history = loadHistory()
        guard !history.isEmpty else { return [] }

        // Group by route (from-to-direction)
        var routeCounts: [String: [CommuteHistoryEntry]] = [:]
        for entry in history {
            let key = "\(entry.fromStopCode)-\(entry.toStopCode)-\(entry.direction)"
            routeCounts[key, default: []].append(entry)
        }

        // Find patterns for routes checked 3+ times
        return routeCounts.compactMap { key, entries in
            guard entries.count >= 3 else { return nil }

            let parts = key.split(separator: "-")
            guard parts.count == 3 else { return nil }

            // Find common hours (hours when this route is checked most)
            let hourCounts = Dictionary(grouping: entries, by: { $0.timeOfDay })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }

            return CommutePattern(
                fromStopCode: String(parts[0]),
                toStopCode: String(parts[1]),
                direction: String(parts[2]),
                commonHours: hourCounts,
                frequency: entries.count,
                lastUsed: entries.map { $0.timestamp }.max() ?? Date()
            )
        }.sorted { $0.frequency > $1.frequency }
    }

    // Calculate CO2 savings - only count confirmed trips
    func calculateCO2Savings() -> (trips: Int, co2SavedLbs: Double) {
        let history = loadHistory()

        // Filter to last 30 days AND only trips user confirmed they took
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let confirmedTrips = history.filter { $0.timestamp >= thirtyDaysAgo && $0.wasTripTaken }

        // Average Caltrain trip ~25 miles, car emits ~0.89 lbs CO2/mile
        // So each train trip saves ~22 lbs CO2
        let co2PerTrip = 22.0
        let totalSaved = Double(confirmedTrips.count) * co2PerTrip

        return (trips: confirmedTrips.count, co2SavedLbs: totalSaved)
    }

    // Mark a trip as taken
    func markTripTaken(entryId: UUID) {
        var history = loadHistory()
        if let index = history.firstIndex(where: { $0.id == entryId }) {
            history[index].wasTripTaken = true
            saveHistory(history)
        }
    }

    // Get weekly stats
    func getWeeklyStats() -> (checksThisWeek: Int, mostCommonRoute: String?) {
        let history = loadHistory()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let weekHistory = history.filter { $0.timestamp >= weekAgo }

        let routeCounts = Dictionary(grouping: weekHistory, by: { "\($0.fromStopCode)-\($0.toStopCode)" })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        let mostCommon = routeCounts.first.map { from_to, _ in
            let parts = from_to.split(separator: "-")
            let fromName = CaltrainStops.northbound.first { $0.stopCode == String(parts[0]) }?.name ?? "Unknown"
            let toName = CaltrainStops.northbound.first { $0.stopCode == String(parts[1]) }?.name ?? "Unknown"
            return "\(fromName) → \(toName)"
        }

        return (checksThisWeek: weekHistory.count, mostCommonRoute: mostCommon)
    }
}

// MARK: - Smart Notifications
class SmartNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SmartNotificationManager()
    @Published var notificationsEnabled = false
    @Published var hasRequestedPermission = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkPermissionStatus()
    }

    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = settings.authorizationStatus == .authorized
                self.hasRequestedPermission = settings.authorizationStatus != .notDetermined
            }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.hasRequestedPermission = true
                UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
            }
        }
    }

    // Schedule notification for usual train departing soon
    func scheduleUsualTrainNotification(trainTime: Date, fromStation: String, toStation: String, minutes: Int) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your Usual Train"
        content.body = "The \(trainTime.formatted(date: .omitted, time: .shortened)) train from \(fromStation) to \(toStation) departs in \(minutes) minutes"
        content.sound = .default

        // Trigger 15 minutes before departure
        let triggerDate = Calendar.current.date(byAdding: .minute, value: -(15), to: trainTime)!
        let components = Calendar.current.dateComponents([.hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: "usualTrain-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // Send notification for Giants game crowding
    func notifyGiantsGameCrowding(gameTime: String) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Giants Game Today ⚾"
        content.body = "Expect crowded trains after \(gameTime). Plan extra time for your commute."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "giantsGame-\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // Send notification for service alerts
    func notifyServiceAlert(alert: ServiceAlert) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Caltrain Service Alert"
        content.body = alert.summary
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "alert-\(alert.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // UNUserNotificationCenterDelegate methods
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

// MARK: - Weather Service (OpenWeatherMap)
@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published var currentWeather: [String: (temp: Double, condition: String, symbol: String)] = [:]

    // OpenWeatherMap API - free tier, no signup required for basic usage
    // Using a demo key - users can add their own in Settings for unlimited requests
    private let apiKey = "demo" // Will use free tier endpoint

    func fetchWeather(for station: CaltrainStop) async {
        // Use Open-Meteo - completely free, no API key, very reliable
        // API: https://open-meteo.com/en/docs
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(station.latitude)&longitude=\(station.longitude)&current=temperature_2m,weather_code&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

        guard let url = URL(string: urlString) else {
            print("❌ Invalid weather URL for \(station.name)")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let temp = current["temperature_2m"] as? Double,
               let weatherCode = current["weather_code"] as? Int {

                let emoji = getWeatherEmojiFromCode(weatherCode)
                let condition = getWeatherDescription(weatherCode)

                currentWeather[station.stopCode] = (temp: temp, condition: condition, symbol: emoji)
                print("✅ Weather fetched for \(station.name): \(Int(temp))°F, \(condition)")
            } else {
                print("❌ Failed to parse weather JSON for \(station.name)")
            }
        } catch {
            print("❌ Weather fetch failed for \(station.name): \(error.localizedDescription)")
        }
    }

    // Open-Meteo weather code mapping
    // https://open-meteo.com/en/docs
    func getWeatherEmojiFromCode(_ code: Int) -> String {
        switch code {
        case 0: return "☀️" // Clear sky
        case 1, 2: return "🌤️" // Mainly clear, partly cloudy
        case 3: return "☁️" // Overcast
        case 45, 48: return "🌫️" // Fog
        case 51, 53, 55: return "🌦️" // Drizzle
        case 61, 63, 65: return "🌧️" // Rain
        case 71, 73, 75, 77: return "❄️" // Snow
        case 80, 81, 82: return "🌧️" // Rain showers
        case 85, 86: return "🌨️" // Snow showers
        case 95, 96, 99: return "⛈️" // Thunderstorm
        default: return "🌤️"
        }
    }

    func getWeatherDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rainy"
        case 71, 73, 75, 77: return "Snowy"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
}

// MARK: - GTFS Models
struct GTFSStop: Hashable {
    let stopId: String
    let stopName: String
}

struct GTFSTrip: Hashable {
    let tripId: String
    let serviceId: String
    let directionId: Int // 0 = northbound, 1 = southbound
    let routeId: String
}

struct GTFSStopTime: Hashable {
    let tripId: String
    let stopId: String
    let departureTime: String // HH:MM:SS format (can be >24 hours like "25:30:00")
    let stopSequence: Int
}

struct GTFSCalendar: Hashable {
    let serviceId: String
    let monday: Bool
    let tuesday: Bool
    let wednesday: Bool
    let thursday: Bool
    let friday: Bool
    let saturday: Bool
    let sunday: Bool
    let startDate: String // YYYYMMDD
    let endDate: String   // YYYYMMDD
}

struct GTFSCalendarDate: Hashable {
    let serviceId: String
    let date: String // YYYYMMDD
    let exceptionType: Int // 1 = added, 2 = removed
}

// MARK: - GTFS Service
actor GTFSService {
    static let shared = GTFSService()

    private var stops: [GTFSStop] = []
    private var trips: [GTFSTrip] = []
    private var stopTimes: [GTFSStopTime] = []
    private var calendars: [GTFSCalendar] = []
    private var calendarDates: [GTFSCalendarDate] = []
    private var lastFetchDate: Date?

    private let gtfsURL = "https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip"
    private let cacheExpirationHours = 24.0

    func ensureGTFSLoaded() async throws {
        // Check if we need to refresh
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheExpirationHours * 3600,
           !trips.isEmpty {
            return // Already loaded and fresh
        }

        try await downloadAndParseGTFS()
    }

    private func unzipGTFS(from zipPath: URL, to destDir: URL) throws {
        // Simple ZIP extractor for iOS
        let zipData = try Data(contentsOf: zipPath)
        try extractZip(data: zipData, to: destDir)
    }

    // Minimal ZIP file parser (supports basic DEFLATE compressed ZIP files)
    private func extractZip(data: Data, to destDir: URL) throws {
        let fileManager = FileManager.default

        // ZIP file structure parsing
        var offset = 0
        let bytes = [UInt8](data)

        while offset < bytes.count - 30 {
            // Look for local file header signature: 0x04034b50
            guard offset + 30 <= bytes.count else { break }

            let sig = UInt32(bytes[offset]) |
                      (UInt32(bytes[offset+1]) << 8) |
                      (UInt32(bytes[offset+2]) << 16) |
                      (UInt32(bytes[offset+3]) << 24)

            if sig == 0x04034b50 {
                // Local file header found
                let compMethod = UInt16(bytes[offset+8]) | (UInt16(bytes[offset+9]) << 8)
                let compSize = UInt32(bytes[offset+18]) |
                              (UInt32(bytes[offset+19]) << 8) |
                              (UInt32(bytes[offset+20]) << 16) |
                              (UInt32(bytes[offset+21]) << 24)
                let uncompSize = UInt32(bytes[offset+22]) |
                                (UInt32(bytes[offset+23]) << 8) |
                                (UInt32(bytes[offset+24]) << 16) |
                                (UInt32(bytes[offset+25]) << 24)
                let nameLen = UInt16(bytes[offset+26]) | (UInt16(bytes[offset+27]) << 8)
                let extraLen = UInt16(bytes[offset+28]) | (UInt16(bytes[offset+29]) << 8)

                let nameStart = offset + 30
                let nameEnd = nameStart + Int(nameLen)
                guard nameEnd <= bytes.count else { break }

                let fileNameData = Data(bytes[nameStart..<nameEnd])
                guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                    offset = nameEnd + Int(extraLen) + Int(compSize)
                    continue
                }

                // Skip directories
                if fileName.hasSuffix("/") {
                    offset = nameEnd + Int(extraLen) + Int(compSize)
                    continue
                }

                let dataStart = nameEnd + Int(extraLen)
                let dataEnd = dataStart + Int(compSize)
                guard dataEnd <= bytes.count else { break }

                let compData = Data(bytes[dataStart..<dataEnd])

                // Decompress based on compression method
                let decompData: Data
                if compMethod == 0 {
                    // No compression
                    decompData = compData
                } else if compMethod == 8 {
                    // DEFLATE compression
                    decompData = try decompress(compData, uncompressedSize: Int(uncompSize))
                } else {
                    // Unsupported compression method
                    throw NSError(domain: "GTFS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported ZIP compression method: \(compMethod)"])
                }

                // Write file
                let filePath = destDir.appendingPathComponent(fileName)
                try fileManager.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try decompData.write(to: filePath)

                offset = dataEnd
            } else {
                offset += 1
            }
        }
    }

    private func decompress(_ data: Data, uncompressedSize: Int) throws -> Data {
        // Use Apple's Compression framework (available on iOS 9+)
        let sourceBuffer = [UInt8](data)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = sourceBuffer.withUnsafeBufferPointer { srcPtr in
            compression_decode_buffer(
                destinationBuffer,
                uncompressedSize,
                srcPtr.baseAddress!,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw NSError(domain: "GTFS", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress ZIP data"])
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    private func downloadAndParseGTFS() async throws {
        print("📥 Downloading GTFS feed...")

        guard let url = URL(string: gtfsURL) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        print("📦 GTFS downloaded (\(data.count) bytes), extracting...")

        // Create temp directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Save ZIP to temp file
        let zipPath = tempDir.appendingPathComponent("gtfs.zip")
        try data.write(to: zipPath)

        // Unzip the GTFS data
        try unzipGTFS(from: zipPath, to: tempDir)

        print("📖 Parsing GTFS CSV files...")

        // Parse each CSV file
        stops = try parseStops(at: tempDir.appendingPathComponent("stops.txt"))
        trips = try parseTrips(at: tempDir.appendingPathComponent("trips.txt"))
        stopTimes = try parseStopTimes(at: tempDir.appendingPathComponent("stop_times.txt"))
        calendars = try parseCalendars(at: tempDir.appendingPathComponent("calendar.txt"))
        calendarDates = try parseCalendarDates(at: tempDir.appendingPathComponent("calendar_dates.txt"))

        lastFetchDate = Date()

        print("✅ GTFS loaded: \(stops.count) stops, \(trips.count) trips, \(stopTimes.count) stop times")
    }

    private func parseStops(at url: URL) throws -> [GTFSStop] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine)
        guard let stopIdIdx = headers.firstIndex(of: "stop_id"),
              let stopNameIdx = headers.firstIndex(of: "stop_name") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count > max(stopIdIdx, stopNameIdx) else { return nil }
            return GTFSStop(stopId: fields[stopIdIdx], stopName: fields[stopNameIdx])
        }
    }

    private func parseTrips(at url: URL) throws -> [GTFSTrip] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine)
        guard let tripIdIdx = headers.firstIndex(of: "trip_id"),
              let serviceIdIdx = headers.firstIndex(of: "service_id"),
              let directionIdIdx = headers.firstIndex(of: "direction_id"),
              let routeIdIdx = headers.firstIndex(of: "route_id") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count > max(tripIdIdx, serviceIdIdx, directionIdIdx, routeIdIdx),
                  let directionId = Int(fields[directionIdIdx]) else { return nil }
            return GTFSTrip(
                tripId: fields[tripIdIdx],
                serviceId: fields[serviceIdIdx],
                directionId: directionId,
                routeId: fields[routeIdIdx]
            )
        }
    }

    private func parseStopTimes(at url: URL) throws -> [GTFSStopTime] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine)
        guard let tripIdIdx = headers.firstIndex(of: "trip_id"),
              let stopIdIdx = headers.firstIndex(of: "stop_id"),
              let departureTimeIdx = headers.firstIndex(of: "departure_time"),
              let stopSequenceIdx = headers.firstIndex(of: "stop_sequence") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count > max(tripIdIdx, stopIdIdx, departureTimeIdx, stopSequenceIdx),
                  let stopSequence = Int(fields[stopSequenceIdx]) else { return nil }
            return GTFSStopTime(
                tripId: fields[tripIdIdx],
                stopId: fields[stopIdIdx],
                departureTime: fields[departureTimeIdx],
                stopSequence: stopSequence
            )
        }
    }

    private func parseCalendars(at url: URL) throws -> [GTFSCalendar] {
        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine)
        guard let serviceIdIdx = headers.firstIndex(of: "service_id"),
              let mondayIdx = headers.firstIndex(of: "monday"),
              let tuesdayIdx = headers.firstIndex(of: "tuesday"),
              let wednesdayIdx = headers.firstIndex(of: "wednesday"),
              let thursdayIdx = headers.firstIndex(of: "thursday"),
              let fridayIdx = headers.firstIndex(of: "friday"),
              let saturdayIdx = headers.firstIndex(of: "saturday"),
              let sundayIdx = headers.firstIndex(of: "sunday"),
              let startDateIdx = headers.firstIndex(of: "start_date"),
              let endDateIdx = headers.firstIndex(of: "end_date") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            let maxIdx = max(serviceIdIdx, mondayIdx, tuesdayIdx, wednesdayIdx, thursdayIdx, fridayIdx, saturdayIdx, sundayIdx, startDateIdx, endDateIdx)
            guard fields.count > maxIdx else { return nil }
            return GTFSCalendar(
                serviceId: fields[serviceIdIdx],
                monday: fields[mondayIdx] == "1",
                tuesday: fields[tuesdayIdx] == "1",
                wednesday: fields[wednesdayIdx] == "1",
                thursday: fields[thursdayIdx] == "1",
                friday: fields[fridayIdx] == "1",
                saturday: fields[saturdayIdx] == "1",
                sunday: fields[sundayIdx] == "1",
                startDate: fields[startDateIdx],
                endDate: fields[endDateIdx]
            )
        }
    }

    private func parseCalendarDates(at url: URL) throws -> [GTFSCalendarDate] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [] // calendar_dates.txt is optional
        }

        let csv = try String(contentsOf: url, encoding: .utf8)
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine)
        guard let serviceIdIdx = headers.firstIndex(of: "service_id"),
              let dateIdx = headers.firstIndex(of: "date"),
              let exceptionTypeIdx = headers.firstIndex(of: "exception_type") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count > max(serviceIdIdx, dateIdx, exceptionTypeIdx),
                  let exceptionType = Int(fields[exceptionTypeIdx]) else { return nil }
            return GTFSCalendarDate(
                serviceId: fields[serviceIdIdx],
                date: fields[dateIdx],
                exceptionType: exceptionType
            )
        }
    }

    // Simple CSV parser that handles quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField.trimmingCharacters(in: .whitespaces))

        return fields
    }

    // Get scheduled departures for a stop at a given time
    func getScheduledDepartures(stopCode: String, direction: Int, refDate: Date, count: Int = 3) async throws -> [Departure] {
        try await ensureGTFSLoaded()

        // Convert stopCode to GTFS stop_id format
        // Caltrain uses stopCode like "70212" which maps to stop_id in GTFS
        let stopId = stopCode

        // Get current date components in Pacific Time
        var pacificCalendar = Calendar.current
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let today = pacificCalendar.startOfDay(for: refDate)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = pacificCalendar.timeZone
        let todayStr = dateFormatter.string(from: today)

        // Get weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
        let weekday = pacificCalendar.component(.weekday, from: today)

        // Find active services for today
        let activeServices = getActiveServices(dateStr: todayStr, weekday: weekday)

        // Find trips for this direction and active services
        let relevantTrips = trips.filter { trip in
            trip.directionId == direction && activeServices.contains(trip.serviceId)
        }

        // Get stop times for these trips at our stop
        let relevantStopTimes = stopTimes.filter { st in
            st.stopId == stopId && relevantTrips.contains { $0.tripId == st.tripId }
        }

        // Convert reference time to minutes since midnight
        let refComponents = pacificCalendar.dateComponents([.hour, .minute], from: refDate)
        let refMinutes = (refComponents.hour ?? 0) * 60 + (refComponents.minute ?? 0)

        // Parse departure times and filter for times after reference time
        var departures: [(time: String, minutes: Int, tripId: String, departureDate: Date)] = []

        for st in relevantStopTimes {
            let timeComponents = st.departureTime.split(separator: ":")
            guard timeComponents.count == 3,
                  let hours = Int(timeComponents[0]),
                  let minutes = Int(timeComponents[1]) else { continue }

            var totalMinutes = hours * 60 + minutes
            var departureDate = today

            // Handle times >= 24:00:00 (next day)
            if hours >= 24 {
                totalMinutes = (hours - 24) * 60 + minutes
                departureDate = pacificCalendar.date(byAdding: .day, value: 1, to: today)!
            }

            // Only include departures after reference time (same day)
            if totalMinutes >= refMinutes {
                let minutesUntil = totalMinutes - refMinutes
                departures.append((st.departureTime, minutesUntil, st.tripId, departureDate))
            }
        }

        // Sort by minutes until departure and take first N
        departures.sort { $0.minutes < $1.minutes }
        let topDepartures = departures.prefix(count)

        // Get current time for calculating actual minutes until departure
        let now = Date()

        // Convert to Departure objects
        return topDepartures.map { dep in

            // Parse time to create actual departure Date
            let timeComponents = dep.time.split(separator: ":")
            var depDate = dep.departureDate
            if let hours = Int(timeComponents[0]), let mins = Int(timeComponents[1]) {
                let actualHours = hours >= 24 ? hours - 24 : hours
                depDate = pacificCalendar.date(bySettingHour: actualHours, minute: mins, second: 0, of: dep.departureDate) ?? dep.departureDate
            }

            // Calculate minutes until departure from current time (not reference time)
            let minutesUntilDeparture = Int(depDate.timeIntervalSince(now) / 60)

            // Get destination from last stop in trip
            let tripStopTimes = stopTimes.filter { $0.tripId == dep.tripId }.sorted { $0.stopSequence < $1.stopSequence }
            let lastStopId = tripStopTimes.last?.stopId
            let destination = stops.first { $0.stopId == lastStopId }?.stopName ?? "Unknown"

            return Departure(
                journeyRef: dep.tripId,
                minutes: minutesUntilDeparture,
                depTime: depDate,
                direction: direction == 0 ? "North" : "South",
                destination: destination,
                trainNumber: nil // Will be filled with service type from SIRI if available
            )
        }
    }

    private func getActiveServices(dateStr: String, weekday: Int) -> Set<String> {
        var activeServices = Set<String>()

        // Check calendar.txt for regular schedules
        for cal in calendars {
            // Check if date is in range
            guard dateStr >= cal.startDate && dateStr <= cal.endDate else { continue }

            // Check if service runs on this weekday
            let runsToday: Bool
            switch weekday {
            case 1: runsToday = cal.sunday
            case 2: runsToday = cal.monday
            case 3: runsToday = cal.tuesday
            case 4: runsToday = cal.wednesday
            case 5: runsToday = cal.thursday
            case 6: runsToday = cal.friday
            case 7: runsToday = cal.saturday
            default: runsToday = false
            }

            if runsToday {
                activeServices.insert(cal.serviceId)
            }
        }

        // Apply exceptions from calendar_dates.txt
        for calDate in calendarDates {
            guard calDate.date == dateStr else { continue }

            if calDate.exceptionType == 1 {
                // Service added for this date
                activeServices.insert(calDate.serviceId)
            } else if calDate.exceptionType == 2 {
                // Service removed for this date
                activeServices.remove(calDate.serviceId)
            }
        }

        return activeServices
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
    let PublishedLineName: String?
    let VehicleRef: String?

    enum CodingKeys: String, CodingKey {
        case LineRef, DirectionRef, DestinationName, MonitoredCall, FramedVehicleJourneyRef, PublishedLineName, VehicleRef
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.LineRef = try? c.decodeIfPresent(String.self, forKey: .LineRef)
        self.DirectionRef = try? c.decodeIfPresent(String.self, forKey: .DirectionRef)
        self.MonitoredCall = try? c.decodeIfPresent(MonitoredCallNode.self, forKey: .MonitoredCall)
        self.FramedVehicleJourneyRef = try? c.decodeIfPresent(FramedVehicleJourneyRefNode.self, forKey: .FramedVehicleJourneyRef)
        self.PublishedLineName = try? c.decodeIfPresent(String.self, forKey: .PublishedLineName)
        self.VehicleRef = try? c.decodeIfPresent(String.self, forKey: .VehicleRef)

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
        let now = refDate // Use the selected time from the picker

        var out: [Departure] = []
        print("📍 Stop: \(stop), Expected Dir: \(expectedDirection ?? "any"), RefDate: \(now), Visits: \(visits.count)")
        for v in visits {
            let mvj = v.MonitoredVehicleJourney
            let aimed = mvj.MonitoredCall?.AimedDepartureTime
            let date = aimed.flatMap { dfFrac.date(from: $0) ?? df.date(from: $0) }
            // Calculate minutes, rounding up (ceiling) so a train in 30 seconds shows as 1m
            let minutes = date.map { Int(ceil($0.timeIntervalSince(now) / 60)) } ?? 0
            let direction = mvj.DirectionRef

            // Debug: Print all available fields
            print("  🚂 Dir: \(direction ?? "?"), Aimed: \(aimed ?? "nil"), Minutes: \(minutes), Dest: \(mvj.DestinationName ?? "nil")")
            print("     LineRef: \(mvj.LineRef ?? "nil")")
            print("     PublishedLineName: \(mvj.PublishedLineName ?? "nil")")
            print("     VehicleRef: \(mvj.VehicleRef ?? "nil")")
            print("     DatedVehicleJourneyRef: \(mvj.FramedVehicleJourneyRef?.DatedVehicleJourneyRef ?? "nil")")

            // Filter by direction if we have an expected direction
            if let expected = expectedDirection, direction != expected {
                print("    ⏭️  Skipping - wrong direction")
                continue
            }

            // Extract service type (Local, Limited, etc.) from LineRef
            let journeyRef = mvj.FramedVehicleJourneyRef?.DatedVehicleJourneyRef ?? UUID().uuidString
            let serviceType = mvj.LineRef

            let dep = Departure(
                journeyRef: journeyRef,
                minutes: minutes, depTime: date,
                direction: mvj.DirectionRef, destination: mvj.DestinationName,
                trainNumber: serviceType
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
                var venueCapacity: Int?
                if let embedded = eventData["_embedded"] as? [String: Any],
                   let venues = embedded["venues"] as? [[String: Any]],
                   let firstVenue = venues.first {
                    venueName = firstVenue["name"] as? String

                    // Parse capacity
                    if let capacity = firstVenue["capacity"] as? Int {
                        venueCapacity = capacity
                    } else if let capacityStr = firstVenue["capacity"] as? String,
                              let capacity = Int(capacityStr) {
                        venueCapacity = capacity
                    }

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
                    venueLongitude: venueLon,
                    venueCapacity: venueCapacity
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
