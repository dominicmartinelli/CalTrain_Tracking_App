# CalTrain Tracking App

A SwiftUI iOS app for tracking Caltrain departures and SF Giants home games.

## Features

### 🚂 Train Tracking
- Real-time Caltrain departure times from the 511.org SIRI API
- Track trains between any two Caltrain stations
- Shows next 3 departures for both northbound and southbound directions
- Displays departure times and countdown in minutes
- Customizable time selection to check future departures

### ⚾ Giants Game Tracking
- Shows SF Giants home games for today
- Indicates if it's a day game (which may affect Caltrain crowding)
- Uses MLB Stats API for game information

### ⚙️ Settings
- Select any two Caltrain stations for your commute
- Supports all 27 Caltrain stations from Gilroy to San Francisco
- Secure API key storage in iOS Keychain
- Easy station selection with scrollable picker wheels

## Setup

1. Get a free API key from [511.org](https://511.org/open-data/token)
2. Build and run the app in Xcode
3. On first launch, enter your 511.org API key
4. Go to Settings to select your stations:
   - **Southern Station**: Your southern station (e.g., Mountain View)
   - **Northern Station**: Your northern station (e.g., 22nd Street)
5. The app will show:
   - Northbound trains from southern → northern station
   - Southbound trains from northern → southern station

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
