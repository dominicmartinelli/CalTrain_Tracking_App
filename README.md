# CalTrain Tracking App

A SwiftUI iOS app for tracking Caltrain departures, service alerts, and Bay Area events.

## Features

### 🚂 Train Tracking
- Real-time Caltrain departure times from the 511.org SIRI API
- Track trains between any two Caltrain stations
- Shows next 3 departures for both northbound and southbound directions
- Displays departure times and countdown in minutes
- Customizable time selection to check future departures
- Service alerts displayed when active

### 🎟️ Bay Area Events
- Shows events happening today within 50 miles of San Francisco
- Powered by Ticketmaster Discovery API
- Event details include venue, time, and ticket links
- Covers concerts, sports, theater, and more

### 🚨 Service Alerts
- Dedicated alerts tab with visual status indicator
- Green checkmark when no alerts (with "Alright Alright Alright" message)
- Red warning icon with badge count when alerts are active
- Real-time Caltrain service disruption notifications

### 📍 Station Selection
- Dedicated Stations tab for easy configuration
- Select any two Caltrain stations for your commute
- Supports all 27 Caltrain stations from Gilroy to San Francisco
- Visual route preview with northbound/southbound indicators

### ⚙️ Settings
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
5. The app will show:
   - **Trains**: Northbound (southern → northern) and Southbound (northern → southern)
   - **Events**: Today's events in the Bay Area
   - **Alerts**: Service disruptions with visual status
   - **Stations**: Configure your commute stations
   - **Settings**: Manage API keys and view about info

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
- Robust SIRI XML/JSON response parsing

## APIs Used

- **511.org Transit API**: Real-time Caltrain departure data
- **MLB Stats API**: Giants game schedule information

## Data Attribution & Disclaimer

- Transit data provided by 511.org
- Baseball data provided by MLB Stats API
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
