# CalTrain Tracking App - Development Notes

## Project Overview

Single-file SwiftUI iOS app for tracking Caltrain departures with real-time data, service alerts, and Bay Area events.

**Main File:** `CTTracker6App.swift` (~4200 lines)

## Architecture

### Data Sources
1. **GTFS Static Schedule** (Trillium Transit)
   - Complete train schedule for any time
   - Custom pure-Swift ZIP extractor (iOS compatible)
   - 24-hour cache with automatic refresh

2. **511.org Transit API**
   - **SIRI format:** Real-time train numbers from VehicleRef, service types
   - **GTFS Realtime format:** Service alerts with non-standard field naming
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

#### Service Alerts (GTFS Realtime)
- **Format:** 511.org uses non-standard GTFS Realtime JSON
- **Field naming quirks:**
  - "Translations" (plural) not "Translation"
  - "ActivePeriods" and "InformedEntities" (plural)
  - "cause" and "effect" (lowercase, not PascalCase)
- **Parsing strategy:** Flexible CodingKeys with both naming conventions
- **Data extracted:** Header, description, severity, active periods
- **Display:** Dedicated Alerts tab + tappable banner on Trains screen

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
    let oldest = lastRequestTime.min(by: { $0.value < $1.value })?.key
    if let key = oldest { lastRequestTime.removeValue(forKey: key) }
}
```

### 6. Service Alerts Parsing (November 2025)
**Problem:** 511.org service alerts not displaying text - showed only "Service Alert"
**Root cause:** API uses non-standard GTFS Realtime field names
- "Translations" (PLURAL) instead of "Translation"
- "ActivePeriods" and "InformedEntities" (PLURAL)
- "cause" and "effect" (lowercase)

**Fix:** Added flexible CodingKeys to handle both naming conventions
```swift
enum CodingKeys: String, CodingKey {
    case Translation = "Translations"  // 511.org uses PLURAL!
}
```

**Investigation process:**
1. Added debug logging to dump full JSON response
2. Discovered HeaderText/DescriptionText had empty `{}` objects
3. Found actual data in "Translations" (plural) nested array
4. Updated all GTFS Realtime models with correct field names

## Security Features

- **Thread-safe Keychain:** Sync writes with barrier
- **API rate limiting:** 5s minimum between same-endpoint calls
- **Network retry:** Exponential backoff (1s, 2s, 4s)
- **ZIP protection:** Path traversal and ZIP bomb checks
- **Sanitized errors:** No server response leaks

## Performance Optimizations

- **@MainActor:** For WeatherService and other ObservableObjects
- **HTTPClient cache:** Bounded dictionary with O(1) cleanup
- **Async operations:** Heavy tasks off main thread
- **Code reduction:** Removed delay prediction engine (~400 lines)
- **Debug logging:** Conditional compilation with debugLog()

## Common Issues & Solutions

### Service alerts not showing text
**Check:**
1. Debug logs show "Translations" count > 0?
2. GTFS Realtime models using correct field names?
3. API returning non-empty HeaderText/DescriptionText?
4. Check console for "🚨 FULL RESPONSE:" to see actual JSON

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

### Service Alerts (GTFS Realtime)
```
https://api.511.org/transit/servicealerts
?api_key={key}
&agency=CT
&format=json
```
**Returns:** GTFS Realtime JSON with non-standard field names
- "Translations" (plural), "ActivePeriods" (plural)
- Mixed case: PascalCase for most fields, lowercase for "cause"/"effect"

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
- `CaltrainStop` - Station with coordinates
- `GTFSTrip`, `GTFSStopTime`, `GTFSCalendar`, etc.
- `GTFSRealtimeResponse`, `GTFSAlert`, `GTFSTranslatedString` - GTFS Realtime alerts

### Services (Actors/Classes)
- `SIRIService` - Real-time train data + service alerts parsing
- `GTFSService` - Static schedule data
- `HTTPClient` - Rate-limited network client
- `WeatherService` - Destination weather
- `TicketmasterService` - Bay Area events
- `SmartNotificationManager` - Push notifications

### Views
- `TrainsScreen` - Main departure list with alerts banner
- `EventsScreen` - Bay Area events browser
- `AlertsScreen` - Service alerts display
- `InsightsView` - Streaks, achievements, CO₂
- `StationsScreen` - Route selection
- `SettingsScreen` - API keys, themes

## Testing Tips

1. **Check console logs** for detailed debugging
2. **Test on physical device** for real performance
3. **Monitor memory** with Xcode Instruments
4. **Use debugLog()** for conditional debug output
5. **Test service alerts** when Caltrain posts disruptions
6. **Verify GTFS Realtime parsing** with full JSON logging

## Known Limitations

1. **SIRI OnwardCalls not supported** - Must use GTFS for arrivals
2. **Rate limiting strict** - 5s minimum between calls
3. **GTFS cache 24hr** - Updates once per day
4. **Weather at destination only** - Not departure station
5. **511.org non-standard GTFS Realtime** - Custom field names require special parsing

## Future Enhancements (Ideas)

- [ ] Widget for next departure
- [ ] Apple Watch complications
- [ ] Siri shortcuts integration
- [ ] Share routes with friends
- [ ] Bike car availability indicator
- [ ] Crowding predictions (ML)
- [ ] Real-time train tracking on map
- [ ] Push notifications for service alerts

## Git Repository

**URL:** https://github.com/dominicmartinelli/CalTrain_Tracking_App

### Recent Commits (November 2025)
- Fix service alerts parsing - 511.org uses 'Translations' (plural)
- Replace inline service alerts with navigation link on Trains screen
- Add diagnostic logging for service alerts text extraction
- Fix critical bugs and add comprehensive TODO tracking
- Remove delay prediction engine (~400 lines simplified)

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

Last updated: 2025-11-19
