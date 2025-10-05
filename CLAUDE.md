# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Building and Running

This is a single-file SwiftUI iOS app for tracking Caltrain departures:

- **Open in Xcode**: Open `CalTrain_Tracking_App` folder in Xcode
- **Build**: Cmd+B
- **Run**: Cmd+R (requires iOS 17.0+ simulator or device)
- **Clean Build**: Shift+Cmd+K

The entire app is in **CTTracker6App.swift** - there is no separate project structure.

## Architecture Overview

### Single-File Architecture
The app uses a single-file design (`CTTracker6App.swift`) with all components defined in one place:
- SwiftUI views
- Network services
- Data models
- Keychain wrapper
- App state management

### Key Components

**Station Selection System**
- Users configure two stations: "Southern Station" and "Northern Station"
- Northbound trains go from Southern → Northern station
- Southbound trains go from Northern → Southern station
- Stop codes are odd for northbound, even for southbound
- **Critical**: 22nd Street northbound=70021, southbound=70022; Bayshore northbound=70031, southbound=70032

**Data Sources**
- **511.org SIRI API**: Real-time Caltrain departure data (requires API key from 511.org)
- **MLB Stats API**: Giants home game schedule

**API Key Storage**
- API keys stored in iOS Keychain via `Keychain.shared["api_511"]`
- Full-screen cover gate prevents app use without valid key
- Optional embedded key for simulator testing (line 22-28)

### iOS 17 Requirements

The app uses iOS 17+ APIs:
- `.onChange(of:initial:)` with two parameters (old/new values)
- Modern date formatting APIs

### SIRI API Parsing

The 511.org API returns inconsistent JSON structures:
- Root can be `{"Siri": {...}}` or bare `{"ServiceDelivery": {...}}`
- `StopMonitoringDelivery` can be array or single object
- `DestinationName` can be String or [String]

The robust parsing models (`SiriEnvelopeNode`, `ServiceDeliveryNode`, etc.) handle all variants.

### Direction Logic

**Geography**:
- Mountain View is SOUTH of San Francisco
- 22nd Street is NORTH of Mountain View
- Northbound = toward San Francisco (south → north)
- Southbound = toward San Jose (north → south)

**Implementation**:
- Northbound departures query the southern station's northbound stop code
- Southbound departures query the northern station's southbound stop code
- Direction filtering uses `DirectionRef` field ("N" or "S")

### Data Attribution & Compliance

Per 511.org terms of use:
- App must attribute 511.org as data source
- Must include disclaimer about data accuracy ("estimates only", "as is")
- Commercial distribution requires written MTC authorization
- See `AboutScreen` for compliance implementation

## Common Tasks

**Adding a new view/screen**:
1. Define struct conforming to `View` in CTTracker6App.swift
2. Add to TabView in `RootView` if it's a main tab
3. Or add as NavigationLink destination from existing screen

**Modifying station list**:
- Edit `CaltrainStops.northbound` and `CaltrainStops.southbound` arrays
- Maintain stop code format: odd=northbound, even=southbound
- Keep stations in geographic order (south to north for northbound, north to south for southbound)

**Testing API changes**:
- Set `EmbeddedAPIKey_SIMULATOR_ONLY` to valid key for simulator testing
- Use print statements - the app has extensive logging in `load()` functions
- Check Xcode console for 511 API responses

**Debugging direction issues**:
- Check stop codes: northbound stops must use odd codes, southbound must use even
- Verify `DirectionRef` filtering in `SIRIService.nextDepartures`
- Look for console logs showing "Skipping - wrong direction"

## Important Notes

- **Never hardcode API keys** in production code (line 24 is simulator-only)
- **Always commit and push** after significant changes (this is a GitHub-backed project)
- **Stop code accuracy is critical** - incorrect codes cause 4+ minute discrepancies
- The app shows next 3 departures only, filtering out past departures
- Time calculation uses `ceil()` to round up (30 seconds → 1 minute)
