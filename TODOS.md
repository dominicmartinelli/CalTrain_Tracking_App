# Caltrain Tracking App - TODO List

**Generated:** November 3, 2025
**Last Updated:** December 15, 2025
**Total Items:** 18
**Completed:** 13
**Remaining:** 5

---

## ✅ Completed (13)

### 1. ~~Fix critical data race in CommuteHistoryStorage.recordTrip()~~ ✅
- **Priority:** Critical
- **Status:** COMPLETED
- **Location:** `CTTracker6App.swift:3016-3089`
- **Issue:** Multiple users tapping "record trip" simultaneously could cause concurrent writes to UserDefaults, leading to lost trip records or corrupted data
- **Solution:** Added thread-safe DispatchQueue with concurrent reads and barrier writes. Created new `recordTrip()` method with completion handler for atomic operations.
- **Files Changed:**
  - `CTTracker6App.swift:3016-3089` - CommuteHistoryStorage class
  - `CTTracker6App.swift:1803-1828` - DepartureRow.recordTrip() method

### 2. ~~Fix critical GTFS decompression validation~~ ✅
- **Priority:** Critical
- **Status:** COMPLETED
- **Location:** `CTTracker6App.swift:3553-3557`
- **Issue:** After decompressing GTFS ZIP files, code didn't verify actual decompressed size matched expected size. Corrupted data could silently produce invalid train schedules.
- **Solution:** Added strict validation: `guard decompressedSize == uncompressedSize` with descriptive error message.
- **Files Changed:**
  - `CTTracker6App.swift:3553-3557` - Added size validation in decompress()

### 3. ~~Optimize HTTPClient dictionary cleanup from O(n log n) to O(1)~~ ✅
- **Priority:** High
- **Status:** COMPLETED (November 8, 2025)
- **Location:** `CTTracker6App.swift:4077-4080` - `HTTPClient.recordRequest()`
- **Issue:** Dictionary cleanup sorted entire dictionary (O(n log n)) then took suffix. Inefficient when rate limiting many endpoints.
- **Solution:** Changed to O(1) operation that finds and removes only the oldest entry.
- **Files Changed:**
  - `CTTracker6App.swift:4077-4080` - Optimized dictionary cleanup

### 5. ~~Reduce arrival time matching tolerance from ±5 to ±2 minutes~~ ✅
- **Priority:** Medium
- **Status:** COMPLETED (November 8, 2025)
- **Location:** `CTTracker6App.swift:3812` - `GTFSService.getArrivalTime()`
- **Issue:** ±5 minute tolerance for matching departure times could match wrong trip if trains run close together
- **Solution:** Reduced tolerance to ±2 minutes for more accurate trip matching.
- **Files Changed:**
  - `CTTracker6App.swift:3812` - Changed tolerance from 5 to 2 minutes

### 13. ~~Replace all print() statements with debugLog()~~ ✅
- **Priority:** Low
- **Status:** COMPLETED (November 8, 2025)
- **Locations:** Throughout codebase (28 occurrences)
- **Issue:** Many `print()` statements execute in production builds, causing console noise
- **Solution:** Replaced all `print()` with `debugLog()` which respects DEBUG flag.
- **Files Changed:**
  - `CTTracker6App.swift` - 28 print() statements replaced with debugLog()

### 18. ~~Fix nil userInfo in notification posting~~ ✅
- **Priority:** Low
- **Status:** COMPLETED (November 8, 2025)
- **Investigation Result:** No NotificationCenter.default.post() calls found in codebase. All NSError objects properly include userInfo dictionaries. Warning is from iOS internals (UIKit/SwiftUI), not app code.
- **Conclusion:** No code changes needed - warning is system-level, not under app control.

### 4. ~~Optimize delay prediction filtering with indexed data structure~~ ✅
- **Priority:** High
- **Status:** COMPLETED (December 13, 2025)
- **Note:** Delay prediction engine was removed in November 2025 (~400 lines removed). This optimization is no longer needed.

### 6. ~~Improve direction matching from string prefix to exact match~~ ✅
- **Priority:** Medium
- **Status:** COMPLETED (December 13, 2025)
- **Location:** `CTTracker6App.swift:4286-4309` - `SIRIService.nextDepartures()`
- **Solution:** Replaced fragile `starts(with: "N")` with whitelist-based validation using `["N", "NORTH", "NB", "NORTHBOUND"]` arrays
- **Files Changed:** `CTTracker6App.swift:4286-4309` - Direction matching logic

### 7. ~~Add validation for iMessage recipient format~~ ✅
- **Priority:** Medium
- **Status:** COMPLETED (December 13, 2025)
- **Location:** `CTTracker6App.swift:704-728, 757-778, 886-889` - SettingsScreen
- **Solution:** Added real-time phone/email validation with regex, visual feedback (✓ green or ⚠️ orange)
- **Files Changed:** `CTTracker6App.swift` - Added validateRecipient() function and validation UI

### 10. ~~Simplify date math for tomorrow's trains using Calendar API~~ ✅
- **Priority:** Medium
- **Status:** COMPLETED (December 13, 2025)
- **Location:** `CTTracker6App.swift:3669-3701, 3732-3747` - `GTFSService.getScheduledDepartures()`
- **Solution:** Replaced manual minute arithmetic with `Calendar.date(bySettingHour:minute:second:of:)` and `timeIntervalSince()`
- **Files Changed:** `CTTracker6App.swift` - Date calculation logic

### 11. ~~Extract duplicate arrival time calculation code~~ ✅
- **Priority:** Low (Code Quality)
- **Status:** COMPLETED (December 13, 2025)
- **Location:** `CTTracker6App.swift:1378-1390` - TrainsScreen and FullScheduleView
- **Solution:** Created `calculateArrivalTimes()` helper function, eliminated 3 duplicate blocks (~60 lines)
- **Files Changed:** `CTTracker6App.swift:104-146` - New helper function, simplified TrainsScreen and FullScheduleView

### 12. ~~Replace magic numbers with named constants~~ ✅
- **Priority:** Low (Code Quality)
- **Status:** COMPLETED (December 13, 2025)
- **Location:** Throughout codebase
- **Solution:** Created `AppConfig` enum with organized configuration constants (GTFS, Network, Events, History)
- **Files Changed:** `CTTracker6App.swift:29-55` - AppConfig enum, replaced 15+ magic numbers throughout

### 14. ~~Add defensive nil checks in DepartureRow~~ ✅
- **Priority:** Low (Code Quality)
- **Status:** COMPLETED (December 13, 2025)
- **Location:** `CTTracker6App.swift:1647, 1671, 1806` - DepartureRow
- **Solution:** Added `max(0, dep.minutes)` to prevent negative display values from clock skew/data issues
- **Files Changed:** `CTTracker6App.swift` - 3 locations with defensive checks

---

## 🟡 Medium Priority - Bugs (2)

### 8. Increase history limit from 500 to 2000+ entries
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:3019` - CommuteHistoryStorage
- **Issue:** Maximum of 500 history entries may not be sufficient for accurate pattern detection, especially for users with irregular commutes
- **Current Code:**
  ```swift
  private let maxHistoryEntries = 500 // Keep last 500 checks
  ```
- **Recommended Fix:** Increase to 2000-5000 entries, or implement smarter retention (keep at least N entries per unique route)
- **Impact:** Less accurate commute pattern predictions

### 9. Optimize test data generation with batching
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:1056-1118` - `addTestDelayData()`
- **Issue:** Generates ~2,376 records synchronously in detached task. While `Task.detached` prevents UI freezing, still allocates significant memory all at once
- **Recommended Fix:** Generate in batches with small delays between batches, or use `autoreleasepool`
- **Impact:** Memory spike during test data generation

---

## 🏗️ Architecture & Long-term (2)

### 15. Split single 4600+ line file into modules
- **Priority:** Low (Long-term)
- **Location:** Entire `CTTracker6App.swift` (4600+ lines)
- **Issue:** Entire app in one massive Swift file, difficult to navigate, review, and maintain
- **Recommended Structure:**
  ```
  Models/
    - CaltrainModels.swift
    - CommuteModels.swift
    - GamificationModels.swift
  Services/
    - GTFSService.swift
    - SIRIService.swift
    - HTTPClient.swift
    - DelayPredictor.swift
    - WeatherService.swift
    - TicketmasterService.swift
  Views/
    - TrainsScreen.swift
    - EventsScreen.swift
    - AlertsScreen.swift
    - InsightsView.swift
    - StationsScreen.swift
    - SettingsScreen.swift
  Storage/
    - Keychain.swift
    - CommuteStorage.swift
    - GamificationManager.swift
  ```
- **Impact:** Difficult to maintain, hard to navigate, challenging for collaboration

### 16. Standardize error handling patterns across app
- **Priority:** Low (Long-term)
- **Locations:** Throughout codebase
- **Issue:** Inconsistent error handling - some functions use `try?` and fail silently, others throw errors, others return optionals
- **Examples:**
  - Line 1460: `try? await GTFSService.shared.getArrivalTime()` - fails silently
  - Line 3522: `try await downloadAndParseGTFS()` - throws error
  - Line 2750: `predictDelay()` - returns optional
- **Recommended Fix:** Establish consistent error handling pattern:
  - Use `Result<T, Error>` for operations that can fail
  - Reserve optionals for truly optional data
  - Use throwing functions for critical operations
  - Document error handling strategy
- **Impact:** Inconsistent user experience, difficult to debug

---

## 🔵 Low Priority - Warnings (1)

### 17. Fix _UIReparentingView warning in MessageComposer/ShareSheet
- **Priority:** Low
- **Location:** `CTTracker6App.swift:1616-1662` - MessageComposer & ShareSheet
- **Issue:** SwiftUI warning about view hierarchy when presenting MessageComposer
- **Warning Message:**
  ```
  Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported
  and may result in a broken view hierarchy.
  ```
- **Impact:** Potential visual glitches on some iOS versions (works fine, but not ideal)
- **Recommended Fix:** Research SwiftUI best practices for UIViewControllerRepresentable, or test on physical device to confirm it's not actually a problem
- **Note:** This is a known SwiftUI issue with UIViewControllerRepresentable

---

## 📊 Summary

| Priority | Count | Items |
|----------|-------|-------|
| ✅ Completed | 13 | Data race, GTFS decompression, HTTPClient, Arrival tolerance, Print statements, Notifications, Delay prediction, Direction matching, iMessage validation, Date math, Duplicate code, Magic numbers, Nil checks |
| 🟡 Medium | 2 | History limit, Test data generation |
| 🏗️ Architecture | 2 | File splitting, Error handling standardization |
| 🔵 Low Priority | 1 | UIReparentingView warning |
| **REMAINING** | **5** | **Down from 18** |

---

## 🎯 Recommended Order of Implementation

### Phase 1: Quick Wins ✅ COMPLETED (November 8, 2025)
1. ✅ HTTPClient dictionary cleanup (Item #3)
2. ✅ Reduce arrival time tolerance (Item #5)
3. ✅ Replace print() statements (Item #13)
4. ✅ Fix notification userInfo (Item #18)

### Phase 2: Performance & Bugs ✅ COMPLETED (December 13, 2025)
1. ✅ Optimize delay prediction filtering (Item #4) - Already removed
2. ✅ Improve direction matching (Item #6)
3. ✅ Add iMessage validation (Item #7)
4. ✅ Simplify date math (Item #10)

### Phase 3: Code Quality ✅ COMPLETED (December 13, 2025)
1. ✅ Replace magic numbers (Item #12)
2. ✅ Extract duplicate code (Item #11)
3. ✅ Add defensive nil checks (Item #14)

### Phase 4: Long-term Improvements (8-12 hours)
1. Increase history limit (Item #8)
2. Optimize test data generation (Item #9)
3. Standardize error handling (Item #16)
4. Investigate UIReparentingView warning (Item #17)

### Phase 5: Major Refactor (1-2 days)
1. Split single file into modules (Item #15)

---

## 📝 Notes

- **Critical bugs are fixed** - App is production-ready
- **Phase 1 Quick Wins completed** (Nov 8, 2025) - Performance optimizations and code quality improvements
- **Phase 2 Performance & Bugs completed** (Dec 13, 2025) - Direction matching, iMessage validation, date math improvements
- **Phase 3 Code Quality completed** (Dec 13, 2025) - Magic numbers, duplicate code, defensive checks
- **72% complete** - 13 of 18 items done (5 remaining)
- **Simulator warnings** - Most error messages are simulator-only and safe to ignore
- **Test on physical device** - Verify fixes work correctly on actual hardware
- **Incremental improvements** - Tackle remaining items over time, prioritize based on user feedback

## 🎁 Bonus Improvements (December 13, 2025)
- Fixed time calculation bug (minutes showing incorrectly with stale refDate)
- Added arrival times to full schedule drill-down (up to 50 departures)
- Added major Bay Area sports venues to events whitelist (49ers, Giants, Sharks, Warriors)
- Fixed Levi's Stadium detection with flexible venue name matching
- Replaced rate limit errors with silent automatic retry
- Removed service alerts banner from Trains screen (cleaner UI)

## 🎁 New Features (December 15, 2025)
- **Calendar Commute Planning** - Automatic train recommendations for tomorrow's first meeting
  - iOS Calendar integration using EventKit (supports Google Calendar, Outlook, iCloud)
  - Configurable home station, office station, and commute buffer (5-60 min)
  - Smart meeting detection: skips all-day events, finds first timed meeting
  - Optimal train selection: recommends latest train that arrives on time
  - Pacific Time timezone handling for accurate meeting times
  - Validates home ≠ office station configuration
  - New "Commute" tab with calendar permission UI
  - Shows departure time, arrival time, route, and buffer info
  - Privacy-first: all calendar data processed locally

**Last Updated:** December 15, 2025
