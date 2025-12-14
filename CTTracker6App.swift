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
import MessageUI

// MARK: - Debug Configuration
#if DEBUG
private nonisolated let isDebugMode = true
#else
private nonisolated let isDebugMode = false
#endif

private nonisolated func debugLog(_ message: String) {
    if isDebugMode {
        print(message)
    }
}

// MARK: - Global App State
final class AppState: ObservableObject {
    @Published var hasKey: Bool = (Keychain.shared["api_511"]?.isEmpty == false)
    func refreshFromKeychain() { hasKey = (Keychain.shared["api_511"]?.isEmpty == false) }
    func clearKey() { Keychain.shared["api_511"] = nil; hasKey = false }
    func saveKey(_ key: String) { Keychain.shared["api_511"] = key; hasKey = true }
}

// MARK: - Optional embedded key (simulator only)
// Set to a valid API key for simulator auto-seeding during development.
// Intentionally nil by default to avoid committing keys to version control.
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

    // Require minimum 16 characters for security, max 256 for sanity
    guard trimmed.count >= 16, trimmed.count <= 256 else { return false }

    // Allow letters, numbers, hyphens, underscores, and dots (common in API keys)
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

    // Require at least one letter and one number for added security
    let hasLetter = trimmed.rangeOfCharacter(from: .letters) != nil
    let hasNumber = trimmed.rangeOfCharacter(from: .decimalDigits) != nil

    return hasLetter && hasNumber
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
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var notificationManager = SmartNotificationManager.shared
    @State private var tab = 0
    @State private var alerts: [ServiceAlert] = []
    @State private var alertsLoading = false
    @State private var alertsError: String? = nil

    // Bind cover visibility (true when key is missing)
    private var needsKeyBinding: Binding<Bool> {
        Binding(get: { !app.hasKey }, set: { _ in })
    }

    private var totalAlertCount: Int {
        alerts.count
    }

    var body: some View {
        TabView(selection: $tab) {
            TrainsScreen(sharedAlerts: $alerts, selectedTab: $tab)
                .tabItem { Label("Trains", systemImage: "train.side.front.car") }
                .tag(0)
            EventsScreen()
                .tabItem { Label("Events", systemImage: "calendar") }
                .tag(1)
            AlertsScreen(alerts: $alerts, isLoading: $alertsLoading, error: $alertsError, onRetry: { Task { await loadAlerts() } })
                .tabItem {
                    Label("Alerts", systemImage: totalAlertCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                .badge(totalAlertCount == 0 ? 0 : totalAlertCount)
                .tag(2)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                .tag(3)
            StationsScreen()
                .tabItem { Label("Stations", systemImage: "mappin.and.ellipse") }
                .tag(4)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(5)
        }
        .accentColor(themeManager.currentTheme.primaryColor)
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
        alertsError = nil // Clear previous errors
        defer { alertsLoading = false }
        do {
            // Load service alerts
            alerts = try await SIRIService.serviceAlerts(apiKey: key)
            alertsError = nil // Clear error on success
        } catch {
            let errorMessage = (error as NSError).localizedDescription
            alertsError = "Unable to load service alerts: \(errorMessage)"
            debugLog("❌ Failed to load alerts: \(error)")
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
    @State private var gameStats: GameStats = GameStats()

    var body: some View {
        List {
            // Streak Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text("\(gameStats.currentStreak)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(.orange)
                                Text("🔥")
                                    .font(.system(size: 28))
                            }
                            Text("Day streak")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(gameStats.longestStreak)")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Best")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("🔥 Streak")
            } footer: {
                Text("Take a trip each day to maintain your streak!")
                    .font(.caption2)
            }

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
                    ForEach(patterns.prefix(3)) { pattern in
                        VStack(alignment: .leading, spacing: 6) {
                            let allStops = CaltrainStops.northbound + CaltrainStops.southbound
                            let fromName = allStops.first { $0.stopCode == pattern.fromStopCode }?.name ?? "Unknown"
                            let toName = allStops.first { $0.stopCode == pattern.toStopCode }?.name ?? "Unknown"

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

            // Achievements Section
            Section {
                let unlockedCount = gameStats.achievements.filter { $0.isUnlocked }.count
                let totalCount = gameStats.achievements.count

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(unlockedCount)/\(totalCount)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.purple)
                        Text("Achievements")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 8)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                        ForEach(gameStats.achievements) { achievement in
                            VStack(spacing: 6) {
                                Text(achievement.emoji)
                                    .font(.system(size: 40))
                                    .opacity(achievement.isUnlocked ? 1.0 : 0.3)
                                Text(achievement.title)
                                    .font(.caption2)
                                    .foregroundStyle(achievement.isUnlocked ? .primary : .tertiary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(achievement.isUnlocked ? Color.purple.opacity(0.1) : Color.clear)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("🏆 Achievements")
            } footer: {
                Text("Unlock achievements by taking trips! Tap for details.")
                    .font(.caption2)
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
        gameStats = GamificationManager.shared.loadStats()
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
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode
    @AppStorage("iMessageRecipient") private var iMessageRecipient = ""
    @State private var iMessageValidationMessage: String = ""
    @State private var iMessageValidationColor: Color = .secondary

    // Validate phone number or email format
    private func validateRecipient(_ recipient: String) -> (valid: Bool, message: String) {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty is valid (optional field)
        if trimmed.isEmpty {
            return (true, "")
        }

        // Check if it's a valid phone number (digits only, optionally with +, -, (), spaces)
        let phonePattern = "^[+]?[(]?[0-9]{1,4}[)]?[-\\s.]?[(]?[0-9]{1,4}[)]?[-\\s.]?[0-9]{1,9}$"
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phonePattern)

        // Check if it's a valid email
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailTest = NSPredicate(format: "SELF MATCHES %@", emailPattern)

        if phoneTest.evaluate(with: trimmed) {
            return (true, "✓ Valid phone number")
        } else if emailTest.evaluate(with: trimmed) {
            return (true, "✓ Valid email address")
        } else {
            return (false, "⚠️ Please enter a valid phone number or email")
        }
    }

    var body: some View {
        NavigationStack {
            Form {

                Section {
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
                } header: {
                    Text("Smart Features")
                } footer: {
                    Text("Get notified about your usual trains, delays, and Giants game crowding")
                        .font(.caption2)
                }

                Section {
                    TextField("Phone Number or Email", text: $iMessageRecipient)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.default)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: iMessageRecipient) { _, newValue in
                            let validation = validateRecipient(newValue)
                            iMessageValidationMessage = validation.message
                            iMessageValidationColor = validation.valid ? .green : .orange
                        }
                    if !iMessageValidationMessage.isEmpty {
                        Text(iMessageValidationMessage)
                            .font(.caption)
                            .foregroundStyle(iMessageValidationColor)
                    }
                } header: {
                    Text("iMessage Sharing")
                } footer: {
                    Text("Enter a phone number or email to quickly share train arrival times via iMessage from the Trains tab")
                        .font(.caption2)
                }

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
                            debugLog("🔴 CLEAR BUTTON TAPPED")
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
                        ThemeSelectionView()
                    } label: {
                        HStack {
                            Label("Theme", systemImage: "paintbrush.fill")
                            Spacer()
                            Text(ThemeManager.shared.currentTheme.icon + " " + ThemeManager.shared.currentTheme.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Appearance")
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

                // Validate iMessage recipient on load
                let validation = validateRecipient(iMessageRecipient)
                iMessageValidationMessage = validation.message
                iMessageValidationColor = validation.valid ? .green : .orange
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
        debugLog("🔑 Ticketmaster save - Input length: \(trimmed.count)")
        debugLog("🔑 Ticketmaster save - isLikelyAPIKey: \(isLikelyAPIKey(trimmed))")
        guard isLikelyAPIKey(trimmed) else {
            statusTicketmaster = "Please enter a valid key."
            statusTicketmasterColor = .red
            debugLog("🔑 Ticketmaster save - FAILED validation")
            return
        }
        debugLog("🔑 Ticketmaster save - Saving to keychain...")
        Keychain.shared["api_ticketmaster"] = trimmed
        apiKeyTicketmaster = trimmed  // Update state variable
        debugLog("🔑 Ticketmaster save - Verifying...")
        verifyTicketmaster()
    }

    private func verifyTicketmaster() {
        let current = Keychain.shared["api_ticketmaster"] ?? ""
        debugLog("🔑 Ticketmaster verify - Read from keychain length: \(current.count)")
        if !current.isEmpty {
            statusTicketmaster = "Saved ✓  (\(Keychain.masked(current)))"
            statusTicketmasterColor = .green
            debugLog("🔑 Ticketmaster verify - SUCCESS")
        } else {
            statusTicketmaster = "No key in Keychain."
            statusTicketmasterColor = .red
            debugLog("🔑 Ticketmaster verify - EMPTY")
        }
    }
}

// MARK: - Theme Selection Screen
struct ThemeSelectionView: View {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        List {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    withAnimation {
                        themeManager.setTheme(theme)
                    }
                } label: {
                    HStack {
                        Text(theme.icon)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(theme.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.primaryColor)
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .fill(theme.accentColor)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        Spacer()
                        if themeManager.currentTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.primaryColor)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Choose Theme")
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

                    if let termsURL = URL(string: "https://511.org/about/terms") {
                        Link("View 511.org Terms", destination: termsURL)
                            .font(.footnote)
                    }
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
    @Binding var selectedTab: Int
    @AppStorage("northboundStopCode") private var northboundStopCode = CaltrainStops.defaultNorthbound.stopCode
    @AppStorage("southboundStopCode") private var southboundStopCode = CaltrainStops.defaultSouthbound.stopCode
    @State private var refDate = Date()
    @State private var north: [Departure] = []
    @State private var south: [Departure] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showNotificationPrompt = false
    @State private var showFullScheduleSheet = false
    @State private var fullScheduleDirection: String = "North"
    @State private var fullScheduleStopCode: String = ""
    @State private var fullScheduleStopName: String = ""
    @State private var fullScheduleDestStopCode: String = ""
    @State private var fullScheduleDestStopName: String = ""
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
                        .onChange(of: refDate) { oldDate, newDate in
                            // If selected time is more than 5 minutes in the past, assume user means tomorrow
                            let fiveMinutesAgo = Date().addingTimeInterval(-300)
                            if newDate < fiveMinutesAgo {
                                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: newDate) {
                                    refDate = tomorrow
                                }
                            }
                        }

                    Button("Now") { refDate = Date() }
                        .buttonStyle(.bordered)
                }

                if loading { ProgressView("Loading…") }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }

                List {
                    if !sharedAlerts.isEmpty {
                        Section {
                            Button {
                                selectedTab = 2 // Navigate to Alerts tab
                            } label: {
                                HStack {
                                    Label("Service Alerts", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(sharedAlerts.count) alert\(sharedAlerts.count == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        ForEach(north) { DepartureRow(dep: $0, destinationLabel: southboundStop.name, fromStopCode: northboundStopCode, toStopCode: southboundStopCode, direction: "North") }
                    } header: {
                        HStack {
                            Button {
                                fullScheduleDirection = "North"
                                fullScheduleStopCode = northboundStopCode
                                fullScheduleStopName = northboundStop.name
                                fullScheduleDestStopCode = southboundStopCode
                                fullScheduleDestStopName = southboundStop.name
                                showFullScheduleSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Northbound from \(northboundStop.name)")
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
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
                        ForEach(south) { DepartureRow(dep: $0, destinationLabel: northboundStop.name, fromStopCode: southboundStopCode, toStopCode: northboundStopCode, direction: "South") }
                    } header: {
                        HStack {
                            Button {
                                fullScheduleDirection = "South"
                                fullScheduleStopCode = southboundStopCode
                                fullScheduleStopName = southboundStop.name
                                fullScheduleDestStopCode = northboundStopCode
                                fullScheduleDestStopName = northboundStop.name
                                showFullScheduleSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Southbound from \(southboundStop.name)")
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
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
            .sheet(isPresented: $showFullScheduleSheet) {
                FullScheduleView(
                    stopCode: fullScheduleStopCode,
                    stopName: fullScheduleStopName,
                    direction: fullScheduleDirection,
                    refDate: refDate,
                    destinationStopCode: fullScheduleDestStopCode,
                    destinationStopName: fullScheduleDestStopName
                )
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
        debugLog("🔍 Loading trains - Northbound code: \(northboundStopCode), Southbound code: \(southboundStopCode)")
        debugLog("🔍 Northbound station: \(northboundStop.name), Southbound station: \(southboundStop.name)")
        do {
            // Load GTFS scheduled departures
            async let nbScheduled = GTFSService.shared.getScheduledDepartures(stopCode: northboundStopCode, direction: 0, refDate: refDate, count: 3)
            async let sbScheduled = GTFSService.shared.getScheduledDepartures(stopCode: southboundStopCode, direction: 1, refDate: refDate, count: 3)

            // Load SIRI real-time data for service types and delays
            async let nbRealtime = SIRIService.nextDepartures(from: northboundStopCode, to: southboundStopCode, at: refDate, apiKey: key, expectedDirection: "N")
            async let sbRealtime = SIRIService.nextDepartures(from: southboundStopCode, to: northboundStopCode, at: refDate, apiKey: key, expectedDirection: "S")

            let (nScheduled, sScheduled, nRealtime, sRealtime) = try await (nbScheduled, sbScheduled, nbRealtime, sbRealtime)

            debugLog("📅 GTFS Scheduled Northbound: \(nScheduled.count) trains")
            for (i, dep) in nScheduled.enumerated() {
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?")")
            }
            debugLog("🔴 SIRI Realtime Northbound: \(nRealtime.count) trains")
            for (i, dep) in nRealtime.enumerated() {
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?")")
            }
            debugLog("📅 GTFS Scheduled Southbound: \(sScheduled.count) trains")
            for (i, dep) in sScheduled.enumerated() {
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?")")
            }
            debugLog("🔴 SIRI Realtime Southbound: \(sRealtime.count) trains")
            for (i, dep) in sRealtime.enumerated() {
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?")")
            }

            // Merge GTFS scheduled times with SIRI real-time service types
            north = mergeScheduledWithRealtime(scheduled: nScheduled, realtime: nRealtime)
            south = mergeScheduledWithRealtime(scheduled: sScheduled, realtime: sRealtime)

            // Calculate arrival times using GTFS for departures that don't have them
            debugLog("🕐 Calculating arrival times from GTFS...")
            var northWithArrival: [Departure] = []
            for dep in north {
                if dep.arrivalTime == nil, let depTime = dep.depTime {
                    // For northbound trains, both stops need to use northbound stop codes
                    let destStopCode = CaltrainStops.getStopCodeForDirection(southboundStopCode, direction: 0) ?? southboundStopCode
                    if let arrivalTime = try? await GTFSService.shared.getArrivalTime(
                        fromStop: northboundStopCode,
                        toStop: destStopCode,
                        departureTime: depTime,
                        direction: 0
                    ) {
                        debugLog("  ✅ NB: Calculated arrival at \(arrivalTime.formatted(date: .omitted, time: .shortened))")
                        northWithArrival.append(Departure(
                            journeyRef: dep.journeyRef,
                            minutes: dep.minutes,
                            depTime: dep.depTime,
                            direction: dep.direction,
                            destination: dep.destination,
                            trainNumber: dep.trainNumber,
                            arrivalTime: arrivalTime,
                            delayMinutes: dep.delayMinutes
                        ))
                    } else {
                        northWithArrival.append(dep)
                    }
                } else {
                    northWithArrival.append(dep)
                }
            }
            north = northWithArrival

            var southWithArrival: [Departure] = []
            for dep in south {
                if dep.arrivalTime == nil, let depTime = dep.depTime {
                    // For southbound trains, both stops need to use southbound stop codes
                    let destStopCode = CaltrainStops.getStopCodeForDirection(northboundStopCode, direction: 1) ?? northboundStopCode
                    if let arrivalTime = try? await GTFSService.shared.getArrivalTime(
                        fromStop: southboundStopCode,
                        toStop: destStopCode,
                        departureTime: depTime,
                        direction: 1
                    ) {
                        debugLog("  ✅ SB: Calculated arrival at \(arrivalTime.formatted(date: .omitted, time: .shortened))")
                        southWithArrival.append(Departure(
                            journeyRef: dep.journeyRef,
                            minutes: dep.minutes,
                            depTime: dep.depTime,
                            direction: dep.direction,
                            destination: dep.destination,
                            trainNumber: dep.trainNumber,
                            arrivalTime: arrivalTime,
                            delayMinutes: dep.delayMinutes
                        ))
                    } else {
                        southWithArrival.append(dep)
                    }
                } else {
                    southWithArrival.append(dep)
                }
            }
            south = southWithArrival

            debugLog("📋 Merged Northbound departures:")
            for (i, dep) in north.enumerated() {
                let delayStr = dep.delayMinutes.map { "\($0 > 0 ? "+" : "")\($0) min" } ?? "n/a"
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Dest: \(dep.destination ?? "?"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?"), Arrival: \(dep.arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "nil"), Delay: \(delayStr)")
            }
            debugLog("📋 Merged Southbound departures:")
            for (i, dep) in south.enumerated() {
                let delayStr = dep.delayMinutes.map { "\($0 > 0 ? "+" : "")\($0) min" } ?? "n/a"
                debugLog("  \(i+1). Train: \(dep.trainNumber ?? "nil"), Dest: \(dep.destination ?? "?"), Time: \(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "?"), Arrival: \(dep.arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "nil"), Delay: \(delayStr)")
            }

            // Don't fetch alerts here - use shared alerts from main app to avoid duplicate API calls

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
            debugLog("❌ Error loading trains: \(error)")
        }
    }

    // Merge GTFS scheduled times with SIRI real-time service types
    private func mergeScheduledWithRealtime(scheduled: [Departure], realtime: [Departure]) -> [Departure] {
        debugLog("🔀 Merging \(scheduled.count) scheduled with \(realtime.count) realtime departures")

        // If we have realtime data, prefer it over scheduled data
        // Only use scheduled data to fill in gaps
        if !realtime.isEmpty {
            var result = realtime

            // Add any scheduled trains that don't have realtime matches
            for scheduledDep in scheduled {
                guard let scheduledTime = scheduledDep.depTime else { continue }

                let hasMatch = realtime.contains { realtimeDep in
                    guard let realtimeTime = realtimeDep.depTime else { return false }
                    let diff = abs(scheduledTime.timeIntervalSince(realtimeTime))
                    return diff < 120 // 2 minutes tolerance
                }

                if !hasMatch {
                    debugLog("  📅 Adding scheduled train at \(scheduledTime.formatted(date: .omitted, time: .shortened)) - no realtime match")
                    result.append(scheduledDep)
                }
            }

            // Sort by departure time and take first 3
            return Array(result.sorted { ($0.depTime ?? .distantFuture) < ($1.depTime ?? .distantFuture) }.prefix(3))
        }

        // If no realtime data, just return scheduled
        return scheduled
    }
}

struct ServiceAlertRow: View {
    let alert: ServiceAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Summary/Header
            HStack {
                Text(alert.summary)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if let severity = alert.severity {
                    Text(severity)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Description
            if let description = alert.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.primary)
            } else {
                Text("(No description available)")
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            // Timestamp
            if let creationTime = alert.creationTime {
                Text(creationTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Debug: Show raw alert ID
            #if DEBUG
            Text("Alert ID: \(alert.id)")
                .font(.caption2)
                .foregroundStyle(.gray)
            #endif
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Message Composer
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposer

        init(_ parent: MessageComposer) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.dismiss()
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DepartureRow: View {
    let dep: Departure
    let destinationLabel: String
    let fromStopCode: String
    let toStopCode: String
    let direction: String
    @State private var wasTaken = false
    @State private var showMessageComposer = false
    @State private var showMessagingAlert = false
    @State private var showShareSheet = false
    @AppStorage("iMessageRecipient") private var iMessageRecipient = ""

    var arrivalTime: Date? {
        // Use arrival time from the Departure object if available
        return dep.arrivalTime
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Departure → Arrival time
                HStack(spacing: 4) {
                    Text(dep.depTime?.formatted(date: .omitted, time: .shortened) ?? "—")
                        .font(.headline)
                    if let arrival = arrivalTime {
                        Text("→")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(arrival.formatted(date: .omitted, time: .shortened))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(destinationLabel).font(.subheadline).foregroundStyle(.secondary)
                    if let serviceType = dep.trainNumber, !serviceType.isEmpty {
                        Text("(\(serviceType))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()

            // Share button (only show if recipient is configured)
            if !iMessageRecipient.isEmpty {
                Menu {
                    if MFMessageComposeViewController.canSendText() {
                        Button {
                            debugLog("🔵 iMessage option selected")
                            showMessageComposer = true
                        } label: {
                            Label("Send iMessage", systemImage: "message.fill")
                        }
                    }
                    Button {
                        debugLog("🔵 Share option selected")
                        showShareSheet = true
                    } label: {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "message.fill")
                        .foregroundStyle(ThemeManager.shared.currentTheme.accentColor)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if wasTaken {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button {
                    recordTrip()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(dep.minutes)m").font(.title3).monospacedDigit()

                // Display delay information if available
                if let delay = dep.delayMinutes {
                    if delay > 0 {
                        Text("+\(delay) min")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .bold()
                    } else if delay < 0 {
                        Text("\(delay) min")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("On time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var label = "Departure in \(dep.minutes) minutes to \(destinationLabel)"
            if let delay = dep.delayMinutes {
                if delay > 0 {
                    label += ", delayed \(delay) minutes"
                } else if delay < 0 {
                    label += ", running \(abs(delay)) minutes early"
                } else {
                    label += ", on time"
                }
            }
            return label
        }())
        .sheet(isPresented: $showMessageComposer) {
            MessageComposer(
                recipients: [iMessageRecipient],
                body: createMessageBody()
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [createMessageBody()])
        }
        .alert("Messaging Not Available", isPresented: $showMessagingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Text messaging is not available on this device. Please try on a physical device with Messages configured.")
        }
    }

    func recordTrip() {
        // Record for gamification first (thread-safe)
        let (_, newAchievements) = GamificationManager.shared.recordTrip()

        // Record trip in thread-safe storage
        CommuteHistoryStorage.shared.recordTrip(
            fromStopCode: fromStopCode,
            toStopCode: toStopCode,
            direction: direction
        ) {
            // This completion runs on main thread after successful save
        }

        wasTaken = true

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Show achievement notification if any unlocked
        if !newAchievements.isEmpty {
            // You could show an alert or toast here
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    func createMessageBody() -> String {
        let arrTimeStr = arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "Unknown"

        var message = "Train Arrival Update:\n"
        message += "Arrival time: \(arrTimeStr)\n\n"
        message += "Isn't this so awesome! You got to love my brillance."

        return message
    }
}

// MARK: - Full Schedule View
struct FullScheduleView: View {
    let stopCode: String
    let stopName: String
    let direction: String
    let refDate: Date
    let destinationStopCode: String
    let destinationStopName: String

    @State private var allDepartures: [Departure] = []
    @State private var loading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if loading {
                    ProgressView("Loading schedule...")
                        .padding()
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await loadFullSchedule() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if allDepartures.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No departures found")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(allDepartures) { dep in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Show departure → arrival time if arrival is available
                                    if let depTime = dep.depTime {
                                        if let arrivalTime = dep.arrivalTime {
                                            Text("\(depTime.formatted(date: .omitted, time: .shortened)) → \(arrivalTime.formatted(date: .omitted, time: .shortened))")
                                                .font(.headline)
                                        } else {
                                            Text(depTime.formatted(date: .omitted, time: .shortened))
                                                .font(.headline)
                                        }
                                    } else {
                                        Text("—")
                                            .font(.headline)
                                    }
                                    if let serviceType = dep.trainNumber, !serviceType.isEmpty {
                                        Text(serviceType)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(dep.minutes)m")
                                    .font(.title3)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(direction)bound from \(stopName) to \(destinationStopName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFullSchedule()
            }
        }
    }

    func loadFullSchedule() async {
        loading = true
        defer { loading = false }
        error = nil

        guard let key = Keychain.shared["api_511"], !key.isEmpty else {
            error = "API key not found. Please configure in Settings."
            return
        }

        do {
            // Get a large number of departures to show full schedule
            // Use current time (Date()) instead of refDate to ensure accurate minutes calculation
            let directionId = direction == "North" ? 0 : 1
            let now = Date()

            // Reduced to 50 departures for memory optimization
            let departures = try await GTFSService.shared.getScheduledDepartures(
                stopCode: stopCode,
                direction: directionId,
                refDate: now,
                count: 50
            )

            // Calculate arrival times for each departure
            var departuresWithArrival: [Departure] = []
            for dep in departures {
                if let depTime = dep.depTime {
                    // Get the correct destination stop code for the direction
                    let destStopCode = CaltrainStops.getStopCodeForDirection(destinationStopCode, direction: directionId) ?? destinationStopCode

                    if let arrivalTime = try? await GTFSService.shared.getArrivalTime(
                        fromStop: stopCode,
                        toStop: destStopCode,
                        departureTime: depTime,
                        direction: directionId
                    ) {
                        // Create new departure with arrival time
                        departuresWithArrival.append(Departure(
                            journeyRef: dep.journeyRef,
                            minutes: dep.minutes,
                            depTime: dep.depTime,
                            direction: dep.direction,
                            destination: dep.destination,
                            trainNumber: dep.trainNumber,
                            arrivalTime: arrivalTime,
                            delayMinutes: dep.delayMinutes
                        ))
                    } else {
                        // If we can't calculate arrival, keep the departure without it
                        departuresWithArrival.append(dep)
                    }
                } else {
                    // No departure time, keep as-is
                    departuresWithArrival.append(dep)
                }
            }

            // Filter to only show trains with positive minutes (future departures)
            allDepartures = departuresWithArrival.filter { $0.minutes > 0 }
        } catch {
            self.error = (error as NSError).localizedDescription
            debugLog("❌ Error loading full schedule: \(error)")
        }
    }
}

// MARK: - Alerts UI
struct AlertsScreen: View {
    @Binding var alerts: [ServiceAlert]
    @Binding var isLoading: Bool
    @Binding var error: String?
    var onRetry: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Checking for alerts…")
                        .padding()
                }

                // Show error message if there's an error
                if let errorMsg = error, !isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.orange)

                        Text("Unable to Load Alerts")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(errorMsg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: onRetry) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    Spacer()
                } else if alerts.isEmpty && !isLoading {
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
                } else if !isLoading {
                    List {
                        // Service Alerts Section
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
    @State private var maxDistance: Double = 5.0 // Distance from any/selected Caltrain station
    @State private var showAllCapacities: Bool = false // Toggle to show events of any capacity
    @State private var selectedDate: Date = Date() // Date to search for events

    private var allStationNames: [String] {
        var stations = ["All Stations"]
        stations.append(contentsOf: CaltrainStops.northbound.reversed().map { $0.name })
        return stations
    }

    private var filteredEvents: [BayAreaEvent] {
        #if !DEBUG
        debugLog("🎟️ Filtering \(events.count) total events")
        #endif

        // First filter by capacity (20,000+ unless showAllCapacities is enabled)
        let largeEvents: [BayAreaEvent]
        if showAllCapacities {
            largeEvents = events
            #if !DEBUG
            debugLog("🎟️ Showing all capacities: \(largeEvents.count) events")
            #endif
        } else {
            largeEvents = events.filter { event in
                // Always include major Bay Area sports venues that impact Caltrain
                if let venueName = event.venueName {
                    let lowerName = venueName.lowercased()

                    // Major venues to always show (regardless of capacity threshold)
                    // Check for partial matches to handle different name formats
                    if lowerName.contains("chase center") {
                        debugLog("🎟️ Event '\(event.name)' included: Chase Center (Warriors, always shown)")
                        return true
                    }
                    if lowerName.contains("levi") && lowerName.contains("stadium") {
                        debugLog("🎟️ Event '\(event.name)' included: Levi's Stadium (49ers, always shown)")
                        return true
                    }
                    if lowerName.contains("oracle park") {
                        debugLog("🎟️ Event '\(event.name)' included: Oracle Park (Giants, always shown)")
                        return true
                    }
                    if lowerName.contains("sap center") {
                        debugLog("🎟️ Event '\(event.name)' included: SAP Center (Sharks, always shown)")
                        return true
                    }
                }

                guard let capacity = event.venueCapacity else {
                    #if !DEBUG
                    debugLog("🎟️ Event '\(event.name)' filtered out: no capacity data")
                    #endif
                    return false
                }
                let isLarge = capacity >= 20000
                if !isLarge {
                    #if !DEBUG
                    debugLog("🎟️ Event '\(event.name)' filtered out: capacity \(capacity) < 20000")
                    #endif
                }
                return isLarge
            }
            #if !DEBUG
            debugLog("🎟️ After capacity filter: \(largeEvents.count) events")
            #endif
        }

        // Then filter by station/distance
        if selectedStation == "All Stations" {
            // Show events within maxDistance of ANY Caltrain station
            let filtered = largeEvents.filter { event in
                guard let nearest = event.nearestStation else {
                    #if !DEBUG
                    debugLog("🎟️ Event '\(event.name)' filtered out: no nearest station")
                    #endif
                    return false
                }
                let withinRange = nearest.distance <= maxDistance
                if !withinRange {
                    #if !DEBUG
                    debugLog("🎟️ Event '\(event.name)' filtered out: \(String(format: "%.1f", nearest.distance)) mi from \(nearest.station.name) > \(String(format: "%.1f", maxDistance)) mi")
                    #endif
                }
                return withinRange
            }
            #if !DEBUG
            debugLog("🎟️ After distance filter: \(filtered.count) events")
            #endif

            // Deduplicate: only show one event per venue if same name
            let deduplicated = deduplicateEvents(filtered)
            #if !DEBUG
            debugLog("🎟️ After deduplication: \(deduplicated.count) events")
            #endif
            return deduplicated
        }

        let filtered = largeEvents.filter { event in
            guard let nearest = event.nearestStation else { return false }
            return nearest.station.name == selectedStation && nearest.distance <= maxDistance
        }
        #if !DEBUG
        debugLog("🎟️ After station filter: \(filtered.count) events")
        #endif

        // Deduplicate: only show one event per venue if same name
        let deduplicated = deduplicateEvents(filtered)
        #if !DEBUG
        debugLog("🎟️ After deduplication: \(deduplicated.count) events")
        #endif
        return deduplicated
    }

    // Deduplicate events: keep only one per (base name, venue, date) combination
    private func deduplicateEvents(_ events: [BayAreaEvent]) -> [BayAreaEvent] {
        var seen = Set<String>()
        var unique: [BayAreaEvent] = []

        for event in events {
            // Extract base event name by removing ticket package prefixes/suffixes
            var baseName = event.name

            // Remove common ticket package prefixes (case insensitive)
            let prefixPatterns = ["SEC\\. \\d+\\s+", "SECTION \\d+\\s+", "MODELO CANTINA PASS -\\s*", "POSTGAME PASS -\\s*", "VIP PASS -\\s*", "PREMIUM PASS -\\s*", "CLUB PASS -\\s*"]
            for pattern in prefixPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(baseName.startIndex..., in: baseName)
                    baseName = regex.stringByReplacingMatches(in: baseName, range: range, withTemplate: "")
                }
            }

            // Remove common ticket package suffixes
            let suffixPatterns = ["\\s*-\\s*SEC\\. \\d+.*", "\\s*-\\s*SECTION \\d+.*", "\\s*\\(.*PASS.*\\)", "\\s*-\\s*VIP", "\\s*-\\s*PREMIUM"]
            for pattern in suffixPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(baseName.startIndex..., in: baseName)
                    baseName = regex.stringByReplacingMatches(in: baseName, range: range, withTemplate: "")
                }
            }

            baseName = baseName.trimmingCharacters(in: .whitespaces)

            // Create key from base name, venue, and date (ignoring time)
            var dateKey = ""
            if let date = event.date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateKey = formatter.string(from: date)
            }

            let key = "\(baseName)|\(event.venueName ?? "")|\(dateKey)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(event)
            } else {
                #if !DEBUG
                debugLog("🎟️ Duplicate filtered: '\(event.name)' (base: '\(baseName)')")
                #endif
            }
        }

        return unique
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading events…")
                            .foregroundStyle(.secondary)
                        Text("This may take 20-30 seconds")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
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
                    VStack(spacing: 0) {
                        // Filter controls - always visible
                        VStack(spacing: 12) {
                            // Date picker
                            DatePicker("Date:", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .onChange(of: selectedDate) { _, _ in
                                    Task { await load() }
                                }

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

                            VStack(spacing: 4) {
                                HStack {
                                    Text(selectedStation == "All Stations" ? "Max Distance from Any Station" : "Max Distance")
                                    Spacer()
                                    Text("\(String(format: "%.1f", maxDistance)) mi")
                                        .foregroundStyle(.secondary)
                                }
                                if selectedStation == "All Stations" {
                                    Slider(value: $maxDistance, in: 0.5...10.0, step: 0.5)
                                } else {
                                    Slider(value: $maxDistance, in: 0.5...10.0, step: 0.5)
                                }
                            }

                            Toggle(isOn: $showAllCapacities) {
                                HStack {
                                    Text("Show All Venues")
                                    Text("(incl. small venues)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))

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
                                    let dateString = Calendar.current.isDateInToday(selectedDate)
                                        ? "Today"
                                        : DateFormatter.localizedString(from: selectedDate, dateStyle: .medium, timeStyle: .none)

                                    if selectedStation == "All Stations" {
                                        Text("All Events - \(dateString)")
                                    } else {
                                        Text("Events near \(selectedStation) - \(dateString)")
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
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
            events = try await TicketmasterService.searchEvents(apiKey: key, date: selectedDate)
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

// Haversine formula for calculating distance between two lat/lon coordinates (in miles)
private func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadiusMiles = 3959.0
    let lat1Rad = lat1 * .pi / 180
    let lat2Rad = lat2 * .pi / 180
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180

    let a = sin(dLat/2) * sin(dLat/2) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(dLon/2) * sin(dLon/2)
    let c = 2 * atan2(sqrt(a), sqrt(1-a))
    return earthRadiusMiles * c
}

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
        CaltrainStop(name: "Morgan Hill", stopCode: "777400", latitude: 37.1295, longitude: -121.6503),
        CaltrainStop(name: "San Martin", stopCode: "777405", latitude: 37.0855, longitude: -121.6106),
        CaltrainStop(name: "Gilroy", stopCode: "777404", latitude: 37.0035, longitude: -121.5682)
    ]

    // Default stops (Mountain View northbound and 22nd Street southbound)
    static let defaultNorthbound = northbound.first { $0.name == "Mountain View" } ?? northbound[0]
    static let defaultSouthbound = southbound.first { $0.name == "22nd Street" } ?? southbound[southbound.count - 1]

    // Convert a stop code to its counterpart in the opposite direction
    // e.g., 70022 (22nd St southbound) -> 70021 (22nd St northbound)
    static func getStopCodeForDirection(_ stopCode: String, direction: Int) -> String? {
        // direction 0 = northbound, 1 = southbound
        if direction == 0 {
            // Find in northbound list
            if let stop = northbound.first(where: { $0.stopCode == stopCode }) {
                return stop.stopCode
            }
            // If not found, find the southbound stop with same name and return northbound equivalent
            if let southStop = southbound.first(where: { $0.stopCode == stopCode }) {
                return northbound.first(where: { $0.name == southStop.name })?.stopCode
            }
        } else {
            // Find in southbound list
            if let stop = southbound.first(where: { $0.stopCode == stopCode }) {
                return stop.stopCode
            }
            // If not found, find the northbound stop with same name and return southbound equivalent
            if let northStop = northbound.first(where: { $0.stopCode == stopCode }) {
                return southbound.first(where: { $0.name == northStop.name })?.stopCode
            }
        }
        return nil
    }
}

struct Departure: Identifiable, Hashable {
    var id: String { journeyRef + (depTime?.ISO8601Format() ?? "") }
    let journeyRef: String
    let minutes: Int
    let depTime: Date?
    let direction: String?
    let destination: String?
    let trainNumber: String?
    let arrivalTime: Date?
    let delayMinutes: Int? // positive = late, negative = early, nil = no real-time data
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

struct CommutePattern: Codable, Identifiable {
    var id: String { "\(fromStopCode)-\(toStopCode)-\(direction)" }
    let fromStopCode: String
    let toStopCode: String
    let direction: String
    let commonHours: [Int] // Hours user typically checks this route
    let frequency: Int // Number of times checked
    let lastUsed: Date
}

// MARK: - Theme System
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case vintage = "Vintage"
    case modern = "Modern"
    case dark = "Dark"
    case ocean = "Ocean"
    case sunset = "Sunset"

    var id: String { rawValue }

    var primaryColor: Color {
        switch self {
        case .vintage: return Color(red: 0.75, green: 0.42, blue: 0.38) // Muted red-brown
        case .modern: return Color(red: 0.0, green: 0.48, blue: 1.0) // Bright blue
        case .dark: return Color(red: 0.8, green: 0.8, blue: 0.8) // Light gray
        case .ocean: return Color(red: 0.2, green: 0.6, blue: 0.86) // Ocean blue
        case .sunset: return Color(red: 1.0, green: 0.49, blue: 0.31) // Coral orange
        }
    }

    var accentColor: Color {
        switch self {
        case .vintage: return Color(red: 0.95, green: 0.87, blue: 0.73) // Cream
        case .modern: return Color(red: 0.2, green: 0.78, blue: 0.35) // Green
        case .dark: return Color(red: 0.5, green: 0.5, blue: 1.0) // Purple
        case .ocean: return Color(red: 0.0, green: 0.8, blue: 0.8) // Teal
        case .sunset: return Color(red: 1.0, green: 0.76, blue: 0.03) // Golden yellow
        }
    }

    var backgroundColor: Color {
        switch self {
        case .vintage: return Color(red: 0.98, green: 0.95, blue: 0.91) // Light cream
        case .modern: return Color.white
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.12) // Near black
        case .ocean: return Color(red: 0.94, green: 0.97, blue: 0.98) // Very light blue
        case .sunset: return Color(red: 0.99, green: 0.95, blue: 0.93) // Warm white
        }
    }

    var icon: String {
        switch self {
        case .vintage: return "🎨"
        case .modern: return "✨"
        case .dark: return "🌙"
        case .ocean: return "🌊"
        case .sunset: return "🌅"
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published var currentTheme: AppTheme = .vintage

    init() {
        loadTheme()
    }

    func loadTheme() {
        if let themeString = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: themeString) {
            currentTheme = theme
        }
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }
}

// MARK: - Gamification Models
struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let emoji: String
    var isUnlocked: Bool
    var unlockedDate: Date?
}

struct GameStats: Codable {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastTripDate: Date?
    var totalTrips: Int = 0
    var achievements: [Achievement] = []
}

class GamificationManager {
    static let shared = GamificationManager()
    private let statsKey = "gameStats"

    func loadStats() -> GameStats {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(GameStats.self, from: data) else {
            return createInitialStats()
        }
        return stats
    }

    private func createInitialStats() -> GameStats {
        var stats = GameStats()
        stats.achievements = [
            Achievement(id: "first_trip", title: "First Ride", description: "Take your first Caltrain trip", emoji: "🚂", isUnlocked: false),
            Achievement(id: "week_warrior", title: "Week Warrior", description: "Ride 5 days in a row", emoji: "🔥", isUnlocked: false),
            Achievement(id: "month_master", title: "Month Master", description: "Ride 20 days in a month", emoji: "⭐", isUnlocked: false),
            Achievement(id: "eco_hero", title: "Eco Hero", description: "Save 500 lbs of CO₂", emoji: "🌱", isUnlocked: false),
            Achievement(id: "commute_king", title: "Commute King", description: "Take 100 trips", emoji: "👑", isUnlocked: false),
            Achievement(id: "early_bird", title: "Early Bird", description: "Take a train before 7 AM", emoji: "🌅", isUnlocked: false),
            Achievement(id: "night_owl", title: "Night Owl", description: "Take a train after 9 PM", emoji: "🦉", isUnlocked: false),
            Achievement(id: "weekend_explorer", title: "Weekend Explorer", description: "Take 10 weekend trips", emoji: "🎒", isUnlocked: false),
        ]
        return stats
    }

    func saveStats(_ stats: GameStats) {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    func recordTrip(timestamp: Date = Date()) -> (stats: GameStats, newAchievements: [Achievement]) {
        var stats = loadStats()
        var newlyUnlocked: [Achievement] = []

        // Update total trips
        stats.totalTrips += 1

        // Update streak
        let calendar = Calendar.current
        if let lastTrip = stats.lastTripDate {
            let daysSinceLastTrip = calendar.dateComponents([.day], from: lastTrip, to: timestamp).day ?? 0

            if daysSinceLastTrip == 1 {
                // Consecutive day
                stats.currentStreak += 1
            } else if daysSinceLastTrip > 1 {
                // Streak broken
                stats.currentStreak = 1
            }
            // Same day = no change to streak
        } else {
            // First trip ever
            stats.currentStreak = 1
        }

        stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
        stats.lastTripDate = timestamp

        // Check for newly unlocked achievements
        newlyUnlocked = checkAchievements(&stats, timestamp: timestamp)

        saveStats(stats)
        return (stats, newlyUnlocked)
    }

    private func checkAchievements(_ stats: inout GameStats, timestamp: Date) -> [Achievement] {
        var newlyUnlocked: [Achievement] = []

        for i in 0..<stats.achievements.count {
            guard !stats.achievements[i].isUnlocked else { continue }

            var shouldUnlock = false

            switch stats.achievements[i].id {
            case "first_trip":
                shouldUnlock = stats.totalTrips >= 1
            case "week_warrior":
                shouldUnlock = stats.currentStreak >= 5
            case "month_master":
                guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
                    shouldUnlock = false
                    break
                }
                let recentTrips = CommuteHistoryStorage.shared.loadHistory().filter {
                    $0.wasTripTaken && $0.timestamp >= thirtyDaysAgo
                }
                shouldUnlock = recentTrips.count >= 20
            case "eco_hero":
                let co2 = CommuteHistoryStorage.shared.calculateCO2Savings().co2SavedLbs
                shouldUnlock = co2 >= 500
            case "commute_king":
                shouldUnlock = stats.totalTrips >= 100
            case "early_bird":
                let hour = Calendar.current.component(.hour, from: timestamp)
                shouldUnlock = hour < 7
            case "night_owl":
                let hour = Calendar.current.component(.hour, from: timestamp)
                shouldUnlock = hour >= 21
            case "weekend_explorer":
                let weekendTrips = CommuteHistoryStorage.shared.loadHistory().filter {
                    $0.wasTripTaken && (Calendar.current.component(.weekday, from: $0.timestamp) == 1 || Calendar.current.component(.weekday, from: $0.timestamp) == 7)
                }
                shouldUnlock = weekendTrips.count >= 10
            default:
                break
            }

            if shouldUnlock {
                stats.achievements[i].isUnlocked = true
                stats.achievements[i].unlockedDate = timestamp
                newlyUnlocked.append(stats.achievements[i])
            }
        }

        return newlyUnlocked
    }
}

class CommuteHistoryStorage {
    static let shared = CommuteHistoryStorage()
    private let historyKey = "commuteHistory"
    private let maxHistoryEntries = 500 // Keep last 500 checks

    // Thread-safe queue to prevent data races during concurrent writes
    private let queue = DispatchQueue(label: "com.caltrainchecker.commutehistory", attributes: .concurrent)

    func recordCheck(fromStopCode: String, toStopCode: String, direction: String) {
        queue.async(flags: .barrier) {
            var history = self.loadHistoryUnsafe()
            let entry = CommuteHistoryEntry(fromStopCode: fromStopCode, toStopCode: toStopCode, direction: direction)
            history.append(entry)

            // Keep only recent entries
            if history.count > self.maxHistoryEntries {
                history = Array(history.suffix(self.maxHistoryEntries))
            }

            self.saveHistoryUnsafe(history)
        }
    }

    func recordTrip(fromStopCode: String, toStopCode: String, direction: String, completion: @escaping () -> Void) {
        queue.async(flags: .barrier) {
            var history = self.loadHistoryUnsafe()
            let entry = CommuteHistoryEntry(fromStopCode: fromStopCode, toStopCode: toStopCode, direction: direction, wasTripTaken: true)
            history.append(entry)

            // Keep only recent entries
            if history.count > self.maxHistoryEntries {
                history = Array(history.suffix(self.maxHistoryEntries))
            }

            self.saveHistoryUnsafe(history)

            // Call completion on main thread
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func loadHistory() -> [CommuteHistoryEntry] {
        queue.sync {
            return loadHistoryUnsafe()
        }
    }

    private func loadHistoryUnsafe() -> [CommuteHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([CommuteHistoryEntry].self, from: data) else {
            return []
        }
        return history
    }

    private func saveHistoryUnsafe(_ history: [CommuteHistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func saveHistory(_ history: [CommuteHistoryEntry]) {
        queue.async(flags: .barrier) {
            self.saveHistoryUnsafe(history)
        }
    }

    func clearHistory() {
        queue.async(flags: .barrier) {
            UserDefaults.standard.removeObject(forKey: self.historyKey)
        }
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
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return (0, 0.0)
        }
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
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return (0, nil)
        }
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
        guard let triggerDate = Calendar.current.date(byAdding: .minute, value: -15, to: trainTime) else {
            debugLog("⚠️ Failed to calculate trigger date for notification")
            return
        }
        // Use full date components to ensure it triggers today, not tomorrow
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
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

// MARK: - Weather Service (Open-Meteo)
@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published var currentWeather: [String: (temp: Double, condition: String, symbol: String)] = [:]

    // Open-Meteo API - completely free, no API key required, very reliable
    // API: https://open-meteo.com/en/docs

    func fetchWeather(for station: CaltrainStop) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(station.latitude)&longitude=\(station.longitude)&current=temperature_2m,weather_code&temperature_unit=fahrenheit&timezone=America/Los_Angeles"

        guard let url = URL(string: urlString) else {
            debugLog("❌ Invalid weather URL for \(station.name)")
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
                debugLog("✅ Weather fetched for \(station.name): \(Int(temp))°F, \(condition)")
            } else {
                debugLog("❌ Failed to parse weather JSON for \(station.name)")
            }
        } catch {
            debugLog("❌ Weather fetch failed for \(station.name): \(error.localizedDescription)")
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

                // Validate filename to prevent path traversal attacks
                guard !fileName.contains(".."),
                      !fileName.hasPrefix("/"),
                      !fileName.contains("~"),
                      !fileName.isEmpty else {
                    throw NSError(domain: "GTFS", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid file path in ZIP archive"])
                }

                // Write file
                let filePath = destDir.appendingPathComponent(fileName)

                // Ensure final path is within destination directory (security check)
                let canonicalDest = destDir.standardized.path
                let canonicalFile = filePath.standardized.path
                guard canonicalFile.hasPrefix(canonicalDest) else {
                    throw NSError(domain: "GTFS", code: 6, userInfo: [NSLocalizedDescriptionKey: "Path traversal attempt detected in ZIP"])
                }

                try fileManager.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try decompData.write(to: filePath)

                offset = dataEnd
            } else {
                offset += 1
            }
        }
    }

    private func decompress(_ data: Data, uncompressedSize: Int) throws -> Data {
        // Security: Prevent ZIP bombs and excessive memory allocation
        let maxUncompressedSize = 50_000_000 // 50MB per file
        guard uncompressedSize > 0, uncompressedSize <= maxUncompressedSize else {
            throw NSError(domain: "GTFS", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid or excessive uncompressed size: \(uncompressedSize)"])
        }

        // Security: Validate compression ratio to prevent ZIP bombs
        guard data.count > 0 else {
            throw NSError(domain: "GTFS", code: 8, userInfo: [NSLocalizedDescriptionKey: "Empty compressed data"])
        }
        let compressionRatio = Double(uncompressedSize) / Double(data.count)
        guard compressionRatio <= 100 else { // Max 100:1 compression ratio
            throw NSError(domain: "GTFS", code: 9, userInfo: [NSLocalizedDescriptionKey: "Suspicious compression ratio detected (possible ZIP bomb)"])
        }

        // Use Apple's Compression framework (available on iOS 9+)
        let sourceBuffer = [UInt8](data)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = sourceBuffer.withUnsafeBufferPointer { srcPtr in
            guard let baseAddress = srcPtr.baseAddress else {
                return 0
            }
            return compression_decode_buffer(
                destinationBuffer,
                uncompressedSize,
                baseAddress,
                sourceBuffer.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw NSError(domain: "GTFS", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress ZIP data"])
        }

        // Critical: Validate that decompressed size matches expected size
        // This prevents corrupted data from being used in the app
        guard decompressedSize == uncompressedSize else {
            throw NSError(domain: "GTFS", code: 10, userInfo: [NSLocalizedDescriptionKey: "Decompression size mismatch: expected \(uncompressedSize) bytes, got \(decompressedSize) bytes. Data may be corrupted."])
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    private func downloadAndParseGTFS() async throws {
        debugLog("📥 Downloading GTFS feed...")

        guard let url = URL(string: gtfsURL) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        debugLog("📦 GTFS downloaded (\(data.count) bytes), extracting...")

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

        debugLog("📖 Parsing GTFS CSV files...")

        // Parse each CSV file
        stops = try parseStops(at: tempDir.appendingPathComponent("stops.txt"))
        trips = try parseTrips(at: tempDir.appendingPathComponent("trips.txt"))
        stopTimes = try parseStopTimes(at: tempDir.appendingPathComponent("stop_times.txt"))
        calendars = try parseCalendars(at: tempDir.appendingPathComponent("calendar.txt"))
        calendarDates = try parseCalendarDates(at: tempDir.appendingPathComponent("calendar_dates.txt"))

        lastFetchDate = Date()

        debugLog("✅ GTFS loaded: \(stops.count) stops, \(trips.count) trips, \(stopTimes.count) stop times")
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

    // Calculate arrival time at destination stop given a departure time from origin
    func getArrivalTime(fromStop: String, toStop: String, departureTime: Date, direction: Int) async throws -> Date? {
        try await ensureGTFSLoaded()

        var pacificCalendar = Calendar.current
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current

        let targetDate = pacificCalendar.startOfDay(for: departureTime)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = pacificCalendar.timeZone
        let targetDateStr = dateFormatter.string(from: targetDate)
        let weekday = pacificCalendar.component(.weekday, from: targetDate)

        debugLog("🔍 getArrivalTime: from=\(fromStop), to=\(toStop), depTime=\(departureTime.formatted(date: .omitted, time: .shortened)), dir=\(direction)")

        // Find active services
        let activeServices = getActiveServices(dateStr: targetDateStr, weekday: weekday)
        debugLog("  Active services: \(activeServices.count)")

        // Find trips for this direction
        let relevantTrips = trips.filter { trip in
            trip.directionId == direction && activeServices.contains(trip.serviceId)
        }
        debugLog("  Relevant trips for direction \(direction): \(relevantTrips.count)")

        // Get stop times for origin stop
        let relevantTripIds = Set(relevantTrips.map { $0.tripId })
        let originStopTimes = stopTimes.filter { st in
            st.stopId == fromStop && relevantTripIds.contains(st.tripId)
        }
        debugLog("  Origin stop times: \(originStopTimes.count)")

        // Find the trip that matches our departure time (within 5 minutes)
        let depComponents = pacificCalendar.dateComponents([.hour, .minute], from: departureTime)
        let depMinutes = (depComponents.hour ?? 0) * 60 + (depComponents.minute ?? 0)
        debugLog("  Looking for departure at \(depMinutes) minutes (\(depComponents.hour ?? 0):\(depComponents.minute ?? 0))")

        for originST in originStopTimes {
            let timeComponents = originST.departureTime.split(separator: ":")
            guard timeComponents.count == 3,
                  let hours = Int(timeComponents[0]),
                  let minutes = Int(timeComponents[1]) else { continue }

            let actualHours = hours >= 24 ? hours - 24 : hours
            let originMinutes = actualHours * 60 + minutes

            // Match within 2 minutes for accurate trip matching
            if abs(originMinutes - depMinutes) <= 2 {
                debugLog("  ✅ Found matching trip! tripId=\(originST.tripId), originMinutes=\(originMinutes), diff=\(abs(originMinutes - depMinutes))")
                // Found matching trip, now find arrival at destination
                if let destST = stopTimes.first(where: { $0.tripId == originST.tripId && $0.stopId == toStop }) {
                    debugLog("  ✅ Found destination stop in trip!")
                    let arrTimeComponents = destST.departureTime.split(separator: ":")
                    guard arrTimeComponents.count == 3,
                          let arrHours = Int(arrTimeComponents[0]),
                          let arrMinutes = Int(arrTimeComponents[1]) else {
                        debugLog("  ❌ Failed to parse arrival time components")
                        continue
                    }

                    let actualArrHours = arrHours >= 24 ? arrHours - 24 : arrHours
                    var arrivalDate = targetDate
                    if arrHours >= 24 {
                        arrivalDate = pacificCalendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
                    }

                    if let result = pacificCalendar.date(bySettingHour: actualArrHours, minute: arrMinutes, second: 0, of: arrivalDate) {
                        debugLog("  ✅ Calculated arrival: \(result.formatted(date: .omitted, time: .shortened))")
                        return result
                    } else {
                        debugLog("  ❌ Failed to create arrival date")
                    }
                } else {
                    debugLog("  ❌ Destination stop \(toStop) not found in trip \(originST.tripId)")
                }
            }
        }

        debugLog("  ❌ No matching trip found for departure")
        return nil
    }

    // Get scheduled departures for a stop at a given time
    func getScheduledDepartures(stopCode: String, direction: Int, refDate: Date, count: Int = 3) async throws -> [Departure] {
        try await ensureGTFSLoaded()

        // Convert stopCode to GTFS stop_id format
        // Caltrain uses stopCode like "70212" which maps to stop_id in GTFS
        let stopId = stopCode

        // Get current date components in Pacific Time
        var pacificCalendar = Calendar.current
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current

        let now = Date()

        // Check if refDate time is in the past compared to now
        let refComponents = pacificCalendar.dateComponents([.hour, .minute], from: refDate)
        let nowComponents = pacificCalendar.dateComponents([.hour, .minute], from: now)
        let refMinutes = (refComponents.hour ?? 0) * 60 + (refComponents.minute ?? 0)
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)

        // If selected time is before current time, assume user means tomorrow
        let isNextDay = refMinutes < nowMinutes

        // Use today or tomorrow based on whether the time is in the past
        var targetDate = pacificCalendar.startOfDay(for: now)
        if isNextDay {
            guard let tomorrow = pacificCalendar.date(byAdding: .day, value: 1, to: targetDate) else {
                throw NSError(domain: "GTFSService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Date calculation failed"])
            }
            targetDate = tomorrow
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = pacificCalendar.timeZone
        let targetDateStr = dateFormatter.string(from: targetDate)

        // Get weekday
        let weekday = pacificCalendar.component(.weekday, from: targetDate)

        // Find active services for target date
        let activeServices = getActiveServices(dateStr: targetDateStr, weekday: weekday)

        // Find trips for this direction and active services
        let relevantTrips = trips.filter { trip in
            trip.directionId == direction && activeServices.contains(trip.serviceId)
        }

        // Get stop times for these trips at our stop
        // Use Set for faster lookup and reduce memory usage
        let relevantTripIds = Set(relevantTrips.map { $0.tripId })
        let relevantStopTimes = stopTimes.filter { st in
            st.stopId == stopId && relevantTripIds.contains(st.tripId)
        }

        // Parse departure times and filter for times after reference time
        var departures: [(time: String, minutes: Int, tripId: String, departureDate: Date)] = []

        // Process target date's departures
        for st in relevantStopTimes {
            let timeComponents = st.departureTime.split(separator: ":")
            guard timeComponents.count == 3,
                  let hours = Int(timeComponents[0]),
                  let minutes = Int(timeComponents[1]) else { continue }

            var departureDate = targetDate
            var actualHours = hours
            var totalMinutes = hours * 60 + minutes

            // Handle times >= 24:00:00 (next day in GTFS format)
            if hours >= 24 {
                actualHours = hours - 24
                totalMinutes = actualHours * 60 + minutes
                guard let nextDay = pacificCalendar.date(byAdding: .day, value: 1, to: targetDate) else {
                    continue
                }
                departureDate = nextDay
            }

            // Filter by selected time (refMinutes) regardless of which day
            if totalMinutes < refMinutes {
                continue // Skip trains before selected time
            }

            // Create full departure Date using Calendar API
            guard let fullDepDate = pacificCalendar.date(
                bySettingHour: actualHours,
                minute: minutes,
                second: 0,
                of: departureDate
            ) else {
                continue
            }

            // Calculate minutes until departure from NOW using proper Date comparison
            let minutesUntil = Int(ceil(fullDepDate.timeIntervalSince(now) / 60))

            departures.append((st.departureTime, minutesUntil, st.tripId, departureDate))
        }

        // Also add tomorrow's early morning trains if we're currently looking at TODAY's schedule
        // (to catch after-midnight service)
        if !isNextDay {
            if let tomorrow = pacificCalendar.date(byAdding: .day, value: 1, to: targetDate) {
                let tomorrowStr = dateFormatter.string(from: tomorrow)
                let tomorrowWeekday = pacificCalendar.component(.weekday, from: tomorrow)
                let tomorrowServices = getActiveServices(dateStr: tomorrowStr, weekday: tomorrowWeekday)

                let tomorrowTrips = trips.filter { trip in
                    trip.directionId == direction && tomorrowServices.contains(trip.serviceId)
                }

                let tomorrowTripIds = Set(tomorrowTrips.map { $0.tripId })
                let tomorrowStopTimes = stopTimes.filter { st in
                    st.stopId == stopId && tomorrowTripIds.contains(st.tripId)
                }

                // Add early morning trains from tomorrow (before 5 AM to catch all after-midnight service)
                for st in tomorrowStopTimes {
                    let timeComponents = st.departureTime.split(separator: ":")
                    guard timeComponents.count == 3,
                          let hours = Int(timeComponents[0]),
                          let minutes = Int(timeComponents[1]) else { continue }

                    // Include trains before 5 AM (both regular time and GTFS 24+ format)
                    let isEarlyMorning = (hours < 5) || (hours >= 24 && hours < 29)
                    guard isEarlyMorning else { continue }

                    // Handle both regular and GTFS 24+ time format
                    let actualHours = hours >= 24 ? hours - 24 : hours

                    // Create full departure Date using Calendar API
                    guard let fullDepDate = pacificCalendar.date(
                        bySettingHour: actualHours,
                        minute: minutes,
                        second: 0,
                        of: tomorrow
                    ) else {
                        continue
                    }

                    // Calculate minutes until departure from NOW using proper Date comparison
                    let minutesUntilFromNow = Int(ceil(fullDepDate.timeIntervalSince(now) / 60))
                    departures.append((st.departureTime, minutesUntilFromNow, st.tripId, tomorrow))
                }
            }
        }

        // Sort by minutes until departure and take first N
        departures.sort { $0.minutes < $1.minutes }
        let topDepartures = Array(departures.prefix(count))
        departures.removeAll() // Free memory immediately

        // Convert to Departure objects (using 'now' from above)
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
                trainNumber: nil, // Will be filled with service type from SIRI if available
                arrivalTime: nil, // Will be filled from SIRI OnwardCalls if available
                delayMinutes: nil // Static GTFS data doesn't include real-time delays
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
    private var lastRequestTime: [String: Date] = [:]
    private let minimumInterval: TimeInterval = 5.0 // 5 seconds between requests to same endpoint
    private let maxCachedEndpoints = 50

    private func canMakeRequest(to url: URL) -> Bool {
        let endpoint = "\(url.host ?? "")\(url.path)"
        if let lastTime = lastRequestTime[endpoint] {
            return Date().timeIntervalSince(lastTime) >= minimumInterval
        }
        return true
    }

    private func recordRequest(to url: URL) {
        let endpoint = "\(url.host ?? "")\(url.path)"
        lastRequestTime[endpoint] = Date()

        // Clean up old entries if dictionary grows too large (O(1) operation)
        if lastRequestTime.count > maxCachedEndpoints {
            let oldest = lastRequestTime.min(by: { $0.value < $1.value })?.key
            if let key = oldest { lastRequestTime.removeValue(forKey: key) }
        }
    }

    func get(url: URL, headers: [String:String] = [:], maxRetries: Int = 3) async throws -> (Data, HTTPURLResponse) {
        // Rate limiting: prevent excessive API calls
        guard canMakeRequest(to: url) else {
            throw NSError(domain: "HTTPClient", code: 429,
                         userInfo: [NSLocalizedDescriptionKey: "Too many requests. Please wait a moment."])
        }

        var req = URLRequest(url: url)
        var all = headers
        if all["Accept"] == nil { all["Accept"] = "application/json" }
        all["User-Agent"] = all["User-Agent"] ?? "CaltrainChecker/1.0"
        all.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        // Longer timeout for Ticketmaster API which can be slow with large result sets
        req.timeoutInterval = url.host?.contains("ticketmaster") == true ? 45 : 25

        // Network retry logic with exponential backoff
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

                // Retry on server errors (5xx) or specific client errors
                if http.statusCode >= 500 || http.statusCode == 429 || http.statusCode == 408 {
                    lastError = NSError(domain: "HTTPClient", code: http.statusCode,
                                       userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])

                    // Only retry if we have attempts left
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt)) // Exponential: 1s, 2s, 4s
                        debugLog("HTTP \(http.statusCode) on attempt \(attempt + 1)/\(maxRetries). Retrying in \(delay)s...")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }

                recordRequest(to: url)
                return (data, http)
            } catch {
                lastError = error

                // Retry on network errors if we have attempts left
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    debugLog("Network error on attempt \(attempt + 1)/\(maxRetries): \(error). Retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }

        // All retries exhausted
        throw lastError ?? URLError(.unknown)
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
    let OnwardCalls: [OnwardCallNode]?

    enum CodingKeys: String, CodingKey {
        case LineRef, DirectionRef, DestinationName, MonitoredCall, FramedVehicleJourneyRef, PublishedLineName, VehicleRef, OnwardCalls
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.LineRef = try? c.decodeIfPresent(String.self, forKey: .LineRef)
        self.DirectionRef = try? c.decodeIfPresent(String.self, forKey: .DirectionRef)
        self.MonitoredCall = try? c.decodeIfPresent(MonitoredCallNode.self, forKey: .MonitoredCall)
        self.FramedVehicleJourneyRef = try? c.decodeIfPresent(FramedVehicleJourneyRefNode.self, forKey: .FramedVehicleJourneyRef)
        self.PublishedLineName = try? c.decodeIfPresent(String.self, forKey: .PublishedLineName)
        self.VehicleRef = try? c.decodeIfPresent(String.self, forKey: .VehicleRef)
        self.OnwardCalls = try? c.decodeIfPresent([OnwardCallNode].self, forKey: .OnwardCalls)

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
struct MonitoredCallNode: Decodable {
    let AimedDepartureTime: String?
    let ExpectedDepartureTime: String?
}

struct OnwardCallNode: Decodable {
    let StopPointRef: String?
    let AimedArrivalTime: String?
    let AimedDepartureTime: String?
}

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

// MARK: - GTFS Realtime Service Alerts models
// Note: 511.org uses PascalCase (non-standard) instead of standard snake_case
struct GTFSRealtimeResponse: Codable {
    let Header: GTFSHeader
    let Entities: [GTFSEntity]?
}

struct GTFSHeader: Codable {
    let GtfsRealtimeVersion: String?
    let incrementality: Int?
    let Timestamp: Int?
}

struct GTFSEntity: Codable {
    let Id: String
    let TripUpdate: GTFSTripUpdate?
    let Vehicle: GTFSVehicle?
    let Alert: GTFSAlert?
}

struct GTFSTripUpdate: Codable {
    // Placeholder - not used for alerts
}

struct GTFSVehicle: Codable {
    // Placeholder - not used for alerts
}

struct GTFSAlert: Codable {
    let ActivePeriod: [GTFSTimePeriod]?
    let InformedEntity: [GTFSInformedEntity]?
    let Cause: String?
    let Effect: String?
    let Url: GTFSTranslatedString?
    let HeaderText: GTFSTranslatedString?
    let DescriptionText: GTFSTranslatedString?
    let Severity: String?

    enum CodingKeys: String, CodingKey {
        // 511.org uses mixed case - mostly PascalCase but "cause" and "effect" are lowercase!
        case ActivePeriod = "ActivePeriods"  // PLURAL
        case InformedEntity = "InformedEntities"  // PLURAL
        case Cause = "cause"  // lowercase!
        case Effect = "effect"  // lowercase!
        case Url = "Url"
        case HeaderText = "HeaderText"
        case DescriptionText = "DescriptionText"
        case Severity = "Severity"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode using 511.org's mixed-case format
        ActivePeriod = try? container.decode([GTFSTimePeriod].self, forKey: .ActivePeriod)
        InformedEntity = try? container.decode([GTFSInformedEntity].self, forKey: .InformedEntity)
        Cause = try? container.decode(String.self, forKey: .Cause)
        Effect = try? container.decode(String.self, forKey: .Effect)
        Url = try? container.decode(GTFSTranslatedString.self, forKey: .Url)
        HeaderText = try? container.decode(GTFSTranslatedString.self, forKey: .HeaderText)
        DescriptionText = try? container.decode(GTFSTranslatedString.self, forKey: .DescriptionText)
        Severity = try? container.decode(String.self, forKey: .Severity)
    }
}

struct GTFSTimePeriod: Codable {
    let Start: Int?
    let End: Int?
}

struct GTFSInformedEntity: Codable {
    let AgencyId: String?
    let RouteId: String?
    let RouteType: Int?
    let StopId: String?
}

struct GTFSTranslatedString: Codable {
    let Translation: [GTFSTranslation]?

    enum CodingKeys: String, CodingKey {
        case Translation = "Translations"  // 511.org uses PLURAL!
    }

    enum SnakeCaseKeys: String, CodingKey {
        case translation = "translation"  // snake_case (standard GTFS)
    }

    init(from decoder: Decoder) throws {
        // Try "Translations" (plural) first - this is what 511.org uses
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            Translation = try? container.decode([GTFSTranslation].self, forKey: .Translation)
        }
        // Try snake_case singular
        else if let container = try? decoder.container(keyedBy: SnakeCaseKeys.self) {
            Translation = try? container.decode([GTFSTranslation].self, forKey: .translation)
        } else {
            Translation = nil
        }
    }
}

struct GTFSTranslation: Codable {
    let Text: String
    let Language: String?

    enum CodingKeys: String, CodingKey {
        case Text = "Text"  // PascalCase
        case Language = "Language"
    }

    enum SnakeCaseKeys: String, CodingKey {
        case text = "text"  // snake_case
        case language = "language"
    }

    init(from decoder: Decoder) throws {
        // Try PascalCase first
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let text = try? container.decode(String.self, forKey: .Text) {
            Text = text
            Language = try? container.decode(String.self, forKey: .Language)
        }
        // Try snake_case
        else if let container = try? decoder.container(keyedBy: SnakeCaseKeys.self),
                let text = try? container.decode(String.self, forKey: .text) {
            Text = text
            Language = try? container.decode(String.self, forKey: .language)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.Text,
                DecodingError.Context(codingPath: decoder.codingPath,
                                     debugDescription: "Text field not found in either PascalCase or snake_case format"))
        }
    }
}

// MARK: - SIRI service
struct SIRIService {
    static func serviceAlerts(apiKey: String) async throws -> [ServiceAlert] {
        guard var comps = URLComponents(string: "https://api.511.org/transit/servicealerts") else {
            throw NSError(domain: "SIRI-SX", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        comps.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "agency", value: "CT"),
            .init(name: "format", value: "json")
        ]
        guard let url = comps.url else {
            throw NSError(domain: "SIRI-SX", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])
        }
        debugLog("🚨 Fetching service alerts from: \(url.host ?? "unknown")\(url.path)")
        let (raw, http) = try await HTTPClient.shared.get(url: url)
        guard (200..<300).contains(http.statusCode) else {
            debugLog("🚨 Service alerts HTTP error: \(http.statusCode)")
            // Security: Don't expose server response details to users
            let userMessage = http.statusCode >= 500
                ? "Service temporarily unavailable. Please try again later."
                : "Unable to fetch service alerts. Please check your connection."
            throw NSError(domain: "SIRI-SX", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }

        // Log raw response for debugging
        if let rawString = String(data: raw, encoding: .utf8) {
            debugLog("🚨 Raw response length: \(rawString.count) characters")
            debugLog("🚨 Response preview: \(String(rawString.prefix(200)))")
        }

        let cleaned = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) ?? raw

        do {
            // Parse GTFS Realtime format
            let gtfsResponse = try JSONDecoder().decode(GTFSRealtimeResponse.self, from: cleaned)
            debugLog("🚨 GTFS Realtime version: \(gtfsResponse.Header.GtfsRealtimeVersion ?? "unknown")")
            debugLog("🚨 Found \(gtfsResponse.Entities?.count ?? 0) entities")

            let entities = gtfsResponse.Entities ?? []
            let alertEntities = entities.filter { $0.Alert != nil }
            debugLog("🚨 Found \(alertEntities.count) alert entities")

            var alerts: [ServiceAlert] = []
            for (index, entity) in alertEntities.enumerated() {
                guard let alert = entity.Alert else { continue }

                // Extract header text (summary)
                let headerText = alert.HeaderText?.Translation?.first?.Text ?? "Service Alert"
                debugLog("🚨 Alert \(index + 1): \(headerText)")

                // Extract description text
                let descriptionText = alert.DescriptionText?.Translation?.first?.Text

                // Get active period for creation time
                var creationTime: Date?
                if let start = alert.ActivePeriod?.first?.Start {
                    creationTime = Date(timeIntervalSince1970: TimeInterval(start))
                }

                let serviceAlert = ServiceAlert(
                    id: entity.Id,
                    summary: headerText,
                    description: descriptionText,
                    severity: alert.Severity,
                    creationTime: creationTime
                )
                alerts.append(serviceAlert)
            }

            debugLog("🚨 Returning \(alerts.count) service alerts")
            return alerts
        } catch {
            debugLog("🚨 Failed to decode alerts: \(error)")
            // Security: Don't expose parsing details to users
            throw NSError(domain: "GTFS.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to process service alerts. Please try again later."])
        }
    }

    static func stopMonitoring(stopCode: String, max: Int = 6, apiKey: String) async throws -> [MonitoredStopVisitNode] {
        guard var comps = URLComponents(string: "https://api.511.org/transit/StopMonitoring") else {
            throw NSError(domain: "SIRI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        comps.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "agency", value: "CT"),
            .init(name: "stopcode", value: stopCode),
            .init(name: "format", value: "json"),
            .init(name: "MaximumStopVisits", value: String(max)),
            .init(name: "MaximumNumberOfCallsOnwards", value: "20")
        ]
        guard let url = comps.url else {
            throw NSError(domain: "SIRI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])
        }
        let (raw, http) = try await HTTPClient.shared.get(url: url)
        guard (200..<300).contains(http.statusCode) else {
            debugLog("SIRI HTTP error: \(http.statusCode)")
            // Security: Don't expose server response details to users
            let userMessage = http.statusCode >= 500
                ? "Service temporarily unavailable. Please try again later."
                : "Unable to fetch real-time data. Please check your connection."
            throw NSError(domain: "SIRI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }
        let cleaned = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) ?? raw
        do {
            let env = try JSONDecoder().decode(SiriEnvelopeNode.self, from: cleaned)
            let sd = env.Siri?.ServiceDelivery ?? env.ServiceDelivery
            let visits = sd?.StopMonitoringDelivery?.first?.MonitoredStopVisit ?? []
            return visits
        } catch {
            debugLog("Failed to decode SIRI response: \(error)")
            // Security: Don't expose parsing details to users
            throw NSError(domain: "SIRI.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to process real-time data. Please try again later."])
        }
    }

    static func nextDepartures(from stop: String, to destinationStop: String? = nil, at refDate: Date, apiKey: String, expectedDirection: String? = nil) async throws -> [Departure] {
        let visits = try await stopMonitoring(stopCode: stop, apiKey: apiKey)
        let dfFrac = ISO8601DateFormatter(); dfFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df = ISO8601DateFormatter()
        // ALWAYS use current time for minutes calculation (real-time data is always "now")
        // The refDate parameter is only used by GTFS for scheduled lookups
        let now = Date()

        var out: [Departure] = []
        debugLog("📍 Stop: \(stop), Destination: \(destinationStop ?? "any"), Expected Dir: \(expectedDirection ?? "any"), RefDate: \(now), Visits: \(visits.count)")
        for v in visits {
            let mvj = v.MonitoredVehicleJourney
            let aimed = mvj.MonitoredCall?.AimedDepartureTime
            let expected = mvj.MonitoredCall?.ExpectedDepartureTime
            let date = aimed.flatMap { dfFrac.date(from: $0) ?? df.date(from: $0) }
            // Calculate minutes, rounding up (ceiling) so a train in 30 seconds shows as 1m
            let minutes = date.map { Int(ceil($0.timeIntervalSince(now) / 60)) } ?? 0
            let direction = mvj.DirectionRef

            // Calculate delay: ExpectedDepartureTime - AimedDepartureTime
            var delayMinutes: Int? = nil
            if let aimedStr = aimed, let expectedStr = expected {
                if let aimedDate = dfFrac.date(from: aimedStr) ?? df.date(from: aimedStr),
                   let expectedDate = dfFrac.date(from: expectedStr) ?? df.date(from: expectedStr) {
                    delayMinutes = Int(round((expectedDate.timeIntervalSince(aimedDate)) / 60))
                }
            }

            // Debug: Print all available fields
            debugLog("  🚂 Dir: \(direction ?? "?"), Aimed: \(aimed ?? "nil"), Expected: \(expected ?? "nil"), Minutes: \(minutes), Delay: \(delayMinutes?.description ?? "n/a"), Dest: \(mvj.DestinationName ?? "nil")")
            debugLog("     LineRef: \(mvj.LineRef ?? "nil")")
            debugLog("     PublishedLineName: \(mvj.PublishedLineName ?? "nil")")
            debugLog("     VehicleRef: \(mvj.VehicleRef ?? "nil")")
            debugLog("     DatedVehicleJourneyRef: \(mvj.FramedVehicleJourneyRef?.DatedVehicleJourneyRef ?? "nil")")

            // Filter by direction if we have an expected direction
            if let expected = expectedDirection, let dir = direction {
                // Whitelist of valid northbound and southbound direction strings
                let northboundDirections = ["N", "NORTH", "NB", "NORTHBOUND"]
                let southboundDirections = ["S", "SOUTH", "SB", "SOUTHBOUND"]

                let expectedUpper = expected.uppercased()
                let dirUpper = dir.uppercased()

                let matches: Bool
                if northboundDirections.contains(expectedUpper) {
                    matches = northboundDirections.contains(dirUpper)
                } else if southboundDirections.contains(expectedUpper) {
                    matches = southboundDirections.contains(dirUpper)
                } else {
                    // Fallback: exact match if expected direction not in whitelist
                    matches = (expectedUpper == dirUpper)
                }

                if !matches {
                    debugLog("    ⏭️  Skipping - wrong direction (expected: \(expected), got: \(dir))")
                    continue
                }
            }

            // Extract train number from VehicleRef (e.g., "167")
            let journeyRef = mvj.FramedVehicleJourneyRef?.DatedVehicleJourneyRef ?? UUID().uuidString
            let trainNumber = mvj.VehicleRef // Use VehicleRef instead of LineRef for actual train number
            debugLog("  🚂 Creating departure with trainNumber: '\(trainNumber ?? "nil")'")

            // Extract arrival time from OnwardCalls if destination stop is specified
            var arrivalTime: Date? = nil
            if let destStop = destinationStop {
                if let onwardCalls = mvj.OnwardCalls {
                    debugLog("     🔍 Searching \(onwardCalls.count) onward calls for stop \(destStop)")
                    for call in onwardCalls {
                        debugLog("        Stop: \(call.StopPointRef ?? "nil"), Arrival: \(call.AimedArrivalTime ?? "nil")")
                        if call.StopPointRef == destStop, let arrivalTimeStr = call.AimedArrivalTime {
                            arrivalTime = dfFrac.date(from: arrivalTimeStr) ?? df.date(from: arrivalTimeStr)
                            debugLog("     ✅ Found arrival time: \(arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "nil")")
                            break
                        }
                    }
                } else {
                    debugLog("     ⚠️ No OnwardCalls in API response - API may need MaximumNumberOfCallsOnwards parameter")
                }
            }

            let dep = Departure(
                journeyRef: journeyRef,
                minutes: minutes, depTime: date,
                direction: mvj.DirectionRef, destination: mvj.DestinationName,
                trainNumber: trainNumber,
                arrivalTime: arrivalTime,
                delayMinutes: delayMinutes
            )
            // Only include future departures (at least 1 minute away)
            if minutes > 0 { out.append(dep) }
        }
        // Sort by time and take first 3
        let result = Array(out.sorted { ($0.depTime ?? .distantFuture) < ($1.depTime ?? .distantFuture) }.prefix(3))
        debugLog("  ✅ Returning \(result.count) departures")
        return result
    }
}

// MARK: - Ticketmaster API
struct TicketmasterService {
    static func searchEvents(apiKey: String, city: String = "San Jose", radius: String = "75", date: Date = Date()) async throws -> [BayAreaEvent] {
        // Get the selected date's start and end
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw NSError(domain: "CaltrainChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to calculate end of day"])
        }

        // Format with local timezone to avoid UTC offset issues
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let startDateTime = dateFormatter.string(from: startOfDay)
        let endDateTime = dateFormatter.string(from: endOfDay)

        guard var comps = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json") else {
            throw NSError(domain: "Ticketmaster", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        // Use lat/lon centered on Bay Area (Redwood City) with large radius to cover entire region
        // This ensures we get events from San Jose, SF, Oakland, etc.
        comps.queryItems = [
            .init(name: "apikey", value: apiKey),
            .init(name: "latlong", value: "37.4852,-122.2364"),  // Redwood City (center of Caltrain)
            .init(name: "radius", value: "50"),  // 50 miles covers SF to San Jose
            .init(name: "unit", value: "miles"),
            .init(name: "startDateTime", value: startDateTime),
            .init(name: "endDateTime", value: endDateTime),
            .init(name: "size", value: "200"),  // Increased to get more events
            .init(name: "sort", value: "date,asc")
        ]

        guard let url = comps.url else {
            throw NSError(domain: "Ticketmaster", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct URL"])
        }
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        #if !DEBUG
        debugLog("🎟️ Fetching Ticketmaster events for \(dateString) (\(startDateTime) to \(endDateTime))")
        #endif
        debugLog("🎟️ URL: \(url.host ?? "unknown")\(url.path)")
        let (data, http) = try await HTTPClient.shared.get(url: url)
        guard (200..<300).contains(http.statusCode) else {
            debugLog("🎟️ Ticketmaster HTTP error: \(http.statusCode)")
            // Security: Don't expose server response details to users
            let userMessage = http.statusCode >= 500
                ? "Event service temporarily unavailable. Please try again later."
                : "Unable to fetch events. Please check your connection."
            throw NSError(domain: "Ticketmaster", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                debugLog("🎟️ Failed to parse JSON as dictionary")
                return []
            }
            guard let embedded = json["_embedded"] as? [String: Any],
                  let eventsArray = embedded["events"] as? [[String: Any]] else {
                #if !DEBUG
                debugLog("🎟️ No events found in response")
                #endif
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

            #if !DEBUG
            debugLog("🎟️ Found \(events.count) events")
            #endif
            return events
        } catch {
            debugLog("🎟️ Failed to decode: \(error)")
            // Security: Don't expose parsing details to users
            throw NSError(domain: "Ticketmaster.decode", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to process events. Please try again later."])
        }
    }
}

// MARK: - Keychain Wrapper
final class Keychain {
    static let shared = Keychain(service: Bundle.main.bundleIdentifier ?? "CaltrainChecker")
    private let service: String
    private let queue = DispatchQueue(label: "com.caltrainchecker.keychain", attributes: .concurrent)

    init(service: String) { self.service = service }

    subscript(key: String) -> String? {
        get { queue.sync { read(key) } }
        set { queue.sync(flags: .barrier) { if let v = newValue { self.save(key, v) } else { self.delete(key) } } }
    }

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
        debugLog("🔐 Keychain saving key=\(key) value_length=\(value.count)")
        SecItemDelete(q as CFDictionary)
        let status = SecItemAdd(q as CFDictionary, nil)
        debugLog("🔐 Keychain save status: \(status == errSecSuccess ? "SUCCESS" : "FAILED(\(status))")")
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
