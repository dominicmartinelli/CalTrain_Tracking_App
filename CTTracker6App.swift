// Caltrain + Giants Checker (iOS 17+, single file)
// - Single @main app file
// - Uses .task { } + iOS17 .onChange(of:initial:) (no .task(id:) ambiguity)
// - Robust 511 SIRI decode (wrapped/bare root, array/single deliveries, String/[String] destination)
// - Keychain-backed API key gate with full-screen cover
// - Giants home-game indicator via MLB Stats API

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
    guard !trimmed.isEmpty, trimmed.count <= 128 else { return false }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
    return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
}

// MARK: - App Entry (single @main)
@main
struct CaltrainCheckerApp: App {
    @StateObject private var app = AppState()

    init() {
        // Seed Keychain from embedded key if none present
        if (Keychain.shared["api_511"] ?? "").isEmpty,
           let embedded = EmbeddedAPIKey_SIMULATOR_ONLY, !embedded.isEmpty {
            Keychain.shared["api_511"] = embedded
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
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

    // Bind cover visibility (true when key is missing)
    private var needsKeyBinding: Binding<Bool> {
        Binding(get: { !app.hasKey }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $tab) {
            TrainsScreen()
                .tabItem { Label("Trains", systemImage: "train.side.front.car") }.tag(0)
            GiantsScreen()
                .tabItem { Label("Giants", systemImage: "baseball") }.tag(1)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .fullScreenCover(isPresented: needsKeyBinding) {
            APIKeySetupScreen().environmentObject(app)
        }
        .onAppear { app.refreshFromKeychain() }
    }
}

// MARK: - Settings
struct SettingsScreen: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode
    @State private var apiKey: String = ""
    @State private var status: String = ""
    @State private var statusColor: Color = .secondary

    private var selectedNorthbound: CaltrainStop {
        CaltrainStops.northbound.first { $0.stopCode == northboundStopCode } ?? CaltrainStops.defaultNorthbound
    }

    private var selectedSouthbound: CaltrainStop {
        CaltrainStops.southbound.first { $0.stopCode == southboundStopCode } ?? CaltrainStops.defaultSouthbound
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Train Stations") {
                    Picker("Southern Station", selection: $northboundStopCode) {
                        ForEach(CaltrainStops.northbound) { stop in
                            Text(stop.name).tag(stop.stopCode)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 80)

                    Picker("Northern Station", selection: $southboundStopCode) {
                        ForEach(CaltrainStops.southbound) { stop in
                            Text(stop.name).tag(stop.stopCode)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 80)
                }

                Section("511.org API") {
                    SecureField("API Key", text: $apiKey)
                    if !status.isEmpty { Text(status).foregroundStyle(statusColor) }
                    HStack {
                        Button("Save") { save() }
                        Button("Verify") { verify() }
                        Button("Clear") {
                            app.clearKey()
                            apiKey = ""
                            status = "Cleared from Keychain."
                            statusColor = .orange
                        }
                        .tint(.red)
                    }
                    if let stored = Keychain.shared["api_511"], !stored.isEmpty {
                        LabeledContent("Stored", value: Keychain.masked(stored))
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
            .onAppear {
                apiKey = Keychain.shared["api_511"] ?? ""
                verify()
            }
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyAPIKey(trimmed) else {
            status = "Please enter a valid key."
            statusColor = .red
            return
        }
        app.saveKey(trimmed)
        verify()
    }
    private func verify() {
        let current = Keychain.shared["api_511"] ?? ""
        if !current.isEmpty { status = "Saved ✓  (\(Keychain.masked(current)))"; statusColor = .green }
        else { status = "No key in Keychain."; statusColor = .red }
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
                        Text("Baseball Data")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Provided by MLB Stats API")
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
    }
}

// MARK: - Trains UI
struct TrainsScreen: View {
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode
    @State private var refDate = Date()
    @State private var north: [Departure] = []
    @State private var south: [Departure] = []
    @State private var alerts: [ServiceAlert] = []
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
                    if !alerts.isEmpty {
                        Section {
                            ForEach(alerts) { alert in
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
            north = n; south = s; alerts = a
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

// MARK: - Giants UI
struct GiantsScreen: View {
    @State private var info: GiantsGameInfo?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if loading { ProgressView("Checking schedule…") }
                if let error { Text(error).foregroundStyle(.red) }
                if let info = info {
                    VStack(spacing: 8) {
                        Text(info.title).font(.title3).bold()
                        Text(info.localTime.formatted(date: .omitted, time: .shortened))
                        if info.isDayGame { Label("Day game today — Caltrain may be busy", systemImage: "exclamationmark.triangle") }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("No Giants home game today (or couldn’t fetch).").foregroundStyle(.secondary)
                }

                Button { Task { await load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Giants")
            .task { await load() }
        }
    }

    func load() async {
        loading = true; defer { loading = false }; error = nil
        do { info = try await GiantsService.todayHomeGame() } catch { self.error = (error as NSError).localizedDescription }
    }
}

// MARK: - Domain & Networking

// Station model
struct CaltrainStop: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let stopCode: String

    init(name: String, stopCode: String) {
        self.id = stopCode
        self.name = name
        self.stopCode = stopCode
    }
}

// All available Caltrain stops
struct CaltrainStops {
    // Northbound stops (toward San Francisco) - odd numbered stop codes
    static let northbound: [CaltrainStop] = [
        CaltrainStop(name: "Gilroy", stopCode: "777403"),
        CaltrainStop(name: "San Martin", stopCode: "777402"),
        CaltrainStop(name: "Morgan Hill", stopCode: "777401"),
        CaltrainStop(name: "Blossom Hill", stopCode: "70007"),
        CaltrainStop(name: "Capitol", stopCode: "70005"),
        CaltrainStop(name: "Tamien", stopCode: "70003"),
        CaltrainStop(name: "San Jose Diridon", stopCode: "70261"),
        CaltrainStop(name: "Santa Clara", stopCode: "70271"),
        CaltrainStop(name: "Lawrence", stopCode: "70281"),
        CaltrainStop(name: "Sunnyvale", stopCode: "70291"),
        CaltrainStop(name: "Mountain View", stopCode: "70211"),
        CaltrainStop(name: "San Antonio", stopCode: "70221"),
        CaltrainStop(name: "California Ave", stopCode: "70231"),
        CaltrainStop(name: "Palo Alto", stopCode: "70241"),
        CaltrainStop(name: "Menlo Park", stopCode: "70251"),
        CaltrainStop(name: "Redwood City", stopCode: "70311"),
        CaltrainStop(name: "San Carlos", stopCode: "70321"),
        CaltrainStop(name: "Belmont", stopCode: "70331"),
        CaltrainStop(name: "Hillsdale", stopCode: "70341"),
        CaltrainStop(name: "San Mateo", stopCode: "70351"),
        CaltrainStop(name: "Burlingame", stopCode: "70361"),
        CaltrainStop(name: "Millbrae", stopCode: "70371"),
        CaltrainStop(name: "San Bruno", stopCode: "70381"),
        CaltrainStop(name: "South San Francisco", stopCode: "70011"),
        CaltrainStop(name: "Bayshore", stopCode: "70031"),
        CaltrainStop(name: "22nd Street", stopCode: "70021"),
        CaltrainStop(name: "San Francisco", stopCode: "70041")
    ]

    // Southbound stops (toward San Jose) - even numbered stop codes
    static let southbound: [CaltrainStop] = [
        CaltrainStop(name: "San Francisco", stopCode: "70042"),
        CaltrainStop(name: "22nd Street", stopCode: "70022"),
        CaltrainStop(name: "Bayshore", stopCode: "70032"),
        CaltrainStop(name: "South San Francisco", stopCode: "70012"),
        CaltrainStop(name: "San Bruno", stopCode: "70382"),
        CaltrainStop(name: "Millbrae", stopCode: "70372"),
        CaltrainStop(name: "Burlingame", stopCode: "70362"),
        CaltrainStop(name: "San Mateo", stopCode: "70352"),
        CaltrainStop(name: "Hillsdale", stopCode: "70342"),
        CaltrainStop(name: "Belmont", stopCode: "70332"),
        CaltrainStop(name: "San Carlos", stopCode: "70322"),
        CaltrainStop(name: "Redwood City", stopCode: "70312"),
        CaltrainStop(name: "Menlo Park", stopCode: "70252"),
        CaltrainStop(name: "Palo Alto", stopCode: "70242"),
        CaltrainStop(name: "California Ave", stopCode: "70232"),
        CaltrainStop(name: "San Antonio", stopCode: "70222"),
        CaltrainStop(name: "Mountain View", stopCode: "70212"),
        CaltrainStop(name: "Sunnyvale", stopCode: "70292"),
        CaltrainStop(name: "Lawrence", stopCode: "70282"),
        CaltrainStop(name: "Santa Clara", stopCode: "70272"),
        CaltrainStop(name: "San Jose Diridon", stopCode: "70262"),
        CaltrainStop(name: "Tamien", stopCode: "70004"),
        CaltrainStop(name: "Capitol", stopCode: "70006"),
        CaltrainStop(name: "Blossom Hill", stopCode: "70008"),
        CaltrainStop(name: "Morgan Hill", stopCode: "777402"),
        CaltrainStop(name: "San Martin", stopCode: "777403"),
        CaltrainStop(name: "Gilroy", stopCode: "777404")
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
        let (raw, http) = try await HTTPClient.shared.get(url: comps.url!)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: raw, encoding: .utf8)?.prefix(200) ?? ""
            throw NSError(domain: "SIRI-SX", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(snippet)"])
        }

        let cleaned = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) ?? raw

        do {
            let env = try JSONDecoder().decode(AlertsEnvelope.self, from: cleaned)
            let sd = env.Siri?.ServiceDelivery ?? env.ServiceDelivery
            let situations = sd?.SituationExchangeDelivery?.first?.Situations?.PtSituationElement ?? []

            let dfFrac = ISO8601DateFormatter(); dfFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let df = ISO8601DateFormatter()

            var alerts: [ServiceAlert] = []
            for sit in situations {
                let creationTime = sit.CreationTime.flatMap { dfFrac.date(from: $0) ?? df.date(from: $0) }
                let summary = sit.Summary ?? "Service Alert"
                let alert = ServiceAlert(
                    id: sit.SituationNumber ?? UUID().uuidString,
                    summary: summary,
                    description: sit.Description,
                    severity: sit.Severity,
                    creationTime: creationTime
                )
                alerts.append(alert)
            }
            return alerts
        } catch {
            let snippet = String(data: cleaned, encoding: .utf8)?.prefix(280) ?? ""
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

// MARK: - Giants helper
struct GiantsGameInfo: Identifiable { let id = UUID(); let title: String; let localTime: Date; let isDayGame: Bool }
enum Teams { static let giantsId = 137 }

struct GiantsService {
    static func todayHomeGame() async throws -> GiantsGameInfo? {
        let dateStr = Date.now.formatted(.iso8601.year().month().day())
        var comps = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        comps.queryItems = [
            .init(name: "sportId", value: "1"),
            .init(name: "teamId", value: String(Teams.giantsId)),
            .init(name: "date", value: dateStr)
        ]
        let (data, http) = try await HTTPClient.shared.get(url: comps.url!)
        guard (200..<300).contains(http.statusCode) else { return nil }
        let obj = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        guard let dates = obj["dates"] as? [[String:Any]], let day = dates.first else { return nil }
        for g in (day["games"] as? [[String:Any]] ?? []) {
            guard
                let teams = g["teams"] as? [String:Any],
                let home = (teams["home"] as? [String:Any])?["team"] as? [String:Any],
                let homeId = home["id"] as? Int,
                let awayName = ((teams["away"] as? [String:Any])?["team"] as? [String:Any])?["name"] as? String,
                homeId == Teams.giantsId
            else { continue }

            let df = ISO8601DateFormatter(); df.formatOptions = [.withInternetDateTime]
            guard let utc = df.date(from: (g["gameDate"] as? String) ?? "") else { continue }
            let local = utc
            let hour = Calendar.current.component(.hour, from: local)
            return GiantsGameInfo(title: "Giants vs. \(awayName)", localTime: local, isDayGame: hour < 18)
        }
        return nil
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
        SecItemDelete(q as CFDictionary)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { print("Keychain save failed: \(status)") }
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
