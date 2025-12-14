# CalTrain Tracking App

A SwiftUI iOS app for tracking Caltrain departures, service alerts, and Bay Area events.

## Features

### 🎨 Branding
- Vintage-style Caltrain Checker logo with full-screen splash screen on launch
- Logo icon displayed in navigation bar across all screens
- Cohesive retro aesthetic throughout the app

### 🚂 Train Tracking
- **Complete Caltrain schedule** using GTFS static data - shows all scheduled trains
- **Real-time enhancements** from 511.org SIRI API (train numbers, service types, delays)
- **Arrival times** - displays both departure and arrival times (e.g., "8:16 PM → 8:45 PM")
  - Calculated from GTFS schedule data for accurate end-to-end trip times
  - Shows expected arrival at your destination station
- **Train numbers** - displays actual train numbers in parentheses (e.g., "(163)")
  - Extracted from SIRI API VehicleRef field for real-time accuracy
- **Full schedule view** - tap section headers to view up to 50 upcoming departures in either direction
- Track trains between any two Caltrain stations
- Shows next 3 departures for both northbound and southbound directions
- Displays departure times, service types (Local, Limited, etc.), and countdown in minutes
- **Time picker** to check departures at any future time - shows full schedule, not just real-time trains
  - Smart date detection: selecting a past time (>5 min ago) automatically assumes you mean tomorrow
- **Weather at destination** - see current conditions and temperature in section headers (via Open-Meteo API)
- **"I took this train" button** - tap checkmark to log trips for CO₂ tracking and achievements
- **Service alerts banner** - tappable link at top of screen when alerts are active
  - Shows alert count and navigates to Alerts tab for full details
- Automatic GTFS feed updates (24-hour cache)

### 🎟️ Bay Area Events
- **Date picker** - browse events for today or any future date
- **Smart filtering** - show all venues or only large venues (20,000+ capacity)
  - Major sports venues always included regardless of capacity:
    - Chase Center (Warriors, 18,064)
    - Levi's Stadium (49ers, 68,500)
    - Oracle Park (Giants, 41,915)
    - SAP Center (Sharks, 17,562)
- **Station-based search** - filter by "All Stations" or specific Caltrain station
- **Adjustable distance radius** - 0.5 to 10 miles from selected station(s)
- Powered by Ticketmaster Discovery API
- Event details include venue, time, ticket links, and nearest Caltrain station
- Covers concerts, sports (including Warriors, 49ers, Giants, and Sharks games), theater, and more
- Perfect for planning weekend trips or finding events near your commute

### 🚨 Service Alerts
- Dedicated alerts tab with visual status indicator
- **GTFS Realtime service alerts** from 511.org API
  - Displays official Caltrain service disruption notifications
  - Shows alert summary and detailed description
  - Includes severity level and active time period
  - Links to caltrain.com/status for more information
- Checkmark icon when no alerts (with "Alright Alright Alright" message)
- Warning triangle icon with badge count when alerts are active
- Tappable banner on Trains screen links to full alert details
- Alerts automatically load on app start and refresh when viewing Alerts tab
- **Note:** Parses 511.org's non-standard GTFS Realtime format with custom field names

### 📍 Station Selection
- Dedicated Stations tab for easy configuration
- **Save multiple commute routes** with custom names (e.g., "Home → Work", "Weekend SF Trip")
- Quick-switch between saved commutes with one tap
- Swipe to rename or delete saved routes
- Select any two Caltrain stations for your current route
- Supports all 27 Caltrain stations from Gilroy to San Francisco
- Visual route preview with northbound/southbound indicators

### 📊 Commute Insights (Dedicated Tab)
- **Streak Tracking** - maintain daily riding streaks with fire emoji 🔥
- **Achievement Badges** - unlock 8 achievements:
  - 🚂 First Ride - Take your first trip
  - 🔥 Week Warrior - 5 day streak
  - ⭐ Month Master - 20 trips in a month
  - 🌱 Eco Hero - Save 500 lbs CO₂
  - 👑 Commute King - 100 total trips
  - 🌅 Early Bird - Train before 7 AM
  - 🦉 Night Owl - Train after 9 PM
  - 🎒 Weekend Explorer - 10 weekend trips
- **Weekly Stats** - track schedule checks and most common routes
- **Environmental Impact** - CO₂ savings calculator (only counts manually logged trips)
- **Pattern Detection** - learns your regular commute routes and times
- **Privacy-first** - all data stored locally on device, never uploaded

### 🔔 Smart Notifications
- Opt-in alerts for:
  - Your usual trains departing soon
  - Service delays on your regular routes
  - Giants game crowding warnings
- Configure in Settings tab

### ⚙️ Settings
- **Custom themes** - Choose from 5 beautiful color schemes:
  - 🎨 Vintage (default) - Muted red-brown with cream accents
  - ✨ Modern - Bright blue with green accents
  - 🌙 Dark - Light gray on near-black background with purple accents
  - 🌊 Ocean - Deep ocean blue with teal accents
  - 🌅 Sunset - Coral orange with golden yellow accents
  - Theme persists across app launches
  - Live preview with color circles in theme selector
- Smart notification toggle (appears first for easy access)
- Secure API key management for 511.org and Ticketmaster
- All credentials stored in iOS Keychain
- About page with data attribution and compliance info

## Setup

### Required API Keys

1. **511.org API Key** (Required for train tracking)
   - Get free key: [511.org/open-data/token](https://511.org/open-data/token)
   - Used for real-time Caltrain data and service alerts

2. **Ticketmaster API Key** (Optional for events)
   - Get free key: [developer.ticketmaster.com](https://developer.ticketmaster.com)
   - Used for Bay Area events discovery

### First Launch

1. Build and run the app in Xcode
2. On first launch, enter your 511.org API key
3. Go to **Stations** tab to select your two stations:
   - **Southern Station**: Your station closer to San Jose (e.g., Mountain View)
   - **Northern Station**: Your station closer to SF (e.g., 22nd Street)
4. (Optional) Go to **Settings** tab to add Ticketmaster API key for events
5. The app has 6 tabs:
   - **Trains**: Northbound and Southbound departures with weather
   - **Events**: Browse Bay Area events by date near Caltrain stations
   - **Alerts**: Service disruptions with visual status
   - **Insights**: Streak tracking, achievements, CO₂ savings, and patterns
   - **Stations**: Configure and save multiple commute routes
   - **Settings**: Smart notifications toggle and API key management

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Active internet connection
- 511.org API key (free)

## Supported Stations

All Caltrain stations are supported:
- Gilroy
- San Martin
- Morgan Hill
- Blossom Hill
- Capitol
- Tamien
- San Jose Diridon
- Santa Clara
- Lawrence
- Sunnyvale
- Mountain View
- San Antonio
- California Ave
- Palo Alto
- Menlo Park
- Redwood City
- San Carlos
- Belmont
- Hillsdale
- San Mateo
- Burlingame
- Millbrae
- San Bruno
- South San Francisco
- Bayshore
- 22nd Street
- San Francisco

## Architecture

- Single-file SwiftUI app (`CTTracker6App.swift`)
- Uses iOS 17's `.onChange(of:initial:)` for reactive updates
- Secure keychain storage for API credentials
- Async/await networking with URLSession
- **GTFS (General Transit Feed Specification)** static schedule parsing
  - Downloads and parses Caltrain GTFS feed from Trillium Transit
  - Shows complete train schedule for any selected time (not just real-time trains)
  - Custom pure-Swift ZIP extractor using Apple's Compression framework (iOS compatible)
  - Parses CSV files: stops.txt, trips.txt, stop_times.txt, calendar.txt, calendar_dates.txt
  - Service calendar logic determines which trips run on which days (handles weekdays and exception dates)
  - Handles GTFS time format (supports times like "25:30:00" for next day)
  - Includes after-midnight trains (up to 5 AM) in evening schedules
  - Automatically fetches tomorrow's early morning service when viewing late-night departures
  - Calculates actual minutes until departure from current time
  - 24-hour cache with automatic refresh
- **SIRI API integration** for real-time enhancements
  - Extracts train numbers from VehicleRef field for accurate identification
  - Overlays real-time service types (Local, Limited, etc.) on scheduled trains
  - Smart merge strategy: prefers real-time data over scheduled data for accuracy
  - Calculates arrival times from GTFS when OnwardCalls unavailable
- **Arrival Time Calculation**
  - Matches departure time to GTFS trip (within 2 minutes)
  - Finds arrival time at destination stop from schedule
  - Displays full journey time (e.g., "8:16 PM → 8:45 PM")
  - Fallback when SIRI OnwardCalls not supported by API
- **GTFS Realtime Service Alerts** (from 511.org)
  - Parses 511.org's non-standard GTFS Realtime JSON format
  - Handles mixed PascalCase and lowercase field names:
    - "Translations" (plural) instead of standard "Translation" (singular)
    - "ActivePeriods" and "InformedEntities" (plural)
    - "cause" and "effect" (lowercase)
  - Flexible decoding with fallback for both naming conventions
  - Extracts alert header, description, severity, and active time periods
  - Displays in dedicated Alerts tab with tappable banner on Trains screen
- **Security Features**
  - Thread-safe Keychain access with concurrent DispatchQueue (sync writes to prevent race conditions)
  - API rate limiting (5 seconds between requests to same endpoint)
  - Smart rate limit handling: 15s initial delay + 5s between calls to avoid 429 errors
  - Network retry logic with exponential backoff (1s, 2s, 4s)
  - Sanitized error messages (no server response leaks)
  - ZIP path traversal and ZIP bomb protection
  - Input validation for API keys and file paths
- **Performance Optimizations** (Updated November 2025)
  - O(1) dictionary cleanup in HTTPClient for efficient rate limiting
  - Optimized arrival time matching with ±2 minute tolerance for accuracy
  - Debug-only logging with debugLog() to eliminate production console overhead
  - Removed delay prediction engine for simplified codebase (~400 lines removed)
- Robust SIRI XML/JSON response parsing
- Haversine formula for calculating distances between venues and stations
- Custom splash screen with fade-out animation
- Event capacity filtering (optional 20,000+ venues filter)

## APIs & Data Sources

- **Caltrain GTFS Feed**: Static schedule data from https://data.trilliumtransit.com/gtfs/caltrain-ca-us/
- **511.org Transit API**:
  - SIRI format: Real-time train numbers and service types
  - GTFS Realtime format: Service alerts (non-standard field naming)
- **Open-Meteo API**: Free weather data (no API key required)
- **Ticketmaster Discovery API**: Bay Area events information

## Data Attribution & Disclaimer

- Static schedule data provided by Caltrain GTFS feed via Trillium Transit
- Real-time data and service alerts provided by 511.org
- Weather data provided by Open-Meteo (https://open-meteo.com)
- Events data provided by Ticketmaster Discovery API
- Transit times are estimates only and provided "as is" without warranty
- Always verify departure times before traveling
- Users should exercise reasonable judgment when planning trips

## Compliance

This app complies with 511.org's terms of use:
- Properly attributes 511.org as the data source
- Includes required disclaimers about data accuracy
- Uses authorized API access for transit data
- Does not redistribute or resell transit data

For 511.org API terms: https://511.org/about/terms

## License

This project was created for personal use. Feel free to use and modify as needed.

**Note**: If you plan to distribute this app commercially or publicly, you must obtain written authorization from MTC (Metropolitan Transportation Commission) as required by 511.org's terms of use.

## Credits

🤖 Generated with [Claude Code](https://claude.com/claude-code)
