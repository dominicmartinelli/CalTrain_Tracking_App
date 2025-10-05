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
    @AppStorage("username") private var username = ""
    @State private var apiKey: String = ""
    @State private var status: String = ""
    @State private var statusColor: Color = .secondary

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Username (optional)", text: $username)
                        .textInputAutocapitalization(.never)
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
                Section("About") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
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

// MARK: - Trains UI
struct TrainsScreen: View {
    @State private var refDate = Date()
    @State private var north: [Departure] = []
    @State private var south: [Departure] = []
    @State private var loading = false
    @State private var error: String?
    @State private var sel = 0 // 0 = MV→22nd, 1 = 22nd→MV (UI only)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Time", selection: $refDate, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.compact)

                Picker("Route", selection: $sel) {
                    Text("MV → 22nd").tag(0)
                    Text("22nd → MV").tag(1)
                }
                .pickerStyle(.segmented)

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
                    Section("Northbound MV → 22nd") { ForEach(north) { DepartureRow(dep: $0) } }
                    Section("Southbound 22nd → MV") { ForEach(south) { DepartureRow(dep: $0) } }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal)
            .navigationTitle("Caltrain MV ⇄ 22nd")
            .task { await load() } // initial fetch
            .onChange(of: refDate, initial: false) { _, _ in // iOS 17 two-arg
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
        do {
            async let nb = SIRIService.nextDepartures(from: Stops.mvNorth, at: refDate, apiKey: key)
            async let sb = SIRIService.nextDepartures(from: Stops.st22South, at: refDate, apiKey: key)
            let (n, s) = try await (nb, sb)
            north = n; south = s
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

struct DepartureRow: View {
    let dep: Departure

    private var destinationLabel: String {
        // Show the actual stations for this route (MV ⇄ 22nd)
        if dep.direction == "N" {
            return "22nd Street"
        } else if dep.direction == "S" {
            return "Mountain View"
        }
        return "—"
    }

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
enum Stops {
    // Caltrain 511 Stop Codes
    // Mountain View station code is 70211 (northbound) and 70212 (southbound)
    // 22nd Street station code is 70021 (northbound) and 70022 (southbound)
    static let mvNorth = "70211"   // Mountain View → SF (northbound platform)
    static let st22South = "70022"  // 22nd Street → SJ (southbound platform)
}

struct Departure: Identifiable, Hashable {
    var id: String { journeyRef + (depTime?.ISO8601Format() ?? "") }
    let journeyRef: String
    let minutes: Int
    let depTime: Date?
    let direction: String?
    let destination: String?
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let many = try? c.decode([StopMonitoringDeliveryNode].self, forKey: .StopMonitoringDelivery) {
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.LineRef = try? c.decodeIfPresent(String.self, forKey: .LineRef)
        self.DirectionRef = try? c.decodeIfPresent(String.self, forKey: .DirectionRef)
        self.MonitoredCall = try? c.decodeIfPresent(MonitoredCallNode.self, forKey: .MonitoredCall)
        self.FramedVehicleJourneyRef = try? c.decodeIfPresent(FramedVehicleJourneyRefNode.self, forKey: .FramedVehicleJourneyRef)

        if let s = try? c.decodeIfPresent(String.self, forKey: .DestinationName) {
            self.DestinationName = s
        } else if let arr = try? c.decodeIfPresent([String].self, forKey: .DestinationName) {
            self.DestinationName = arr.first
        } else {
            self.DestinationName = nil
        }
    }
}

struct FramedVehicleJourneyRefNode: Decodable { let DatedVehicleJourneyRef: String? }
struct MonitoredCallNode: Decodable { let AimedDepartureTime: String? }

// MARK: - SIRI service
struct SIRIService {
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

    static func nextDepartures(from stop: String, at refDate: Date, apiKey: String) async throws -> [Departure] {
        let visits = try await stopMonitoring(stopCode: stop, apiKey: apiKey)
        let dfFrac = ISO8601DateFormatter(); dfFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df = ISO8601DateFormatter()
        let now = Date() // Use actual current time, not the picker time

        // Determine expected direction based on stop code
        let expectedDirection = (stop == Stops.mvNorth || stop == Stops.st22South) ?
            (stop == Stops.mvNorth ? "N" : "S") : nil

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
