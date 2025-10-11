# CalTrain Tracking App - Development Notes

## Project Overview

Single-file SwiftUI iOS app for tracking Caltrain departures with real-time data, delay predictions, and Bay Area events.

**Main File:** `CTTracker6App.swift` (~4100 lines)

## Architecture

### Data Sources
1. **GTFS Static Schedule** (Trillium Transit)
   - Complete train schedule for any time
   - Custom pure-Swift ZIP extractor (iOS compatible)
   - 24-hour cache with automatic refresh

2. **SIRI API (511.org)**
   - Real-time train numbers from VehicleRef
   - Service types and delays
   - **Note:** OnwardCalls NOT supported by API despite parameter

3. **Open-Meteo API** (Free, no key)
   - Weather at destination stations

4. **Ticketmaster Discovery API** (Optional)
   - Bay Area events near stations

### Key Components

#### Stop Codes
- **Northbound stops:** Different codes than southbound
- **Example:** San Jose Diridon NB=70211, SB=70022
- **Critical:** Must use correct stop code for direction

#### Train Numbers
- Extracted from SIRI `VehicleRef` field
- Even numbers typically northbound, odd southbound
- Range: 101-199 for typical service

#### Arrival Times
- **GTFS-based calculation** (SIRI OnwardCalls not available)
- Matches departure time to trip (±2 min tolerance)
- Finds arrival at destination stop from schedule
- Uses `departureTime` field (arrivalTime doesn't exist in GTFSStopTime)

#### Delay Prediction Engine
- **Pattern matching:** train number, stop code, weekday, hour (±1)
- **Storage:** UserDefaults JSON encoded
- **Limits:** 500 records (production), 20,000 (DEBUG)
- **Confidence:** High (≥10), Medium (≥5), Low (<5)
- **Privacy-first:** All data local, never uploaded

## Critical Bug Fixes

### 1. Keychain Race Condition
**Problem:** Async writes with sync reads
**Fix:** Changed to sync writes with barrier flag
```swift
set { queue.sync(flags: .barrier) { ... } }  // Was: queue.async
```

### 2. Wrong Stop Codes (Morgan Hill/San Martin)
**Problem:** Reused northbound codes for southbound array
**Fix:** Corrected southbound codes
```swift
// Before: 777402, 777403
// After:  777400, 777405
```

### 3. GTFSStopTime Field Name
**Problem:** Used non-existent `arrivalTime` field
**Fix:** Use `departureTime` for both dep/arr
```swift
destST.departureTime  // Not: destST.arrivalTime
```

### 4. Rate Limiting (429 Errors)
**Problem:** Too many API calls too fast
**Fix:** 15s initial delay + 5s between calls
```swift
try? await Task.sleep(nanoseconds: 15_000_000_000)
// ... first call ...
try? await Task.sleep(nanoseconds: 5_000_000_000)
// ... second call ...
```

### 5. HTTPClient Memory Leak
**Problem:** Unbounded lastRequestTime dictionary growth
**Fix:** Limit to 50 entries, auto-cleanup
```swift
if lastRequestTime.count > maxCachedEndpoints {
    lastRequestTime = Dictionary(uniqueKeysWithValues: Array(sorted.suffix(50)))
}
```

### 6. Test Data Generation Issues

#### Memory Bloat (8,484 records → 2,376 records)
**Problem:** Creating test data for every train × 7 hours
**Fix:** Current hour ±1 only, both stops

#### Weekday Mismatch
**Problem:** Going back random weeks changed weekday
**Fix:** Use 7-day increments (7, 14, 21, 28 days)
```swift
let daysAgo = (i + 1) * 7  // Preserves weekday
```

#### Train Number Mismatch
**Problem:** Hardcoded trains didn't match actual trains showing
**Fix:** Generate for all trains 101-199

#### UI Freeze on Physical Device
**Problem:** UserDefaults writes blocking main thread
**Fix:** Async with Task.detached
```swift
Task.detached {
    await addTestDelayData(northStopCode: northCode, southStopCode: southCode)
}
```

## Debug Tools (DEBUG builds only)

### Add Test Delay Data
- Creates ~2,376 records
- Covers trains 101-199
- Current hour ±1, same weekday
- Both northbound and southbound stops
- Async execution (no UI freeze)

### Clear Delay Data
- Removes `delayHistory` key from UserDefaults
- Use before regenerating test data

## Security Features

- **Thread-safe Keychain:** Sync writes with barrier
- **API rate limiting:** 5s minimum between same-endpoint calls
- **Network retry:** Exponential backoff (1s, 2s, 4s)
- **ZIP protection:** Path traversal and ZIP bomb checks
- **Sanitized errors:** No server response leaks

## Performance Optimizations

- **@MainActor:** For WeatherService and other ObservableObjects
- **Memory limits:** DelayPredictor maxRecords cap
- **HTTPClient cache:** Bounded dictionary (50 entries)
- **Async operations:** Heavy tasks off main thread

## Common Issues & Solutions

### "No predictions found"
**Check:**
1. Test data weekday matches current weekday?
2. Test data hour matches train departure hour ±1?
3. Stop codes correct for direction?
4. Train numbers match actual trains (101-199)?

### "429 Too many requests"
**Check:**
1. Increase delay between API calls
2. Check HTTPClient rate limiting (5s minimum)
3. Don't make calls too soon after app load

### Arrival times not showing
**Check:**
1. GTFS data loaded? (24hr cache)
2. Departure time matches trip? (±2 min tolerance)
3. Destination stop exists in schedule?

### App freeze on device
**Check:**
1. Heavy operations in Task.detached?
2. UserDefaults writes too large?
3. Using await MainActor.run for UI updates?

## API Endpoints

### 511.org SIRI
```
https://api.511.org/transit/StopMonitoring
?api_key={key}
&agency=CT
&stopcode={code}
&format=json
&MaximumStopVisits={max}
&MaximumNumberOfCallsOnwards=20  // Not supported by API
```

### Service Alerts
```
https://api.511.org/transit/servicealerts
?api_key={key}
&agency=CT
&format=json
```

### GTFS Feed
```
https://data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip
```

### Open-Meteo Weather
```
https://api.open-meteo.com/v1/forecast
?latitude={lat}
&longitude={lon}
&current=temperature_2m,weather_code
```

### Ticketmaster Events
```
https://app.ticketmaster.com/discovery/v2/events.json
?apikey={key}
&latlong={lat},{lon}
&radius={miles}
&unit=miles
&startDateTime={iso8601}
&endDateTime={iso8601}
```

## File Structure

```
CalTrain_Tracking_App/
├── CTTracker6App.swift          # Main app file (~4100 lines)
├── README.md                     # User documentation
├── DEVELOPMENT_NOTES.md          # This file
└── Assets.xcassets/
    ├── AppIcon.appiconset/
    ├── LaunchScreen.imageset/   # Vintage logo
    └── LogoIcon.imageset/       # Nav bar logo
```

## Key Structs & Classes

### Models
- `Departure` - Train departure info
- `ServiceAlert` - Caltrain service disruption
- `DelayRecord` - Historical delay data point
- `CaltrainStop` - Station with coordinates
- `GTFSTrip`, `GTFSStopTime`, `GTFSCalendar`, etc.

### Services (Actors/Classes)
- `SIRIService` - Real-time train data
- `GTFSService` - Static schedule data
- `DelayPredictor` - ML-based delay predictions
- `HTTPClient` - Rate-limited network client
- `WeatherService` - Destination weather
- `TicketmasterService` - Bay Area events
- `SmartNotificationManager` - Push notifications

### Views
- `TrainsScreen` - Main departure list
- `EventsScreen` - Bay Area events browser
- `AlertsScreen` - Service alerts + delay predictions
- `InsightsScreen` - Streaks, achievements, CO₂
- `StationsScreen` - Route selection
- `SettingsScreen` - API keys, themes, debug tools

## Testing Tips

1. **Use DEBUG mode** for test data generation
2. **Clear data first** before regenerating
3. **Check console logs** for detailed debugging
4. **Verify weekday/hour** matches test data
5. **Test on physical device** for real performance
6. **Monitor memory** with Xcode Instruments

## Known Limitations

1. **SIRI OnwardCalls not supported** - Must use GTFS for arrivals
2. **Rate limiting strict** - 5s minimum between calls
3. **GTFS cache 24hr** - Updates once per day
4. **Delay predictions local only** - No cloud sync
5. **Weather at destination only** - Not departure station

## Future Enhancements (Ideas)

- [ ] Widget for next departure
- [ ] Apple Watch complications
- [ ] Siri shortcuts integration
- [ ] Push notifications for delays
- [ ] Share routes with friends
- [ ] Historical delay trends chart
- [ ] Bike car availability indicator
- [ ] Crowding predictions (ML)

## Git Repository

**URL:** https://github.com/dominicmartinelli/CalTrain_Tracking_App

### Recent Commits
- Fix delay prediction test data generation
- Update README with optimized debug test data details
- Add arrival time calculation from GTFS
- Fix keychain race condition
- Optimize memory usage for delay predictions

## Development Environment

- **iOS:** 17.0+
- **Xcode:** 15.0+
- **Swift:** 5.9+
- **Architecture:** SwiftUI, async/await
- **No external dependencies**

## Contact & Support

Created for personal use. For issues or questions, see GitHub issues.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Last updated: 2025-10-11
